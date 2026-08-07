# Install CAF 4.4 kernel modules
# The kernel itself lives in the boot partition (boot.img), not the rootfs.
# boot.img is built and flashed by the CAF 4.4 kernel repo directly.
wlan="$CAF_44_REPO/output/drivers/staging/prima/wlan.ko"
if [ ! -f "$wlan" ]; then
    echo "ERROR: CAF 4.4 wlan.ko not found at $wlan" >&2
    echo "  Build it: cd $CAF_44_REPO && make -j\$(nproc) ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- O=output modules" >&2
    exit 1
fi
kver="$(strings "$wlan" | sed -n 's/^vermagic=\([^ ]*\).*/\1/p' | sed 's/-g[0-9a-f]*\(-dirty\)\?$//')"
echo "--- Installing CAF 4.4 modules ($kver) ---"
mkdir -p "$ROOTFS/lib/modules/$kver"
find "$CAF_44_REPO/output" -name "*.ko" -exec cp {} "$ROOTFS/lib/modules/$kver/" \; 2>/dev/null || true
chroot "$ROOTFS" /usr/bin/qemu-arm-static /sbin/depmod "$kver" 2>/dev/null || true
echo "  Modules:"
ls "$ROOTFS/lib/modules/$kver/"*.ko 2>/dev/null | xargs -I{} basename {} || true

# Custom reboot-bootloader (uses RESTART2 syscall with "bootloader" arg)
if [ -f "$SCRIPT_DIR/tools/reboot-bootloader" ]; then
    cp "$SCRIPT_DIR/tools/reboot-bootloader" "$ROOTFS/usr/local/bin/"
    chmod 755 "$ROOTFS/usr/local/bin/reboot-bootloader"
    echo "  reboot-bootloader installed"
fi

# Custom reboot-edl (RESTART2 syscall with "edl" arg → emergency download / 9008)
if [ -f "$SCRIPT_DIR/tools/reboot-edl" ]; then
    cp "$SCRIPT_DIR/tools/reboot-edl" "$ROOTFS/usr/local/bin/"
    chmod 755 "$ROOTFS/usr/local/bin/reboot-edl"
    echo "  reboot-edl installed"
fi
