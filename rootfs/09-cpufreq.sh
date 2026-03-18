# CPU frequency governor
echo "--- Setting up CPU frequency governor ---"

cat > "$ROOTFS/etc/init.d/cpufreq" << 'CPUFREQ'
#!/sbin/openrc-run

description="CPU frequency governor"

start() {
    ebegin "Setting CPU governor to interactive"
    local gov
    for gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        [ -f "$gov" ] && echo "interactive" > "$gov" 2>/dev/null
    done
    eend 0
}
CPUFREQ
chmod 755 "$ROOTFS/etc/init.d/cpufreq"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add cpufreq boot
'
