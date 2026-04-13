#!/bin/sh
# cell-data: manage cellular data session and modem power state
#
# Data path is PPP over SMD (/dev/smd7). BAM DMUX / rmnet is unused on
# this firmware — see docs/modem_data.md.
#
# Usage:
#   cell-data up      — wake modem, enforce LTE prefs, PS attach, pppd up
#   cell-data down    — stop pppd (modem stays online)
#   cell-data status  — show current state
#   cell-data sleep   — put modem in low-power mode (RF off, ~5-10 mA)
#   cell-data wake    — bring modem online, enforce prefs, wait for PS attach
#   cell-data force   — force both WiFi+cellular on, disable watchdog failover
#   cell-data auto    — re-enable normal failover (undo force)
#
# Force mode is for debugging: keeps both interfaces up and prevents
# the watchdog/wpa_cli hooks from tearing down cellular. Touch
# /run/cell-data.force to enable, remove to disable.

set -e

QMI_DEV="msmipc://0"
PPP_IF="ppp0"
PPP_PEER="cellular"
STATE_FILE="/run/cell-data.state"
FORCE_FILE="/run/cell-data.force"
CELL_LOG="/var/log/cellular.log"

# Bounded budgets — total wake+attach must fit in ~2 minutes.
WAKE_BUDGET=20          # seconds to get modem out of transient states
ATTACH_BUDGET=90        # seconds to wait for PS attach after online
PPP_BUDGET=30           # seconds for pppd to bring ppp0 up with an IP
RESET_SETTLE=10         # seconds to wait after dms reset before polling

log() {
    logger -t cell-data "$@"
    echo "cell-data: $*"
}

modem_mode() {
    qmicli -d "$QMI_DEV" --dms-get-operating-mode 2>&1 | \
        sed -n "s/.*Mode: '\([^']*\)'.*/\1/p"
}

# Ensure LTE-only + automatic network selection. Idempotent: re-applies
# only when current prefs differ (avoids the "replug your device" reset
# when already correct).
ensure_lte_prefs() {
    local prefs
    prefs=$(qmicli -d "$QMI_DEV" --nas-get-system-selection-preference 2>&1 || true)
    if echo "$prefs" | grep -q "Mode preference: 'lte'" && \
       echo "$prefs" | grep -q "Network selection preference: 'automatic'"; then
        return 0
    fi
    log "enforcing LTE-only, automatic network selection"
    qmicli -d "$QMI_DEV" --nas-set-system-selection-preference='lte,automatic' 2>&1 \
        | logger -t cell-data || true
    # Setting is non-volatile across reboots but needs a modem reset to
    # take effect. Caller should issue a reset and wait.
    return 1
}

# Drive the modem into 'online' from whatever state it's in. Handles:
#   online                 → no-op
#   low-power / offline    → set online
#   shutting-down          → wait (boot transient)
#   persistent-low-power   → set online
#   anything else / stuck  → reset + settle
# Bounded by WAKE_BUDGET. Returns 1 if we can't reach online.
set_online() {
    local start now mode tried_reset=0
    start=$(date +%s)
    while :; do
        mode=$(modem_mode)
        case "$mode" in
            online)
                return 0 ;;
            low-power|persistent-low-power|offline)
                log "modem $mode → online"
                qmicli -d "$QMI_DEV" --dms-set-operating-mode=online 2>&1 \
                    | logger -t cell-data || true
                ;;
            shutting-down|resetting)
                : ;;  # transient — just wait
            "")
                log "modem not responding"
                ;;
            *)
                log "modem in unexpected mode '$mode'"
                ;;
        esac
        sleep 2
        now=$(date +%s)
        if [ $((now - start)) -ge "$WAKE_BUDGET" ]; then
            if [ "$tried_reset" -eq 0 ]; then
                log "wake budget (${WAKE_BUDGET}s) exhausted in mode '$mode', escalating to reset"
                qmicli -d "$QMI_DEV" --dms-set-operating-mode=reset 2>&1 \
                    | logger -t cell-data || true
                sleep "$RESET_SETTLE"
                tried_reset=1
                start=$(date +%s)
                continue
            fi
            log "error: modem stuck in '$mode' after reset attempt"
            return 1
        fi
    done
}

wait_ps_attached() {
    local budget="${1:-$ATTACH_BUDGET}" elapsed=0 s
    while [ $elapsed -lt "$budget" ]; do
        s=$(qmicli -d "$QMI_DEV" --nas-get-serving-system 2>&1 || true)
        if echo "$s" | grep -q "PS: 'attached'"; then
            return 0
        fi
        sleep 3
        elapsed=$((elapsed + 3))
    done
    return 1
}

# Log serving PLMN + roaming status to /var/log/cellular.log and syslog.
# Pulled after a successful attach so data-byte correlation is possible.
log_serving() {
    local s mcc mnc rat roaming h hmcc hmnc
    s=$(qmicli -d "$QMI_DEV" --nas-get-serving-system 2>&1 || true)
    mcc=$(echo "$s" | awk -F"'" '/MCC:/ {print $2; exit}')
    mnc=$(echo "$s" | awk -F"'" '/MNC:/ {print $2; exit}')
    rat=$(echo "$s" | awk -F"'" '/Radio interfaces/{getline; print $2; exit}')
    roaming=$(echo "$s" | awk -F"'" '/Roaming status:/ {print $2; exit}')
    h=$(qmicli -d "$QMI_DEV" --nas-get-home-network 2>&1 || true)
    hmcc=$(echo "$h" | awk -F"'" '/MCC:/ {print $2; exit}')
    hmnc=$(echo "$h" | awk -F"'" '/MNC:/ {print $2; exit}')

    local roaming_bool=false
    if [ "$mcc" != "$hmcc" ] || [ "$mnc" != "$hmnc" ]; then
        roaming_bool=true
    fi

    log "serving plmn=$mcc/$mnc rat=$rat roaming=$roaming_bool (home=$hmcc/$hmnc)"
    mkdir -p "$(dirname "$CELL_LOG")"
    printf '%s plmn=%s/%s rat=%s roaming=%s home=%s/%s qmi_roaming=%s\n' \
        "$(date -Iseconds)" "$mcc" "$mnc" "$rat" "$roaming_bool" \
        "$hmcc" "$hmnc" "$roaming" >> "$CELL_LOG"
}

do_wake() {
    # Prefs are persistent in modem NV, so ensure_lte_prefs is usually a
    # no-op and does NOT force a reset. If it did change prefs, set_online
    # + reset escalation below will pick up the new config.
    ensure_lte_prefs || true

    set_online || return 1

    if wait_ps_attached "$ATTACH_BUDGET"; then
        log_serving
        return 0
    fi

    log "warning: PS not attached after ${ATTACH_BUDGET}s — check coverage / roaming"
    return 2
}

do_sleep() {
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

ppp_pid() {
    pgrep -f "pppd call $PPP_PEER" 2>/dev/null | head -1
}

do_up() {
    if [ -f "$STATE_FILE" ] && [ -n "$(ppp_pid)" ]; then
        log "already up (pppd pid $(ppp_pid))"
        return 0
    fi
    # Stale state from crashed prior run — clear it.
    rm -f "$STATE_FILE"

    do_wake || {
        log "error: do_wake failed, aborting up"
        return 1
    }

    log "starting pppd call $PPP_PEER..."
    /usr/sbin/pppd call "$PPP_PEER" 2>&1 | logger -t cell-data &

    # Wait for ppp0 to exist with an IP
    local elapsed=0
    while [ $elapsed -lt "$PPP_BUDGET" ]; do
        if ip -4 addr show "$PPP_IF" 2>/dev/null | grep -q 'inet '; then
            echo "up" > "$STATE_FILE"
            local ip
            ip=$(ip -4 addr show "$PPP_IF" | awk '/inet /{print $2; exit}')
            log "data path up on $PPP_IF ($ip)"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done
    log "error: $PPP_IF did not come up within ${PPP_BUDGET}s"
    # Kill whatever pppd we started so we don't leak it
    local p; p=$(ppp_pid)
    [ -n "$p" ] && kill "$p" 2>/dev/null || true
    return 1
}

do_down() {
    if [ -f "$FORCE_FILE" ]; then
        log "force mode active, ignoring down (use 'cell-data auto' to disable)"
        return 0
    fi

    local p; p=$(ppp_pid)
    if [ -z "$p" ] && [ ! -f "$STATE_FILE" ]; then
        log "already down"
        return 0
    fi

    log "tearing down pppd..."
    if [ -n "$p" ]; then
        kill "$p" 2>/dev/null || true
        local w=0
        while [ $w -lt 10 ] && kill -0 "$p" 2>/dev/null; do
            sleep 1; w=$((w+1))
        done
        kill -9 "$p" 2>/dev/null || true
    fi
    rm -f "$STATE_FILE"
    log "data path down"
}

do_force() {
    touch "$FORCE_FILE"
    log "force mode ON — both interfaces stay up, failover disabled"
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

    local p; p=$(ppp_pid)
    if [ -n "$p" ]; then
        echo "  data: up (pppd pid $p)"
        ip -4 addr show "$PPP_IF" 2>/dev/null | grep -w inet | sed 's/^/  /'
        ip route show dev "$PPP_IF" 2>/dev/null | sed 's/^/  route: /'
    else
        echo "  data: down"
    fi

    echo "  modem: $(modem_mode)"
    qmicli -d "$QMI_DEV" --nas-get-system-selection-preference 2>&1 | \
        grep -E "Mode preference|Network selection|Acquisition order" | sed 's/^[[:space:]]*/  /'
    qmicli -d "$QMI_DEV" --nas-get-serving-system 2>&1 | \
        grep -E "Registration|CS:|PS:|Roaming status|PLMN" | sed 's/^[[:space:]]*/  /'
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
