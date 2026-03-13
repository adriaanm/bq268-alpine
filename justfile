# BQ268 postmarketOS port recipes
# Run `just` to list available recipes, `just <recipe>` to run one.

kernel_repo := env("HOME") / "bq268-kernel"
edl_dump    := env("HOME") / "bq268-edl/dump"
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

# ── Rootfs ───────────────────────────────────────────────────────────────

# build Alpine rootfs image (requires sudo)
build-rootfs:
    sudo bash build-rootfs.sh

# ── Sibling repo shortcuts ────────────────────────────────────────────────────

# build mainline kernel for MSM8909
kernel-build:
    #!/usr/bin/env bash
    set -eo pipefail
    cd {{kernel_repo}}
    export ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- O=output
    if [ ! -f output/.config ]; then
        echo "--- Generating config from msm8916_defconfig ---"
        make msm8916_defconfig
    fi
    echo "--- Building kernel ---"
    make -j$(nproc)
    echo "---"
    ls -lh output/arch/arm/boot/zImage
    ls -lh output/arch/arm/boot/dts/qcom/qcom-msm8909-udotech-bq268.dtb
    # Copy to output/ root for easy access
    cp output/arch/arm/boot/zImage output/zImage
    cp output/arch/arm/boot/dts/qcom/qcom-msm8909-udotech-bq268.dtb output/qcom-msm8909-udotech-bq268.dtb

# ── boot.img (for stock aboot) ────────────────────────────────────────────────

# build boot.img: mainline kernel + appended DTB + initramfs, for aboot
build-bootimg:
    #!/usr/bin/env bash
    set -eo pipefail
    mkdir -p {{outdir}}
    zimage="{{kernel_repo}}/out/zImage"
    dtb="{{kernel_repo}}/out/qcom-msm8909-udotech-bq268.dtb"
    # Verify DTB has board-id (aboot won't find it otherwise)
    if command -v fdtget >/dev/null 2>&1; then
        msm_id=$(fdtget "$dtb" / qcom,msm-id 2>/dev/null || true)
        board_id=$(fdtget "$dtb" / qcom,board-id 2>/dev/null || true)
        if [ -z "$msm_id" ] || [ -z "$board_id" ]; then
            echo "ERROR: DTB missing qcom,msm-id or qcom,board-id — aboot will not find it!"
            echo "  Add to DTS: qcom,msm-id = <245 0>; qcom,board-id = <0x08 0x100>;"
            exit 1
        fi
        echo "  DTB msm-id=$msm_id board-id=$board_id"
    fi
    # Append DTB to kernel (aboot scans for FDT magic 0xd00dfeed)
    echo "--- Creating kernel+dtb ---"
    cat "$zimage" "$dtb" > {{outdir}}/zImage-dtb
    # Build boot.img (base/addresses don't matter — aboot hardcodes them)
    # No ramdisk — kernel mounts root= directly
    echo "--- Building boot.img ---"
    mkbootimg \
        --kernel {{outdir}}/zImage-dtb \
        --cmdline "root=LABEL=rootfs rootfstype=ext4 rootwait rw console=tty0 console=ttyGS0,115200 fbcon=rotate:1 consoleblank=0 panic=5" \
        --base 0x80000000 \
        --pagesize 2048 \
        -o {{outdir}}/boot.img
    echo "---"
    ls -lh {{outdir}}/boot.img

# generate ST7735S panel firmware binary for panel-mipi-dbi driver
gen-panel-fw:
    #!/usr/bin/env bash
    set -eo pipefail
    mkdir -p firmware/panel
    python3 {{kernel_repo}}/scripts/gen-panel-fw.py firmware/panel/udotech,bq268-st7735s-panel.bin
    ls -lh firmware/panel/udotech,bq268-st7735s-panel.bin

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
        -append "console=ttyAMA0 root=/dev/vda rootfstype=ext4 rw" \
        -serial stdio \
        -display none \
        -no-reboot

# ── Sync (pull build artifacts from buildbox) ─────────────────────────────

buildbox := "debian"

# sync all build artifacts from buildbox
sync:
    rsync -av {{buildbox}}:~/bq268-pmos/out/rootfs.img {{outdir}}/
    rsync -av {{buildbox}}:~/bq268-kernel/out/boot.img {{outdir}}/ 2>/dev/null || true

# sync rootfs only
sync-rootfs:
    rsync -av {{buildbox}}:~/bq268-pmos/out/rootfs.img {{outdir}}/

# sync boot.img only
sync-boot:
    rsync -av {{buildbox}}:~/bq268-kernel/out/boot.img {{outdir}}/

# ── Flash ────────────────────────────────────────────────────────────────

# flash boot.img to boot partition (device must be in fastboot mode)
flash-boot:
    #!/usr/bin/env bash
    set -eo pipefail
    img="{{outdir}}/boot.img"
    [ -f "$img" ] || { echo "ERROR: $img not found — run 'just sync-boot' first"; exit 1; }
    echo "Flashing $img ($(ls -lh "$img" | awk '{print $5}')) → boot"
    fastboot flash boot "$img"

# flash rootfs to userdata partition (device must be in fastboot mode)
flash-rootfs:
    #!/usr/bin/env bash
    set -eo pipefail
    img="{{outdir}}/rootfs.img"
    [ -f "$img" ] || { echo "ERROR: $img not found — run 'just sync-rootfs' first"; exit 1; }
    echo "Flashing $img ($(ls -lh "$img" | awk '{print $5}')) → userdata"
    fastboot flash userdata "$img"

# flash everything (boot.img + rootfs)
flash-all: flash-boot flash-rootfs
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
