#!/usr/bin/env bash
# Build Alpine Linux rootfs for BQ268 walkie-talkie
# Must be run as root (for chroot/mount)
#
# Produces: out/rootfs.img (ext4, flash to userdata via fastboot)
# Login: root / bq268
# Console: ttyGS0 @ 115200 (USB gadget serial) + tty0 (fbcon)
#
# Feature modules live in rootfs/*.sh and are sourced in order.
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

# ── 4. Source feature modules ─────────────────────────────────────────────
for mod in "$SCRIPT_DIR"/rootfs/[0-9][0-9]-*.sh; do
    [ -f "$mod" ] || continue
    echo "--- Running $(basename "$mod") ---"
    source "$mod"
done

# ── 5. Cleanup and finalize ──────────────────────────────────────────────
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
