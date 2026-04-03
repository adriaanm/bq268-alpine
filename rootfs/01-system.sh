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
cat > "$ROOTFS/etc/inittab" << 'INITTAB'
# Signal userspace reached
::sysinit:/bin/sh -c 'echo 1 > /sys/class/leds/green/brightness 2>/dev/null'

# Essential mounts before OpenRC (root may be mounted ro, tmpfs may be unavailable)
::sysinit:/bin/mount -o remount,rw /
::sysinit:/bin/mkdir -p /run /run/openrc
::sysinit:/bin/mount -t tmpfs tmpfs /run 2>/dev/null
::sysinit:/bin/mkdir -p /run/openrc
::sysinit:/bin/mount -t proc proc /proc
::sysinit:/bin/mount -t sysfs sysfs /sys
::sysinit:/bin/mount -t configfs none /sys/kernel/config 2>/dev/null

# OpenRC init sequence
::sysinit:/sbin/openrc sysinit
::sysinit:/sbin/openrc boot
::once:/sbin/openrc default

# System menu on VT1
tty1::respawn:/usr/local/bin/system-menu
ttyGS0::respawn:/bin/sh -c 'while [ ! -e /dev/ttyGS0 ]; do sleep 1; done; exec /sbin/getty -n -l /bin/sh -L 115200 ttyGS0 vt100'

# Shutdown
::shutdown:/sbin/openrc shutdown
::ctrlaltdel:/sbin/reboot
INITTAB

# Set root password to "bq268" (change on first login)
chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
echo "root:bq268" | chpasswd
'

# Device configuration
cat > "$ROOTFS/etc/bq268.conf" << 'BQ268CONF'
# BQ268 device configuration
# Backlight brightness (0-255, default 20)
BACKLIGHT_BRIGHTNESS=20
# Screen idle timeout in seconds (0 = never blank)
SCREEN_TIMEOUT=30
# Battery critical threshold (%) — triggers graceful shutdown
BATTERY_CRITICAL=5
# Battery low threshold (%) — triggers red LED warning
BATTERY_LOW=15
BQ268CONF

# OpenRC logging — captures all init output to /var/log/rc.log
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
cat > "$ROOTFS/etc/init.d/dev" << 'DEVINIT'
#!/sbin/openrc-run
description="devtmpfs (kernel-managed /dev)"
depend() {
    provide dev
    need devfs
    keyword -docker -podman -prefix -systemd-nspawn -vserver
}
start() {
    ebegin "Using kernel devtmpfs for /dev"
    eend 0
}
DEVINIT
chmod 755 "$ROOTFS/etc/init.d/dev"

# Override /usr/lib/sysctl.d/00-alpine.conf — same file minus keys unsupported
# by the CAF 4.4 kernel (no CONFIG_SYN_COOKIES, no CONFIG_BPF_SYSCALL).
# OpenRC's sysctl init skips /usr/lib/sysctl.d/X if /etc/sysctl.d/X exists.
mkdir -p "$ROOTFS/etc/sysctl.d"
cat > "$ROOTFS/etc/sysctl.d/00-alpine.conf" << 'SYSCTL'
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.ping_group_range=999 59999
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 1
net.ipv6.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.tcp_rfc1337 = 1
net.ipv6.conf.default.use_tempaddr = 2
net.ipv6.conf.all.use_tempaddr = 2
kernel.panic = 120
fs.protected_hardlinks = 1
fs.protected_symlinks = 1
SYSCTL

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
cat > "$ROOTFS/etc/network/interfaces" << 'NET'
auto lo
iface lo inet loopback

# USB ECM gadget ethernet (brought up by usb-gadget-ecm service, not auto)
iface usb0 inet static
    address 192.168.7.2
    netmask 255.255.255.0

# WiFi (bring up manually: ifup wlan0)
iface wlan0 inet dhcp
NET

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
cat > "$ROOTFS/etc/fstab" << 'FSTAB'
# <device>  <mount>  <type>  <options>       <dump> <pass>
/dev/root   /        ext4    rw,noatime      0      1
proc        /proc    proc    defaults        0      0
sysfs       /sys     sysfs   defaults        0      0
devtmpfs    /dev     devtmpfs defaults       0      0
tmpfs       /var/log tmpfs   size=2M,nosuid,nodev 0 0
pstore      /sys/fs/pstore pstore  defaults        0      0
FSTAB
