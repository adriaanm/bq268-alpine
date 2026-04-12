# inittab: system-menu on tty0 (replaces shell — no keyboard on device)
# The system-menu is the main UI. It launches wata (unbinding fbcon),
# and provides settings, sysinfo, and reboot. If wata exits, it returns
# to the menu. inittab respawns the menu if it crashes.
echo "--- Installing /opt/wata/start.sh ---"

mkdir -p "$ROOTFS/opt/wata"
install -m 755 "$SCRIPT_DIR/rootfs/files/opt/wata/start.sh" "$ROOTFS/opt/wata/start.sh"
