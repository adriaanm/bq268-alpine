# Modem bringup: rmt_storage daemon + subsystem boot
echo "--- Setting up modem support ---"

# Install rmt_storage binary
install -m 755 "$SCRIPT_DIR/tools/rmt_storage" "$ROOTFS/usr/sbin/rmt_storage"

# Install custom libqmi with native AF_MSM_IPC support (replaces Alpine's libqmi/qmi-utils).
# Built from ~/libqmi with -Dmsmipc=true — no LD_PRELOAD shim needed.
install -m 755 "$SCRIPT_DIR/tools/libqmi/libqmi-glib.so.5.12.0" "$ROOTFS/usr/lib/"
ln -sf libqmi-glib.so.5.12.0 "$ROOTFS/usr/lib/libqmi-glib.so.5"
ln -sf libqmi-glib.so.5 "$ROOTFS/usr/lib/libqmi-glib.so"
install -m 755 "$SCRIPT_DIR/tools/libqmi/qmicli" "$ROOTFS/usr/bin/"
install -m 755 "$SCRIPT_DIR/tools/libqmi/qmi-network" "$ROOTFS/usr/bin/"
install -D -m 755 "$SCRIPT_DIR/tools/libqmi/qmi-proxy" "$ROOTFS/usr/libexec/qmi-proxy"

# OpenRC init scripts
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/rmt-storage" "$ROOTFS/etc/init.d/rmt-storage"
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/modem"       "$ROOTFS/etc/init.d/modem"
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/qmi-proxy"   "$ROOTFS/etc/init.d/qmi-proxy"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add rmt-storage default
rc-update add modem default
rc-update add qmi-proxy default
'
echo "  rmt-storage + modem + qmi-proxy services installed (auto-start in default runlevel)"
