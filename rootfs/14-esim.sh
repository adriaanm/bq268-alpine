# eSIM provisioning support: lpac + qmicli APDU wrapper
echo "--- Setting up eSIM support ---"

# Install runtime dependencies (curl for SM-DP+ HTTPS, cJSON for lpac)
chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
apk add --no-cache libcurl cjson
'

# Install lpac binary
install -m 755 "$SCRIPT_DIR/tools/lpac-esim/lpac" "$ROOTFS/usr/bin/"

# Install lpac shared libraries
mkdir -p "$ROOTFS/usr/lib/lpac/driver"
for lib in libeuicc.so libeuicc.so.2 liblpac-utils.so \
           libeuicc-drivers.so libeuicc-drivers.so.2 \
           libeuicc-driver-loader.so libeuicc-driver-loader.so.2; do
    src="$SCRIPT_DIR/tools/lpac-esim/$lib"
    if [ -L "$src" ]; then
        # Preserve symlinks
        cp -a "$src" "$ROOTFS/usr/lib/lpac/"
    elif [ -f "$src" ]; then
        install -m 755 "$src" "$ROOTFS/usr/lib/lpac/"
    fi
done

# Install driver shared libraries
for drv in driver_apdu_stdio.so driver_http_curl.so; do
    install -m 755 "$SCRIPT_DIR/tools/lpac-esim/driver/$drv" "$ROOTFS/usr/lib/lpac/driver/"
done

# Install QMI APDU daemon (persistent AF_MSM_IPC session, short AID bypass)
install -m 755 "$SCRIPT_DIR/tools/qmi-send-apdu" "$ROOTFS/usr/bin/qmi-send-apdu"

# Install QMI APDU wrapper (translates lpac stdio ↔ qmi-send-apdu daemon)
install -m 755 "$SCRIPT_DIR/tools/lpac-qmi-wrapper.sh" "$ROOTFS/usr/bin/lpac-qmi-wrapper"

# Install user-facing provisioning script
install -m 755 "$SCRIPT_DIR/tools/esim-provision.sh" "$ROOTFS/usr/bin/esim-provision"

echo "  lpac + wrapper installed to /usr/bin/"
echo "  Usage: esim-provision 'LPA:1\$smdp.example.com\$CODE'"
