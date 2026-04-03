#!/bin/sh
# cell-data: manage cellular data session and modem power state
#
# Usage:
#   cell-data up      — wake modem, PS attach, start WDS, configure rmnet0
#   cell-data down    — stop WDS, flush rmnet0 (modem stays online)
#   cell-data status  — show current state
#   cell-data sleep   — put modem in low-power mode (RF off, ~5-10mA)
#   cell-data wake    — bring modem back online from low-power
#   cell-data force   — force both WiFi+cellular on, disable watchdog failover
#   cell-data auto    — re-enable normal failover (undo force)
#
# Force mode is for debugging: keeps both interfaces up and prevents
# the watchdog/wpa_cli hooks from tearing down cellular. Touch
# /run/cell-data.force to enable, remove to disable.

set -e

QMI_DEV="msmipc://0"
RMNET="rmnet0"
STATE_FILE="/run/cell-data.state"
WDS_HANDLE_FILE="/run/cell-data.wds-handle"
FORCE_FILE="/run/cell-data.force"
METRIC=700  # higher than WiFi (default ~300), so WiFi is always preferred

log() {
    logger -t cell-data "$@"
    echo "cell-data: $*"
}

# Get current modem operating mode
modem_mode() {
    qmicli -d "$QMI_DEV" --dms-get-operating-mode 2>&1 | \
        sed -n "s/.*Mode: '\([^']*\)'.*/\1/p"
}

do_wake() {
    local mode
    mode=$(modem_mode)
    case "$mode" in
        online)
            log "modem already online"
            return 0 ;;
        low-power|persistent-low-power)
            log "waking modem from $mode..."
            qmicli -d "$QMI_DEV" --dms-set-operating-mode=online 2>&1 | logger -t cell-data
            # Wait for PS attach (up to 30s)
            local w=0
            while [ $w -lt 60 ]; do
                if qmicli -d "$QMI_DEV" --nas-get-serving-system 2>&1 | grep -q "PS: 'attached'"; then
                    log "modem online, PS attached"
                    return 0
                fi
                sleep 0.5
                w=$((w + 1))
            done
            log "warning: modem online but PS not attached after 30s"
            return 0 ;;
        *)
            log "modem in unexpected mode: $mode"
            qmicli -d "$QMI_DEV" --dms-set-operating-mode=online 2>&1 | logger -t cell-data
            return 0 ;;
    esac
}

do_sleep() {
    # Don't sleep if data session is active
    if [ -f "$STATE_FILE" ]; then
        log "data session active, not sleeping (call 'down' first)"
        return 1
    fi

    local mode
    mode=$(modem_mode)
    if [ "$mode" = "low-power" ] || [ "$mode" = "persistent-low-power" ]; then
        log "modem already in $mode"
        return 0
    fi

    log "putting modem to low-power mode..."
    qmicli -d "$QMI_DEV" --dms-set-operating-mode=low-power 2>&1 | logger -t cell-data
    log "modem sleeping (RF off)"
}

do_up() {
    if [ -f "$STATE_FILE" ]; then
        log "already up (handle $(cat "$WDS_HANDLE_FILE" 2>/dev/null))"
        return 0
    fi

    # Wake modem if sleeping
    do_wake

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

    # Start WDS network
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
    # In force mode, refuse to tear down
    if [ -f "$FORCE_FILE" ]; then
        log "force mode active, ignoring down (use 'cell-data auto' to disable)"
        return 0
    fi

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

do_force() {
    touch "$FORCE_FILE"
    log "force mode ON — both interfaces stay up, failover disabled"
    log "  use 'cell-data auto' to re-enable failover"
    # Bring up cellular if not already
    if [ ! -f "$STATE_FILE" ]; then
        do_up
    fi
}

do_auto() {
    rm -f "$FORCE_FILE"
    log "force mode OFF — normal failover resumed"
}

do_status() {
    echo "=== cell-data status ==="
    if [ -f "$FORCE_FILE" ]; then
        echo "  mode: FORCE (both interfaces pinned on)"
    else
        echo "  mode: auto (WiFi primary, cellular failover)"
    fi

    if [ -f "$STATE_FILE" ]; then
        echo "  data: up"
        echo "  WDS handle: $(cat "$WDS_HANDLE_FILE" 2>/dev/null || echo unknown)"
        ip addr show "$RMNET" 2>/dev/null | grep -w inet | sed 's/^/  /'
        ip route show dev "$RMNET" 2>/dev/null | sed 's/^/  route: /'
    else
        echo "  data: down"
    fi

    echo "  modem: $(modem_mode)"

    # Registration
    qmicli -d "$QMI_DEV" --nas-get-serving-system 2>&1 | \
        grep -E "Registration|CS:|PS:|Current PLMN" | sed 's/^[[:space:]]*/  /'
}

case "${1:-status}" in
    up)     do_up ;;
    down)   do_down ;;
    sleep)  do_sleep ;;
    wake)   do_wake ;;
    force)  do_force ;;
    auto)   do_auto ;;
    status) do_status ;;
    *)      echo "Usage: cell-data {up|down|sleep|wake|force|auto|status}" >&2; exit 1 ;;
esac
