# Battery monitor + graceful shutdown
echo "--- Setting up battery monitor ---"

install -m 755 "$SCRIPT_DIR/rootfs/files/usr/local/bin/graceful-shutdown.sh" "$ROOTFS/usr/local/bin/graceful-shutdown.sh"
install -m 755 "$SCRIPT_DIR/rootfs/files/usr/local/bin/battmon.sh"           "$ROOTFS/usr/local/bin/battmon.sh"
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/battmon"                 "$ROOTFS/etc/init.d/battmon"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add battmon default
'
