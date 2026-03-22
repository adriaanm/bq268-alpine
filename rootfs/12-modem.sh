# Modem bringup: rmt_storage daemon + subsystem boot
echo "--- Setting up modem support ---"

# Install rmt_storage binary
install -m 755 "$SCRIPT_DIR/tools/rmt_storage" "$ROOTFS/usr/sbin/rmt_storage"

# OpenRC init script: rmt_storage daemon
cat > "$ROOTFS/etc/init.d/rmt-storage" << 'RMTFS'
#!/sbin/openrc-run

description="Modem EFS storage daemon (rmt_storage)"
command="/usr/sbin/rmt_storage"
command_args="-v -w 15"
command_background=true
pidfile="/run/rmt-storage.pid"

depend() {
    after modules
    before modem
}

start_pre() {
    # Ensure block devices exist
    for dev in /dev/mmcblk0p26 /dev/mmcblk0p27 /dev/mmcblk0p3 /dev/mmcblk0p29; do
        if [ ! -b "$dev" ]; then
            ewarn "Missing $dev — rmt_storage may fail"
        fi
    done
}
RMTFS
chmod 755 "$ROOTFS/etc/init.d/rmt-storage"

# OpenRC init script: modem subsystem boot (holds /dev/subsys_modem open)
cat > "$ROOTFS/etc/init.d/modem" << 'MODEM'
#!/sbin/openrc-run

description="Modem subsystem (Q6 DSP)"
pidfile="/run/modem.pid"

depend() {
    need rmt-storage
    after modules
}

start() {
    if [ ! -c /dev/subsys_modem ]; then
        ewarn "No /dev/subsys_modem — modem subsystem not available"
        return 0
    fi

    ebegin "Booting modem (Q6 DSP)"
    # Hold subsys_modem fd open to keep the modem running.
    # When this process dies, the fd closes and subsystem_put() shuts it down.
    start-stop-daemon --start --background --make-pidfile \
        --pidfile "$pidfile" \
        --exec /bin/sh -- -c 'exec sleep 999999 < /dev/subsys_modem'
    eend $?
}

stop() {
    ebegin "Stopping modem"
    start-stop-daemon --stop --pidfile "$pidfile" 2>/dev/null
    eend 0
}
MODEM
chmod 755 "$ROOTFS/etc/init.d/modem"

# Services installed but NOT auto-enabled — start manually:
#   rc-service rmt-storage start
#   rc-service modem start
echo "  rmt-storage + modem services installed (manual start)"
