# Time sync (chrony NTP)
echo "--- Setting up time sync ---"
mkdir -p "$ROOTFS/etc/chrony"
cat > "$ROOTFS/etc/chrony/chrony.conf" << 'CHRONY'
pool pool.ntp.org iburst
driftfile /var/lib/chrony/drift
makestep 1 3
rtcsync
CHRONY
mkdir -p "$ROOTFS/var/lib/chrony"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add chronyd default
'
