# Battery monitor + graceful shutdown
echo "--- Setting up battery monitor ---"

cat > "$ROOTFS/usr/local/bin/graceful-shutdown.sh" << 'SHUTDOWN'
#!/bin/sh
# Graceful shutdown — log reason, signal via LED, power off
REASON="${1:-unknown}"
logger -t shutdown "Graceful shutdown: $REASON"
echo 1 > /sys/class/leds/red/brightness 2>/dev/null
echo 0 > /sys/class/leds/green/brightness 2>/dev/null
sync
poweroff
SHUTDOWN
chmod 755 "$ROOTFS/usr/local/bin/graceful-shutdown.sh"

cat > "$ROOTFS/usr/local/bin/battmon.sh" << 'BATTMON'
#!/bin/sh
# Battery monitor daemon — polls BMS sysfs, manages LEDs, shuts down on critical
. /etc/bq268.conf 2>/dev/null
CRITICAL=${BATTERY_CRITICAL:-5}
LOW=${BATTERY_LOW:-15}
POLL=60
BATT="/sys/class/power_supply/battery"
RED="/sys/class/leds/red/brightness"
GREEN="/sys/class/leds/green/brightness"
STATE_FILE="/run/battery.state"
PREV_STATE=""

while true; do
    capacity=$(cat "$BATT/capacity" 2>/dev/null || echo "-1")
    status=$(cat "$BATT/status" 2>/dev/null || echo "Unknown")
    voltage=$(cat "$BATT/voltage_now" 2>/dev/null || echo "0")

    # Determine state
    if [ "$capacity" = "-1" ]; then
        state="unknown"
    elif [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
        state="charging"
    elif [ "$capacity" -le "$CRITICAL" ]; then
        state="critical"
    elif [ "$capacity" -le "$LOW" ]; then
        state="low"
    else
        state="normal"
    fi

    # Write state for other scripts/app to read
    echo "$state $capacity $status $voltage" > "$STATE_FILE"

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
BATTMON
chmod 755 "$ROOTFS/usr/local/bin/battmon.sh"

cat > "$ROOTFS/etc/init.d/battmon" << 'BATTMONINIT'
#!/sbin/openrc-run

description="Battery monitor"
command="/usr/local/bin/battmon.sh"
command_background=true
pidfile="/run/battmon.pid"

depend() {
    after modules
}
BATTMONINIT
chmod 755 "$ROOTFS/etc/init.d/battmon"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add battmon default
'
