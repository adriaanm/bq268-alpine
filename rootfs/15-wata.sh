# inittab: system-menu on tty0 (replaces shell — no keyboard on device)
echo "--- Setting up tty0 launcher ---"

# The system-menu is the main UI. It launches wata (unbinding fbcon),
# and provides settings, sysinfo, and reboot. If wata exits, it returns
# to the menu. inittab respawns the menu if it crashes.
#
# The old wata-launcher.sh is replaced by system-menu.sh which handles
# fbcon bind/unbind internally when launching wata.
