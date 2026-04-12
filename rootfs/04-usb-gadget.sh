# USB gadget (ACM serial only)
echo "--- Setting up USB gadget ---"
mkdir -p "$ROOTFS/etc/init.d"

install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/usb-gadget" "$ROOTFS/etc/init.d/usb-gadget"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add usb-gadget boot
'
