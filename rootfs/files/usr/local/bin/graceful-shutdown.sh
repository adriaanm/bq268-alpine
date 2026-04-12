#!/bin/sh
# Graceful shutdown — log reason, signal via LED, power off
REASON="${1:-unknown}"
logger -t shutdown "Graceful shutdown: $REASON"
echo 1 > /sys/class/leds/red/brightness 2>/dev/null
echo 0 > /sys/class/leds/green/brightness 2>/dev/null
sync
poweroff
