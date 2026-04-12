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
