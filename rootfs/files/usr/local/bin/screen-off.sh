#!/bin/sh
echo 1 > /sys/class/graphics/fb0/blank 2>/dev/null
echo 0 > /sys/class/leds/lcd-bl/brightness 2>/dev/null
# All 4 Cortex-A7 cores share a single clock domain — cpu0 applies to all
echo powersave > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null
echo "off" > /run/screen.state
