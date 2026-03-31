# Console keymap + TUI menus (settings, sysinfo)
echo "--- Setting up console keymap and TUI menus ---"

# PTT (F1, keycode 59) → spacebar at the console level.
# The native app reads evdev directly and sees KEY_F1.
cat > "$ROOTFS/etc/bq268.kmap" << 'KMAP'
keycode 59 = space
KMAP

cat > "$ROOTFS/etc/init.d/console-keymap" << 'KMAPINIT'
#!/sbin/openrc-run

description="Console keymap (PTT→space)"

depend() {
    after devfs
}

start() {
    ebegin "Loading console keymap"
    loadkeys /etc/bq268.kmap 2>/dev/null
    eend $?
}
KMAPINIT
chmod 755 "$ROOTFS/etc/init.d/console-keymap"

# Settings menu (F3) — brightness, WiFi, screen timeout, reboot
# Designed for 20×8 char fbcon (160×128 px, 8×16 font)
cat > "$ROOTFS/usr/local/bin/settings-menu.sh" << 'SETMENU'
#!/bin/sh
# Settings menu — launched via openvt from keyd on F3 press.
# Input via evtest (reads evdev directly, not console layer).

. /etc/bq268.conf 2>/dev/null
SEL=0
ITEMS=4
BRIGHTNESS=${BACKLIGHT_BRIGHTNESS:-20}
TIMEOUT=${SCREEN_TIMEOUT:-30}

# Current WiFi state
[ -d /sys/class/net/wlan0 ] && WIFI_ON=1 || WIFI_ON=0

# Read live brightness
bl=$(cat /sys/class/leds/lcd-bl/brightness 2>/dev/null)
[ -n "$bl" ] && [ "$bl" -gt 0 ] 2>/dev/null && BRIGHTNESS=$bl

# Cache modem status (qmicli is slow)
MODEM="off"
qmicli -d msmipc://0 --dms-get-operating-mode 2>/dev/null | grep -q online && MODEM="online"

# Key reader: evtest → awk → FIFO
FIFO="/tmp/menu-keys.$$"
mkfifo "$FIFO" 2>/dev/null

cleanup() {
    kill $KR_PID 2>/dev/null
    rm -f "$FIFO"
    clear
}
trap cleanup EXIT INT TERM

(
    for dev in /dev/input/event*; do
        [ -e "$dev" ] || continue
        evtest "$dev" 2>/dev/null &
    done
    wait
) 2>/dev/null | awk '/EV_KEY.*value 1$/{
    match($0, /KEY_[A-Z0-9_]+/)
    if (RSTART) { print substr($0, RSTART, RLENGTH); fflush() }
}' > "$FIFO" &
KR_PID=$!

draw() {
    printf '\033[H\033[2J'
    # Status bar (refreshes battery/IP each draw)
    local bat=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "?")
    local bst=$(cat /sys/class/power_supply/battery/status 2>/dev/null || echo "?")
    case "$bst" in
        Charging)     bst="+" ;;
        Full)         bst="=" ;;
        *)            bst="" ;;
    esac
    local ip=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
    [ -z "$ip" ] && ip="--"
    printf '%s%%%s %s mdm:%s\n' "$bat" "$bst" "$ip" "$MODEM"
    printf '--------------------\n'
    [ $SEL -eq 0 ] && printf '>' || printf ' '
    printf ' Bright   [%3d]\n' "$BRIGHTNESS"
    [ $SEL -eq 1 ] && printf '>' || printf ' '
    [ $WIFI_ON -eq 1 ] && printf ' WiFi      [ON]\n' || printf ' WiFi     [OFF]\n'
    [ $SEL -eq 2 ] && printf '>' || printf ' '
    printf ' Timeout  [%3ds]\n' "$TIMEOUT"
    [ $SEL -eq 3 ] && printf '>' || printf ' '
    printf ' Reboot\n'
}

adjust() {
    local dir="$1"
    case $SEL in
        0) # Brightness: step 25, range 5-255
            if [ "$dir" = "R" ] || [ "$dir" = "ENTER" ]; then
                BRIGHTNESS=$((BRIGHTNESS + 25))
                [ $BRIGHTNESS -gt 255 ] && BRIGHTNESS=255
            else
                BRIGHTNESS=$((BRIGHTNESS - 25))
                [ $BRIGHTNESS -lt 5 ] && BRIGHTNESS=5
            fi
            echo "$BRIGHTNESS" > /sys/class/leds/lcd-bl/brightness 2>/dev/null
            sed -i "s/^BACKLIGHT_BRIGHTNESS=.*/BACKLIGHT_BRIGHTNESS=$BRIGHTNESS/" /etc/bq268.conf
            ;;
        1) # WiFi toggle
            if [ $WIFI_ON -eq 1 ]; then
                killall wpa_supplicant 2>/dev/null
                ip link set wlan0 down 2>/dev/null
                WIFI_ON=0
            else
                ip link set wlan0 up 2>/dev/null
                wpa_supplicant -B -i wlan0 \
                    -c /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null
                udhcpc -i wlan0 -b -R -q 2>/dev/null &
                WIFI_ON=1
            fi
            ;;
        2) # Screen timeout: cycle 15/30/60/120/0
            if [ "$dir" = "R" ]; then
                case $TIMEOUT in
                    15) TIMEOUT=30 ;; 30) TIMEOUT=60 ;; 60) TIMEOUT=120 ;;
                    120) TIMEOUT=0 ;; *) TIMEOUT=15 ;;
                esac
            else
                case $TIMEOUT in
                    15) TIMEOUT=0 ;; 30) TIMEOUT=15 ;; 60) TIMEOUT=30 ;;
                    120) TIMEOUT=60 ;; *) TIMEOUT=120 ;;
                esac
            fi
            sed -i "s/^SCREEN_TIMEOUT=.*/SCREEN_TIMEOUT=$TIMEOUT/" /etc/bq268.conf
            ;;
        3) # Reboot to bootloader (fastboot mode)
            printf '\033[H\033[2J'
            printf 'Rebooting to\nbootloader...\n'
            sleep 1
            /usr/local/bin/reboot-bootloader
            ;;
    esac
}

draw
while read -r key; do
    case "$key" in
        KEY_UP)    SEL=$(( (SEL - 1 + ITEMS) % ITEMS )) ;;
        KEY_DOWN)  SEL=$(( (SEL + 1) % ITEMS )) ;;
        KEY_LEFT)  adjust L ;;
        KEY_RIGHT) adjust R ;;
        KEY_ENTER) adjust ENTER ;;
        KEY_ESC|KEY_F3) break ;;
    esac
    draw
done < "$FIFO"
SETMENU
chmod 755 "$ROOTFS/usr/local/bin/settings-menu.sh"

# System info menu (F4) — battery, WiFi, IP, uptime, memory
cat > "$ROOTFS/usr/local/bin/sysinfo-menu.sh" << 'INFOMENU'
#!/bin/sh
# System info — launched via openvt from keyd on F4 press.

FIFO="/tmp/sysinfo-keys.$$"
mkfifo "$FIFO" 2>/dev/null

cleanup() {
    kill $KR_PID 2>/dev/null
    rm -f "$FIFO"
    clear
}
trap cleanup EXIT INT TERM

(
    for dev in /dev/input/event*; do
        [ -e "$dev" ] || continue
        evtest "$dev" 2>/dev/null &
    done
    wait
) 2>/dev/null | awk '/EV_KEY.*value 1$/{
    match($0, /KEY_[A-Z0-9_]+/)
    if (RSTART) { print substr($0, RSTART, RLENGTH); fflush() }
}' > "$FIFO" &
KR_PID=$!

draw() {
    printf '\033[H\033[2J'
    local cap=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "?")
    local bst=$(cat /sys/class/power_supply/battery/status 2>/dev/null || echo "?")
    # Abbreviate status
    case "$bst" in
        Charging)     bst="Chrg" ;;
        Discharging)  bst="Dchg" ;;
        Full)         bst="Full" ;;
        Not?charging) bst="Idle" ;;
    esac
    local ssid=$(iw dev wlan0 info 2>/dev/null | awk '/ssid/{print $2}')
    [ -z "$ssid" ] && ssid="--"
    local ip=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
    [ -z "$ip" ] && ip="--"
    local up=$(cut -d. -f1 /proc/uptime)
    local h=$((up / 3600)) m=$(( (up % 3600) / 60 ))
    local mem=$(awk '/MemTotal/{t=$2} /MemAvail/{a=$2} END{printf "%d/%dM",(t-a)/1024,t/1024}' /proc/meminfo)

    printf '=== SYSTEM ===\n'
    printf ' Bat:  %s%% %s\n' "$cap" "$bst"
    printf ' WiFi: %s\n' "$ssid"
    printf ' IP:   %s\n' "$ip"
    printf ' Up:   %dh %dm\n' "$h" "$m"
    printf ' Mem:  %s\n' "$mem"
    printf '\n'
    printf ' BACK: close\n'
}

draw
while read -r key; do
    case "$key" in
        KEY_ESC|KEY_F4) break ;;
        *) draw ;;
    esac
done < "$FIFO"
INFOMENU
chmod 755 "$ROOTFS/usr/local/bin/sysinfo-menu.sh"
