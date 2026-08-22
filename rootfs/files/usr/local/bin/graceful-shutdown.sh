#!/bin/sh
# Graceful shutdown — log reason, signal via LED, power off
REASON="${1:-unknown}"
logger -t shutdown "Graceful shutdown: $REASON"

# Persist the attribution (docs/planning/charging-telemetry.md §5): syslog
# is tmpfs, so the reason dies with the rail. Append to the same file the
# per-boot PMIC PON/POFF reasons land in — the next boot's entry then sits
# directly under the shutdown that caused it. Strictly best-effort: a
# missing /data mount or any failure here must never block the poweroff.
{
    B=/sys/class/power_supply/battery
    U=/sys/class/power_supply/usb
    if [ -d /data/log ]; then
        echo "--- poweroff $(date -u '+%Y-%m-%dT%H:%M:%SZ') reason=\"$REASON\"" \
             "capacity=$(cat $B/capacity 2>/dev/null || echo '?')%" \
             "voltage=$(cat $B/voltage_now 2>/dev/null || echo '?')uV" \
             "usb_online=$(cat $U/online 2>/dev/null || echo '?')" \
             >> /data/log/boot-reasons.log
        sync
    fi
} 2>/dev/null || true

echo 1 > /sys/class/leds/red/brightness 2>/dev/null
echo 0 > /sys/class/leds/green/brightness 2>/dev/null
sync
poweroff
