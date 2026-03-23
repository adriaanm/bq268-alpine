# Install Alpine packages
echo "--- Installing packages ---"
chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
apk update
apk add \
    openrc busybox-openrc \
    dropbear openssh-sftp-server \
    wpa_supplicant \
    evtest \
    iproute2 \
    util-linux \
    e2fsprogs \
    nano \
    htop \
    strace \
    linux-firmware-none \
    wireless-regdb \
    kmod \
    modemmanager \
    bluez \
    chrony \
    kbd
'

# Fix /run — ensure it's a real directory so tmpfs mount works at boot
if [ -L "$ROOTFS/run" ]; then
    rm -f "$ROOTFS/run"
fi
mkdir -p "$ROOTFS/run"
