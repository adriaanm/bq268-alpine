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

# Consoles (autologin root, no password prompt)
tty0::respawn:/sbin/getty -n -l /bin/sh 38400 tty0
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

# Enable services
chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add devfs sysinit
rc-update add dmesg sysinit
rc-update add hwdrivers sysinit
rc-update add modules boot
rc-update add sysctl boot
rc-update add hostname boot
rc-update add bootmisc boot
rc-update add syslog boot
rc-update add networking boot
rc-update add dropbear default
rc-update add killprocs shutdown
rc-update add mount-ro shutdown
rc-update add savecache shutdown
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
FSTAB
