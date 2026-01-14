#!/bin/sh
set -e
set -u

#######################################
# 1. Minimal base system + nmap
#######################################

apk update
apk add --no-cache \
    openrc \
    agetty \
    dropbear \
    unudhcpd \
    python3 \
    openssl \
    nmap \
    busybox-extras \
    --repository=https://dl-cdn.alpinelinux.org/alpine/edge/testing \
    responder \
    py3-aioquic

#######################################
# 2. OpenRC services (only required)
#######################################

rc-update add devfs boot
rc-update add procfs boot
rc-update add sysfs boot
rc-update add networking default
rc-update add dropbear default

#######################################
# 3. Lean User Setup
# Instead of installing 'shadow' (which is large), use 'chpasswd' if available 
# or use the built-in busybox 'passwd' non-interactively.
#######################################

echo "root:luckfox" | chpasswd || (echo -e "luckfox\nluckfox" | passwd)

#######################################
# 4. Aggressive Python pruning (safe for responder)
#######################################

rm -rf \
    /usr/lib/python3*/ensurepip \
    /usr/lib/python3*/idlelib \
    /usr/lib/python3*/tkinter \
    /usr/lib/python3*/test \
    /usr/lib/python3*/distutils \
    /usr/lib/python3*/site-packages/pip*

find /usr/lib/python3* -type d -name "__pycache__" -exec rm -rf {} +
find /usr/lib/python3* -type f \( -name "*.pyc" -o -name "*.pyo" \) -delete
find /usr/lib/python3* -type d -name "test" -exec rm -rf {} +
find /usr/lib/python3* -type d -name "tests" -exec rm -rf {} +

#######################################
# 5. Nmap-specific size trimming
#######################################

# Remove nmap docs, NSE docs, unused data
rm -rf \
    /usr/share/nmap/docs \
    /usr/share/nmap/nselib/data \
    /usr/share/nmap/scripts/*.lua \
    /usr/share/nmap/scripts/*.nse

# Keep only default + discovery scripts
find /usr/share/nmap/scripts -type f ! \
    \( -name "default.nse" -o -name "discovery.nse" \) -delete || true

#######################################
# 6. Strip ELF binaries & libraries
#######################################

find /bin /sbin /usr/bin /usr/sbin /lib /usr/lib \
    -type f \
    -exec sh -c 'file "$1" | grep -q ELF && strip --strip-unneeded "$1" || true' sh {} \;

#######################################
# 7. Remove non-runtime junk
#######################################

rm -rf /var/cache/apk/* \
    /usr/share/man \
    /usr/share/doc \
    /usr/share/info \
    /usr/share/locale \
    /usr/include \
    /usr/lib/pkgconfig \
    /usr/lib/*.a \
    /usr/lib/*.la \
    /tmp/* \
    /var/tmp/* \
    /root/.cache

#######################################
# 8. Package only runtime filesystem
#######################################

mkdir -p /extrootfs
# Only copy the essential system directories
for d in bin etc lib sbin usr; do 
    cp -a /$d /extrootfs/
done
# Create empty mount points
for d in dev proc sys run var root tmp; do
    mkdir -p "/extrootfs/$d"
done

chmod 1777 /extrootfs/tmp
