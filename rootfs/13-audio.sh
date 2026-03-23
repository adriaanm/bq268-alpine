# Audio: ALSA mixer setup for external speaker via HPHR → class-D PA
echo "--- Setting up audio ---"

# OpenRC init script: set ALSA mixer controls after modem boots
cat > "$ROOTFS/etc/init.d/audio-mixer" << 'AUDIOMIX'
#!/sbin/openrc-run

description="ALSA mixer setup for BQ268 speaker"

depend() {
    after modem
}

start() {
    ebegin "Setting ALSA mixer controls"

    # Wait for sound card to appear (LPASS registers after modem DSP boots)
    local tries=0
    while [ ! -e /dev/snd/controlC0 ] && [ $tries -lt 30 ]; do
        sleep 1
        tries=$((tries + 1))
    done

    if [ ! -e /dev/snd/controlC0 ]; then
        eerror "No sound card found after 30s"
        eend 1
        return 1
    fi

    # Route: MultiMedia1 → PRI_MI2S_RX → RX2 (HPHR) → RDAC2 → class-D PA
    amixer -c 0 cset name="PRI_MI2S_RX Audio Mixer MultiMedia1" 1
    amixer -c 0 cset name="RX2 MIX1 INP1" 3        # 3 = RX1
    amixer -c 0 cset name="RDAC2 MUX" 1             # 1 = RX2
    amixer -c 0 cset name="HPHR" 1                   # 1 = Switch on
    amixer -c 0 cset name="Ext Spk Switch" 1         # 1 = On
    amixer -c 0 cset name="RX2 Digital Volume" 96

    eend $?
}
AUDIOMIX
chmod 755 "$ROOTFS/etc/init.d/audio-mixer"

# Enable at default runlevel
chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add audio-mixer default
'
echo "  audio-mixer service enabled (default runlevel)"
