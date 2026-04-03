#!/bin/sh
# cell-data: bring up / tear down cellular data session
#
# Usage:
#   cell-data up    — start WDS data call, configure rmnet0 via DHCP
#   cell-data down  — stop WDS data call, flush rmnet0
#   cell-data status — show current state
#
# The modem must be registered (CS+PS attached) before calling 'up'.
# This script only manages the IP data session, not modem registration.

set -e

QMI_DEV="msmipc://0"
RMNET="rmnet0"
STATE_FILE="/run/cell-data.state"
WDS_HANDLE_FILE="/run/cell-data.wds-handle"
METRIC=700  # higher than WiFi (default ~300), so WiFi is always preferred

log() {
    logger -t cell-data "$@"
    echo "cell-data: $*"
}

do_up() {
    if [ -f "$STATE_FILE" ]; then
        log "already up (handle $(cat "$WDS_HANDLE_FILE" 2>/dev/null))"
        return 0
    fi

    # Check modem is registered
    if ! qmicli -d "$QMI_DEV" --nas-get-serving-system 2>&1 | grep -q "PS: 'attached'"; then
        log "error: modem PS not attached"
        return 1
    fi

    # Check rmnet interface exists
    if [ ! -d "/sys/class/net/$RMNET" ]; then
        log "error: $RMNET interface not found (BAM DMUX not loaded?)"
        return 1
    fi

    log "starting data call..."

    # Start WDS network — try common APNs
    local result
    result=$(qmicli -d "$QMI_DEV" --wds-start-network="apn=internet,ip-type=4" \
        --client-no-release-cid 2>&1) || true

    local handle
    handle=$(echo "$result" | sed -n 's/.*Packet data handle: .//;s/..$//p')
    local cid
    cid=$(echo "$result" | sed -n "s/.*CID.*'\([0-9]*\)'.*/\1/p")

    if [ -z "$handle" ]; then
        log "error: WDS start-network failed: $result"
        return 1
    fi

    echo "$handle" > "$WDS_HANDLE_FILE"
    echo "$cid" > "/run/cell-data.cid"
    log "WDS connected (handle=$handle, cid=$cid)"

    # Get IP settings from WDS
    local settings
    settings=$(qmicli -d "$QMI_DEV" --wds-get-current-settings \
        --client-cid="$cid" --client-no-release-cid 2>&1) || true

    local ip gw dns1 dns2 mtu
    ip=$(echo "$settings" | sed -n "s/.*IPv4 address: //p")
    gw=$(echo "$settings" | sed -n "s/.*IPv4 gateway address: //p")
    dns1=$(echo "$settings" | sed -n "s/.*IPv4 primary DNS: //p")
    dns2=$(echo "$settings" | sed -n "s/.*IPv4 secondary DNS: //p")
    mtu=$(echo "$settings" | sed -n "s/.*MTU: //p")

    if [ -z "$ip" ]; then
        log "warning: no IP from WDS, trying udhcpc on $RMNET"
        ip link set "$RMNET" up
        udhcpc -i "$RMNET" -n -q -t 5 -p /run/udhcpc.$RMNET.pid 2>&1 | logger -t cell-data
    else
        log "configuring $RMNET: $ip via $gw"
        ip link set "$RMNET" up
        ip addr flush dev "$RMNET" 2>/dev/null
        ip addr add "$ip/32" dev "$RMNET"
        [ -n "$mtu" ] && ip link set "$RMNET" mtu "$mtu"
        ip route add default via "$gw" dev "$RMNET" metric "$METRIC" 2>/dev/null || \
            ip route replace default via "$gw" dev "$RMNET" metric "$METRIC"

        # Add cellular DNS to resolv.conf (below WiFi entries)
        if [ -n "$dns1" ]; then
            {
                [ -n "$dns1" ] && echo "nameserver $dns1  # cell-data"
                [ -n "$dns2" ] && echo "nameserver $dns2  # cell-data"
            } >> /etc/resolv.conf
        fi
    fi

    echo "up" > "$STATE_FILE"
    log "data path up on $RMNET ($ip)"
}

do_down() {
    if [ ! -f "$STATE_FILE" ]; then
        log "already down"
        return 0
    fi

    log "tearing down data call..."

    # Kill udhcpc if running
    kill $(cat /run/udhcpc.$RMNET.pid 2>/dev/null) 2>/dev/null || true

    # Stop WDS
    local handle cid
    handle=$(cat "$WDS_HANDLE_FILE" 2>/dev/null)
    cid=$(cat "/run/cell-data.cid" 2>/dev/null)

    if [ -n "$handle" ] && [ -n "$cid" ]; then
        qmicli -d "$QMI_DEV" --wds-stop-network="$handle" \
            --client-cid="$cid" 2>&1 | logger -t cell-data || true
    fi

    # Flush interface
    ip addr flush dev "$RMNET" 2>/dev/null || true
    ip link set "$RMNET" down 2>/dev/null || true
    ip route del default dev "$RMNET" 2>/dev/null || true

    # Remove cellular DNS entries
    sed -i '/# cell-data$/d' /etc/resolv.conf 2>/dev/null || true

    rm -f "$STATE_FILE" "$WDS_HANDLE_FILE" "/run/cell-data.cid"
    log "data path down"
}

do_status() {
    if [ -f "$STATE_FILE" ]; then
        echo "cell-data: up"
        echo "  WDS handle: $(cat "$WDS_HANDLE_FILE" 2>/dev/null || echo unknown)"
        ip addr show "$RMNET" 2>/dev/null | grep inet
        ip route show dev "$RMNET" 2>/dev/null
    else
        echo "cell-data: down"
    fi

    # Modem registration
    qmicli -d "$QMI_DEV" --nas-get-serving-system 2>&1 | \
        grep -E "Registration|CS:|PS:|Current PLMN"
}

case "${1:-status}" in
    up)     do_up ;;
    down)   do_down ;;
    status) do_status ;;
    *)      echo "Usage: cell-data {up|down|status}" >&2; exit 1 ;;
esac
