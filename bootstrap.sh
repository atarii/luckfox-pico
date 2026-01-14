#!/bin/sh
set -e # Exit on error

# 1. Install base packages with minimal dependencies
apk update
apk add --no-cache --no-scripts \
    openrc agetty dropbear mtd-utils-ubi btop unudhcpd nmap \
    python3 openssl

# 2. Add OpenRC services
rc-update add devfs boot
rc-update add procfs boot
rc-update add sysfs boot
rc-update add networking default
rc-update add local default
rc-update add dropbear default

# 3. Set password without installing shadow permanently
chroot /tmp sh -c 'echo "root:luckfox" | chpasswd' 2>/dev/null || \
    (apk add --no-cache shadow && echo -e "luckfox\nluckfox" | passwd && apk del shadow)

# 4. Install Responder with aggressive cleanup
apk add --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
    --no-cache responder py3-aioquic

# 5. Aggressive Python optimization - remove tests, cache, and optional files
find /usr/lib/python3* -type d \( -name "__pycache__" -o -name "test" -o -name "tests" \) -exec rm -rf {} + 2>/dev/null || true
find /usr/lib/python3* \( -name "*.pyc" -o -name "*.pyo" -o -name "*.dist-info" \) -delete 2>/dev/null || true
# Remove Python ensurepip (can save ~2MB)
rm -rf /usr/lib/python3*/ensurepip

# 6. Strip binaries to remove debug symbols
find /usr/bin /usr/sbin /bin /sbin -type f -exec strip --strip-all {} + 2>/dev/null || true

# 7. Remove unnecessary files and documentation
rm -rf /var/cache/apk/* \
    /usr/share/man \
    /usr/share/doc \
    /usr/share/info \
    /usr/share/locale \
    /tmp/* \
    /var/tmp/* \
    /root/.cache

# 8. Remove apk cache database if not needed
rm -f /lib/apk/db/installed

# 9. Packaging rootfs (optimized)
mkdir -p /extrootfs
for d in bin etc lib sbin usr; do 
    tar c "$d" | tar x -C /extrootfs
done
for dir in dev proc root run sys var oem userdata; do 
    mkdir -p /extrootfs/${dir}
done

# 10. Final cleanup in extrootfs
rm -rf /extrootfs/var/cache/* \
    /extrootfs/tmp/* \
    /extrootfs/root/.cache 2>/dev/null || true
