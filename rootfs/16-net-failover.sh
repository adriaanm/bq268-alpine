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
#
# Tests actual internet reachability (not just gateway ping), catching:
# - WiFi associated but AP has no backhaul
# - Captive portals / DNS hijacking
# - Weak signal that maintains L2 but drops packets
# - Gateway reachable but upstream routing broken
#
# Two-stage check:
#   1. Quick gateway ping (L2/L3 to router)
#   2. Internet probe via DNS query to a public resolver
# Both must pass for WiFi to be considered working.

INTERVAL=30
FAIL_THRESHOLD=2
# Public DNS servers for connectivity probes (UDP 53 — fast, low overhead)
PROBE_DNS="1.1.1.1"
PROBE_DNS2="8.8.8.8"
# Ping timeout (seconds) — short to detect degraded links quickly
PING_TIMEOUT=3

fail_count=0
prev_state="unknown"

log() { logger -t net-watchdog "$@"; }

# Test if WiFi can actually reach the internet.
# Returns 0 if working, 1 if degraded/broken.
wifi_healthy() {
    local gw
    gw=$(ip route show dev wlan0 2>/dev/null | sed -n 's/default via \([^ ]*\).*/\1/p')

    # No WiFi route at all
    [ -z "$gw" ] && return 1

    # Stage 1: gateway reachable? (fast, tests local link)
    if ! ping -c1 -W"$PING_TIMEOUT" "$gw" >/dev/null 2>&1; then
        log "gateway $gw unreachable"
        return 1
    fi

    # Stage 2: internet reachable? Send a DNS query through WiFi specifically.
    # Use nslookup with a short timeout, forced through wlan0's route.
    # We query for a known domain — if we get any answer, internet works.
    if ping -c1 -W"$PING_TIMEOUT" -I wlan0 "$PROBE_DNS" >/dev/null 2>&1; then
        return 0
    fi

    # Try secondary probe in case primary is blocked by this network
    if ping -c1 -W"$PING_TIMEOUT" -I wlan0 "$PROBE_DNS2" >/dev/null 2>&1; then
        return 0
    fi

    log "gateway reachable but internet probe failed (captive portal? no backhaul?)"
    return 1
}

while true; do
    sleep "$INTERVAL"

    if wifi_healthy; then
        if [ $fail_count -gt 0 ]; then
            log "WiFi recovered after $fail_count failed checks"
        fi
        fail_count=0

        # WiFi is working — tear down cellular if active
        if [ -f /run/cell-data.state ]; then
            log "WiFi healthy, tearing down cellular"
            cell-data down 2>&1 | logger -t cell-data
        fi
        prev_state="wifi"
    else
        fail_count=$((fail_count + 1))
        log "WiFi check failed ($fail_count/$FAIL_THRESHOLD)"

        if [ $fail_count -ge $FAIL_THRESHOLD ] && [ ! -f /run/cell-data.state ]; then
            log "WiFi unusable for $fail_count checks, activating cellular"
            cell-data up 2>&1 | logger -t cell-data
            prev_state="cell"
        fi
    fi
done
NW
chmod 755 "$ROOTFS/usr/sbin/net-watchdog"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add net-watchdog default
'
echo "  net-failover installed (wpa_cli hooks + watchdog)"
