# Install kernel + modules (mainline and CAF)
echo "--- Installing kernel ---"
mkdir -p "$ROOTFS/boot"
if [ -f "$KERNEL_REPO/out/zImage" ]; then
    cp "$KERNEL_REPO/out/zImage" "$ROOTFS/boot/zImage"
    cp "$KERNEL_REPO/out/qcom-msm8909-udotech-bq268.dtb" "$ROOTFS/boot/msm8909-bq268.dtb" 2>/dev/null || true
    echo "  Kernel copied to /boot"
else
    echo "  WARN: kernel not built yet — skipping /boot copy"
fi

# Kernel modules
KVER="$(cat "$KERNEL_REPO/out/include/config/kernel.release" 2>/dev/null || echo "6.19.0-msm8916")"
if [ -d "$KERNEL_REPO/out/lib/modules/$KVER" ]; then
    cp -a "$KERNEL_REPO/out/lib/modules/$KVER" "$ROOTFS/lib/modules/"
    chroot "$ROOTFS" /usr/bin/qemu-arm-static /sbin/depmod "$KVER" 2>/dev/null || true
    echo "  Modules installed for $KVER"
else
    mkdir -p "$ROOTFS/lib/modules/$KVER"
    find "$KERNEL_REPO/output" -name "*.ko" -exec cp {} "$ROOTFS/lib/modules/$KVER/" \; 2>/dev/null || true
    chroot "$ROOTFS" /usr/bin/qemu-arm-static /sbin/depmod "$KVER" 2>/dev/null || true
    echo "  Modules dir: $KVER"
fi

# CAF 3.18 kernel modules (wlan.ko from prima build)
CAF_KVER="$(cat "$CAF_KERNEL_REPO/output/include/config/kernel.release" 2>/dev/null || true)"
if [ -n "$CAF_KVER" ]; then
    echo "--- Installing CAF kernel modules ($CAF_KVER) ---"
    mkdir -p "$ROOTFS/lib/modules/$CAF_KVER"
    find "$CAF_KERNEL_REPO/output" -name "*.ko" -exec cp {} "$ROOTFS/lib/modules/$CAF_KVER/" \; 2>/dev/null || true
    chroot "$ROOTFS" /usr/bin/qemu-arm-static /sbin/depmod "$CAF_KVER" 2>/dev/null || true
    echo "  Modules:"
    ls "$ROOTFS/lib/modules/$CAF_KVER/"*.ko 2>/dev/null | xargs -I{} basename {} || true
fi
