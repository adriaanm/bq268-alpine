#!/bin/sh
# Called by wpa_cli -a: $1=interface, $2=event
IFACE="$1"
EVENT="$2"

# Is this a real wifi loss worth answering with a data call, or the boot still
# settling? Both conditions matter: the modem subsystem has to be ONLINE for
# QMI to be safe, and the first minute of a boot is scanning, not failure.
cell_fallback_ok() {
    up=$(cut -d. -f1 /proc/uptime)
    [ "${up:-0}" -ge 60 ] || return 1
    for d in /sys/bus/msm_subsys/devices/subsys*; do
        [ "$(cat "$d"/name 2>/dev/null)" = modem ] || continue
        [ "$(cat "$d"/state 2>/dev/null)" = ONLINE ] && return 0
    done
    return 1
}

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

        # WiFi lost — bring up cellular as fallback (unless force mode).
        #
        # NOT DURING BOOT, and not before the Q6 is up. wpa_supplicant reports
        # DISCONNECTED the moment it starts scanning, so at boot this reflex
        # fired while the modem was still booting: cell-data's QMI traffic hit
        # a Q6 that was not ready, which is the `send_filled_buffers_to_user:
        # Send Failed -3` storm that wedges four kworkers in D state — on the
        # SAME msm_ipc_router the wlan driver uses, whose scan then found no AP
        # at all and never associated. Wifi lost its own boot to a fallback for
        # a loss that had not happened yet. net-watchdog owns real failover.
        if [ ! -f /run/cell-data.force ] && cell_fallback_ok; then
            logger -t wpa-action "$IFACE: WiFi down, activating cellular data"
            cell-data up 2>&1 | logger -t cell-data
        fi
        ;;
esac
