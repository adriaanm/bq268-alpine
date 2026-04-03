# Network failover: WiFi primary, cellular backup
# Cellular data session only active when WiFi is down (saves data).
echo "--- Setting up network failover ---"

# cell-data: start/stop cellular data session
install -m 755 "$SCRIPT_DIR/tools/cell-data.sh" "$ROOTFS/usr/sbin/cell-data"

# Extend wpa_cli action script to trigger cellular failover
cat > "$ROOTFS/etc/wpa_supplicant/wpa_cli.sh" << 'ACTION'
#!/bin/sh
# Called by wpa_cli -a: $1=interface, $2=event
IFACE="$1"
EVENT="$2"

case "$EVENT" in
    CONNECTED)
        logger -t wpa-action "$IFACE: connected, starting DHCP"
        kill $(cat /run/udhcpc.$IFACE.pid 2>/dev/null) 2>/dev/null
        udhcpc -i "$IFACE" -b -R -p /run/udhcpc.$IFACE.pid

        # WiFi is back — tear down cellular to save data
        logger -t wpa-action "$IFACE: WiFi up, tearing down cellular data"
        cell-data down 2>&1 | logger -t cell-data
        ;;
    DISCONNECTED)
        logger -t wpa-action "$IFACE: disconnected, releasing DHCP"
        kill $(cat /run/udhcpc.$IFACE.pid 2>/dev/null) 2>/dev/null
        ip addr flush dev "$IFACE" 2>/dev/null

        # WiFi lost — bring up cellular as fallback
        logger -t wpa-action "$IFACE: WiFi down, activating cellular data"
        cell-data up 2>&1 | logger -t cell-data
        ;;
esac
ACTION
chmod 755 "$ROOTFS/etc/wpa_supplicant/wpa_cli.sh"

# Connectivity watchdog: catches silent WiFi drops that don't trigger
# wpa_supplicant events (e.g., AP unreachable but still associated).
# Runs every 60s, pings the gateway. If WiFi gateway is unreachable
# for 3 consecutive checks, brings up cellular.
cat > "$ROOTFS/etc/init.d/net-watchdog" << 'WATCHDOG'
#!/sbin/openrc-run

description="Network connectivity watchdog (WiFi/cellular failover)"
command="/usr/sbin/net-watchdog"
command_background=true
pidfile="/run/net-watchdog.pid"

depend() {
    after wifi modem
}
WATCHDOG
chmod 755 "$ROOTFS/etc/init.d/net-watchdog"

cat > "$ROOTFS/usr/sbin/net-watchdog" << 'NW'
#!/bin/sh
# net-watchdog: periodic connectivity check for WiFi/cellular failover
# If WiFi gateway is unreachable for FAIL_THRESHOLD consecutive checks,
# bring up cellular. When WiFi recovers, tear it down.

INTERVAL=60
FAIL_THRESHOLD=3
PING_TARGET=""  # auto-detect from default route
fail_count=0

log() { logger -t net-watchdog "$@"; }

while true; do
    sleep "$INTERVAL"

    # Find WiFi gateway
    gw=$(ip route show dev wlan0 2>/dev/null | sed -n 's/default via \([^ ]*\).*/\1/p')

    if [ -n "$gw" ]; then
        # WiFi route exists — check if gateway is reachable
        if ping -c1 -W3 "$gw" >/dev/null 2>&1; then
            # WiFi is working
            if [ $fail_count -gt 0 ]; then
                log "WiFi recovered (was failing for $fail_count checks)"
                fail_count=0
            fi
            # If cellular is up but WiFi is working, tear it down
            if [ -f /run/cell-data.state ]; then
                log "WiFi up, tearing down cellular"
                cell-data down 2>&1 | logger -t cell-data
            fi
        else
            fail_count=$((fail_count + 1))
            log "WiFi gateway $gw unreachable ($fail_count/$FAIL_THRESHOLD)"
            if [ $fail_count -ge $FAIL_THRESHOLD ] && [ ! -f /run/cell-data.state ]; then
                log "WiFi failed $FAIL_THRESHOLD checks, activating cellular"
                cell-data up 2>&1 | logger -t cell-data
            fi
        fi
    else
        # No WiFi default route at all
        if [ ! -f /run/cell-data.state ]; then
            log "no WiFi route, activating cellular"
            cell-data up 2>&1 | logger -t cell-data
        fi
    fi
done
NW
chmod 755 "$ROOTFS/usr/sbin/net-watchdog"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add net-watchdog default
'
echo "  net-failover installed (wpa_cli hooks + watchdog)"
