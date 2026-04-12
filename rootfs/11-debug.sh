# Diagnostic init (boot with init=/sbin/init.debug)
install -m 755 "$SCRIPT_DIR/rootfs/files/sbin/init.debug" "$ROOTFS/sbin/init.debug"
