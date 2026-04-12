# Console keymap + system menu (main UI on fbcon)
echo "--- Setting up console keymap and system menu ---"

# PTT (F1, keycode 59) → spacebar at the console level.
cat > "$ROOTFS/etc/bq268.kmap" << 'KMAP'
keycode 59 = space
KMAP

install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/console-keymap" "$ROOTFS/etc/init.d/console-keymap"

# System menu (main UI on tty0, Python)
install -m 755 "$SCRIPT_DIR/tools/system-menu.py" "$ROOTFS/usr/local/bin/system-menu"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add console-keymap default
'
