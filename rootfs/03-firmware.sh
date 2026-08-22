# Install firmware files
echo "--- Installing firmware ---"
mkdir -p "$ROOTFS/lib/firmware/qcom"

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
# Disable prima's host-log netlink service: with the kernel diag driver
# removed (its only consumer), it spams dmesg with
# "send_filled_buffers_to_user: Send Failed -3" every ~30s. Must land
# above the END marker or the parser never sees it.
INI="$ROOTFS/lib/firmware/wlan/prima/WCNSS_qcom_cfg.ini"
if [ -f "$INI" ] && ! grep -q '^wlanLoggingEnable=' "$INI"; then
    sed -i '/^END$/i wlanLoggingEnable=0' "$INI"
fi

# Staged WiFi firmware (from /tmp/bq268-wifi-fw if available)
WIFI_FW_STAGED="/tmp/bq268-wifi-fw/lib/firmware"
if [ -d "$WIFI_FW_STAGED" ]; then
    echo "  Installing staged WiFi firmware from $WIFI_FW_STAGED"
    cp "$WIFI_FW_STAGED"/wcnss.* "$ROOTFS/lib/firmware/" 2>/dev/null || true
    mkdir -p "$ROOTFS/lib/firmware/wlan/prima"
    cp "$WIFI_FW_STAGED"/wlan/prima/WCNSS_qcom_wlan_nv.bin "$ROOTFS/lib/firmware/wlan/prima/" 2>/dev/null || true
fi
