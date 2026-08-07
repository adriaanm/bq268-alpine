#!/bin/sh
# Called by wpa_cli -a: $1=interface, $2=event
IFACE="$1"
EVENT="$2"

case "$EVENT" in
    CONNECTED)
        logger -t wpa-action "$IFACE: connected, starting DHCP"
        kill $(cat /run/udhcpc.$IFACE.pid 2>/dev/null) 2>/dev/null
        udhcpc -i "$IFACE" -b -R -p /run/udhcpc.$IFACE.pid

        # DHCP has written the resolvers: this is the first moment NTP can be
        # asked. The board has no RTC, and a wrong clock fails every TLS
        # handshake — so the app is offline until this lands.
        clock-kick &

        # WiFi is back — tear down cellular to save data (unless force mode)
        if [ ! -f /run/cell-data.force ]; then
            logger -t wpa-action "$IFACE: WiFi up, tearing down cellular data"
            cell-data down 2>&1 | logger -t cell-data
        fi
        ;;
    DISCONNECTED)
        logger -t wpa-action "$IFACE: disconnected, releasing DHCP"
        kill $(cat /run/udhcpc.$IFACE.pid 2>/dev/null) 2>/dev/null
        ip addr flush dev "$IFACE" 2>/dev/null

        # WiFi lost — bring up cellular as fallback (unless force mode)
        if [ ! -f /run/cell-data.force ]; then
            logger -t wpa-action "$IFACE: WiFi down, activating cellular data"
            cell-data up 2>&1 | logger -t cell-data
        fi
        ;;
esac
