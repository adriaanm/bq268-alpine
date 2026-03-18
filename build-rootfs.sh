#!/usr/bin/env bash
# Build Alpine Linux rootfs for BQ268 walkie-talkie
# Must be run as root (for chroot/mount)
#
# Produces: out/rootfs.img (ext4, flash to userdata via fastboot)
# Login: root / bq268
# Console: ttyGS0 @ 115200 (USB gadget serial) + tty0 (fbcon)
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="$SCRIPT_DIR/out"
ROOTFS="$OUTDIR/rootfs"
ROOTFS_IMG="$OUTDIR/rootfs.img"
KERNEL_REPO="${SUDO_USER:+/home/$SUDO_USER}/bq268-kernel"
KERNEL_REPO="${KERNEL_REPO:-$HOME/bq268-kernel}"
CAF_KERNEL_REPO="${SUDO_USER:+/home/$SUDO_USER}/bq268-caf_msm-3.18"
CAF_KERNEL_REPO="${CAF_KERNEL_REPO:-$HOME/bq268-caf_msm-3.18}"
FIRMWARE_DIR="$SCRIPT_DIR/firmware"

# Alpine minirootfs URL (armv7, latest stable)
ALPINE_VERSION="3.21"
ALPINE_MINOR="3.21.3"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/armhf/alpine-minirootfs-${ALPINE_MINOR}-armhf.tar.gz"
ALPINE_TAR="$OUTDIR/alpine-minirootfs-${ALPINE_MINOR}-armhf.tar.gz"

# Image size (MB)
IMG_SIZE=256

echo "=== BQ268 Alpine rootfs builder ==="

# Check prerequisites
if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (for chroot)" >&2
    exit 1
fi

# Determine the calling user for chown at the end
SUDO_UID="${SUDO_UID:-1000}"
SUDO_GID="${SUDO_GID:-1000}"

mkdir -p "$OUTDIR"

# ── 1. Download Alpine minirootfs ──────────────────────────────────────────
if [ ! -f "$ALPINE_TAR" ]; then
    echo "--- Downloading Alpine minirootfs ${ALPINE_MINOR} ---"
    wget -q -O "$ALPINE_TAR" "$ALPINE_URL"
fi
echo "  Alpine tarball: $(ls -lh "$ALPINE_TAR" | awk '{print $5}')"

# ── 2. Create ext4 image and populate ─────────────────────────────────────
echo "--- Creating ${IMG_SIZE}MB ext4 image ---"
# Clean up stale mounts from previous runs
umount "$ROOTFS/dev/pts" 2>/dev/null || true
umount "$ROOTFS/dev" 2>/dev/null || true
umount "$ROOTFS/proc" 2>/dev/null || true
umount "$ROOTFS/sys" 2>/dev/null || true
umount "$ROOTFS" 2>/dev/null || true
rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"
dd if=/dev/zero of="$ROOTFS_IMG" bs=1M count=$IMG_SIZE status=none
mkfs.ext4 -q -b 4096 -L rootfs "$ROOTFS_IMG"
mount -o loop "$ROOTFS_IMG" "$ROOTFS"

# Extract Alpine
echo "--- Extracting Alpine rootfs ---"
tar xzf "$ALPINE_TAR" -C "$ROOTFS"

# Create essential device nodes (needed before devtmpfs is mounted)
mknod -m 622 "$ROOTFS/dev/console" c 5 1
mknod -m 666 "$ROOTFS/dev/null" c 1 3
mknod -m 666 "$ROOTFS/dev/zero" c 1 5
mknod -m 444 "$ROOTFS/dev/urandom" c 1 9
mknod -m 666 "$ROOTFS/dev/tty" c 5 0

# ── 3. Set up chroot ─────────────────────────────────────────────────────
echo "--- Setting up chroot ---"
cp /usr/bin/qemu-arm-static "$ROOTFS/usr/bin/"
mount -t proc proc "$ROOTFS/proc"
mount -t sysfs sys "$ROOTFS/sys"
mount -o bind /dev "$ROOTFS/dev"
mount -o bind /dev/pts "$ROOTFS/dev/pts"

# DNS for package downloads
cp /etc/resolv.conf "$ROOTFS/etc/resolv.conf"

# Set up Alpine repositories
cat > "$ROOTFS/etc/apk/repositories" << 'REPO'
https://dl-cdn.alpinelinux.org/alpine/v3.21/main
https://dl-cdn.alpinelinux.org/alpine/v3.21/community
REPO

# ── 4. Install packages ──────────────────────────────────────────────────
echo "--- Installing packages ---"
chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
apk update
apk add \
    openrc busybox-openrc \
    dropbear openssh-sftp-server \
    wpa_supplicant \
    evtest \
    iproute2 \
    util-linux \
    e2fsprogs \
    nano \
    htop \
    strace \
    linux-firmware-none \
    wireless-regdb \
    kmod \
    modemmanager libqmi \
    bluez \
    chrony
'

# Fix /run — ensure it's a real directory so tmpfs mount works at boot
if [ -L "$ROOTFS/run" ]; then
    rm -f "$ROOTFS/run"
fi
mkdir -p "$ROOTFS/run"

# ── 5. Configure system ──────────────────────────────────────────────────
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
::wait:/sbin/openrc default

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

# ── 6. Install kernel + modules ──────────────────────────────────────────
echo "--- Installing kernel ---"
mkdir -p "$ROOTFS/boot"
if [ -f "$KERNEL_REPO/out/zImage" ]; then
    cp "$KERNEL_REPO/out/zImage" "$ROOTFS/boot/zImage"
    cp "$KERNEL_REPO/out/qcom-msm8909-udotech-bq268.dtb" "$ROOTFS/boot/msm8909-bq268.dtb" 2>/dev/null || true
    echo "  Kernel copied to /boot"
else
    echo "  WARN: kernel not built yet — skipping /boot copy"
fi

# Kernel modules
KVER="$(cat "$KERNEL_REPO/out/include/config/kernel.release" 2>/dev/null || echo "6.19.0-msm8916")"
if [ -d "$KERNEL_REPO/out/lib/modules/$KVER" ]; then
    cp -a "$KERNEL_REPO/out/lib/modules/$KVER" "$ROOTFS/lib/modules/"
    chroot "$ROOTFS" /usr/bin/qemu-arm-static /sbin/depmod "$KVER" 2>/dev/null || true
    echo "  Modules installed for $KVER"
else
    mkdir -p "$ROOTFS/lib/modules/$KVER"
    find "$KERNEL_REPO/output" -name "*.ko" -exec cp {} "$ROOTFS/lib/modules/$KVER/" \; 2>/dev/null || true
    chroot "$ROOTFS" /usr/bin/qemu-arm-static /sbin/depmod "$KVER" 2>/dev/null || true
    echo "  Modules dir: $KVER"
fi

# CAF 3.18 kernel modules (wlan.ko from prima build)
CAF_KVER="$(cat "$CAF_KERNEL_REPO/output/include/config/kernel.release" 2>/dev/null || true)"
if [ -n "$CAF_KVER" ]; then
    echo "--- Installing CAF kernel modules ($CAF_KVER) ---"
    mkdir -p "$ROOTFS/lib/modules/$CAF_KVER"
    find "$CAF_KERNEL_REPO/output" -name "*.ko" -exec cp {} "$ROOTFS/lib/modules/$CAF_KVER/" \; 2>/dev/null || true
    chroot "$ROOTFS" /usr/bin/qemu-arm-static /sbin/depmod "$CAF_KVER" 2>/dev/null || true
    echo "  Modules:"
    ls "$ROOTFS/lib/modules/$CAF_KVER/"*.ko 2>/dev/null | xargs -I{} basename {} || true
fi

# ── 7. Install firmware ──────────────────────────────────────────────────
echo "--- Installing firmware ---"
mkdir -p "$ROOTFS/lib/firmware/qcom"

# Panel firmware (panel-mipi-dbi-spi driver)
cp "$KERNEL_REPO/out/udotech,bq268-st7735s-panel.bin" "$ROOTFS/lib/firmware/" 2>/dev/null || true

# GPU firmware
cp "$FIRMWARE_DIR/gpu/a300_pfp.fw" "$ROOTFS/lib/firmware/" 2>/dev/null || true
cp "$FIRMWARE_DIR/gpu/a300_pm4.fw" "$ROOTFS/lib/firmware/" 2>/dev/null || true

# Modem firmware (PIL expects these at /lib/firmware/)
cp "$FIRMWARE_DIR/modem"/modem.* "$ROOTFS/lib/firmware/" 2>/dev/null || true
cp "$FIRMWARE_DIR/modem/mba.mbn" "$ROOTFS/lib/firmware/" 2>/dev/null || true

# WCNSS firmware (PIL expects wcnss.mdt at /lib/firmware/)
cp "$FIRMWARE_DIR/wcnss"/wcnss.* "$ROOTFS/lib/firmware/" 2>/dev/null || true

# WLAN NV data + config
mkdir -p "$ROOTFS/lib/firmware/wlan/prima"
cp "$FIRMWARE_DIR/wlan/WCNSS_qcom_wlan_nv.bin" "$ROOTFS/lib/firmware/wlan/prima/" 2>/dev/null || true
cp "$FIRMWARE_DIR/wlan/WCNSS_cfg.dat" "$ROOTFS/lib/firmware/wlan/prima/" 2>/dev/null || true
cp "$FIRMWARE_DIR/wlan/WCNSS_qcom_cfg.ini" "$ROOTFS/lib/firmware/wlan/prima/" 2>/dev/null || true

# Staged WiFi firmware (from /tmp/bq268-wifi-fw if available)
WIFI_FW_STAGED="/tmp/bq268-wifi-fw/lib/firmware"
if [ -d "$WIFI_FW_STAGED" ]; then
    echo "  Installing staged WiFi firmware from $WIFI_FW_STAGED"
    cp "$WIFI_FW_STAGED"/wcnss.* "$ROOTFS/lib/firmware/" 2>/dev/null || true
    mkdir -p "$ROOTFS/lib/firmware/wlan/prima"
    cp "$WIFI_FW_STAGED"/wlan/prima/WCNSS_qcom_wlan_nv.bin "$ROOTFS/lib/firmware/wlan/prima/" 2>/dev/null || true
fi

# ── 8. USB gadget (ACM serial + ECM ethernet) ─────────────────────────────
echo "--- Creating USB gadget setup ---"
mkdir -p "$ROOTFS/etc/init.d"

# Stage 1 (boot): ACM serial only — the debug lifeline.
# Detects CAF android_usb vs mainline configfs automatically.
cat > "$ROOTFS/etc/init.d/usb-gadget" << 'GADGET'
#!/sbin/openrc-run

description="USB gadget serial (ACM)"

depend() {
    after devfs
    before networking
}

start() {
    if [ -d /sys/class/android_usb/android0 ]; then
        # CAF 3.18 android_usb driver
        ebegin "Configuring USB gadget (ACM serial) via android_usb"
        A=/sys/class/android_usb/android0
        echo 0 > $A/enable
        echo 1d6b > $A/idVendor
        echo 0104 > $A/idProduct
        echo UdoTech > $A/iManufacturer
        echo BQ268 > $A/iProduct
        echo acm > $A/functions
        echo 1 > $A/enable
        eend $?
    else
        # Mainline configfs
        ebegin "Configuring USB gadget (ACM serial) via configfs"
        G=/sys/kernel/config/usb_gadget/g1

        [ -d /sys/kernel/config ] || mount -t configfs none /sys/kernel/config 2>/dev/null

        # Wait for a UDC controller to appear (up to 5s)
        local udc="" i=0
        while [ $i -lt 50 ] && [ -z "$udc" ]; do
            udc=$(ls /sys/class/udc/ 2>/dev/null | head -1)
            [ -z "$udc" ] && sleep 0.1
            i=$((i + 1))
        done
        if [ -z "$udc" ]; then
            eerror "No UDC found"
            eend 1
            return 1
        fi

        mkdir -p $G
        echo 0x1d6b > $G/idVendor
        echo 0x0104 > $G/idProduct

        mkdir -p $G/strings/0x409
        echo "UdoTech"  > $G/strings/0x409/manufacturer
        echo "BQ268"    > $G/strings/0x409/product
        echo "00000000" > $G/strings/0x409/serialnumber

        mkdir -p $G/configs/c.1/strings/0x409
        echo "Serial" > $G/configs/c.1/strings/0x409/configuration

        # ACM serial only — ECM added later in default runlevel
        mkdir -p $G/functions/acm.usb0
        ln -sf $G/functions/acm.usb0 $G/configs/c.1/ 2>/dev/null

        echo "$udc" > $G/UDC
        eend $?
    fi
}
GADGET
chmod 755 "$ROOTFS/etc/init.d/usb-gadget"

# Stage 2 (default): Add ECM ethernet after boot is stable.
# Skipped on CAF (android_usb handles functions in a single step).
# On mainline, unbinds UDC briefly to add the function.
cat > "$ROOTFS/etc/init.d/usb-gadget-ecm" << 'GADGETECM'
#!/sbin/openrc-run

description="USB gadget ECM ethernet"

depend() {
    need usb-gadget
    after networking
}

start() {
    # CAF android_usb: skip ECM (could add rndis later if needed)
    if [ -d /sys/class/android_usb/android0 ]; then
        ebegin "ECM skipped (android_usb)"
        eend 0
        return 0
    fi

    ebegin "Adding ECM ethernet to USB gadget"
    G=/sys/kernel/config/usb_gadget/g1

    # Read current UDC
    local udc
    udc=$(cat $G/UDC 2>/dev/null)
    [ -z "$udc" ] && { eerror "Gadget not bound"; eend 1; return 1; }

    # Unbind, add ECM, rebind (safe — we're in default runlevel, boot is done)
    echo "" > $G/UDC

    mkdir -p $G/functions/ecm.usb0
    ln -sf $G/functions/ecm.usb0 $G/configs/c.1/ 2>/dev/null

    echo "$udc" > $G/UDC

    # Wait for usb0 network interface, then bring it up via ifupdown
    local i=0
    while [ $i -lt 30 ] && [ ! -d /sys/class/net/usb0 ]; do
        sleep 0.1
        i=$((i + 1))
    done

    if [ -d /sys/class/net/usb0 ]; then
        ifup usb0 2>/dev/null
    fi

    eend $?
}
GADGETECM
chmod 755 "$ROOTFS/etc/init.d/usb-gadget-ecm"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add usb-gadget boot
rc-update add usb-gadget-ecm default
'

# ── 9. WiFi bringup ──────────────────────────────────────────────────────
echo "--- Creating WiFi init script ---"
cat > "$ROOTFS/etc/init.d/wifi" << 'WIFI'
#!/sbin/openrc-run

description="WiFi (WCNSS + wlan driver + wpa_supplicant + DHCP)"

depend() {
    after modules
    before chronyd
}

start() {
    if [ -e /dev/wcnss_wlan ]; then
        # CAF 3.18: trigger WCNSS PIL firmware load, then insmod wlan.ko
        ebegin "Starting WiFi (CAF WCNSS)"
        cat /dev/wcnss_wlan &
        sleep 5  # wait for SMD channel + NV download
        local kver
        kver=$(uname -r)
        insmod /lib/modules/$kver/wlan.ko
        eend $?
    else
        # Mainline: wcn36xx/pronto_wlan loaded by hwdrivers or modprobe
        ebegin "Starting WiFi (mainline)"
        modprobe pronto_wlan 2>/dev/null || true
        eend 0
    fi

    # Wait for wlan0 to appear (up to 5s)
    local i=0
    while [ $i -lt 50 ] && [ ! -d /sys/class/net/wlan0 ]; do
        sleep 0.1
        i=$((i + 1))
    done

    if [ -d /sys/class/net/wlan0 ]; then
        ebegin "Starting wpa_supplicant"
        wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
        eend $?
        ebegin "Starting DHCP on wlan0"
        udhcpc -i wlan0 -b -R -p /run/udhcpc.wlan0.pid -q 2>/dev/null &
        eend 0
    else
        ewarn "wlan0 not found — skipping wpa_supplicant"
    fi
}

stop() {
    ebegin "Stopping WiFi"
    kill $(cat /run/udhcpc.wlan0.pid 2>/dev/null) 2>/dev/null
    killall wpa_supplicant 2>/dev/null
    eend 0
}
WIFI
chmod 755 "$ROOTFS/etc/init.d/wifi"

# wpa_supplicant base config
mkdir -p "$ROOTFS/etc/wpa_supplicant"
cat > "$ROOTFS/etc/wpa_supplicant/wpa_supplicant.conf" << 'WPACFG'
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=US

# Add networks via: wpa_cli -i wlan0
#   > add_network
#   > set_network 0 ssid "MySSID"
#   > set_network 0 psk "MyPassword"
#   > enable_network 0
#   > save_config
WPACFG

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add wifi default
'

echo "--- Setting up modem ---"

# Mainline modem stack:
#   - q6v5-mss remoteproc loads modem firmware from /lib/firmware/
#   - BAM-DMUX creates rmnet data interfaces
#   - QMI via QRTR (not SMD like CAF)
#   - ModemManager talks QMI over QRTR
#
# To bring up cellular data after boot:
#   mmcli -L                                    # list modems
#   mmcli -m 0 --simple-connect="apn=your.apn"  # connect

# ── 10. Time sync (chrony) ────────────────────────────────────────────────
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

# ── 11. Battery monitor + graceful shutdown ──────────────────────────────
echo "--- Setting up battery monitor ---"

cat > "$ROOTFS/usr/local/bin/graceful-shutdown.sh" << 'SHUTDOWN'
#!/bin/sh
# Graceful shutdown — log reason, signal via LED, power off
REASON="${1:-unknown}"
logger -t shutdown "Graceful shutdown: $REASON"
echo 1 > /sys/class/leds/red/brightness 2>/dev/null
echo 0 > /sys/class/leds/green/brightness 2>/dev/null
sync
poweroff
SHUTDOWN
chmod 755 "$ROOTFS/usr/local/bin/graceful-shutdown.sh"

cat > "$ROOTFS/usr/local/bin/battmon.sh" << 'BATTMON'
#!/bin/sh
# Battery monitor daemon — polls BMS sysfs, manages LEDs, shuts down on critical
. /etc/bq268.conf 2>/dev/null
CRITICAL=${BATTERY_CRITICAL:-5}
LOW=${BATTERY_LOW:-15}
POLL=60
BATT="/sys/class/power_supply/battery"
RED="/sys/class/leds/red/brightness"
GREEN="/sys/class/leds/green/brightness"
STATE_FILE="/run/battery.state"
PREV_STATE=""

while true; do
    capacity=$(cat "$BATT/capacity" 2>/dev/null || echo "-1")
    status=$(cat "$BATT/status" 2>/dev/null || echo "Unknown")
    voltage=$(cat "$BATT/voltage_now" 2>/dev/null || echo "0")

    # Determine state
    if [ "$capacity" = "-1" ]; then
        state="unknown"
    elif [ "$status" = "Charging" ] || [ "$status" = "Full" ]; then
        state="charging"
    elif [ "$capacity" -le "$CRITICAL" ]; then
        state="critical"
    elif [ "$capacity" -le "$LOW" ]; then
        state="low"
    else
        state="normal"
    fi

    # Write state for other scripts/app to read
    echo "$state $capacity $status $voltage" > "$STATE_FILE"

    # Log on state change
    if [ "$state" != "$PREV_STATE" ]; then
        logger -t battmon "state=$state capacity=$capacity% status=$status voltage=${voltage}uV"
        PREV_STATE="$state"
    fi

    # LED + action
    case "$state" in
        charging)
            echo 1 > "$GREEN" 2>/dev/null
            echo 0 > "$RED" 2>/dev/null
            ;;
        critical)
            echo 1 > "$RED" 2>/dev/null
            echo 0 > "$GREEN" 2>/dev/null
            /usr/local/bin/graceful-shutdown.sh "battery critical ($capacity%)"
            exit 0
            ;;
        low)
            # Blink red: on for this cycle, off next cycle
            if [ -f /run/battmon.blink ]; then
                echo 0 > "$RED" 2>/dev/null
                rm -f /run/battmon.blink
            else
                echo 1 > "$RED" 2>/dev/null
                touch /run/battmon.blink
            fi
            echo 0 > "$GREEN" 2>/dev/null
            ;;
        normal)
            echo 0 > "$RED" 2>/dev/null
            echo 0 > "$GREEN" 2>/dev/null
            ;;
    esac

    sleep "$POLL"
done
BATTMON
chmod 755 "$ROOTFS/usr/local/bin/battmon.sh"

cat > "$ROOTFS/etc/init.d/battmon" << 'BATTMONINIT'
#!/sbin/openrc-run

description="Battery monitor"
command="/usr/local/bin/battmon.sh"
command_background=true
pidfile="/run/battmon.pid"

depend() {
    after modules
}
BATTMONINIT
chmod 755 "$ROOTFS/etc/init.d/battmon"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add battmon default
'

# ── 12. Power button + screen management ─────────────────────────────────
echo "--- Setting up power button and screen management ---"

cat > "$ROOTFS/usr/local/bin/screen-toggle.sh" << 'SCREENTOGGLE'
#!/bin/sh
# Toggle screen on/off. Reads brightness from /etc/bq268.conf.
. /etc/bq268.conf 2>/dev/null
BL="/sys/class/leds/lcd-bl/brightness"
STATE="/run/screen.state"
BRIGHTNESS="${BACKLIGHT_BRIGHTNESS:-20}"

if [ "$(cat "$STATE" 2>/dev/null)" = "off" ]; then
    echo "$BRIGHTNESS" > "$BL" 2>/dev/null
    echo "on" > "$STATE"
else
    echo 0 > "$BL" 2>/dev/null
    echo "off" > "$STATE"
fi
# Reset idle timer on toggle-on
touch /run/screen.activity
SCREENTOGGLE
chmod 755 "$ROOTFS/usr/local/bin/screen-toggle.sh"

cat > "$ROOTFS/usr/local/bin/screen-wake.sh" << 'SCREENWAKE'
#!/bin/sh
# Wake screen on any keypress. Called by triggerhappy for all key events.
. /etc/bq268.conf 2>/dev/null
BL="/sys/class/leds/lcd-bl/brightness"
STATE="/run/screen.state"
BRIGHTNESS="${BACKLIGHT_BRIGHTNESS:-20}"

touch /run/screen.activity
if [ "$(cat "$STATE" 2>/dev/null)" = "off" ]; then
    echo "$BRIGHTNESS" > "$BL" 2>/dev/null
    echo "on" > "$STATE"
fi
SCREENWAKE
chmod 755 "$ROOTFS/usr/local/bin/screen-wake.sh"

cat > "$ROOTFS/usr/local/bin/screen-idle.sh" << 'SCREENIDLE'
#!/bin/sh
# Screen idle daemon — blanks screen after SCREEN_TIMEOUT seconds of inactivity
. /etc/bq268.conf 2>/dev/null
TIMEOUT="${SCREEN_TIMEOUT:-30}"
BL="/sys/class/leds/lcd-bl/brightness"
STATE="/run/screen.state"

[ "$TIMEOUT" -eq 0 ] 2>/dev/null && exit 0

# Initialize
echo "on" > "$STATE"
touch /run/screen.activity

while true; do
    sleep 5
    [ "$(cat "$STATE" 2>/dev/null)" = "off" ] && continue
    # Check how long since last activity
    now=$(date +%s)
    last=$(stat -c %Y /run/screen.activity 2>/dev/null || echo "$now")
    idle=$((now - last))
    if [ "$idle" -ge "$TIMEOUT" ]; then
        echo 0 > "$BL" 2>/dev/null
        echo "off" > "$STATE"
    fi
done
SCREENIDLE
chmod 755 "$ROOTFS/usr/local/bin/screen-idle.sh"

# Key daemon — monitors all input devices, dispatches power toggle + screen wake
cat > "$ROOTFS/usr/local/bin/keyd.sh" << 'KEYD'
#!/bin/sh
# Key event daemon — uses evtest to monitor input devices.
# Power button (KEY_POWER) toggles screen; all other keys wake screen.
# Runs one evtest per input device, parses key press events.

handle_key() {
    case "$1" in
        KEY_POWER) /usr/local/bin/screen-toggle.sh ;;
        KEY_*)     /usr/local/bin/screen-wake.sh ;;
    esac
}

# Monitor all event devices
for dev in /dev/input/event*; do
    [ -e "$dev" ] || continue
    evtest "$dev" 2>/dev/null | while read -r line; do
        # Match: "Event: ... type 1 (EV_KEY), code ... (...), value 1"
        # value 1 = key press, value 0 = release, value 2 = repeat
        case "$line" in
            *"(EV_KEY)"*"value 1")
                # Extract key name: ... code 116 (KEY_POWER), value 1
                key=$(echo "$line" | sed 's/.*(\(KEY_[^)]*\)).*/\1/')
                handle_key "$key"
                ;;
        esac
    done &
done

# Wait for all background evtest processes
wait
KEYD
chmod 755 "$ROOTFS/usr/local/bin/keyd.sh"

# Combined key + screen idle daemon as OpenRC service
cat > "$ROOTFS/etc/init.d/keyd" << 'KEYDINIT'
#!/sbin/openrc-run

description="Key event daemon (power button + screen idle)"
command="/usr/local/bin/keyd.sh"
command_background=true
pidfile="/run/keyd.pid"

depend() {
    after modules
}
KEYDINIT
chmod 755 "$ROOTFS/etc/init.d/keyd"

# Screen idle daemon as OpenRC service
cat > "$ROOTFS/etc/init.d/screen-idle" << 'SCREENIDINIT'
#!/sbin/openrc-run

description="Screen idle blanker"
command="/usr/local/bin/screen-idle.sh"
command_background=true
pidfile="/run/screen-idle.pid"

depend() {
    after keyd
}
SCREENIDINIT
chmod 755 "$ROOTFS/etc/init.d/screen-idle"

chroot "$ROOTFS" /usr/bin/qemu-arm-static /bin/sh -c '
rc-update add keyd default
rc-update add screen-idle default
'

# ── 13. CPU frequency governor ───────────────────────────────────────────
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

# ── 14. Diagnostic init (boot with init=/sbin/init.debug) ─────────────────
cat > "$ROOTFS/sbin/init.debug" << 'INITDBG'
#!/bin/sh
# Diagnostic init — signals progress via LEDs, prints to console.
# Boot with: init=/sbin/init.debug

G=/sys/class/leds/green/brightness
R=/sys/class/leds/red/brightness

echo "=== init.debug: ALIVE ===" > /dev/console 2>&1
echo 1 > $G 2>/dev/null

mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev
echo "=== init.debug: filesystems mounted ===" > /dev/console 2>&1
echo 1 > $R 2>/dev/null

echo "--- /proc/version ---" > /dev/console 2>&1
cat /proc/version > /dev/console 2>&1
echo "--- /proc/cmdline ---" > /dev/console 2>&1
cat /proc/cmdline > /dev/console 2>&1
echo "--- block devices ---" > /dev/console 2>&1
cat /proc/partitions > /dev/console 2>&1

echo "=== init.debug: dropping to shell ===" > /dev/console 2>&1
echo 0 > $R 2>/dev/null
exec /bin/sh < /dev/console > /dev/console 2>&1
INITDBG
chmod 755 "$ROOTFS/sbin/init.debug"

# ── 15. Cleanup and finalize ─────────────────────────────────────────────
echo "--- Finalizing ---"
rm -f "$ROOTFS/usr/bin/qemu-arm-static"
rm -f "$ROOTFS/etc/resolv.conf"

# Unmount chroot
umount "$ROOTFS/dev/pts" 2>/dev/null || true
umount "$ROOTFS/dev" 2>/dev/null || true
umount "$ROOTFS/proc" 2>/dev/null || true
umount "$ROOTFS/sys" 2>/dev/null || true
umount "$ROOTFS" 2>/dev/null || true

# Fix ownership
chown "$SUDO_UID:$SUDO_GID" "$ROOTFS_IMG"

echo "==="
echo "Rootfs image: $ROOTFS_IMG ($(ls -lh "$ROOTFS_IMG" | awk '{print $5}'))"
echo "Root password: bq268"
echo "Console: ttyGS0 @ 115200 (USB gadget serial) + tty0 (fbcon)"
echo "==="
