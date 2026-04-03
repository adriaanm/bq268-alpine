# Cellular data: PPP over SMD (/dev/smd7)
# The modem uses AT+CGDATA="PPP" for data, not BAM DMUX.
echo "--- Setting up cellular PPP ---"

mkdir -p "$ROOTFS/etc/ppp/peers"

# pppd peer config
cat > "$ROOTFS/etc/ppp/peers/cellular" << 'EOF'
# Cellular data over SMD (PPP over AT on /dev/smd7)
/dev/smd7
115200
noauth
defaultroute
replacedefaultroute
usepeerdns
nodetach
noipdefault
novj
novjccomp
noccp
ipcp-accept-local
ipcp-accept-remote
connect "/usr/sbin/chat -v -f /etc/ppp/cellular-chat"
disconnect "/usr/sbin/chat -v -f /etc/ppp/cellular-disconnect"
EOF

# Chat script: set APN, dial
cat > "$ROOTFS/etc/ppp/cellular-chat" << 'EOF'
ABORT "ERROR"
ABORT "NO CARRIER"
ABORT "NO DIALTONE"
TIMEOUT 30
"" AT
OK AT+CGDCONT=1,"IP","globaldata"
OK ATD*99***1#
CONNECT ""
EOF

# Disconnect script: escape data mode, hang up, deactivate PDP
cat > "$ROOTFS/etc/ppp/cellular-disconnect" << 'EOF'
"" +++
"" ATH
OK AT+CGACT=0,1
OK ""
EOF

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
