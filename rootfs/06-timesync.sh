# Time sync (chrony NTP)
echo "--- Setting up time sync ---"
mkdir -p "$ROOTFS/etc/chrony"
install -m 644 "$SCRIPT_DIR/rootfs/files/etc/chrony/chrony.conf" "$ROOTFS/etc/chrony/chrony.conf"
mkdir -p "$ROOTFS/var/lib/chrony"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add chronyd default
'
