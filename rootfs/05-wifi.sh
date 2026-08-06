# WiFi bringup + cellular failover
echo "--- Setting up WiFi and network failover ---"

# WiFi init service (CAF WCNSS + wlan.ko + wpa_supplicant)
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/wifi" "$ROOTFS/etc/init.d/wifi"

# wpa_cli action script (DHCP on connect + cellular failover)
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/wpa_supplicant/wpa_cli.sh" "$ROOTFS/etc/wpa_supplicant/wpa_cli.sh"

# cell-data: start/stop cellular data session
install -m 755 "$SCRIPT_DIR/tools/cell-data.sh" "$ROOTFS/usr/sbin/cell-data"

# Approved roaming partners (Singtel ReadyRoam allowlist, LTE-only)
install -d "$ROOTFS/etc/cellular"
install -m 644 "$SCRIPT_DIR/rootfs/files/etc/cellular/roaming-partners" \
    "$ROOTFS/etc/cellular/roaming-partners"

# net-watchdog: catches silent WiFi drops, triggers cellular failover
install -m 755 "$SCRIPT_DIR/rootfs/files/usr/sbin/net-watchdog" "$ROOTFS/usr/sbin/net-watchdog"
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/net-watchdog" "$ROOTFS/etc/init.d/net-watchdog"

# wifi-join: wata-fb's join-a-network helper (ssid via argv, PSK via stdin)
install -m 755 "$SCRIPT_DIR/rootfs/files/usr/local/bin/wifi-join" "$ROOTFS/usr/local/bin/wifi-join"

# wpa_supplicant base config
mkdir -p "$ROOTFS/etc/wpa_supplicant"
install -m 644 "$SCRIPT_DIR/rootfs/files/etc/wpa_supplicant/wpa_supplicant.conf" "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf"

# Append local WiFi networks from wifi.conf (gitignored, contains passwords)
if [ -f "$SCRIPT_DIR/wifi.conf" ]; then
    echo "" >> "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf"
    cat "$SCRIPT_DIR/wifi.conf" >> "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf"
    echo "  WiFi networks added from wifi.conf"
fi

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add wifi default
rc-update add net-watchdog default
'
