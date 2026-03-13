# CLAUDE.md — BQ268 Alpine Linux Port

## Project

Alpine Linux port for the BQ268 walkie-talkie.
Single-app device: fast boot, low RAM, mainline kernel, open source.
Inspired by the postmarketOS project's approach to running mainline Linux on Qualcomm phones.

## Build Environment

This repo runs on a headless buildbox. Flashing and device interaction (fastboot, serial console) happens from a separate machine. The justfile `flash-*` and `serial` recipes are for reference only — they won't be run from this machine.

## Hardware

- **SoC**: MSM8909 (Snapdragon 210), 4× Cortex-A7 @ 1.267 GHz, 32-bit ARM
- **RAM**: ~512 MB
- **Storage**: eMMC 8-bit DDR HS200
- **Display**: ST7735S 128×160 SPI (BLSP1 QUP5), 27 Hz, RGB565, 90° rotation
- **Audio**: MSM8x16 WCD internal codec + external class-D PA on GPIO36
- **WiFi/BT**: WCNSS (Pronto) + WCN3620
- **Modem**: Hexagon DSP, 4G LTE data-only
- **Keypad**: 2×3 GPIO matrix (UP/DOWN/LEFT/RIGHT/BACK/SELECT) + 4 GPIO keys (F1=PTT, F2, F3, F6)
- **LEDs**: GPIO1 (button backlight), GPIO68 (red), GPIO69 (green)
- **USB**: HS device-mode only
- **Battery**: Linear charger + VM-BMS, 4.2V / 800mA
- **PMIC**: PM8909 via SPMI

## Sibling Repos

| Repo | Path | Contents |
|------|------|----------|
| Kernel (mainline) | `~/bq268-kernel` | Mainline 6.19 kernel, BQ268 DTS, msm8916_defconfig |
| Kernel (CAF, archived) | `~/bq268-caf_msm-3.18` | CAF 3.18.140 kernel (abandoned — MDSS/USB drivers need Android HAL) |
| LineageOS device tree | `~/bq268-lineage` | Android device/vendor tree (completed, archived) |
| EDL dumps | `~/bq268-edl/dump` | Full partition dumps from device |

## Key Decisions

- **Mainline 6.x kernel** — standard DRM, USB configfs, no Android HAL dependencies.
- **Custom aboot** — built from our own lk/aboot repo, flashed to `aboot` partition.
- **panel-mipi-dbi-spi** for display — DRM tiny driver, fbcon works directly.
- **USB configfs** for gadget serial + RNDIS — no CAF android_usb driver.
- **Firmware from EDL dumps** — extract offline, bake into rootfs. No runtime partition reading.
- **Data-only modem** — no voice calls, no VoLTE/IMS.
- **No camera, GPS, sensors, touchscreen** — none fitted.
- **No audio yet** — LPASS has no mainline driver for MSM8909.

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

### Commit Before Build/Flash

Same discipline as the kernel and lineage repos:
1. Commit changes
2. Build / flash
3. Record outcome: `just note "BOOT TEST: PASS"` or `just note "BOOT TEST: FAIL (reason)"`

### Git Notes

- **`experiments`** — build/boot test log attached to the commit that was tested
- **`tasks`** — lightweight task tracking on HEAD

## Important Docs

| File | Contents |
|------|----------|
| `docs/device_properties.md` | Hardware analysis, partition layout, build.prop dumps |
| `docs/vendor_blobs.md` | Line-by-line blob audit from Android vendor partition |

## Reference

- **msm8916-mainline kernel**: `github.com/msm8916-mainline/linux` (`wip/msm8916/6.19`)
- **Nokia 6300 DTS** (closest reference): `qcom-msm8909-nokia-leo.dts`
- **Nokia 8110 4G wiki**: `wiki.postmarketos.org/wiki/Nokia_8110_4G_(nokia-argon)`
- **BQ268 mainline DTS**: `~/bq268-kernel/arch/arm/boot/dts/qcom/qcom-msm8909-udotech-bq268.dts`
- **CAF BQ268 DTS** (archived): `~/bq268-caf_msm-3.18/arch/arm/boot/dts/qcom/msm8909-bq268.dts`
