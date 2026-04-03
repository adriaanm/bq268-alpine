# Console keymap + system menu (main UI on fbcon)
echo "--- Setting up console keymap and system menu ---"

# PTT (F1, keycode 59) → spacebar at the console level.
cat > "$ROOTFS/etc/bq268.kmap" << 'KMAP'
keycode 59 = space
KMAP

cat > "$ROOTFS/etc/init.d/console-keymap" << 'KMAPINIT'
#!/sbin/openrc-run

description="Console keymap (PTT→space)"

depend() {
    after devfs
}

start() {
    ebegin "Loading console keymap"
    loadkeys /etc/bq268.kmap 2>/dev/null
    eend $?
}
KMAPINIT
chmod 755 "$ROOTFS/etc/init.d/console-keymap"

# Status library (sourced by menus)
install -D -m 644 "$SCRIPT_DIR/tools/bq268-status.sh" "$ROOTFS/usr/local/lib/bq268-status.sh"

# System menu (main UI on tty0)
install -m 755 "$SCRIPT_DIR/tools/system-menu.sh" "$ROOTFS/usr/local/bin/system-menu.sh"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add console-keymap default
'
