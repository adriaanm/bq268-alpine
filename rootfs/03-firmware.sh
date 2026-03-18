# Install firmware files
echo "--- Installing firmware ---"
mkdir -p "$ROOTFS/lib/firmware/qcom"

# Panel firmware (panel-mipi-dbi-spi driver)
cp "$KERNEL_REPO/out/udotech,bq268-st7735s-panel.bin" "$ROOTFS/lib/firmware/" 2>/dev/null || true

# GPU firmware
cp "$FIRMWARE_DIR/gpu/a300_pfp.fw" "$ROOTFS/lib/firmware/" 2>/dev/null || true
cp "$FIRMWARE_DIR/gpu/a300_pm4.fw" "$ROOTFS/lib/firmware/" 2>/dev/null || true

# Modem firmware (PIL expects these at /lib/firmware/)
cp "$FIRMWARE_DIR/modem"/modem.* "$ROOTFS/lib/firmware/" 2>/dev/null || true
cp "$FIRMWARE_DIR/modem/mba.mbn" "$ROOTFS/lib/firmware/" 2>/dev/null || true

# WCNSS firmware (PIL expects wcnss.mdt at /lib/firmware/)
cp "$FIRMWARE_DIR/wcnss"/wcnss.* "$ROOTFS/lib/firmware/" 2>/dev/null || true

# WLAN NV data + config
mkdir -p "$ROOTFS/lib/firmware/wlan/prima"
cp "$FIRMWARE_DIR/wlan/WCNSS_qcom_wlan_nv.bin" "$ROOTFS/lib/firmware/wlan/prima/" 2>/dev/null || true
cp "$FIRMWARE_DIR/wlan/WCNSS_cfg.dat" "$ROOTFS/lib/firmware/wlan/prima/" 2>/dev/null || true
cp "$FIRMWARE_DIR/wlan/WCNSS_qcom_cfg.ini" "$ROOTFS/lib/firmware/wlan/prima/" 2>/dev/null || true

# Staged WiFi firmware (from /tmp/bq268-wifi-fw if available)
WIFI_FW_STAGED="/tmp/bq268-wifi-fw/lib/firmware"
if [ -d "$WIFI_FW_STAGED" ]; then
    echo "  Installing staged WiFi firmware from $WIFI_FW_STAGED"
    cp "$WIFI_FW_STAGED"/wcnss.* "$ROOTFS/lib/firmware/" 2>/dev/null || true
    mkdir -p "$ROOTFS/lib/firmware/wlan/prima"
    cp "$WIFI_FW_STAGED"/wlan/prima/WCNSS_qcom_wlan_nv.bin "$ROOTFS/lib/firmware/wlan/prima/" 2>/dev/null || true
fi
