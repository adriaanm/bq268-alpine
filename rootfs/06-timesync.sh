# Time sync (chrony NTP) — and a clock that survives a boot without an RTC.
#
# The board has no battery-backed RTC (/dev/rtc0 exists but reads 1970), and a
# wrong clock is not cosmetic: every TLS handshake fails certificate
# validation, so wata cannot reach its server at all over a working wifi. Three
# parts, in the order they matter on a cold boot:
#
#   swclock      restores the clock at boot from the mtime of
#                /var/lib/misc/openrc-shutdowntime, so the device starts within
#                minutes of the real time instead of at 1970. It replaces
#                hwclock as the `clock` provider (an unbacked RTC only ever
#                hands back 1970).
#   save-clock   a 15-minute cron job re-saving that file, because swclock's
#                own save runs at clean shutdown only — which a handset whose
#                battery is pulled never gets.
#   clock-kick   run when an interface comes up (wpa_cli CONNECTED, pppd
#                ip-up): restarts chronyd so it resolves its pool NOW. chronyd
#                starts before the network, and its own retry cadence is
#                minutes.
echo "--- Setting up time sync ---"
mkdir -p "$ROOTFS/etc/chrony"
install -m 644 "$SCRIPT_DIR/rootfs/files/etc/chrony/chrony.conf" "$ROOTFS/etc/chrony/chrony.conf"
mkdir -p "$ROOTFS/var/lib/chrony" "$ROOTFS/var/lib/misc"

install -m 755 "$SCRIPT_DIR/rootfs/files/usr/local/bin/clock-kick" \
    "$ROOTFS/usr/local/bin/clock-kick"
install -d "$ROOTFS/etc/periodic/15min"
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/periodic/15min/save-clock" \
    "$ROOTFS/etc/periodic/15min/save-clock"

# Seed the saved time with the image build date: a freshly flashed device then
# boots into a plausible clock on its very first boot, before it has ever seen
# a network.
touch "$ROOTFS/var/lib/misc/openrc-shutdowntime"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add chronyd default
rc-update add swclock boot
rc-update add crond default
'
