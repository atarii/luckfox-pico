#!/bin/bash
set -e  # Exit on error

# Configuration
OUTPUT_DIR="output"
ROOTFS_FILE="rootfs-alpine.tar.gz"
ROOTFS_WORKSPACE_NAME="rootfs-alpine"
ROOTFS_WORKSPACE_FILE="$ROOTFS_WORKSPACE_NAME.ext4"
ROOTFS_WORKSPACE_MNT="/tmp/$ROOTFS_WORKSPACE_NAME/"
ROOTFS_SIZE="500M"  # Increased from 200M for better margin

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Cleanup function
rootfs_workspace_drop() {
    log_info "Cleaning up workspace..."
    
    # Unmount with retry
    if mountpoint -q "$ROOTFS_WORKSPACE_MNT" 2>/dev/null; then
        umount -R "$ROOTFS_WORKSPACE_MNT" 2>/dev/null || {
            log_warn "First unmount attempt failed, retrying with lazy unmount..."
            umount -l "$ROOTFS_WORKSPACE_MNT" 2>/dev/null || true
            sleep 1
        }
    fi
    
    # Remove files
    rm -rf "$ROOTFS_WORKSPACE_FILE" "$ROOTFS_WORKSPACE_MNT"
}

# Create new workspace
rootfs_workspace_new() {
    log_info "Creating new rootfs workspace (size: $ROOTFS_SIZE)..."
    
    mkdir -p "$ROOTFS_WORKSPACE_MNT"
    
    # Create sparse file and format
    truncate -s "$ROOTFS_SIZE" "$ROOTFS_WORKSPACE_FILE"
    
    # Use mke2fs for better control and reduced reserved blocks
    mke2fs -t ext4 -m 0 -F "$ROOTFS_WORKSPACE_FILE" || {
        log_error "Failed to create ext4 filesystem"
        exit 1
    }
    
    # Mount with noatime for better performance
    mount -o noatime "$ROOTFS_WORKSPACE_FILE" "$ROOTFS_WORKSPACE_MNT" || {
        log_error "Failed to mount workspace"
        exit 1
    }
    
    log_info "Workspace mounted at $ROOTFS_WORKSPACE_MNT"
}

# Check disk space before proceeding
check_disk_space() {
    log_info "Checking disk space..."
    local available_kb=$(df "$ROOTFS_WORKSPACE_MNT" | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))
    log_info "Available space in workspace: ${available_mb}MB"
    
    if [ "$available_mb" -lt 150 ]; then
        log_error "Insufficient space in workspace (${available_mb}MB available, need at least 150MB)"
        exit 1
    fi
}

# Apply overlay configuration
overlay() {
    log_info "Applying overlay configuration..."
    
    local OVERLAY_WORKSPACE="overlay-workspace"
    rm -rf "$OVERLAY_WORKSPACE"
    
    if [ ! -d "overlay" ]; then
        log_error "Overlay directory not found!"
        exit 1
    fi
    
    cp -R overlay "$OVERLAY_WORKSPACE"
    
    # Configuration variables
    HOSTNAME="luckfox"
    TTY_PORT="ttyFIQ0"
    
    # Apply substitutions
    sed -i -e "s/{HOSTNAME}/$HOSTNAME/g" "$OVERLAY_WORKSPACE/etc/hostname"
    sed -i -e "s/{TTY_PORT}/$TTY_PORT/g" "$OVERLAY_WORKSPACE/etc/securetty"
    sed -i -e "s/{TTY_PORT}/$TTY_PORT/g" "$OVERLAY_WORKSPACE/etc/inittab"
    
    # Sync overlay to workspace
    rsync -a "$OVERLAY_WORKSPACE/" "$ROOTFS_WORKSPACE_MNT/" || {
        log_error "Failed to sync overlay"
        exit 1
    }
    
    rm -rf "$OVERLAY_WORKSPACE"
    
    # Create symlinks for init.d services
    mkdir -p "$ROOTFS_WORKSPACE_MNT/etc/runlevels/default/"
    
    ln -sf "/etc/init.d/link_mount" \
        "$ROOTFS_WORKSPACE_MNT/etc/runlevels/default/link_mount"
    ln -sf "/etc/init.d/usb_gadget" \
        "$ROOTFS_WORKSPACE_MNT/etc/runlevels/default/usb_gadget"
    
    # Set permissions
    if [ -f "$ROOTFS_WORKSPACE_MNT/etc/local.d/00-responder-certs.start" ]; then
        chmod +x "$ROOTFS_WORKSPACE_MNT/etc/local.d/00-responder-certs.start"
    else
        log_warn "Responder cert script not found"
    fi
    
    # Create responder directories
    mkdir -p "$ROOTFS_WORKSPACE_MNT/var/log/responder"
    mkdir -p "$ROOTFS_WORKSPACE_MNT/var/lib/responder"
    mkdir -p "$ROOTFS_WORKSPACE_MNT/var/run/responder"
    
    log_info "Overlay configuration applied successfully"
}

# Package rootfs
package_rootfs() {
    log_info "Packaging rootfs..."
    
    # Check final size before packaging
    local used_kb=$(df "$ROOTFS_WORKSPACE_MNT" | awk 'NR==2 {print $3}')
    local used_mb=$((used_kb / 1024))
    log_info "Total rootfs size: ${used_mb}MB"
    
    pushd "$ROOTFS_WORKSPACE_MNT" > /dev/null || exit
    
    # Create tarball with progress
    tar czf "$ROOTFS_FILE" ./* || {
        log_error "Failed to create tarball"
        popd > /dev/null || true
        exit 1
    }
    
    popd > /dev/null || exit
    
    # Prepare output directory
    rm -rf "$OUTPUT_DIR"
    mkdir -p "$OUTPUT_DIR"
    
    # Move tarball to output
    mv "$ROOTFS_WORKSPACE_MNT/$ROOTFS_FILE" "$OUTPUT_DIR/" || {
        log_error "Failed to move tarball to output directory"
        exit 1
    }
    
    # Show final file size
    local final_size=$(du -h "$OUTPUT_DIR/$ROOTFS_FILE" | cut -f1)
    log_info "Rootfs package created: $OUTPUT_DIR/$ROOTFS_FILE ($final_size)"
}

# Main execution
main() {
    log_info "Starting rootfs build process..."
    
    # Cleanup any existing workspace
    rootfs_workspace_drop
    
    # Create new workspace
    rootfs_workspace_new
    
    # Setup multiarch support
    log_info "Setting up multiarch support..."
    docker run --rm --privileged multiarch/qemu-user-static --reset -p yes
    
    # Build rootfs in Docker
    log_info "Building rootfs in Docker container..."
    docker container rm -f armv7alpine 2>/dev/null || true
    
    if [ ! -f "bootstrap.sh" ]; then
        log_error "bootstrap.sh not found!"
        exit 1
    fi
    
    docker run \
        --platform linux/arm/v7 \
        --name armv7alpine \
        --net host \
        --mount type=bind,source="$(pwd)/bootstrap.sh",target=/bootstrap.sh,ro \
        -v "$ROOTFS_WORKSPACE_MNT:/extrootfs" \
        arm32v7/alpine \
        /bootstrap.sh || {
        log_error "Docker build failed"
        exit 1
    }
    
    # Check available space after Docker build
    check_disk_space
    
    # Apply overlay configuration
    overlay
    
    # Package the rootfs
    package_rootfs
    
    # Cleanup
    log_info "Cleaning up..."
    rootfs_workspace_drop
    
    log_info "Build completed successfully!"
    log_info "Output: $OUTPUT_DIR/$ROOTFS_FILE"
}

# Trap errors and cleanup
trap 'log_error "Build failed!"; rootfs_workspace_drop; exit 1' ERR

# Run main function
main
