# BQ268 postmarketOS port recipes
# Run `just` to list available recipes, `just <recipe>` to run one.

kernel_repo := env("HOME") / "bq268-caf_msm-3.18"
edl_dump    := env("HOME") / "bq268-edl/dump"
lk2nd_repo  := env("HOME") / "lk2nd"
outdir      := "out"

# list recipes
default:
    @just --list

# ── Experiment & task tracking ────────────────────────────────────────────────

# show experiment log
experiments:
    git log --oneline --notes=experiments --notes=tasks

# note an experiment outcome on HEAD (e.g. just note "BOOT TEST: PASS")
note message:
    git notes --ref=experiments append HEAD -m "{{message}}"

# show current tasks
tasks:
    @git notes --ref=tasks show HEAD 2>/dev/null || echo "No tasks on HEAD"

# add a task (e.g. just task-add "Build lk2nd for MSM8909")
task-add description:
    #!/usr/bin/env bash
    existing=$(git notes --ref=tasks show HEAD 2>/dev/null || true)
    if [ -z "$existing" ]; then
        git notes --ref=tasks add -f HEAD -m "[todo] {{description}}"
    else
        tmpf=$(mktemp)
        printf '%s\n[todo] %s\n' "$existing" "{{description}}" > "$tmpf"
        git notes --ref=tasks add -f -F "$tmpf" HEAD
        rm -f "$tmpf"
    fi

# mark a task done (matches substring)
task-done pattern:
    #!/usr/bin/env bash
    existing=$(git notes --ref=tasks show HEAD 2>/dev/null || true)
    if [ -z "$existing" ]; then
        echo "No tasks on HEAD"; exit 1
    fi
    tmpf=$(mktemp)
    echo "$existing" | sed '/\[todo\].*{{pattern}}/s/\[todo\]/[done]/' | \
        sed '/\[in_progress\].*{{pattern}}/s/\[in_progress\]/[done]/' > "$tmpf"
    git notes --ref=tasks add -f -F "$tmpf" HEAD
    rm -f "$tmpf"
    git notes --ref=tasks show HEAD

# mark a task in-progress (matches substring)
task-start pattern:
    #!/usr/bin/env bash
    existing=$(git notes --ref=tasks show HEAD 2>/dev/null || true)
    if [ -z "$existing" ]; then
        echo "No tasks on HEAD"; exit 1
    fi
    tmpf=$(mktemp)
    echo "$existing" | sed '/\[todo\].*{{pattern}}/s/\[todo\]/[in_progress]/' > "$tmpf"
    git notes --ref=tasks add -f -F "$tmpf" HEAD
    rm -f "$tmpf"
    git notes --ref=tasks show HEAD

# ── lk2nd ────────────────────────────────────────────────────────────────

# build lk2nd bootloader for MSM8909
lk2nd-build:
    cd {{lk2nd_repo}} && make TOOLCHAIN_PREFIX=arm-none-eabi- lk2nd-msm8909 -j$(nproc)
    mkdir -p {{outdir}}
    cp {{lk2nd_repo}}/build-lk2nd-msm8909/lk2nd.img {{outdir}}/lk2nd.img
    @ls -lh {{outdir}}/lk2nd.img

# clean lk2nd build
lk2nd-clean:
    cd {{lk2nd_repo}} && make clean 2>/dev/null || true

# ── Rootfs ───────────────────────────────────────────────────────────────

# build Alpine rootfs image (requires sudo)
build-rootfs:
    sudo bash build-rootfs.sh

# ── Sibling repo shortcuts ────────────────────────────────────────────────────

# build kernel (delegates to kernel repo)
kernel-build:
    just -f {{kernel_repo}}/justfile build

# build boot.img (delegates to kernel repo)
kernel-bootimg:
    just -f {{kernel_repo}}/justfile bootimg

# ── QEMU testing ──────────────────────────────────────────────────────────

# boot rootfs in QEMU (tests Alpine userspace without real hardware)
qemu-test:
    #!/usr/bin/env bash
    set -eo pipefail
    kernel="{{outdir}}/qemu/vmlinuz-virt"
    initrd="{{outdir}}/qemu/initramfs.cpio.gz"
    rootfs="{{outdir}}/rootfs.img"
    for f in "$kernel" "$initrd" "$rootfs"; do
        [ -f "$f" ] || { echo "ERROR: $f not found"; exit 1; }
    done
    echo "Booting rootfs in QEMU (Ctrl-A X to quit)..."
    echo "Login: root / bq268"
    qemu-system-arm \
        -machine virt \
        -cpu cortex-a7 \
        -m 512 \
        -kernel "$kernel" \
        -initrd "$initrd" \
        -drive file="$rootfs",if=none,format=raw,id=hd0,snapshot=on \
        -device virtio-blk-pci,drive=hd0 \
        -append "console=ttyAMA0 root=/dev/vda rootfstype=ext2 rw" \
        -serial stdio \
        -display none \
        -no-reboot

# ── Flash ────────────────────────────────────────────────────────────────

# flash lk2nd to boot partition (device must be in fastboot mode)
flash-lk2nd:
    #!/usr/bin/env bash
    set -eo pipefail
    img="{{outdir}}/lk2nd.img"
    [ -f "$img" ] || { echo "ERROR: $img not found — run 'just lk2nd-build' first"; exit 1; }
    echo "Flashing lk2nd to boot partition..."
    echo "  Image: $img ($(ls -lh "$img" | awk '{print $5}'))"
    echo "  WARNING: This replaces the boot partition. Stock aboot is NOT touched."
    read -p "  Continue? [y/N] " confirm
    [ "$confirm" = "y" ] || { echo "Aborted."; exit 1; }
    fastboot flash boot "$img"
    echo "Done. Reboot to enter lk2nd (hold Vol Down for fastboot)."

# flash rootfs to system partition (device must be in fastboot mode)
flash-rootfs:
    #!/usr/bin/env bash
    set -eo pipefail
    img="{{outdir}}/rootfs.img"
    [ -f "$img" ] || { echo "ERROR: $img not found — run 'just build-rootfs' first"; exit 1; }
    echo "Flashing rootfs to system partition..."
    echo "  Image: $img ($(ls -lh "$img" | awk '{print $5}'))"
    echo "  WARNING: This ERASES the system partition (Android is replaced with Alpine)."
    read -p "  Continue? [y/N] " confirm
    [ "$confirm" = "y" ] || { echo "Aborted."; exit 1; }
    fastboot flash system "$img"
    echo "Done."

# flash everything (lk2nd + rootfs)
flash-all: flash-lk2nd flash-rootfs
    @echo "All images flashed. Run: fastboot reboot"

# reboot device from fastboot
reboot:
    fastboot reboot

# connect to USB gadget serial console (ttyACM0)
serial:
    @echo "Connecting to USB gadget serial (Ctrl-A Ctrl-X to quit)..."
    picocom -b 115200 /dev/ttyACM0

# ── Firmware extraction ───────────────────────────────────────────────────────

# extract firmware files from EDL dump into firmware/ directory
extract-firmware:
    #!/usr/bin/env bash
    set -eo pipefail
    mkdir -p firmware/modem firmware/wcnss firmware/gpu firmware/wlan
    echo "--- GPU firmware ---"
    outdir="$(pwd)/firmware"
    # Try vendor partition first, fall back to system
    for part in vendor system; do
        img="{{edl_dump}}/${part}.bin"
        [ -f "$img" ] || continue
        mnt=$(mktemp -d)
        sudo mount -o ro,loop "$img" "$mnt" 2>/dev/null || { rmdir "$mnt"; continue; }
        for fw in a300_pfp.fw a300_pm4.fw; do
            found=$(sudo find "$mnt" -name "$fw" -print -quit 2>/dev/null)
            if [ -n "$found" ]; then
                sudo cp "$found" "$outdir/gpu/"
                echo "  $fw ← $part"
            fi
        done
        sudo umount "$mnt" && rmdir "$mnt"
    done
    echo "--- WCNSS NV data ---"
    persist_img="{{edl_dump}}/persist.bin"
    if [ -f "$persist_img" ]; then
        mnt=$(mktemp -d)
        sudo mount -o ro,loop "$persist_img" "$mnt" 2>/dev/null || { rmdir "$mnt"; persist_img=""; }
        if mountpoint -q "$mnt" 2>/dev/null; then
            nv=$(sudo find "$mnt" -name "WCNSS_qcom_wlan_nv.bin" -print -quit 2>/dev/null)
            [ -n "$nv" ] && sudo cp "$nv" "$outdir/wlan/" && echo "  WCNSS_qcom_wlan_nv.bin ← persist"
            sudo umount "$mnt"; rmdir "$mnt"
        fi
    fi
    echo "--- Modem + WCNSS firmware ---"
    modem_img="{{edl_dump}}/modem.bin"
    if [ -f "$modem_img" ]; then
        mnt=$(mktemp -d)
        # modem partition is FAT16
        sudo mount -o ro,loop -t vfat "$modem_img" "$mnt" 2>/dev/null || {
            echo "  WARN: modem.bin mount failed (expected FAT16)"
            rmdir "$mnt"
            mnt=""
        }
        if [ -n "$mnt" ] && mountpoint -q "$mnt" 2>/dev/null; then
            sudo cp "$mnt"/image/modem.* "$outdir/modem/" 2>/dev/null && echo "  modem.mdt + segments ← modem" || true
            sudo cp "$mnt"/image/wcnss.* "$outdir/wcnss/" 2>/dev/null && echo "  wcnss.mdt + segments ← modem" || true
            sudo cp "$mnt"/image/mba.mbn "$outdir/modem/" 2>/dev/null && echo "  mba.mbn ← modem" || true
            sudo umount "$mnt"; rmdir "$mnt"
        fi
    fi
    echo "--- WiFi config from system ---"
    system_img="{{edl_dump}}/system.bin"
    if [ -f "$system_img" ]; then
        mnt=$(mktemp -d)
        sudo mount -o ro,loop "$system_img" "$mnt" 2>/dev/null || { rmdir "$mnt"; system_img=""; }
        if mountpoint -q "$mnt" 2>/dev/null; then
            for cfg in WCNSS_cfg.dat; do
                found=$(sudo find "$mnt" -name "$cfg" -print -quit 2>/dev/null)
                [ -n "$found" ] && sudo cp "$found" "$outdir/wlan/" && echo "  $cfg ← system"
            done
            sudo umount "$mnt"; rmdir "$mnt"
        fi
    fi
    sudo chown -R "$(id -u):$(id -g)" "$outdir"
    echo "---"
    echo "Firmware files:"
    find firmware/ -type f | sort
