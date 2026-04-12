# Power toggle switch + screen management (keyd, screen-idle)
echo "--- Setting up power switch and screen management ---"

install -m 755 "$SCRIPT_DIR/rootfs/files/usr/local/bin/screen-off.sh"  "$ROOTFS/usr/local/bin/screen-off.sh"
install -m 755 "$SCRIPT_DIR/rootfs/files/usr/local/bin/screen-on.sh"   "$ROOTFS/usr/local/bin/screen-on.sh"
install -m 755 "$SCRIPT_DIR/rootfs/files/usr/local/bin/screen-wake.sh" "$ROOTFS/usr/local/bin/screen-wake.sh"
install -m 755 "$SCRIPT_DIR/rootfs/files/usr/local/bin/screen-idle.sh" "$ROOTFS/usr/local/bin/screen-idle.sh"
install -m 755 "$SCRIPT_DIR/rootfs/files/usr/local/bin/keyd.sh"        "$ROOTFS/usr/local/bin/keyd.sh"
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/keyd"              "$ROOTFS/etc/init.d/keyd"
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/screen-idle"       "$ROOTFS/etc/init.d/screen-idle"
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/cpufreq"           "$ROOTFS/etc/init.d/cpufreq"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add keyd default
rc-update add screen-idle default
rc-update add cpufreq default
'
