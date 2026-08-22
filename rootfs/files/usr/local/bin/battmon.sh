#!/bin/sh
# Battery monitor daemon — polls BMS sysfs, manages LEDs, shuts down on critical
. /etc/bq268.conf 2>/dev/null
CRITICAL=${BATTERY_CRITICAL:-5}
LOW=${BATTERY_LOW:-15}
VMIN=${BATTERY_VMIN:-3400000}  # voltage floor (uV) — shutdown below this
POLL=60
BATT="/sys/class/power_supply/battery"
USB="/sys/class/power_supply/usb"
RED="/sys/class/leds/red/brightness"
GREEN="/sys/class/leds/green/brightness"
STATE_FILE="/run/battery.state"
VLOG="/tmp/battery.log"
VLOG_INTERVAL=10  # log every N polls (10 × 60s = 10min)
PLOG="/data/log/battmon.log"   # persistent state-change log (survives poweroff)
PLOG_MAX=65536                 # rotate to .old past 64 KB
PREV_STATE=""
TICK=0

# --- charge-nanny state (docs/planning/charging-telemetry.md §3) ---
ANOM_LOG="/data/log/charge-anomaly.log"
ANOM=0      # consecutive polls with usb online but not charging
KICKED=0    # FSM kick done this episode
SNAPPED=0   # register snapshot taken this episode
DCP_SEEN=0  # latched: a DCP (wall charger) BC1.2 detection seen this boot

# Append a line to the persistent log (best-effort; /data may not be up
# in early boot or on a degraded system — never let this kill the loop).
plog() {
    logger -t battmon "$*"
    [ -d /data/log ] || return 0
    if [ "$(wc -c < "$PLOG" 2>/dev/null || echo 0)" -gt "$PLOG_MAX" ]; then
        mv -f "$PLOG" "$PLOG.old" 2>/dev/null
    fi
    echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ') $*" >> "$PLOG" 2>/dev/null
}

# One decoded LBC register snapshot — the same debugfs-regmap reads as
# `just chg-status`. Written to stdout; caller appends to $ANOM_LOG.
chg_snapshot() {
    grep -q " debugfs " /proc/mounts || mount -t debugfs none /sys/kernel/debug 2>/dev/null
    R=/sys/kernel/debug/regmap/spmi0-00
    echo "=== anomaly $(date -u '+%Y-%m-%dT%H:%M:%SZ') capacity=$capacity% status=$status voltage=${voltage}uV usb_ma=$(cat "$USB/current_max" 2>/dev/null || echo '?')"
    grep -E "fastchg|usbin_valid|chg_gone" /proc/interrupts 2>/dev/null || echo "(no LBC IRQ rows)"
    for spec in \
        "0x1009 CHGR_CHG_STATUS(bit3=VINMIN_loop)" \
        "0x1010 CHGR_RT_STS(bit5=FAST_CHG_ON)" \
        "0x1044 CHGR_IBAT_MAX(90mA_steps)" \
        "0x1045 CHGR_IBAT_SAFE(90mA_steps)" \
        "0x1049 CHGR_CHG_CTRL(0x90=enabled)" \
        "0x1052 CHGR_VBAT_WEAK" \
        "0x10EE CHGR_COMP_OVR1(0x02=charging-allowed)" \
        "0x1310 USB_RT_STS(0x03=VBUS_valid)"; do
        addr=${spec%% *}
        label=${spec#* }
        if echo "$addr" > "$R/address" 2>/dev/null; then
            echo "$addr = 0x$(head -1 "$R/data" 2>/dev/null | awk '{print $NF}')  $label"
        else
            echo "$addr = ??  $label"
        fi
    done
}

while true; do
    capacity=$(cat "$BATT/capacity" 2>/dev/null || echo "-1")
    status=$(cat "$BATT/status" 2>/dev/null || echo "Unknown")
    voltage=$(cat "$BATT/voltage_now" 2>/dev/null || echo "0")

    # Determine state
    if [ "$capacity" = "-1" ]; then
        state="unknown"
    elif [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
        state="charging"
    elif [ "$voltage" -gt 0 ] && [ "$voltage" -lt "$VMIN" ]; then
        # Voltage floor — catches low battery even when SOC reads 0
        state="critical"
    elif [ "$capacity" -gt 0 ] && [ "$capacity" -le "$CRITICAL" ]; then
        state="critical"
    elif [ "$capacity" -gt 0 ] && [ "$capacity" -le "$LOW" ]; then
        state="low"
    else
        state="normal"
    fi

    # Write state for other scripts/app to read
    echo "$state $capacity $status $voltage" > "$STATE_FILE"

    # Periodic voltage log (CSV in tmpfs)
    TICK=$((TICK + 1))
    if [ "$TICK" -ge "$VLOG_INTERVAL" ]; then
        TICK=0
        echo "$(date '+%Y-%m-%d %H:%M'),${capacity},${voltage},${status}" >> "$VLOG"
    fi

    # Log on state change
    if [ "$state" != "$PREV_STATE" ]; then
        plog "state=$state capacity=$capacity% status=$status voltage=${voltage}uV"
        PREV_STATE="$state"
    fi

    # --- charge-nanny (spec §3): docked but not charging ≥3 polls (~3 min) ---
    usb_online=$(cat "$USB/online" 2>/dev/null || echo 0)
    if [ "$usb_online" = "1" ] && [ "$status" != "Charging" ] && [ "$status" != "Full" ]; then
        ANOM=$((ANOM + 1))
        if [ "$ANOM" -ge 3 ]; then
            # (a) BC1.2 SDP-misdetect recovery: only if a DCP ("wall
            # charger") detection has been seen this boot — NEVER raise
            # the limit if only SDP was ever seen (real computer port).
            if [ "$DCP_SEEN" != "1" ] && dmesg | grep -q "BC1\.2: DCP"; then
                DCP_SEEN=1
            fi
            cur=$(cat "$USB/current_max" 2>/dev/null || echo 9999999)
            if [ "$DCP_SEEN" = "1" ] && [ "$cur" -le 100000 ] 2>/dev/null; then
                echo 1500000 > "$USB/current_max" 2>/dev/null
                plog "nanny: restored usb/current_max to 1500000 (was $cur, DCP seen this boot)"
            fi
            if [ "$KICKED" != "1" ]; then
                # (b) one FSM kick per anomaly episode
                KICKED=1
                echo 0 > "$BATT/charging_enabled" 2>/dev/null
                echo 1 > "$BATT/charging_enabled" 2>/dev/null
                plog "nanny: charging_enabled toggled 0->1 (anomaly: usb online, status=$status for ${ANOM} polls)"
            elif [ "$SNAPPED" != "1" ]; then
                # (c) still not charging a poll after the kick — one
                # decoded register snapshot per episode
                SNAPPED=1
                if [ -d /data/log ]; then
                    chg_snapshot >> "$ANOM_LOG" 2>/dev/null
                fi
                plog "nanny: still not charging after kick — snapshot appended to $ANOM_LOG"
            fi
        fi
    else
        # charging resumed or usb offline — episode over
        if [ "$ANOM" -ge 3 ]; then
            plog "nanny: anomaly episode ended (status=$status usb_online=$usb_online)"
        fi
        ANOM=0
        KICKED=0
        SNAPPED=0
    fi

    # LED + action
    case "$state" in
        charging)
            echo 1 > "$GREEN" 2>/dev/null
            echo 0 > "$RED" 2>/dev/null
            ;;
        critical)
            echo 1 > "$RED" 2>/dev/null
            echo 0 > "$GREEN" 2>/dev/null
            /usr/local/bin/graceful-shutdown.sh "battery critical ($capacity%)"
            exit 0
            ;;
        low)
            # Blink red: on for this cycle, off next cycle
            if [ -f /run/battmon.blink ]; then
                echo 0 > "$RED" 2>/dev/null
                rm -f /run/battmon.blink
            else
                echo 1 > "$RED" 2>/dev/null
                touch /run/battmon.blink
            fi
            echo 0 > "$GREEN" 2>/dev/null
            ;;
        normal)
            echo 0 > "$RED" 2>/dev/null
            echo 0 > "$GREEN" 2>/dev/null
            ;;
    esac

    sleep "$POLL"
done
