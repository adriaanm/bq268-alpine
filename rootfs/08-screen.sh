# Power toggle switch + screen management (keyd, screen-idle)
echo "--- Setting up power switch and screen management ---"

# Screen on/off scripts — use fb0 blank (also sleeps the display controller)
cat > "$ROOTFS/usr/local/bin/screen-off.sh" << 'SCREENOFF'
#!/bin/sh
echo 1 > /sys/class/graphics/fb0/blank 2>/dev/null
echo 0 > /sys/class/leds/lcd-bl/brightness 2>/dev/null
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo powersave > "$gov" 2>/dev/null
done
echo "off" > /run/screen.state
SCREENOFF
chmod 755 "$ROOTFS/usr/local/bin/screen-off.sh"

cat > "$ROOTFS/usr/local/bin/screen-on.sh" << 'SCREENON'
#!/bin/sh
echo 0 > /sys/class/graphics/fb0/blank 2>/dev/null
. /etc/bq268.conf 2>/dev/null
echo "${BACKLIGHT_BRIGHTNESS:-20}" > /sys/class/leds/lcd-bl/brightness 2>/dev/null
for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    echo ondemand > "$gov" 2>/dev/null
done
echo "on" > /run/screen.state
touch /run/screen.activity
SCREENON
chmod 755 "$ROOTFS/usr/local/bin/screen-on.sh"

# Screen wake on keypress (called by keyd for all key events)
cat > "$ROOTFS/usr/local/bin/screen-wake.sh" << 'SCREENWAKE'
#!/bin/sh
touch /run/screen.activity
if [ "$(cat /run/screen.state 2>/dev/null)" = "off" ]; then
    /usr/local/bin/screen-on.sh
fi
SCREENWAKE
chmod 755 "$ROOTFS/usr/local/bin/screen-wake.sh"

# Screen idle daemon — blanks screen after SCREEN_TIMEOUT seconds of inactivity
cat > "$ROOTFS/usr/local/bin/screen-idle.sh" << 'SCREENIDLE'
#!/bin/sh
echo "on" > /run/screen.state
touch /run/screen.activity

while true; do
    sleep 5
    . /etc/bq268.conf 2>/dev/null
    TIMEOUT="${SCREEN_TIMEOUT:-30}"
    [ "$TIMEOUT" -eq 0 ] && continue
    [ "$(cat /run/screen.state 2>/dev/null)" = "off" ] && continue
    now=$(date +%s)
    last=$(stat -c %Y /run/screen.activity 2>/dev/null || echo "$now")
    idle=$((now - last))
    if [ "$idle" -ge "$TIMEOUT" ]; then
        /usr/local/bin/screen-off.sh
    fi
done
SCREENIDLE
chmod 755 "$ROOTFS/usr/local/bin/screen-idle.sh"

# Key daemon — monitors input devices for SW_LID (power switch) and key wake
cat > "$ROOTFS/usr/local/bin/keyd.sh" << 'KEYD'
#!/bin/sh
# Key event daemon — uses evtest to monitor input devices.
#
# SW_LID (power toggle switch): 1 = screen off, 0 = screen on
# EV_KEY (any keypress): wake screen from blank

for dev in /dev/input/event*; do
    [ -e "$dev" ] || continue
    evtest "$dev" 2>/dev/null | while read -r line; do
        case "$line" in
            *"(EV_SW)"*"SW_LID"*"value 1")
                /usr/local/bin/screen-off.sh
                ;;
            *"(EV_SW)"*"SW_LID"*"value 0")
                /usr/local/bin/screen-on.sh
                ;;
            *"(EV_KEY)"*"value 1")
                /usr/local/bin/screen-wake.sh
                ;;
        esac
    done &
done

wait
KEYD
chmod 755 "$ROOTFS/usr/local/bin/keyd.sh"

# OpenRC services
cat > "$ROOTFS/etc/init.d/keyd" << 'KEYDINIT'
#!/sbin/openrc-run

description="Key event daemon (power switch + screen wake)"
command="/usr/local/bin/keyd.sh"
command_background=true
pidfile="/run/keyd.pid"

depend() {
    after modules
}
KEYDINIT
chmod 755 "$ROOTFS/etc/init.d/keyd"

cat > "$ROOTFS/etc/init.d/screen-idle" << 'SCREENIDINIT'
#!/sbin/openrc-run

description="Screen idle blanker"
command="/usr/local/bin/screen-idle.sh"
command_background=true
pidfile="/run/screen-idle.pid"

depend() {
    after keyd
}
SCREENIDINIT
chmod 755 "$ROOTFS/etc/init.d/screen-idle"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add keyd default
rc-update add screen-idle default
'
