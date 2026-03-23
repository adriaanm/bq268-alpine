#!/usr/bin/env bash
# Cross-build libqmi (with AF_MSM_IPC) for ARM/musl using an Alpine chroot.
# Must be run as root (for chroot). Outputs stripped binaries to tools/libqmi/.
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LIBQMI_SRC="${SUDO_USER:+/home/$SUDO_USER}/libqmi"
LIBQMI_SRC="${LIBQMI_SRC:-$HOME/libqmi}"
STRIP="${SUDO_USER:+/home/$SUDO_USER}/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-strip"
STRIP="${STRIP:-$HOME/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-strip}"

BUILDROOT="/tmp/alpine-build"
ALPINE_TAR="/tmp/alpine-minirootfs.tar.gz"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/armhf/alpine-minirootfs-3.21.3-armhf.tar.gz"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (for chroot)" >&2
    exit 1
fi

if [ ! -d "$LIBQMI_SRC" ]; then
    echo "ERROR: $LIBQMI_SRC not found" >&2
    exit 1
fi

# Download Alpine minirootfs if needed
if [ ! -f "$ALPINE_TAR" ]; then
    echo "--- Downloading Alpine minirootfs ---"
    wget -q -O "$ALPINE_TAR" "$ALPINE_URL"
fi

# Set up chroot if not already present
if [ ! -f "$BUILDROOT/usr/bin/qemu-arm-static" ]; then
    echo "--- Setting up build chroot ---"
    rm -rf "$BUILDROOT"
    mkdir -p "$BUILDROOT"
    tar xzf "$ALPINE_TAR" -C "$BUILDROOT"
    cp /usr/bin/qemu-arm-static "$BUILDROOT/usr/bin/"
    cp /etc/resolv.conf "$BUILDROOT/etc/"

    # Install build deps
    mount -t proc proc "$BUILDROOT/proc"
    mount -t sysfs sys "$BUILDROOT/sys"
    mount -t devtmpfs dev "$BUILDROOT/dev"
    chroot "$BUILDROOT" /usr/bin/qemu-arm-static /bin/sh -c \
        'apk add --no-cache gcc musl-dev meson ninja glib-dev linux-headers'
    umount "$BUILDROOT/proc" "$BUILDROOT/sys" "$BUILDROOT/dev"
fi

# Mount for build
cleanup() {
    umount "$BUILDROOT/src/libqmi" 2>/dev/null || true
    umount "$BUILDROOT/proc" 2>/dev/null || true
    umount "$BUILDROOT/sys" 2>/dev/null || true
    umount "$BUILDROOT/dev" 2>/dev/null || true
}
trap cleanup EXIT

mount -t proc proc "$BUILDROOT/proc"
mount -t sysfs sys "$BUILDROOT/sys"
mount -t devtmpfs dev "$BUILDROOT/dev"
mkdir -p "$BUILDROOT/src/libqmi"
mount --bind "$LIBQMI_SRC" "$BUILDROOT/src/libqmi"

echo "--- Building libqmi ---"
chroot "$BUILDROOT" /usr/bin/qemu-arm-static /bin/sh -c '
cd /src/libqmi
rm -rf builddir-arm
meson setup builddir-arm \
    -Dmsmipc=true \
    -Dqrtr=false \
    -Dmbim_qmux=false \
    -Dudev=false \
    -Dintrospection=false \
    -Dman=false \
    -Dfirmware_update=false \
    -Dbash_completion=false \
    -Dprefix=/usr
ninja -C builddir-arm
DESTDIR=/tmp/libqmi-install ninja -C builddir-arm install
'

echo "--- Installing to tools/libqmi/ ---"
OUTDIR="$SCRIPT_DIR/tools/libqmi"
mkdir -p "$OUTDIR"

# Copy and fix ownership
cp "$BUILDROOT/tmp/libqmi-install/usr/lib/libqmi-glib.so.5.12.0" "$OUTDIR/"
cp "$BUILDROOT/tmp/libqmi-install/usr/bin/qmicli" "$OUTDIR/"
cp "$BUILDROOT/tmp/libqmi-install/usr/bin/qmi-network" "$OUTDIR/"
cp "$BUILDROOT/tmp/libqmi-install/usr/libexec/qmi-proxy" "$OUTDIR/"

REAL_USER="${SUDO_USER:-$(id -un)}"
chown "$REAL_USER:" "$OUTDIR"/*

# Strip debug symbols
if [ -x "$STRIP" ]; then
    "$STRIP" "$OUTDIR/libqmi-glib.so.5.12.0"
    "$STRIP" "$OUTDIR/qmicli"
    "$STRIP" "$OUTDIR/qmi-proxy"
fi

echo "--- Done ---"
ls -lh "$OUTDIR"/
