# CLAUDE.md — bq268-alpine

## Project

Alpine Linux port for the BQ268 walkie-talkie.
Single-app device: fast boot, low RAM, mainline kernel, open source.
Inspired by the postmarketOS project's approach to running mainline Linux on Qualcomm phones.

## Build Environment

This repo runs on a headless buildbox. The device is attached directly — `just flash-*` and `ssh bq268` work from this machine.

## Hardware

- **SoC**: MSM8909 (Snapdragon 210), 4× Cortex-A7 @ 1.267 GHz, 32-bit ARM
- **RAM**: ~512 MB
- **Storage**: eMMC 8-bit DDR HS200
- **Display**: ST7735S 128×160 SPI (BLSP1 QUP5), 27 Hz, RGB565, 90° rotation
- **Audio**: MSM8x16 WCD internal codec + external class-D PA on GPIO36
- **WiFi/BT**: WCNSS (Pronto) + WCN3620
- **Modem**: Hexagon DSP, 4G LTE data-only
- **Keypad**: 2×3 GPIO matrix (UP/DOWN/LEFT/RIGHT/BACK/SELECT) + 4 GPIO keys (F1=PTT, F2, F3, F6)
- **Power switch**: Toggle switch (not a button), generates SW_LID on gpio-keys. Handled by keyd.
- **LEDs**: GPIO1 (button backlight), GPIO68 (red), GPIO69 (green)
- **USB**: HS device-mode only
- **Battery**: Linear charger + VM-BMS, 4.2V / 2300mAh, ibatsafe=800mA
- **PMIC**: PM8909 via SPMI

## Sibling Repos

| Repo | Path | Contents |
|------|------|----------|
| Kernel (CAF 4.4) | `~/bq268-caf-4.4` | CAF 4.4.302 kernel, BQ268 DTS, modules (wlan.ko) — the production kernel |
| EDL dumps | `~/bq268-edl/dump` | Full partition dumps from device |
| libqmi | `~/libqmi` | Custom libqmi with native AF_MSM_IPC support |
| lpac | `~/lpac` | eSIM LPA (cross-compiled for ARM/musl) |
| Modem DIAG tools | `~/bq268-modem-diag` | Qualcomm DIAG tools (cell-diag, diag-apdu, diag-efs-write) — extracted from this repo, being ported to Zig |
| Modem FW workshop | `~/bq268-modem-fw` | Hexagon decompilation of the MPSS firmware. Historically used to iterate firmware patches; bq268-alpine itself no longer ships or needs any modem patches — lpac runs against golden firmware via `tools/qmi-send-apdu`. |

## Key Decisions

- **CAF 4.4 kernel** — vendor drivers for modem, audio, WiFi, bus scaling. Mainline 6.19 abandoned (PMIC brownouts from missing RPM bus bandwidth voting).
- **Custom aboot** — built from our own lk/aboot repo, flashed to `aboot` partition.
- **CAF MDSS** for display — ST7735S via SPI, fbcon works directly.
- **USB configfs** for gadget serial + RNDIS.
- **Firmware from EDL dumps** — extract offline, bake into rootfs. No runtime partition reading.
- **Data-only modem** — no voice calls, no VoLTE/IMS.
- **No camera, GPS, sensors, touchscreen** — none fitted.
- **No CPU hotplug or suspend** — re-onlining CPUs crashes the device (CAF 4.4 SPM/power-collapse bug). Suspend-to-RAM likely broken for the same reason. Power saving is governor-only (powersave when screen off, ondemand when on).

## Boot Chain

`aboot (custom lk)` → reads `boot` partition → `boot.img` (zImage-dtb + initramfs)

### boot.img constraints (aboot requirements)

- **32-bit ARM zImage** — aboot checks magic at kernel+0x38. Cortex-A7, no ARM64.
- **Appended DTB** — aboot ignores `dt_size` in boot.img header. It scans the kernel
  image for FDT magic (0xd00dfeed) and matches by `qcom,msm-id` + `qcom,board-id`.
  Build: `cat zImage dtb > zImage-dtb`, then `mkbootimg --kernel zImage-dtb`.
- **DTB board-id matching** — mainline DTB **must** contain:
  ```
  qcom,msm-id = <245 0>;   /* 245 = MSM8909 */
  qcom,board-id = <0x08 0x100>;   /* 8 = MTP, 0x100 = subtype */
  ```
  Without these, `dev_tree_appended()` fails silently and no DTB is passed to the kernel.
- **Hardcoded addresses** — aboot forces kernel=0x80008000, ramdisk=0x82300000,
  tags=0x82100000 regardless of boot.img header values.
- **Quiet boot (2026-08-05)** — the LIVE boot partition's header cmdline was
  patched in place (page 0 only): `loglevel=7` dropped, `quiet logo.nologo
  vt.global_cursor_default=0` appended. The flashed image did NOT match any
  `out/*.img` (it is a later buildbox assembly); source of truth is the device
  partition itself. Backup of the pre-patch partition: `out/boot-live-backup-
  20260805.img` (sha256 a37edc19…); patched: `out/boot-quiet-20260805.img`
  (914d655b…). Method: dd the 2048-byte page 0 over `/dev/mmcblk0p5`
  (PARTNAME=boot), readback-verified, reboot BOOT TEST PASS. Any future
  boot.img assembly must carry the quiet cmdline forward.
- **Cmdline** — aboot appends its own params (`androidboot.*`, `verifiedbootstate`, etc.)
  to whatever is set in the boot.img header. Mainline ignores the android-specific ones.

## Firmware Files Needed

Extracted from EDL dumps into `/lib/firmware/`:

| File | Source partition | Driver |
|------|----------------|--------|
| `udotech,bq268-st7735s-panel.bin` | generated (gen-panel-fw.py) | panel-mipi-dbi-spi |
| `modem.mdt` + `modem.b00-b25` | modem | q6v5-mss |
| `wcnss.mdt` + `wcnss.b00-b12` | modem | wcnss-pil (pronto) |
| `a300_pfp.fw`, `a300_pm4.fw` | vendor (or linux-firmware) | Freedreno |
| `WCNSS_qcom_wlan_nv.bin` | persist | wcn36xx |

## Workflows

### Reproducibility

All repeated commands go in the `justfile`. Single entry point for build, flash, firmware extraction.

### Build After Every Change

After any change to rootfs or build scripts, always run `just build-rootfs` so the user can flash immediately.

### Commit Granularly

Each logical change gets its own commit — don't batch unrelated work. A "logical change" is one thing you could describe in a single sentence, e.g.:
- Add WiFi init script for CAF WCNSS bringup
- Fix fbcon rotation (rotate:1 → rotate:3)
- Remove obsolete lk2nd-era docs

If you've touched build-rootfs.sh, the justfile, and docs in the same session, that's probably 2–3 commits, not one. Commit after each change, not at the end of a session.

### Commit Before Build/Flash

Same discipline as the kernel and lineage repos:
1. Commit changes
2. Build / flash
3. Record outcome: `just note "BOOT TEST: PASS"` or `just note "BOOT TEST: FAIL (reason)"`

### Task Tracking

`TASKS.md` is the single source of truth for open work. Update it as tasks are added, completed, or change status. Keep it concise — one line per task, checkbox format.

### Inter-repo agent communication

When work in this repo requires a change in a sibling repo (e.g. wata, libqmi, lpac), don't implement it there directly — hand off a spec the other repo's agent can pick up:

1. Write the spec as a planning doc in the sibling repo under `docs/planning/<feature>.md`. State the origin (this repo), the rationale, the contract, and what the sibling must NOT do. Keep all implementation detail that belongs on *our* side in this repo, not theirs.
2. Add a one-line task to the sibling's `TASKS.md` pointing at the planning doc.
3. Track the our-side work in this repo's `TASKS.md` as usual.

This keeps each repo's agent able to work independently from its own `TASKS.md` without needing cross-repo context.

### Git Notes

- **`experiments`** — build/boot test log attached to the commit that was tested

## Important Docs

| File | Contents |
|------|----------|
| `TASKS.md` | Open tasks (active + backlog) |
| `docs/roadmap.md` | Project roadmap, DTS status, remaining work (audio, modem, app) |
| `docs/modem_bringup.md` | Modem/WiFi/BT bringup guide (mainline stack) |
| `docs/device_properties.md` | Hardware analysis, partition layout, build.prop dumps |
| `docs/vendor_blobs.md` | Line-by-line blob audit from Android vendor partition |

## Reference

- **BQ268 CAF DTS**: `~/bq268-caf-4.4/arch/arm/boot/dts/qcom/msm8909-bq268.dts`
- **Nokia 8110 4G wiki**: `wiki.postmarketos.org/wiki/Nokia_8110_4G_(nokia-argon)`
- **msm8916-mainline kernel**: `github.com/msm8916-mainline/linux` (reference only)
