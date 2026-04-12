#!/bin/sh
# Battery monitor daemon — polls BMS sysfs, manages LEDs, shuts down on critical
. /etc/bq268.conf 2>/dev/null
CRITICAL=${BATTERY_CRITICAL:-5}
LOW=${BATTERY_LOW:-15}
VMIN=${BATTERY_VMIN:-3400000}  # voltage floor (uV) — shutdown below this
POLL=60
BATT="/sys/class/power_supply/battery"
RED="/sys/class/leds/red/brightness"
GREEN="/sys/class/leds/green/brightness"
STATE_FILE="/run/battery.state"
VLOG="/tmp/battery.log"
VLOG_INTERVAL=10  # log every N polls (10 × 60s = 10min)
PREV_STATE=""
TICK=0

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
        logger -t battmon "state=$state capacity=$capacity% status=$status voltage=${voltage}uV"
        PREV_STATE="$state"
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
