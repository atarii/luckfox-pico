#!/bin/sh

# Install base
apk update
apk add openrc
rc-update add devfs boot
rc-update add procfs boot
rc-update add sysfs boot
rc-update add networking default
rc-update add local default

# Install TTY
apk add agetty

# Setting up shell
apk add shadow --no-cache
echo -e "luckfox\nluckfox" | passwd
apk del -r shadow

# Install SSH
apk add dropbear mtd-utils-ubi btop unudhcpd --no-cache
rc-update add dropbear default

# Install Python, OpenSSL, Responder and aioquic from testing repo
apk add python3 openssl --no-cache
ln -sf /usr/bin/python3 /usr/bin/python
# Enable testing repository and install responder and aioquic
apk add --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing responder py3-aioquic --no-cache

# Clear apk cache
rm -rf /var/cache/apk/*

# Packaging rootfs
for d in bin etc lib sbin usr; do tar c "$d" | tar x -C /extrootfs; done
for dir in dev proc root run sys var oem userdata; do mkdir /extrootfs/${dir}; done

# Create responder directories in the final rootfs
mkdir -p /extrootfs/var/log/responder
mkdir -p /extrootfs/var/lib/responder
mkdir -p /extrootfs/var/run/responder

# Set execute permissions for scripts
chmod +x /extrootfs/etc/local.d/00-responder-certs.start 2>/dev/null || true
chmod +x /extrootfs/etc/init.d/udhcpd 2>/dev/null || true

# Enable udhcpd service
ln -s /etc/init.d/udhcpd /extrootfs/etc/runlevels/default/udhcpd 2>/dev/null || true
