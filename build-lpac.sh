#!/usr/bin/env bash
# Cross-build lpac (eSIM LPA) for ARM/musl using an Alpine chroot.
# Must be run as root (for chroot). Outputs binaries to tools/lpac/.
#
# Builds with:
#   - stdio APDU backend (for use with qmicli wrapper)
#   - curl HTTP backend (for SM-DP+ communication)
#   - No PCSC, QMI, MBIM, AT backends
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LPAC_SRC="${SUDO_USER:+/home/$SUDO_USER}/lpac"
LPAC_SRC="${LPAC_SRC:-$HOME/lpac}"
STRIP="${SUDO_USER:+/home/$SUDO_USER}/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-strip"
STRIP="${STRIP:-$HOME/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-strip}"

BUILDROOT="/tmp/alpine-build"
ALPINE_TAR="/tmp/alpine-minirootfs.tar.gz"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/armhf/alpine-minirootfs-3.21.3-armhf.tar.gz"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: must run as root (for chroot)" >&2
    exit 1
fi

if [ ! -d "$LPAC_SRC" ]; then
    echo "ERROR: $LPAC_SRC not found — clone https://github.com/estkme-group/lpac" >&2
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

    mount -t proc proc "$BUILDROOT/proc"
    mount -t sysfs sys "$BUILDROOT/sys"
    mount -t devtmpfs dev "$BUILDROOT/dev"
    chroot "$BUILDROOT" /usr/bin/qemu-arm-static /bin/sh -c \
        'apk add --no-cache gcc musl-dev meson ninja glib-dev linux-headers cmake make curl-dev cjson-dev'
    umount "$BUILDROOT/proc" "$BUILDROOT/sys" "$BUILDROOT/dev"
fi

# Ensure build deps are installed (chroot may exist from libqmi build)
cleanup() {
    umount "$BUILDROOT/src/lpac" 2>/dev/null || true
    umount "$BUILDROOT/proc" 2>/dev/null || true
    umount "$BUILDROOT/sys" 2>/dev/null || true
    umount "$BUILDROOT/dev" 2>/dev/null || true
}
trap cleanup EXIT

mount -t proc proc "$BUILDROOT/proc"
mount -t sysfs sys "$BUILDROOT/sys"
mount -t devtmpfs dev "$BUILDROOT/dev"

# Install lpac build deps if cmake/curl-dev not yet present
chroot "$BUILDROOT" /usr/bin/qemu-arm-static /bin/sh -c \
    'apk add --no-cache cmake make curl-dev cjson-dev 2>/dev/null || true'

mkdir -p "$BUILDROOT/src/lpac"
mount --bind "$LPAC_SRC" "$BUILDROOT/src/lpac"

echo "--- Building lpac ---"
chroot "$BUILDROOT" /usr/bin/qemu-arm-static /bin/sh -c '
cd /src/lpac
rm -rf builddir-arm
cmake -B builddir-arm \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX=/usr \
    -DUSE_SYSTEM_DEPS=ON \
    -DLPAC_WITH_APDU_PCSC=OFF \
    -DLPAC_WITH_APDU_AT=OFF \
    -DLPAC_WITH_APDU_GBINDER=OFF \
    -DLPAC_WITH_APDU_QMI=OFF \
    -DLPAC_WITH_APDU_QMI_QRTR=OFF \
    -DLPAC_WITH_APDU_UQMI=OFF \
    -DLPAC_WITH_APDU_MBIM=OFF \
    -DLPAC_WITH_HTTP_CURL=ON \
    -DLPAC_DYNAMIC_LIBEUICC=ON
cmake --build builddir-arm -j$(nproc)
DESTDIR=/tmp/lpac-install cmake --install builddir-arm
'

echo "--- Installing to tools/lpac/ ---"
OUTDIR="$SCRIPT_DIR/tools/lpac-esim"
mkdir -p "$OUTDIR/driver"

# Copy binaries
cp "$BUILDROOT/tmp/lpac-install/usr/bin/lpac" "$OUTDIR/"

# Copy shared libraries
for lib in libeuicc.so* liblpac-utils.so* libeuicc-drivers.so* libeuicc-driver-loader.so*; do
    for f in "$BUILDROOT"/tmp/lpac-install/usr/lib/$lib; do
        [ -f "$f" ] && cp -a "$f" "$OUTDIR/" || true
    done
    # Also copy symlinks
    for f in "$BUILDROOT"/tmp/lpac-install/usr/lib/$lib; do
        [ -L "$f" ] && cp -a "$f" "$OUTDIR/" || true
    done
done

# Copy driver .so files
for f in "$BUILDROOT"/tmp/lpac-install/usr/lib/lpac/driver/driver_*.so; do
    [ -f "$f" ] && cp -a "$f" "$OUTDIR/driver/" || true
done

REAL_USER="${SUDO_USER:-$(id -un)}"
chown -R "$REAL_USER:" "$OUTDIR"

# Strip debug symbols
if [ -x "$STRIP" ]; then
    "$STRIP" "$OUTDIR/lpac" 2>/dev/null || true
    for f in "$OUTDIR"/*.so* "$OUTDIR"/driver/*.so*; do
        [ -f "$f" ] && "$STRIP" "$f" 2>/dev/null || true
    done
fi

echo "--- Done ---"
ls -lhR "$OUTDIR"/
