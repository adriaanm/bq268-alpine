# Audio: ALSA mixer setup for external speaker via HPHR → class-D PA
echo "--- Setting up audio ---"

install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/audio-mixer" "$ROOTFS/etc/init.d/audio-mixer"

# Enable at default runlevel
chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add audio-mixer default
'
echo "  audio-mixer service enabled (default runlevel)"
