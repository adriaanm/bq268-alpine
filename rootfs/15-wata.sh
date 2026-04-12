# inittab: system-menu on tty0 (replaces shell — no keyboard on device)
# The system-menu is the main UI. It launches wata (unbinding fbcon),
# and provides settings, sysinfo, and reboot. If wata exits, it returns
# to the menu. inittab respawns the menu if it crashes.
echo "--- Installing /opt/wata/start.sh ---"

mkdir -p "$ROOTFS/opt/wata"
cat > "$ROOTFS/opt/wata/start.sh" << 'WATA_START'
#!/bin/sh
exec /opt/wata/wata-fb
WATA_START
chmod 755 "$ROOTFS/opt/wata/start.sh"
