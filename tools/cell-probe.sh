#!/bin/sh
# cell-probe: periodic attach probe, logs outcome + RF state.
#
# Run as: cell-probe loop            (foreground, every $INTERVAL)
#         cell-probe once            (one iteration, then exit)
#
# Output: /var/log/cellular-probe.log (one line per probe)
#         ts|mode|reg_state|ps|selected|rat|status|rsrp|ever_attached
#
# `ever_attached` = "yes" if EF_EPSLOCI on the SIM has ever been
# written to a real TAI (i.e. a past LTE attach actually completed
# and stuck long enough to persist). Detects the "brief PS-attach"
# success case even if we missed it in the live poll.

QMI="msmipc://0"
LOG=/var/log/cellular-probe.log
INTERVAL="${INTERVAL:-600}"   # 10 minutes default

probe_once() {
    local ts mode serv reg ps sel rat status rsrp
    ts=$(date +%Y-%m-%dT%H:%M:%S)

    /usr/sbin/cell-data wake >/dev/null 2>&1
    mode=$(qmicli -p -d "$QMI" --dms-get-operating-mode 2>&1 | \
        sed -n "s/.*Mode: '\([^']*\)'.*/\1/p")

    serv=$(qmicli -p -d "$QMI" --nas-get-serving-system 2>&1 || true)
    reg=$(echo "$serv" | sed -n "s/.*Registration state: '\([^']*\)'.*/\1/p" | head -1)
    ps=$(echo "$serv"  | sed -n "s/.*PS: '\([^']*\)'.*/\1/p" | head -1)
    sel=$(echo "$serv" | sed -n "s/.*Selected network: '\([^']*\)'.*/\1/p" | head -1)
    rat=$(echo "$serv" | sed -n "s/.*\[0\]: '\([^']*\)'.*/\1/p" | head -1)
    status=$(echo "$serv" | sed -n "s/.*Status: '\([^']*\)'.*/\1/p" | head -1)

    rsrp=$(qmicli -p -d "$QMI" --nas-get-signal-strength 2>&1 | \
        sed -n "/^Current:/,/^[A-Z]/ p" | \
        sed -n "s/.*'\(-[0-9]*\) dBm'.*/\1/p" | head -1)
    [ -z "$rsrp" ] && rsrp=unknown

    local eps
    eps=$(qmicli -p -d "$QMI" --uim-read-transparent=0x3F00,0x7FFF,0x6FE3 2>&1 \
          | grep -c ':')
    local ever=no
    [ "$eps" -gt 1 ] && ever=yes

    echo "$ts|$mode|$reg|$ps|$sel|$rat|$status|$rsrp|$ever" >> "$LOG"

    # On PS attached, also capture scan + signal details for forensics
    if [ "$ps" = "attached" ]; then
        {
            echo "=== $ts PS ATTACHED — snapshot ==="
            qmicli -p -d "$QMI" --nas-get-serving-system 2>&1
            qmicli -p -d "$QMI" --nas-get-signal-info 2>&1
            qmicli -p -d "$QMI" --nas-get-rf-band-info 2>&1
        } >> "${LOG}.attached"
    fi
}

case "${1:-loop}" in
    once)   probe_once ;;
    loop)
        while :; do
            probe_once
            sleep "$INTERVAL"
        done
        ;;
    *)      echo "usage: $0 {once|loop}" >&2; exit 1 ;;
esac
