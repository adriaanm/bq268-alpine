# Power button + screen management (keyd, screen toggle/wake/idle)
echo "--- Setting up power button and screen management ---"

cat > "$ROOTFS/usr/local/bin/screen-toggle.sh" << 'SCREENTOGGLE'
#!/bin/sh
# Toggle screen on/off. Reads brightness from /etc/bq268.conf.
. /etc/bq268.conf 2>/dev/null
BL="/sys/class/leds/lcd-bl/brightness"
STATE="/run/screen.state"
BRIGHTNESS="${BACKLIGHT_BRIGHTNESS:-20}"

if [ "$(cat "$STATE" 2>/dev/null)" = "off" ]; then
    echo "$BRIGHTNESS" > "$BL" 2>/dev/null
    echo "on" > "$STATE"
else
    echo 0 > "$BL" 2>/dev/null
    echo "off" > "$STATE"
fi
# Reset idle timer on toggle-on
touch /run/screen.activity
SCREENTOGGLE
chmod 755 "$ROOTFS/usr/local/bin/screen-toggle.sh"

cat > "$ROOTFS/usr/local/bin/screen-wake.sh" << 'SCREENWAKE'
#!/bin/sh
# Wake screen on any keypress. Called by keyd for all key events.
. /etc/bq268.conf 2>/dev/null
BL="/sys/class/leds/lcd-bl/brightness"
STATE="/run/screen.state"
BRIGHTNESS="${BACKLIGHT_BRIGHTNESS:-20}"

touch /run/screen.activity
if [ "$(cat "$STATE" 2>/dev/null)" = "off" ]; then
    echo "$BRIGHTNESS" > "$BL" 2>/dev/null
    echo "on" > "$STATE"
fi
SCREENWAKE
chmod 755 "$ROOTFS/usr/local/bin/screen-wake.sh"

cat > "$ROOTFS/usr/local/bin/screen-idle.sh" << 'SCREENIDLE'
#!/bin/sh
# Screen idle daemon — blanks screen after SCREEN_TIMEOUT seconds of inactivity
BL="/sys/class/leds/lcd-bl/brightness"
STATE="/run/screen.state"

# Initialize
echo "on" > "$STATE"
touch /run/screen.activity

while true; do
    sleep 5
    # Re-read config each iteration (settings menu can change it)
    . /etc/bq268.conf 2>/dev/null
    TIMEOUT="${SCREEN_TIMEOUT:-30}"
    [ "$TIMEOUT" -eq 0 ] && continue
    [ "$(cat "$STATE" 2>/dev/null)" = "off" ] && continue
    now=$(date +%s)
    last=$(stat -c %Y /run/screen.activity 2>/dev/null || echo "$now")
    idle=$((now - last))
    if [ "$idle" -ge "$TIMEOUT" ]; then
        echo 0 > "$BL" 2>/dev/null
        echo "off" > "$STATE"
    fi
done
SCREENIDLE
chmod 755 "$ROOTFS/usr/local/bin/screen-idle.sh"

# Key daemon — monitors all input devices, dispatches power toggle + screen wake
cat > "$ROOTFS/usr/local/bin/keyd.sh" << 'KEYD'
#!/bin/sh
# Key event daemon — uses evtest to monitor input devices.
#
# Key map:
#   POWER     → toggle screen on/off
#   F1 (PTT)  → spacebar (via console keymap)
#   F3 (side) → settings menu
#   F4 (side) → system info
#   All keys  → wake screen from blank

handle_key() {
    case "$1" in
        KEY_POWER)
            /usr/local/bin/screen-toggle.sh
            ;;
        KEY_F3)
            /usr/local/bin/screen-wake.sh
            (
                [ -f /run/menu.lock ] && exit 0
                touch /run/menu.lock
                openvt -s -w -- /usr/local/bin/settings-menu.sh
                rm -f /run/menu.lock
            ) &
            ;;
        KEY_F4)
            /usr/local/bin/screen-wake.sh
            (
                [ -f /run/menu.lock ] && exit 0
                touch /run/menu.lock
                openvt -s -w -- /usr/local/bin/sysinfo-menu.sh
                rm -f /run/menu.lock
            ) &
            ;;
        KEY_*)
            /usr/local/bin/screen-wake.sh
            ;;
    esac
}

# Monitor all event devices
for dev in /dev/input/event*; do
    [ -e "$dev" ] || continue
    evtest "$dev" 2>/dev/null | while read -r line; do
        case "$line" in
            *"(EV_KEY)"*"value 1")
                key=$(echo "$line" | sed 's/.*(\(KEY_[^)]*\)).*/\1/')
                handle_key "$key"
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

description="Key event daemon (power button + screen idle)"
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
