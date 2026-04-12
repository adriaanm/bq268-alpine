#!/bin/sh
echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null
. /etc/bq268.conf 2>/dev/null
echo "${BACKLIGHT_BRIGHTNESS:-20}" > /sys/class/leds/lcd-bl/brightness 2>/dev/null
# All 4 Cortex-A7 cores share a single clock domain — cpu0 applies to all
echo ondemand > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
echo "on" > /run/screen.state
touch /run/screen.activity
