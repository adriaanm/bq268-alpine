# Cellular data: PPP over SMD (/dev/smd7)
# The modem uses AT+CGDATA="PPP" for data, not BAM DMUX.
echo "--- Setting up cellular PPP ---"

mkdir -p "$ROOTFS/etc/ppp/peers"

install -m 644 "$SCRIPT_DIR/rootfs/files/etc/ppp/peers/cellular"      "$ROOTFS/etc/ppp/peers/cellular"
install -m 644 "$SCRIPT_DIR/rootfs/files/etc/ppp/cellular-chat"        "$ROOTFS/etc/ppp/cellular-chat"
install -m 644 "$SCRIPT_DIR/rootfs/files/etc/ppp/cellular-disconnect"  "$ROOTFS/etc/ppp/cellular-disconnect"

# /dev/ppp device node (required by pppd, kernel CONFIG_PPP)
cat >> "$ROOTFS/etc/conf.d/mdev" 2>/dev/null << 'EOF' || true
# PPP device node
EOF
# Create at boot via init script since devtmpfs won't have it
sed -i '/^start()/,/^}/{/ebegin/a\    [ -c /dev/ppp ] || mknod /dev/ppp c 108 0' "$ROOTFS/etc/init.d/modem" 2>/dev/null || true

# Simpler: just create it in the rootfs (devtmpfs overlays this, but
# if CONFIG_DEVTMPFS_MOUNT is not set it persists)
[ ! -c "$ROOTFS/dev/ppp" ] && mknod "$ROOTFS/dev/ppp" c 108 0 2>/dev/null || true

echo "  pppd peer 'cellular' installed"
echo "  Usage: pppd call cellular"
echo "  Requires kernel CONFIG_PPP + CONFIG_PPP_ASYNC"
