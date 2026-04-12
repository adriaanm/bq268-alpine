#!/bin/sh
touch /run/screen.activity
if [ "$(cat /run/screen.state 2>/dev/null)" = "off" ]; then
    /usr/local/bin/screen-on.sh
fi
