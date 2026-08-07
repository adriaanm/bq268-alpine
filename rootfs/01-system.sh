# System configuration: hostname, inittab, fstab, syslog, passwords, services
echo "--- Configuring system ---"

# Hostname
echo "bq268" > "$ROOTFS/etc/hostname"
cat > "$ROOTFS/etc/hosts" << 'HOSTS'
127.0.0.1	localhost
127.0.1.1	bq268
::1		localhost
HOSTS

# Inittab — busybox init configuration
# Mounts essential filesystems before OpenRC, since the kernel may mount
# root read-only and CONFIG_TMPFS may not be available.
install -m 644 "$SCRIPT_DIR/rootfs/files/etc/inittab" "$ROOTFS/etc/inittab"

# Set root password to "bq268" (change on first login)
chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
echo "root:bq268" | chpasswd
'

# Device configuration
install -m 644 "$SCRIPT_DIR/rootfs/files/etc/bq268.conf" "$ROOTFS/etc/bq268.conf"

# OpenRC logging — captures all init output to /var/log/rc.log.
#
# NOT rc_parallel="YES". It was tried (2026-08-07) and reverted: it does cut
# the runlevel from ~40s to ~16s, but on this board the two radios cannot come
# up together. WCNSS pushes the wlan chip's NV calibration blob over the same
# SMD transport the Q6's firmware load saturates, and overlapping them makes
# cold-boot calibration fail outright ("hdd_driver_init:CBC not completed") —
# after which wlan0 comes up and wpa_supplicant scans forever with an empty
# result list. That cost the device its wifi on roughly one boot in three. The
# services that need Q6-backed hardware (audio-mixer, wifi) instead do their
# waiting in the background, which recovers most of the time without the race.
cat > "$ROOTFS/etc/rc.conf" << 'RCCONF'
rc_logger="YES"
RCCONF

# Syslog — small buffers to limit eMMC wear (/var/log is tmpfs)
mkdir -p "$ROOTFS/etc/conf.d"
cat > "$ROOTFS/etc/conf.d/syslog" << 'SYSLOGCONF'
SYSLOGD_OPTS="-s 256 -b 2 -O /var/log/messages"
SYSLOGCONF

# 'dev' service — satisfies the 'dev' dependency for hwdrivers, acpid, etc.
# On this device /dev is kernel-managed devtmpfs, so no mdev/udev needed.
install -m 755 "$SCRIPT_DIR/rootfs/files/etc/init.d/dev" "$ROOTFS/etc/init.d/dev"

# Override /usr/lib/sysctl.d/00-alpine.conf — same file minus keys unsupported
# by the CAF 4.4 kernel (no CONFIG_SYN_COOKIES, no CONFIG_BPF_SYSCALL).
# OpenRC's sysctl init skips /usr/lib/sysctl.d/X if /etc/sysctl.d/X exists.
mkdir -p "$ROOTFS/etc/sysctl.d"
install -m 644 "$SCRIPT_DIR/rootfs/files/etc/sysctl.d/00-alpine.conf" "$ROOTFS/etc/sysctl.d/00-alpine.conf"

# Silence kernel console — only panics reach tty0 (menu runs there)
echo "kernel.printk = 1 4 1 7" >> "$ROOTFS/etc/sysctl.conf"

# Enable services
chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add devfs sysinit
rc-update add dev sysinit
rc-update add dmesg sysinit
rc-update add sysctl boot
rc-update add hostname boot
rc-update add bootmisc boot
rc-update add syslog boot
rc-update add networking boot
rc-update add dropbear default
rc-update add killprocs shutdown
rc-update add mount-ro shutdown
'

# Network interfaces
mkdir -p "$ROOTFS/etc/network"
install -m 644 "$SCRIPT_DIR/rootfs/files/etc/network/interfaces" "$ROOTFS/etc/network/interfaces"

# SSH authorized key (passwordless login from buildbox)
mkdir -p "$ROOTFS/root/.ssh"
chmod 700 "$ROOTFS/root/.ssh"
cat > "$ROOTFS/root/.ssh/authorized_keys" << 'SSHKEY'
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPo7EfYxKIzg5LwncN5r2kpeTlNQl6GFLJCv0qE8DeOk adriaan@debian-bq268
SSHKEY
chmod 600 "$ROOTFS/root/.ssh/authorized_keys"

# Module loading
mkdir -p "$ROOTFS/etc/modules-load.d"
# WiFi module not auto-loaded — load manually: modprobe pronto_wlan
# echo "pronto_wlan" > "$ROOTFS/etc/modules-load.d/wifi.conf"

# fstab
install -m 644 "$SCRIPT_DIR/rootfs/files/etc/fstab" "$ROOTFS/etc/fstab"
