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
