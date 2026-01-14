#!/bin/sh
set -e # Exit on error

# 1. Install base with disk-saving flags
apk update
apk add --no-cache openrc agetty dropbear mtd-utils-ubi btop unudhcpd nmap python3 openssl

# 2. Add OpenRC services
rc-update add devfs boot
rc-update add procfs boot
rc-update add sysfs boot
rc-update add networking default
rc-update add local default
rc-update add dropbear default

# 3. Setting up shell (Keep it lean)
apk add shadow --no-cache
echo -e "luckfox\nluckfox" | passwd
apk del shadow

# 4. Install Responder WITHOUT bytecode (-pyc) files
# We use the --no-cache flag and manually exclude -pyc packages if possible
# Or simply delete them after installation to save massive space
apk add --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
    responder py3-aioquic --no-cache

# 5. MASSIVE SPACE SAVER: Delete all python cache/bytecode files
find /usr/lib/python3* -name "__pycache__" -type d -exec rm -rf {} +
find /usr/lib/python3* -name "*.pyc" -delete

# 6. Remove unnecessary files before packaging
rm -rf /var/cache/apk/*
rm -rf /usr/share/man
rm -rf /usr/share/doc

# 7. Packaging rootfs
# Ensure the destination has enough space or is mounted correctly
for d in bin etc lib sbin usr; do 
    tar c "$d" | tar x -C /extrootfs
done

for dir in dev proc root run sys var oem userdata; do 
    mkdir -p /extrootfs/${dir}
done
