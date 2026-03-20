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

# Helper: install CAF wlan.ko from a kernel build tree
# Derives module version from vermagic, stripping any -gSHA/-dirty suffix
install_caf_modules() {
    local label="$1" repo="$2"
    local wlan="$repo/output/drivers/staging/prima/wlan.ko"
    if [ ! -f "$wlan" ]; then
        echo "  WARN: $label wlan.ko not found — skipping"
        return
    fi
    local kver
    kver="$(strings "$wlan" | sed -n 's/^vermagic=\([^ ]*\).*/\1/p' | sed 's/-g[0-9a-f]*\(-dirty\)\?$//')"
    echo "--- Installing $label modules ($kver) ---"
    mkdir -p "$ROOTFS/lib/modules/$kver"
    find "$repo/output" -name "*.ko" -exec cp {} "$ROOTFS/lib/modules/$kver/" \; 2>/dev/null || true
    chroot "$ROOTFS" /usr/bin/qemu-arm-static /sbin/depmod "$kver" 2>/dev/null || true
    echo "  Modules:"
    ls "$ROOTFS/lib/modules/$kver/"*.ko 2>/dev/null | xargs -I{} basename {} || true
}

install_caf_modules "CAF 3.18" "$CAF_318_REPO"
install_caf_modules "CAF 4.4"  "$CAF_44_REPO"

# Custom reboot-bootloader (uses RESTART2 syscall with "bootloader" arg)
if [ -f "$SCRIPT_DIR/tools/reboot-bootloader" ]; then
    cp "$SCRIPT_DIR/tools/reboot-bootloader" "$ROOTFS/usr/local/bin/"
    chmod 755 "$ROOTFS/usr/local/bin/reboot-bootloader"
    echo "  reboot-bootloader installed"
fi
