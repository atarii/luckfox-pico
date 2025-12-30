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

# Install Python and responder
apk add python3 py3-pip python3-dev build-base --no-cache
ln -sf /usr/bin/python3 /usr/bin/python
pip3 install --no-cache-dir responder

# Clear apk cache
rm -rf /var/cache/apk/*

# Packaging rootfs
for d in bin etc lib sbin usr; do tar c "$d" | tar x -C /extrootfs; done
for dir in dev proc root run sys var oem userdata; do mkdir /extrootfs/${dir}; done
