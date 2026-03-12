# CLAUDE.md — BQ268 postmarketOS Port

## Project

postmarketOS (Alpine Linux) port for the BQ268 walkie-talkie.
Single-app device: fast boot, low RAM, mainline kernel, open source.

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
| Kernel | `~/bq268-caf_msm-3.18` | CAF 3.18.140 kernel, DTS, defconfig, Prima WLAN |
| LineageOS device tree | `~/bq268-lineage` | Android device/vendor tree (completed, archived) |
| EDL dumps | `~/bq268-edl/dump` | Full partition dumps from device |

## Key Decisions

- **lk2nd bootloader** — stock aboot → lk2nd → kernel. Only `boot` partition changes.
- **Phase 1: CAF 3.18 kernel** — existing kernel + DTS unchanged, just swap rootfs to Alpine.
- **Phase 2: mainline 6.x kernel** — port DTS to mainline bindings (optional, later).
- **Firmware from EDL dumps** — extract offline, bake into rootfs. No runtime partition reading.
- **Data-only modem** — no voice calls, no VoLTE/IMS.
- **No camera, GPS, sensors, touchscreen** — none fitted.
- **SELinux**: not applicable (Linux, not Android).

## Firmware Files Needed

Extracted from EDL dumps into `/lib/firmware/`:

| File | Source partition | Driver |
|------|----------------|--------|
| `modem.mdt` + `modem.b00-b25` | modem | PIL (3.18) / q6v5-mss (mainline) |
| `wcnss.mdt` + `wcnss.b00-b12` | modem | PIL (3.18) / pronto (mainline) |
| `a300_pfp.fw`, `a300_pm4.fw` | vendor (or linux-firmware) | Adreno / Freedreno |
| `WCNSS_qcom_wlan_nv.bin` | persist | Prima (3.18) / wcn36xx (mainline) |

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
| `docs/postmarketos_plan.md` | Full spec and implementation plan |
| `docs/device_properties.md` | Hardware analysis, partition layout, build.prop dumps |
| `docs/vendor_blobs.md` | Line-by-line blob audit from Android vendor partition |

## Reference

- **msm8916-mainline kernel**: `github.com/msm8916-mainline/linux` (`wip/msm8916/6.19`)
- **lk2nd**: `github.com/msm8916-mainline/lk2nd` (supports MSM8909)
- **Nokia 6300 DTS** (closest reference): `qcom-msm8909-nokia-leo.dts`
- **Nokia 8110 4G pmOS wiki**: `wiki.postmarketos.org/wiki/Nokia_8110_4G_(nokia-argon)`
- **CAF BQ268 DTS**: `~/bq268-caf_msm-3.18/arch/arm/boot/dts/qcom/msm8909-bq268.dts`
