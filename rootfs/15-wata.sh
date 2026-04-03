# inittab: system-menu on tty0 (replaces shell — no keyboard on device)
# The system-menu is the main UI. It launches wata (unbinding fbcon),
# and provides settings, sysinfo, and reboot. If wata exits, it returns
# to the menu. inittab respawns the menu if it crashes.
echo "--- tty0 runs system-menu (wata launched from there) ---"
