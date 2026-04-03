# Console keymap + system menu (main UI on fbcon)
echo "--- Setting up console keymap and system menu ---"

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

# Helper: read system status (sourced by menus)
cat > "$ROOTFS/usr/local/lib/bq268-status.sh" << 'STATUSLIB'
# Source this to populate status variables. Fast — no qmicli unless needed.

status_battery() {
    BAT_PCT=$(cat /sys/class/power_supply/battery/capacity 2>/dev/null || echo "?")
    BAT_ST=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
    case "$BAT_ST" in
        Charging)     BAT_ICO="+" ;;
        Full)         BAT_ICO="=" ;;
        Discharging)  BAT_ICO="-" ;;
        *)            BAT_ICO="" ;;
    esac
}

status_wifi() {
    WIFI_IP=$(ip -4 addr show wlan0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
    WIFI_SSID=$(iw dev wlan0 info 2>/dev/null | awk '/ssid/{print $2}')
    if [ -n "$WIFI_IP" ]; then
        WIFI_ST="on"
    elif [ -d /sys/class/net/wlan0 ]; then
        WIFI_ST="--"
    else
        WIFI_ST="off"
    fi
}

status_modem() {
    # Cache modem info (qmicli is slow, ~200ms per call)
    local nas
    nas=$(qmicli -d msmipc://0 --nas-get-serving-system 2>&1)
    if echo "$nas" | grep -q "'registered'"; then
        MODEM_REG=1
        MODEM_NET=$(echo "$nas" | sed -n "s/.*Description: '\(.*\)'/\1/p")
        [ -z "$MODEM_NET" ] && MODEM_NET=$(echo "$nas" | awk '/MCC/{mcc=$2} /MNC/{mnc=$2} END{printf "%s/%s",mcc,mnc}')
        MODEM_RAT=$(echo "$nas" | sed -n "s/.*\[0\]: '\(.*\)'/\1/p" | head -1)
    else
        MODEM_REG=0
        MODEM_NET="--"
        MODEM_RAT=""
    fi

    # Signal strength
    local sig
    sig=$(qmicli -d msmipc://0 --nas-get-signal-strength 2>&1)
    MODEM_DBM=$(echo "$sig" | awk '/Current:/{getline; print $NF}' | tr -d "'")
    [ "$MODEM_DBM" = "-128" ] && MODEM_DBM="--"

    # PPP data session
    if ip link show ppp0 >/dev/null 2>&1; then
        MODEM_IP=$(ip -4 addr show ppp0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1)
        MODEM_DATA="up"
    else
        MODEM_IP=""
        MODEM_DATA="off"
    fi
}

# Quick status line (battery + connectivity) — fits 20 chars
status_line() {
    status_battery
    local wifi_s modem_s
    if [ -n "$WIFI_IP" ]; then
        wifi_s="W"
    else
        wifi_s="w"
    fi
    if [ -n "$MODEM_IP" ]; then
        modem_s="M"
    elif [ "$MODEM_REG" = "1" ]; then
        modem_s="m"
    else
        modem_s="."
    fi
    printf '%s%%%s %s%s' "$BAT_PCT" "$BAT_ICO" "$wifi_s" "$modem_s"
}
STATUSLIB

# --- Main system menu (replaces shell on tty0) ---
cat > "$ROOTFS/usr/local/bin/system-menu.sh" << 'SYSMENU'
#!/bin/sh
# System menu — main UI on fbcon (160×128, 20×8 chars).
# Launched by inittab as respawn on tty0.
# UP/DOWN to navigate, SELECT/RIGHT to activate, BACK to return.

. /usr/local/lib/bq268-status.sh

SEL=0
ITEMS=4

# Key reader via evtest
FIFO="/tmp/sysmenu-keys.$$"
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
    status_battery
    status_wifi
    # Modem status is slow — only refresh every 10 draws or on first draw
    if [ -z "$_mdm_cached" ] || [ "$(( _draw_count % 10 ))" -eq 0 ]; then
        status_modem
        _mdm_cached=1
    fi
    _draw_count=$(( ${_draw_count:-0} + 1 ))

    printf '\033[H\033[2J'
    # Line 1: status bar
    local wifi_s modem_s
    [ -n "$WIFI_IP" ] && wifi_s="W:on" || wifi_s="W:--"
    if [ -n "$MODEM_IP" ]; then
        modem_s="M:$MODEM_DBM"
    elif [ "$MODEM_REG" = "1" ]; then
        modem_s="m:$MODEM_DBM"
    else
        modem_s="M:--"
    fi
    printf '%s%%%s %s %s\n' "$BAT_PCT" "$BAT_ICO" "$wifi_s" "$modem_s"
    printf '%-20s\n' "--------------------"

    # Menu items
    local i=0
    for label in "Wata" "System Info" "Settings" "Reboot"; do
        [ $i -eq $SEL ] && printf '> ' || printf '  '
        printf '%s\n' "$label"
        i=$((i + 1))
    done
}

launch_wata() {
    # Find fbcon bind path
    local FBCON=""
    for vtc in /sys/class/vtconsole/vtcon*; do
        [ -e "$vtc/name" ] || continue
        read name < "$vtc/name" 2>/dev/null
        case "$name" in *"frame buffer"*) FBCON="$vtc/bind" ;; esac
    done
    if [ -x /opt/wata/start.sh ]; then
        [ -n "$FBCON" ] && echo 0 > "$FBCON" 2>/dev/null
        /opt/wata/start.sh
        [ -n "$FBCON" ] && echo 1 > "$FBCON" 2>/dev/null
    else
        printf '\033[H\033[2J'
        printf 'Wata not installed\n\n/opt/wata/start.sh\nnot found\n'
        sleep 2
    fi
}

launch_sysinfo() {
    status_battery
    status_wifi
    status_modem
    printf '\033[H\033[2J'
    printf '=== System Info ===\n'

    # Battery
    local bst
    case "$(cat /sys/class/power_supply/battery/status 2>/dev/null)" in
        Charging) bst="Chrg" ;; Discharging) bst="Dchg" ;; Full) bst="Full" ;; *) bst="Idle" ;;
    esac
    local mv=$(cat /sys/class/power_supply/battery/voltage_now 2>/dev/null)
    [ -n "$mv" ] && mv="$(( mv / 1000 ))mV" || mv="?"
    printf 'Bat: %s%% %s %s\n' "$BAT_PCT" "$bst" "$mv"

    # WiFi
    printf 'WiFi:%s %s\n' "${WIFI_SSID:---}" "${WIFI_IP:---}"

    # Modem
    local rat="${MODEM_RAT:+($MODEM_RAT)}"
    printf 'Net: %s %s\n' "${MODEM_NET:---}" "$rat"
    printf 'Sig: %s\n' "${MODEM_DBM:---}"
    if [ -n "$MODEM_IP" ]; then
        printf 'IP:  %s\n' "$MODEM_IP"
    else
        printf 'Data:off\n'
    fi

    # Uptime / mem
    local up=$(cut -d. -f1 /proc/uptime)
    printf 'Up:%dh%dm Mem:%s\n' "$((up/3600))" "$(((up%3600)/60))" \
        "$(awk '/MemAvail/{printf "%dM",$2/1024}' /proc/meminfo)"

    # Wait for any key
    read -r _ < "$FIFO"
}

launch_settings() {
    . /etc/bq268.conf 2>/dev/null
    local sel=0 items=4
    local br=${BACKLIGHT_BRIGHTNESS:-20}
    local to=${SCREEN_TIMEOUT:-30}
    local wifi_on=0
    [ -d /sys/class/net/wlan0 ] && wifi_on=1

    local blv=$(cat /sys/class/leds/lcd-bl/brightness 2>/dev/null)
    [ -n "$blv" ] && [ "$blv" -gt 0 ] 2>/dev/null && br=$blv

    draw_settings() {
        status_battery
        printf '\033[H\033[2J'
        printf '%s%%%s  Settings\n' "$BAT_PCT" "$BAT_ICO"
        printf '%-20s\n' "--------------------"
        [ $sel -eq 0 ] && printf '>' || printf ' '
        printf ' Bright   [%3d]\n' "$br"
        [ $sel -eq 1 ] && printf '>' || printf ' '
        [ $wifi_on -eq 1 ] && printf ' WiFi      [ON]\n' || printf ' WiFi     [OFF]\n'
        [ $sel -eq 2 ] && printf '>' || printf ' '
        printf ' Timeout  [%3ds]\n' "$to"
        [ $sel -eq 3 ] && printf '>' || printf ' '
        printf ' Reboot→BL\n'
    }

    draw_settings
    while read -r key; do
        case "$key" in
            KEY_UP)    sel=$(( (sel - 1 + items) % items )) ;;
            KEY_DOWN)  sel=$(( (sel + 1) % items )) ;;
            KEY_RIGHT|KEY_ENTER)
                case $sel in
                    0) br=$((br + 25)); [ $br -gt 255 ] && br=255
                       echo "$br" > /sys/class/leds/lcd-bl/brightness 2>/dev/null
                       sed -i "s/^BACKLIGHT_BRIGHTNESS=.*/BACKLIGHT_BRIGHTNESS=$br/" /etc/bq268.conf ;;
                    1) if [ $wifi_on -eq 1 ]; then
                           killall wpa_supplicant 2>/dev/null; ip link set wlan0 down 2>/dev/null; wifi_on=0
                       else
                           ip link set wlan0 up 2>/dev/null
                           wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf 2>/dev/null
                           udhcpc -i wlan0 -b -R -q 2>/dev/null &
                           wifi_on=1
                       fi ;;
                    2) case $to in 15) to=30;; 30) to=60;; 60) to=120;; 120) to=0;; *) to=15;; esac
                       sed -i "s/^SCREEN_TIMEOUT=.*/SCREEN_TIMEOUT=$to/" /etc/bq268.conf ;;
                    3) printf '\033[H\033[2JRebooting to\nbootloader...\n'; sleep 1
                       /usr/local/bin/reboot-bootloader ;;
                esac ;;
            KEY_LEFT)
                case $sel in
                    0) br=$((br - 25)); [ $br -lt 5 ] && br=5
                       echo "$br" > /sys/class/leds/lcd-bl/brightness 2>/dev/null
                       sed -i "s/^BACKLIGHT_BRIGHTNESS=.*/BACKLIGHT_BRIGHTNESS=$br/" /etc/bq268.conf ;;
                    2) case $to in 15) to=0;; 30) to=15;; 60) to=30;; 120) to=60;; *) to=120;; esac
                       sed -i "s/^SCREEN_TIMEOUT=.*/SCREEN_TIMEOUT=$to/" /etc/bq268.conf ;;
                esac ;;
            KEY_ESC|KEY_BACK|KEY_F3) break ;;
        esac
        draw_settings
    done < "$FIFO"
}

activate() {
    case $SEL in
        0) launch_wata ;;
        1) launch_sysinfo ;;
        2) launch_settings ;;
        3) printf '\033[H\033[2JRebooting...\n'; sleep 1; reboot ;;
    esac
}

# Main loop
draw
while read -r key; do
    case "$key" in
        KEY_UP)    SEL=$(( (SEL - 1 + ITEMS) % ITEMS )) ;;
        KEY_DOWN)  SEL=$(( (SEL + 1) % ITEMS )) ;;
        KEY_RIGHT|KEY_ENTER) activate ;;
        KEY_F3)    launch_settings ;;
    esac
    draw
done < "$FIFO"
SYSMENU
chmod 755 "$ROOTFS/usr/local/bin/system-menu.sh"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add console-keymap default
'
