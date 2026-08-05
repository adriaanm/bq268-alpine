#!/bin/sh
# Unbind the framebuffer console: while wata-fb owns the panel, nothing
# else (fbcon repaints, key echo, kernel/openrc writes to tty1) may paint
# it. Same mechanism system-menu used around its wata launch. Rebind
# manually with: echo 1 > /sys/class/vtconsole/vtcon*/bind
for v in /sys/class/vtconsole/vtcon*; do
  grep -q "frame buffer" "$v/name" 2>/dev/null && echo 0 > "$v/bind" 2>/dev/null
done
exec /opt/wata/wata-fb ui
