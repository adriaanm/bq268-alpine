#!/bin/sh
# Unbind the framebuffer console: while wata-fb owns the panel, nothing
# else (fbcon repaints, key echo, kernel/openrc writes to tty1) may paint
# it. Same mechanism system-menu used around its wata launch. Rebind
# manually with: echo 1 > /sys/class/vtconsole/vtcon*/bind
for v in /sys/class/vtconsole/vtcon*; do
  grep -q "frame buffer" "$v/name" 2>/dev/null && echo 0 > "$v/bind" 2>/dev/null
done
# The iroh transport is the handset's permanent transport when the config
# exists (plan 0014's flip); a TCP-LAN deployment simply has no such file.
if [ -f /etc/wata/iroh.json ]; then
  exec env WATA_IROH_CONFIG=/etc/wata/iroh.json /opt/wata/wata-fb ui
fi
exec /opt/wata/wata-fb ui
