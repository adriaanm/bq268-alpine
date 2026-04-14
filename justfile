# BQ268 Alpine Linux port recipes
# Run `just` to list available recipes, `just <recipe>` to run one.

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

zig         := env("ZIG", home_dir() / "zig-x86_64-linux-0.16.0-dev.3059+42e33db9d/zig")

# cross-compile tools/ for ARM
build-tools: build-wata-metricsd
    arm-linux-gnueabihf-gcc -static -o tools/reboot-bootloader tools/reboot-bootloader.c
    arm-linux-gnueabihf-gcc -static -o tools/rmt_storage tools/rmt_storage.c
    ~/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-gcc -std=c99 -Wall -Wextra -Werror -fPIC -shared -o tools/libqipcrtr4msmipc.so tools/libqipcrtr4msmipc.c -ldl
    ~/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-gcc -static -O2 -o tools/qmi-send-apdu tools/qmi-send-apdu.c
    ~/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-gcc -static -O2 -o tools/diag-apdu tools/diag-apdu.c
    ~/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-gcc -static -O2 -o tools/diag-efs-write tools/diag-efs-write.c
    ~/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-gcc -static -O2 -Wall -o tools/cell-diag tools/cell-diag.c

# cross-compile wata-metricsd (Zig 0.16-dev → arm-linux-musleabihf, ReleaseSmall ≈ 65 KB)
build-wata-metricsd:
    cd tools/wata-metricsd && {{zig}} build -Dtarget=arm-linux-musleabihf -Doptimize=ReleaseSmall

# run wata-metricsd unit tests
test-wata-metricsd:
    cd tools/wata-metricsd && {{zig}} build test --summary all

# host-side end-to-end smoke test: build native, run with /tmp paths and
# --max-iters=3 (clean exit, no kill), send 3 ticks, verify JSONL output
smoke-wata-metricsd:
    #!/usr/bin/env bash
    set -eo pipefail
    cd tools/wata-metricsd
    {{zig}} build
    SMOKEDIR=$(mktemp -d -t wata-metricsd-smoke.XXXXXX)
    trap 'rm -rf "$SMOKEDIR"' EXIT
    ./zig-out/bin/wata-metricsd --tick="$SMOKEDIR/wata.tick" --log="$SMOKEDIR/log" --max-iters=3 >"$SMOKEDIR/stderr.log" 2>&1 &
    PID=$!
    sleep 0.2
    python3 scripts/send-tick.py --path "$SMOKEDIR/wata.tick" --count 3 --interval-ms 30
    wait $PID
    LINES=$(wc -l <"$SMOKEDIR/log/current.jsonl")
    echo "got $LINES JSONL lines:"
    cat "$SMOKEDIR/log/current.jsonl"
    test "$LINES" = "3"

# cross-compile libqmi with AF_MSM_IPC support (requires sudo for chroot)
build-libqmi:
    #!/usr/bin/env bash
    set -eo pipefail
    sudo bash build-libqmi.sh
    echo "--- Output in tools/libqmi/ ---"
    ls -lh tools/libqmi/

# cross-compile lpac (eSIM LPA) for ARM/musl (requires sudo for chroot)
build-lpac:
    #!/usr/bin/env bash
    set -eo pipefail
    sudo bash build-lpac.sh
    echo "--- Output in tools/lpac-esim/ ---"
    ls -lhR tools/lpac-esim/

# build Alpine rootfs image (requires sudo)
# Ensures firmware is extracted and modem patch applied before building.
build-rootfs: extract-firmware patch-modem build-tools
    sudo bash build-rootfs.sh

# ── Cellular ─────────────────────────────────────────────────────────────

# Regenerate rootfs/files/etc/cellular/roaming-partners from
# eskimo_roaming.md + tools/data/mcc-mnc-list.json. Re-run after
# editing the Eskimo list or bumping the vendored MCC/MNC database.
gen-roaming-partners:
    python3 tools/gen-roaming-partners.py

# Push the current cell-data.sh to the device in-place (no rebuild).
push-cell-data:
    scp -q tools/cell-data.sh bq268:/usr/sbin/cell-data
    ssh bq268 'chmod +x /usr/sbin/cell-data && sh -n /usr/sbin/cell-data && echo ok'

# Build + push cell-diag and run it in the background for DURATION
# seconds against the live device, then fetch the log. Useful for
# capturing NAS reject causes during a failing attach attempt.
#   just diag-capture             # 60s default
#   just diag-capture 120         # 2 minutes
diag-capture duration="60":
    #!/usr/bin/env bash
    set -eo pipefail
    ~/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-gcc -static -O2 -Wall -o tools/cell-diag tools/cell-diag.c
    scp -q tools/cell-diag bq268:/tmp/cell-diag
    ssh bq268 'chmod +x /tmp/cell-diag && : > /tmp/cell-diag.log && \
        /tmp/cell-diag -o /tmp/cell-diag.log -d >/tmp/cell-diag.stderr 2>&1 & \
        echo $! >/tmp/cell-diag.pid; sleep 1; \
        echo "=== triggering wake ==="; cell-data wake || true; \
        sleep {{duration}}; \
        kill -TERM $(cat /tmp/cell-diag.pid) 2>/dev/null || true; \
        sleep 1; \
        echo "=== stderr ==="; cat /tmp/cell-diag.stderr; \
        echo "=== log lines: $(wc -l </tmp/cell-diag.log) ===" '
    scp -q bq268:/tmp/cell-diag.log ./cell-diag.log
    echo "--- cell-diag.log (tail) ---"
    tail -n 40 ./cell-diag.log || true

# LTE-only DIAG capture: force lte,automatic before wake so the modem
# cannot fall back to UMTS. Answers "does the modem ever transmit an
# RRC Connection Request (UL_CCCH) on LTE?" — key datapoint for the
# B20 UL-TX hypothesis. Restores lte|umts,automatic on exit.
#   just diag-capture-lte          # 90s default
diag-capture-lte duration="90":
    #!/usr/bin/env bash
    set -eo pipefail
    ~/arm-linux-musleabihf-cross/bin/arm-linux-musleabihf-gcc -static -O2 -Wall -o tools/cell-diag tools/cell-diag.c
    scp -q tools/cell-diag bq268:/tmp/cell-diag
    scp -q tools/cell-data.sh bq268:/usr/sbin/cell-data
    ssh bq268 'chmod +x /usr/sbin/cell-data && sh -n /usr/sbin/cell-data'
    ssh bq268 'chmod +x /tmp/cell-diag && : > /tmp/cell-diag.log && \
        /tmp/cell-diag -o /tmp/cell-diag.log -d >/tmp/cell-diag.stderr 2>&1 & \
        echo $! >/tmp/cell-diag.pid; sleep 1; \
        echo "=== triggering LTE-only wake ==="; CELL_DATA_RAT=lte cell-data wake || true; \
        sleep {{duration}}; \
        kill -TERM $(cat /tmp/cell-diag.pid) 2>/dev/null || true; \
        sleep 1; \
        echo "=== restoring lte|umts ==="; cell-data wake || true; \
        echo "=== stderr ==="; tail -n 20 /tmp/cell-diag.stderr; \
        echo "=== log lines: $(wc -l </tmp/cell-diag.log) ===" '
    scp -q bq268:/tmp/cell-diag.log ./cell-diag-lte.log
    echo "--- cell-diag-lte.log (RRC summary) ---"
    grep RRC_SUMMARY ./cell-diag-lte.log || echo "(no RRC_SUMMARY line — capture aborted?)"
    echo "--- RRC channel breakdown (parsed events) ---"
    grep '"event":"LTE_RRC_OTA"' ./cell-diag-lte.log | \
        sed -n 's/.*"ch_name":"\([^"]*\)".*/\1/p' | sort | uniq -c || true

# End-to-end cellular smoke test against the live device. Bounded at
# ~2 minutes: wake (LTE-only, automatic, PS attach 90s), pppd up
# (30s), ping, teardown. Exits non-zero on any failure.
smoke-cellular:
    #!/usr/bin/env bash
    set -eo pipefail
    ssh bq268 'set -e; \
        echo "=== wake ==="; time cell-data wake; \
        echo "=== up ===";   time cell-data up; \
        echo "=== ping ==="; ping -c 3 -W 5 -I ppp0 8.8.8.8; \
        echo "=== status ==="; cell-data status; \
        echo "=== down ==="; cell-data down'

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

# sync rootfs from buildbox
sync:
    rsync -av {{buildbox}}:~/bq268-alpine/out/rootfs.img {{outdir}}/

# ── Flash ────────────────────────────────────────────────────────────────

# flash rootfs to userdata partition (device must be in fastboot mode)
flash-rootfs:
    #!/usr/bin/env bash
    set -eo pipefail
    img="{{outdir}}/rootfs.img"
    [ -f "$img" ] || { echo "ERROR: $img not found — run 'just build-rootfs' first"; exit 1; }
    echo "Flashing $img ($(ls -lh "$img" | awk '{print $5}')) → userdata"
    fastboot flash userdata "$img"

# patch modem firmware for eSIM (APDU restriction bypass only)
patch-modem:
    python3 tools/patch-modem-b12.py firmware/modem

# check modem patch status without modifying
check-modem:
    python3 tools/patch-modem-b12.py firmware/modem --check

# deploy patched modem firmware to device (must be reachable via ssh)
flash-modem:
    scp firmware/modem/modem.b12 firmware/modem/modem.b14 firmware/modem/modem.b01 firmware/modem/modem.mdt bq268:/lib/firmware/
    ssh bq268 'sync'
    @echo "Firmware deployed. Reboot device to apply."

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
