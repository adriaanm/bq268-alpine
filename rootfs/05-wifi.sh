# WiFi bringup + cellular failover
echo "--- Setting up WiFi and network failover ---"

# WiFi init service (CAF WCNSS + wlan.ko + wpa_supplicant)
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/wifi" "$ROOTFS/etc/init.d/wifi"

# wpa_cli action script (DHCP on connect + cellular failover)
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/wpa_supplicant/wpa_cli.sh" "$ROOTFS/etc/wpa_supplicant/wpa_cli.sh"

# cell-data: start/stop cellular data session
install -m 755 "$SCRIPT_DIR/tools/cell-data.sh" "$ROOTFS/usr/sbin/cell-data"

# net-watchdog: catches silent WiFi drops, triggers cellular failover
install -m 755 "$SCRIPT_DIR/rootfs/files/usr/sbin/net-watchdog" "$ROOTFS/usr/sbin/net-watchdog"
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/net-watchdog" "$ROOTFS/etc/init.d/net-watchdog"

# wpa_supplicant base config
mkdir -p "$ROOTFS/etc/wpa_supplicant"
cat > "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf" << 'WPACFG'
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=US

# Add networks via: wpa_cli -i wlan0
#   > add_network
#   > set_network 0 ssid "MySSID"
#   > set_network 0 psk "MyPassword"
#   > enable_network 0
#   > save_config
WPACFG

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
