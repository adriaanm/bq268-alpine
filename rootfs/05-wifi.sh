# WiFi bringup: driver load + wpa_supplicant (DHCP handled by action script)
echo "--- Creating WiFi init script ---"
cat > "$ROOTFS/etc/init.d/wifi" << 'WIFI'
#!/sbin/openrc-run

description="WiFi (WCNSS + wlan driver + wpa_supplicant)"

depend() {
    after modules
}

start() {
    if [ -e /dev/wcnss_wlan ]; then
        # CAF: trigger WCNSS PIL firmware load, then insmod wlan.ko
        ebegin "Starting WiFi (CAF WCNSS)"
        cat /dev/wcnss_wlan &
        sleep 5  # wait for SMD channel + NV download
        local kver
        kver=$(uname -r)
        insmod /lib/modules/$kver/wlan.ko
        eend $?
    else
        # Mainline: wcn36xx/pronto_wlan loaded by hwdrivers or modprobe
        ebegin "Starting WiFi (mainline)"
        modprobe pronto_wlan 2>/dev/null || true
        eend 0
    fi

    # Wait for wlan0 to appear (up to 5s)
    local i=0
    while [ $i -lt 50 ] && [ ! -d /sys/class/net/wlan0 ]; do
        sleep 0.1
        i=$((i + 1))
    done

    if [ -d /sys/class/net/wlan0 ]; then
        ebegin "Starting wpa_supplicant"
        wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
        eend $?
    else
        ewarn "wlan0 not found — skipping wpa_supplicant"
    fi
}

stop() {
    ebegin "Stopping WiFi"
    kill $(cat /run/udhcpc.wlan0.pid 2>/dev/null) 2>/dev/null
    killall wpa_supplicant 2>/dev/null
    eend 0
}
WIFI
chmod 755 "$ROOTFS/etc/init.d/wifi"

# wpa_cli action script — called by the wpa_cli service on CONNECTED/DISCONNECTED
# Alpine's wpa_cli service reads /etc/conf.d/wpa_cli which defaults to:
#   WPACLI_OPTS="-a /etc/wpa_supplicant/wpa_cli.sh"
cat > "$ROOTFS/etc/wpa_supplicant/wpa_cli.sh" << 'ACTION'
#!/bin/sh
# Called by wpa_cli -a: $1=interface, $2=event
IFACE="$1"
EVENT="$2"

case "$EVENT" in
    CONNECTED)
        logger -t wpa-action "$IFACE: connected, starting DHCP"
        kill $(cat /run/udhcpc.$IFACE.pid 2>/dev/null) 2>/dev/null
        udhcpc -i "$IFACE" -b -R -p /run/udhcpc.$IFACE.pid -q
        ;;
    DISCONNECTED)
        logger -t wpa-action "$IFACE: disconnected, releasing DHCP"
        kill $(cat /run/udhcpc.$IFACE.pid 2>/dev/null) 2>/dev/null
        ip addr flush dev "$IFACE" 2>/dev/null
        ;;
esac
ACTION
chmod 755 "$ROOTFS/etc/wpa_supplicant/wpa_cli.sh"

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
rc-update add wpa_cli default
'

echo "--- Setting up modem ---"

# Mainline modem stack:
#   - q6v5-mss remoteproc loads modem firmware from /lib/firmware/
#   - BAM-DMUX creates rmnet data interfaces
#   - QMI via QRTR (not SMD like CAF)
#   - ModemManager talks QMI over QRTR
#
# To bring up cellular data after boot:
#   mmcli -L                                    # list modems
#   mmcli -m 0 --simple-connect="apn=your.apn"  # connect
