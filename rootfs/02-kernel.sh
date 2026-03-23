# Install kernel + CAF modules
echo "--- Installing kernel ---"
mkdir -p "$ROOTFS/boot"
if [ -f "$KERNEL_REPO/out/zImage" ]; then
    cp "$KERNEL_REPO/out/zImage" "$ROOTFS/boot/zImage"
    cp "$KERNEL_REPO/out/qcom-msm8909-udotech-bq268.dtb" "$ROOTFS/boot/msm8909-bq268.dtb" 2>/dev/null || true
    echo "  Kernel copied to /boot"
else
    echo "  WARN: kernel not built yet — skipping /boot copy"
fi

# Install CAF 4.4 wlan.ko (required for WiFi)
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
