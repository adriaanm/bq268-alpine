# BQ268 postmarketOS port recipes
# Run `just` to list available recipes, `just <recipe>` to run one.

kernel_repo := env("HOME") / "bq268-caf_msm-3.18"
edl_dump    := env("HOME") / "bq268-edl/dump"

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

# ── Sibling repo shortcuts ────────────────────────────────────────────────────

# build kernel (delegates to kernel repo)
kernel-build:
    just -f {{kernel_repo}}/justfile build

# build boot.img (delegates to kernel repo)
kernel-bootimg:
    just -f {{kernel_repo}}/justfile bootimg

# ── Firmware extraction ───────────────────────────────────────────────────────

# extract firmware files from EDL dump into firmware/ directory
extract-firmware:
    #!/usr/bin/env bash
    set -eo pipefail
    mkdir -p firmware/modem firmware/wcnss firmware/gpu firmware/wlan
    echo "--- GPU firmware ---"
    # Try vendor partition first, fall back to system
    for part in vendor system; do
        img="{{edl_dump}}/${part}.img"
        [ -f "$img" ] || continue
        mnt=$(mktemp -d)
        sudo mount -o ro,loop "$img" "$mnt" 2>/dev/null || continue
        for fw in a300_pfp.fw a300_pm4.fw; do
            found=$(find "$mnt" -name "$fw" -print -quit 2>/dev/null)
            if [ -n "$found" ]; then
                cp "$found" firmware/gpu/
                echo "  $fw ← $part"
            fi
        done
        sudo umount "$mnt" && rmdir "$mnt"
    done
    echo "--- WCNSS NV data ---"
    persist_img="{{edl_dump}}/persist.img"
    if [ -f "$persist_img" ]; then
        mnt=$(mktemp -d)
        sudo mount -o ro,loop "$persist_img" "$mnt" 2>/dev/null || true
        nv=$(find "$mnt" -name "WCNSS_qcom_wlan_nv.bin" -print -quit 2>/dev/null)
        [ -n "$nv" ] && cp "$nv" firmware/wlan/ && echo "  WCNSS_qcom_wlan_nv.bin ← persist"
        sudo umount "$mnt" 2>/dev/null; rmdir "$mnt" 2>/dev/null
    fi
    echo "--- Modem + WCNSS firmware ---"
    modem_img="{{edl_dump}}/modem.img"
    if [ -f "$modem_img" ]; then
        mnt=$(mktemp -d)
        sudo mount -o ro,loop "$modem_img" "$mnt" 2>/dev/null || {
            # modem partition may be a flat image, not ext4
            echo "  modem.img is not ext4 — try raw copy"
            rmdir "$mnt"
        }
        if mountpoint -q "$mnt" 2>/dev/null; then
            cp "$mnt"/image/modem.* firmware/modem/ 2>/dev/null && echo "  modem.mdt + segments ← modem" || true
            cp "$mnt"/image/wcnss.* firmware/wcnss/ 2>/dev/null && echo "  wcnss.mdt + segments ← modem" || true
            sudo umount "$mnt"; rmdir "$mnt"
        fi
    fi
    echo "---"
    echo "Firmware files:"
    find firmware/ -type f | sort
