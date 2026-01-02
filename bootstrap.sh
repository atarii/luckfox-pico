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

# Generate SSL certificates for Responder
if [ -f /usr/share/responder/certs/gen-self-signed-cert.sh ]; then
    cd /usr/share/responder
    mkdir -p certs
    sh ./certs/gen-self-signed-cert.sh
    cd -
fi

# Clear apk cache
rm -rf /var/cache/apk/*

# Packaging rootfs
for d in bin etc lib sbin usr; do tar c "$d" | tar x -C /extrootfs; done
for dir in dev proc root run sys var oem userdata; do mkdir /extrootfs/${dir}; done

# Create responder directories in the final rootfs
mkdir -p /extrootfs/var/log/responder
mkdir -p /extrootfs/var/lib/responder
