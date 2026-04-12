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
