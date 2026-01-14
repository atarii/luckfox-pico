#!/bin/sh
set -e

# 1. Install packages with --no-cache and exclude documentation
# We use --virtual to group build dependencies if any were needed
apk update
apk add --no-cache \
    openrc agetty dropbear mtd-utils-ubi btop unudhcpd nmap python3 openssl \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
    responder py3-aioquic

# 2. Add OpenRC services (No change needed here)
for svc in devfs procfs sysfs; do rc-update add $svc boot; done
for svc in networking local dropbear; do rc-update add $svc default; done

# 3. Lean User Setup
# Instead of installing 'shadow' (which is large), use 'chpasswd' if available 
# or use the built-in busybox 'passwd' non-interactively.
echo "root:luckfox" | chpasswd || (echo -e "luckfox\nluckfox" | passwd)

# 4. Binary Stripping (The "Secret Sauce" for size)
# This removes debug symbols from all executables and libraries
find /bin /sbin /usr/bin /usr/sbin /usr/lib -type f -exec strip --strip-all {} + || true

# 5. Aggressive Python Shrinking
# Delete __pycache__, tests, and ensure no .pyc or .pyo files remain
find /usr/lib/python* -name "__pycache__" -type d -exec rm -rf {} +
find /usr/lib/python* -name "*.pyc" -delete
find /usr/lib/python* -name "*.pyo" -delete
find /usr/lib/python* -name "test" -type d -exec rm -rf {} +
find /usr/lib/python* -name "tests" -type d -exec rm -rf {} +

# 6. Delete Documentation, Locales, and Headers
rm -rf /usr/share/man /usr/share/doc /usr/share/info /usr/include
rm -rf /usr/lib/*.a /usr/lib/*.la  # Static libraries
rm -rf /var/cache/apk/* /etc/apk/cache/*

# 7. Efficient Rootfs Packaging
# Use 'cp -a' or 'rsync' to maintain links without the overhead of double-tar
# Only copy the essential system directories
for d in bin etc lib sbin usr; do 
    cp -a /$d /extrootfs/
done

# Create empty mount points
mkdir -p /extrootfs/dev /extrootfs/proc /extrootfs/root /extrootfs/run \
         /extrootfs/sys /extrootfs/var /extrootfs/oem /extrootfs/userdata /extrootfs/tmp

# Final cleanup of the target
rm -rf /extrootfs/usr/share/terminfo/[!vlp]* # Keep only vital terminfo if needed
