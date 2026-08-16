# Persistent /data partition: mount + state adoption at boot
# (docs/planning/data-partition.md). The image carries REAL files at the
# canonical paths (wata state, dropbear keys, wpa_supplicant.conf) — the
# data service adopts them into /data on first boot, so a fresh image
# provisions /data and a reflash over an existing /data defers to it.
echo "--- Setting up /data persistence ---"

install -m 755 "$SCRIPT_DIR/rootfs/files/usr/sbin/data-setup" "$ROOTFS/usr/sbin/data-setup"
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/data"     "$ROOTFS/etc/init.d/data"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add data boot
'
