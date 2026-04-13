# wata-metricsd: metrics sampler aligned to wata's matrix long-poll heartbeat.
# Binds /run/wata.tick (AF_UNIX SOCK_DGRAM) and writes JSONL to
# /var/log/metrics/. See tools/wata-metricsd/ and docs/planning/metrics-sampler.md.
echo "--- Installing wata-metricsd ---"

WATA_METRICSD_BIN="$SCRIPT_DIR/tools/wata-metricsd/zig-out/bin/wata-metricsd"
if [ ! -f "$WATA_METRICSD_BIN" ]; then
    echo "ERROR: $WATA_METRICSD_BIN not found — run 'just build-wata-metricsd' first"
    exit 1
fi

install -m 755 "$WATA_METRICSD_BIN" "$ROOTFS/usr/sbin/wata-metricsd"
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/wata-metricsd" "$ROOTFS/etc/init.d/wata-metricsd"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add wata-metricsd default
'
