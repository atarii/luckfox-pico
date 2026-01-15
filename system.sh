#!/bin/bash
set -e  # Exit on error
set -o pipefail  # Catch errors in pipes

# Configuration
ROOTFS_NAME="rootfs-alpine.tar.gz"
DEVICE_NAME="pico-plus"
SDK_DIR="sdk"
TOOLCHAIN_DIR="$SDK_DIR/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf"
CUSTOM_ROOTFS_DIR="$SDK_DIR/sysdrv/custom_rootfs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Parse command line arguments
usage() {
    cat << EOF
Usage: $0 [-f ROOTFS_FILE] [-d DEVICE_NAME]

Options:
    -f ROOTFS_FILE    Path to rootfs tarball (default: rootfs-alpine.tar.gz)
    -d DEVICE_NAME    Target device name (default: pico-plus)
                      Valid devices: pico-mini-b, pico-plus, pico-pro-max

Examples:
    $0 -f custom-rootfs.tar.gz -d pico-pro-max
    $0 -d pico-mini-b

EOF
    exit 1
}

while getopts ":f:d:h" opt; do
    case ${opt} in
        f) ROOTFS_NAME="${OPTARG}" ;;
        d) DEVICE_NAME="${OPTARG}" ;;
        h) usage ;;
        ?)
            log_error "Invalid option: -${OPTARG}"
            usage
            ;;
    esac
done

# Validate device and get device ID
get_device_id() {
    case $1 in
        pico-mini-b) echo "1" ;;
        pico-plus) echo "2" ;;
        pico-pro-max) echo "4" ;;
        *)
            log_error "Invalid device: $1"
            log_info "Valid devices: pico-mini-b, pico-plus, pico-pro-max"
            exit 1
            ;;
    esac
}

DEVICE_ID=$(get_device_id "$DEVICE_NAME")

# Validate prerequisites
validate_prerequisites() {
    log_step "Validating prerequisites..."
    
    # Check if rootfs file exists
    if [ ! -f "$ROOTFS_NAME" ]; then
        log_error "Rootfs file not found: $ROOTFS_NAME"
        exit 1
    fi
    
    # Check if SDK directory exists
    if [ ! -d "$SDK_DIR" ]; then
        log_error "SDK directory not found: $SDK_DIR"
        exit 1
    fi
    
    # Check if toolchain exists
    if [ ! -d "$TOOLCHAIN_DIR" ]; then
        log_error "Toolchain directory not found: $TOOLCHAIN_DIR"
        exit 1
    fi
    
    # Check if build.sh exists
    if [ ! -f "$SDK_DIR/build.sh" ]; then
        log_error "build.sh not found in SDK directory"
        exit 1
    fi
    
    log_info "All prerequisites validated"
}

# Prepare custom rootfs
prepare_rootfs() {
    log_step "Preparing custom rootfs..."
    
    # Clean and create custom rootfs directory
    rm -rf "$CUSTOM_ROOTFS_DIR"
    mkdir -p "$CUSTOM_ROOTFS_DIR"
    
    # Copy rootfs to SDK
    cp "$ROOTFS_NAME" "$CUSTOM_ROOTFS_DIR/" || {
        log_error "Failed to copy rootfs to SDK"
        exit 1
    }
    
    # Get basename only (remove any path components)
    ROOTFS_NAME=$(basename "$ROOTFS_NAME")
    
    log_info "Rootfs copied: $CUSTOM_ROOTFS_DIR/$ROOTFS_NAME"
}

# Setup toolchain
setup_toolchain() {
    log_step "Setting up toolchain..."
    
    pushd "$TOOLCHAIN_DIR" > /dev/null || {
        log_error "Failed to enter toolchain directory"
        exit 1
    }
    
    if [ ! -f "env_install_toolchain.sh" ]; then
        log_error "Toolchain setup script not found"
        popd > /dev/null
        exit 1
    fi
    
    # shellcheck disable=SC1091
    source env_install_toolchain.sh || {
        log_error "Failed to source toolchain environment"
        popd > /dev/null
        exit 1
    }
    
    popd > /dev/null
    log_info "Toolchain configured"
}

# Configure board
configure_board() {
    log_step "Configuring board for $DEVICE_NAME (ID: $DEVICE_ID)..."
    
    pushd "$SDK_DIR" > /dev/null || {
        log_error "Failed to enter SDK directory"
        exit 1
    }
    
    # Remove existing board config
    rm -rf .BoardConfig.mk
    
    # Run lunch with device selection
    # Format: DEVICE_ID\n1\n0 means:
    # - Device ID
    # - Buildroot option (1)
    # - No additional options (0)
    echo -e "$DEVICE_ID\n1\n0" | ./build.sh lunch || {
        log_error "Board configuration failed"
        popd > /dev/null
        exit 1
    }
    
    # Append custom rootfs configuration
    {
        echo "export RK_CUSTOM_ROOTFS=../sysdrv/custom_rootfs/$ROOTFS_NAME"
        echo "export RK_BOOTARGS_CMA_SIZE=\"1M\""
    } >> .BoardConfig.mk
    
    log_info "Board configured with custom rootfs"
    
    popd > /dev/null
}

# Build component
build_component() {
    local component=$1
    log_step "Building $component..."
    
    pushd "$SDK_DIR" > /dev/null || {
        log_error "Failed to enter SDK directory"
        exit 1
    }
    
    ./build.sh "$component" || {
        log_error "Failed to build $component"
        popd > /dev/null
        exit 1
    }
    
    popd > /dev/null
    log_info "$component built successfully"
}

# Build firmware
build_firmware() {
    log_step "Building firmware components..."
    
    # Build all components in order
    build_component "uboot"
    build_component "kernel"
    build_component "driver"
    build_component "env"
    
    # Uncomment if you want to build app
    # build_component "app"
    
    log_info "All firmware components built"
}

# Package firmware
package_firmware() {
    log_step "Packaging firmware..."
    
    pushd "$SDK_DIR" > /dev/null || {
        log_error "Failed to enter SDK directory"
        exit 1
    }
    
    # Build firmware package
    ./build.sh firmware || {
        log_error "Firmware packaging failed"
        popd > /dev/null
        exit 1
    }
    
    # Save firmware
    ./build.sh save || {
        log_error "Firmware save failed"
        popd > /dev/null
        exit 1
    }
    
    popd > /dev/null
    log_info "Firmware packaged successfully"
}

# Prepare output
prepare_output() {
    log_step "Preparing output..."
    
    local update_img="$SDK_DIR/output/image/update.img"
    local output_img="output/$DEVICE_NAME-sysupgrade.img"
    
    # Check if update.img exists
    if [ ! -f "$update_img" ]; then
        log_error "Update image not found: $update_img"
        exit 1
    fi
    
    # Create output directory
    rm -rf output
    mkdir -p output
    
    # Copy firmware with device-specific name
    cp "$update_img" "$output_img" || {
        log_error "Failed to copy firmware to output"
        exit 1
    }
    
    # Show output info
    local img_size=$(du -h "$output_img" | cut -f1)
    log_info "Firmware image created: $output_img ($img_size)"
}

# Print build summary
print_summary() {
    echo
    echo "═══════════════════════════════════════════════════════"
    log_info "Build completed successfully!"
    echo "═══════════════════════════════════════════════════════"
    echo
    log_info "Configuration:"
    echo "  Device:     $DEVICE_NAME (ID: $DEVICE_ID)"
    echo "  Rootfs:     $ROOTFS_NAME"
    echo "  Output:     output/$DEVICE_NAME-sysupgrade.img"
    echo
    log_info "To flash the firmware:"
    echo "  1. Put device in maskrom mode"
    echo "  2. Run: rkdeveloptool wl 0 output/$DEVICE_NAME-sysupgrade.img"
    echo "  3. Run: rkdeveloptool rd"
    echo
    echo "═══════════════════════════════════════════════════════"
}

# Main execution
main() {
    local start_time=$(date +%s)
    
    log_info "Starting build process..."
    log_info "Device: $DEVICE_NAME (ID: $DEVICE_ID)"
    log_info "Rootfs: $ROOTFS_NAME"
    echo
    
    # Execute build steps
    validate_prerequisites
    prepare_rootfs
    setup_toolchain
    configure_board
    build_firmware
    package_firmware
    prepare_output
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local minutes=$((duration / 60))
    local seconds=$((duration % 60))
    
    echo
    log_info "Build took ${minutes}m ${seconds}s"
    print_summary
}

# Trap errors
trap 'log_error "Build failed at line $LINENO"; exit 1' ERR

# Run main function
main
