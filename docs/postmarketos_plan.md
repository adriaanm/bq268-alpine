# postmarketOS Build Plan — BQ268 (MSM8909)

## Goal

Replace the Android/LineageOS stack with postmarketOS (Alpine Linux) running
a single user application. Priorities: fast boot, low RAM footprint, mainline
kernel, open source.

---

## 1. Hardware Summary

| Component | Detail | Mainline driver |
|-----------|--------|-----------------|
| SoC | MSM8909 (Snapdragon 210), 4× Cortex-A7 @ 1.267 GHz | `qcom-msm8909.dtsi` in msm8916-mainline |
| RAM | ~512 MB | — |
| Storage | eMMC, 8-bit DDR HS200 | `sdhci-msm` (mainline) |
| Display | ST7735S 128×160 SPI on BLSP1 QUP5, 27 Hz, RGB565 | `panel-mipi-dbi` or `panel-sitronix-st7735s` |
| Backlight | PM8909 MPP4 WLED, 20 mA | `leds-qcom-lpg` / PWM |
| GPU | Adreno 304 (a3xx) | Freedreno (`a300_pfp.fw`, `a300_pm4.fw`) |
| Audio codec | MSM8x16 WCD (internal) | `qcom,msm8916-wcd-analog` / `qcom,msm8916-wcd-digital` |
| Speaker PA | External class-D on GPIO36 | GPIO toggle (simple-audio-amplifier) |
| Smart PA | TFA98xx / FS16xx on I2C (insmod in stock) | `snd-soc-tfa98xx` (out-of-tree) — may not be fitted |
| WiFi/BT | WCNSS (Pronto) + WCN3620 iris | `qcom,pronto` remoteproc + `wcn36xx` mac80211 |
| Modem | Hexagon DSP, 4G LTE data | `qcom,q6v5-mss` remoteproc + BAM-DMUX + QMI |
| Keypad | 2×3 GPIO matrix + 4 GPIO keys | `matrix-keypad` + `gpio-keys` |
| LEDs | GPIO1 (button BL), GPIO68 (red), GPIO69 (green) | `leds-gpio` |
| USB | HS USB OTG @ 0x78d9000 (device mode) | `chipidea` / `ci-hdrc-msm` |
| Battery | Linear charger + VM-BMS, 4.2V/800mA | `qcom,pm8916-lbc` / `qcom,pm8916-bms-vm` |
| PMIC | PM8909 via SPMI | `qcom,pm8916` (same register map) |
| Vibrator | PMIC @ 0xc000 (disabled in stock) | `qcom,pm8916-vib` |

---

## 2. Bootloader Options

### Current chain

```
SBL1 → RPM → TZ → aboot (LK) → kernel
```

We have LK/aboot building from source. Three options:

### Option A: Stock aboot → lk2nd → mainline kernel (recommended)

Flash lk2nd as a standard boot.img. Stock aboot loads it, lk2nd provides:
- Full fastboot (even if stock fastboot is locked/absent)
- `extlinux.conf` boot (kernel on ext2 partition — standard distro boot)
- Device tree patching (panel detection, GPIO fixup)
- SD card boot for development
- OEM debug commands (`oem dtb`, `oem log`, `oem reboot-edl`)

The real kernel sits at a 512 KiB offset in the boot partition, or on a
separate ext2 partition referenced by extlinux.conf.

lk2nd already supports MSM8909 (`make lk2nd-msm8909`). Adding BQ268 requires
a small DTS in `lk2nd/device/dts/msm8909/` with `qcom,msm-id`, `qcom,board-id`,
and model string.

**Risk**: Near zero — only `boot` partition changes; SBL1/aboot/TZ untouched.
EDL recovery always available.

### Option B: Stock aboot → kernel directly (current approach)

What we do now for LineageOS. Works but:
- Stock aboot passes a downstream DT blob and cmdline
- No extlinux.conf, no panel detection, no OEM debug
- Fine for 3.18 CAF kernel, awkward for mainline

### Option C: Custom aboot (replace stock LK)

We can build LK from source and flash to the `aboot` partition.
- Full control over first-stage app bootloader
- Risk: bad flash requires EDL to recover (we have EDL, so survivable)
- msm8916-mainline project doesn't use this approach
- Only worthwhile if stock aboot has bugs or limitations we hit

**Recommendation**: Option A (lk2nd). Use Option C only if we discover stock
aboot limitations during bringup.

---

## 3. Kernel Strategy

### Phase 1: Boot with CAF 3.18.140 (what we have)

Use the existing kernel to validate the boot chain and userspace:
- Flash lk2nd + 3.18 kernel + Alpine rootfs
- Verify display, keypad, USB, serial console
- This proves the bootloader and rootfs work before changing the kernel

The 3.18 kernel uses Qualcomm's downstream DTS bindings and drivers. WiFi
works (Prima driver built from source). Audio works. This is our fallback.

### Phase 2: Mainline kernel (msm8916-mainline 6.19+)

The msm8916-mainline project already has:
- `qcom-msm8909.dtsi` — base SoC definition
- 10 device-specific DTS files (Nokia 8110/6300, Lenovo Tab, Acer, ZTE, etc.)
- `qcom-msm8909-pm8909.dtsi` — PMIC definitions
- Mainline drivers for all core subsystems

**We write `qcom-msm8909-udotech-bq268.dts`** based on the existing CAF DTS
(`msm8909-bq268.dts`), translating to mainline bindings. Reference: the Nokia
6300 4G DTS (`qcom-msm8909-nokia-leo.dts`) — similar form factor (keypad phone,
SPI display, WCNSS WiFi, modem).

#### DTS porting work

| Subsystem | CAF binding | Mainline binding | Effort |
|-----------|-------------|------------------|--------|
| SPI display | `qcom,mdss-spi-display` | `panel-mipi-dbi` (SPI) | Medium — new panel descriptor |
| Backlight | PMIC MPP WLED | `pwm-backlight` + `qcom,pm8916-pwm` | Low |
| Matrix keypad | `gpio-matrix-keypad` | `gpio-matrix-keypad` (same) | Trivial |
| GPIO keys | `gpio-keys` | `gpio-keys` (same) | Trivial |
| LEDs | `gpio-leds` | `leds-gpio` (same) | Trivial |
| Audio codec | `qcom,msm8x16_wcd_codec` | `qcom,msm8916-wcd-analog/digital` | Low — bindings exist |
| Speaker PA | GPIO36 toggle | `simple-audio-amplifier` | Trivial |
| WiFi/BT | Prima (out-of-tree) | `qcom,pronto` remoteproc + `wcn36xx` | Low — DT node only |
| Modem | PIL + QMI (proprietary) | `qcom,q6v5-mss` + BAM-DMUX | Low — DT node only |
| USB | `qcom,hsusb-otg` | `ci-hdrc-msm` / `chipidea` | Low |
| eMMC | `qcom,sdhci-msm-v4` | `sdhci-msm` | Trivial |
| PMIC/regulators | `qcom,qpnp-*` | `qcom,pm8916-*` | Low — PM8909 ≈ PM8916 |
| Charger/BMS | `qcom,qpnp-linear-charger` | `qcom,pm8916-lbc` | Low |
| Thermal | `qcom,msm-thermal` | `qcom,tsens-v0_1` | Low |

**Biggest effort**: display panel. The ST7735S needs a `panel-mipi-dbi`
descriptor with the exact init sequence extracted from the CAF panel driver
(`mdss_spi_st7735s_panel.h` or equivalent in the kernel source).

### Phase 3: Upstream

Submit the BQ268 DTS upstream to msm8916-mainline, then to Linus's tree.
Also add BQ268 to lk2nd's device list.

---

## 4. Firmware / Binary Blobs

### What the kernel needs (non-replaceable)

Coprocessor firmware — signed by Qualcomm, run on dedicated cores:

| Firmware | Source | Size | Loaded by |
|----------|--------|------|-----------|
| `modem.bin` + segments | modem partition | 66 MB | PIL (3.18) / `qcom,q6v5-mss` (mainline) |
| `wcnss.mdt` + segments | modem/system partition | ~3 MB | PIL (3.18) / `qcom,pronto` (mainline) |
| `a300_pfp.fw`, `a300_pm4.fw` | system/vendor firmware | ~200 KB | Adreno GPU driver / Freedreno |
| WCNSS NV data (`WCNSS_qcom_wlan_nv.bin`) | persist partition | ~4 KB | Prima (3.18) / wcn36xx (mainline) |

**Total: ~70 MB firmware**

### Where firmware comes from

We have complete EDL dumps (`~/bq268-edl/dump`). Firmware files can be
extracted offline and baked directly into the rootfs under `/lib/firmware/`.
No need for runtime extraction.

Source locations in the dumps:
- `modem` partition image → modem.mdt, modem.b00-b25, wcnss.mdt, wcnss.b00-b12
- `persist` partition image → `/WCNSS_qcom_wlan_nv.bin`, BT NV data
- `system`/`vendor` partition images → `a300_pfp.fw`, `a300_pm4.fw`
- `linux-firmware` git repo also has Adreno a3xx firmware (alternative source)

We build our own system/vendor/boot partitions from scratch — no need to
keep stock partitions intact except for the bootloader chain and modem.

### What we DON'T need (Android-only)

Everything else from the LineageOS vendor blob audit is Android framework
specific and not needed:
- All HIDL HAL services and implementations (~100 blobs)
- OpenGL/EGL userspace libraries (replaced by Mesa/Freedreno)
- OMX video codecs, DRM, camera ISP libs (~250 blobs)
- QMI RIL libraries (replaced by libqmi + ModemManager)
- GPS/IMS/sensors/touchscreen HALs
- Qualcomm proprietary daemons (thermal-engine, cnd, dpm, etc.)
- All vendor shell scripts and init.qcom.*.sh

### Co-processor firmware partitions (keep as-is)

These are flashed once and never touched by the OS:

| Partition | Size | Purpose |
|-----------|------|---------|
| `tz` | 2 MB | TrustZone (ARM secure world) |
| `rpm` | 512 KB | Resource Power Manager firmware |
| `sbl1` | 512 KB | Secondary bootloader |
| `cmnlib` | 256 KB | QSEE common library |
| `devcfg` | 256 KB | TZ device config |
| `keymaster` | 512 KB | Hardware keystore trustlet |

---

## 5. Userspace Stack

### Target: Alpine Linux (postmarketOS base)

| Layer | Component | Notes |
|-------|-----------|-------|
| Init | OpenRC | Alpine default, fast boot |
| Libc | musl | Tiny footprint |
| Display | DRM/KMS framebuffer | Direct `/dev/dri/card0` or `/dev/fb0` |
| GUI toolkit | LVGL, SDL2, or direct fbdev | 128×160 too small for Wayland/X11 |
| Audio | ALSA (tinyalsa or alsa-lib) | No PulseAudio needed |
| WiFi | wpa_supplicant + iwd | Standard Linux WiFi |
| Bluetooth | BlueZ | Standard Linux BT |
| Cellular data | ModemManager + libqmi | QMI over BAM-DMUX |
| Connectivity | NetworkManager or ConnMan | Manages WiFi + cellular |
| SSH | dropbear or OpenSSH | Remote access |

### RAM budget estimate

| Component | RAM |
|-----------|-----|
| Kernel | ~15 MB |
| Init + system services | ~10 MB |
| ModemManager + WiFi | ~15 MB |
| User application | ~10 MB |
| Buffers/cache | ~50 MB |
| **Total** | **~100 MB** |
| **Free for app** | **~400 MB** |

Compare: Android 8.1 uses ~300 MB at idle on this device.

---

## 6. Partition Layout (postmarketOS)

postmarketOS typically uses a simple two-partition scheme:

| Partition | Use | Source |
|-----------|-----|--------|
| `boot` | lk2nd (512 KB) + kernel + initramfs | New |
| `system` (repurposed) | Root filesystem (Alpine) | New |
| `userdata` (repurposed) | `/home` or app data | Reformatted |
| `modem` | Firmware (untouched) | Stock |
| `persist` | WiFi/BT NV data (untouched) | Stock |
| `tz`, `rpm`, `sbl1`, `aboot` | Bootloader chain (untouched) | Stock |

Alternative: use `boot` for lk2nd, and an `extlinux.conf` on the system
partition pointing to the kernel. This is the standard pmOS approach.

---

## 7. Implementation Plan

### Phase 1: lk2nd + existing kernel (1-2 days)

**Goal**: Boot Alpine rootfs with the 3.18 CAF kernel we already have.

No kernel or DTS changes needed — the existing `msm8909-bq268.dts` and all
CAF drivers work as-is. The kernel doesn't care whether userspace is Android
or Alpine. We're just swapping the rootfs.

1. **Build lk2nd for MSM8909**
   - Clone `msm8916-mainline/lk2nd`
   - Add BQ268 device DTS (`lk2nd/device/dts/msm8909/msm8909-udotech-bq268.dts`)
   - Build: `make TOOLCHAIN_PREFIX=arm-none-eabi- lk2nd-msm8909`
   - Flash via EDL or fastboot: `fastboot flash boot lk2nd.img`

2. **Extract firmware from EDL dumps**
   - Mount modem/persist/system/vendor partition images from `~/bq268-edl/dump`
   - Copy firmware files into rootfs `/lib/firmware/` tree
   - No runtime extraction needed — we own all the partitions

3. **Build Alpine rootfs**
   - Alpine minirootfs (armv7) + kernel modules from 3.18 build
   - Include: OpenRC, wpa_supplicant, dropbear, evtest, fbtools
   - Bake in firmware from step 2
   - Package as ext4 image for system partition

4. **Flash and boot**
   - `fastboot flash boot lk2nd.img` (via EDL or existing fastboot)
   - Flash kernel at 512 KiB offset, or use extlinux.conf on system partition
   - Flash rootfs to system partition
   - Serial console on BLSP1 UART2 or USB gadget serial
   - Verify: kernel boots, framebuffer console, keypad input, WiFi scan

### Phase 2: Mainline kernel DTS (3-5 days, optional)

**Goal**: Move from CAF 3.18 to mainline 6.x kernel.

This phase is only needed if we want a mainline kernel. The 3.18 CAF kernel
with the existing DTS works fine for Phase 1 — no DTS changes required there
because the kernel and DTS bindings match.

1. **Write `qcom-msm8909-udotech-bq268.dts`**
   - Base: `qcom-msm8909.dtsi` + `qcom-msm8909-pm8909.dtsi`
   - Reference: Nokia 6300 DTS (similar hardware)
   - Port from CAF DTS: GPIO assignments, regulator voltages, keypad matrix

2. **Display panel descriptor**
   - Extract ST7735S init sequence from CAF kernel panel header
   - Create `panel-mipi-dbi` compatible descriptor or use `panel-sitronix-st7735s`
   - SPI5: GPIOs 16-19 (MOSI/CLK/CS/MISO), GPIO2 (reset), GPIO3 (DC)

3. **Audio bringup**
   - Enable `msm8916-wcd-analog` + `msm8916-wcd-digital` codec nodes
   - Add `simple-audio-amplifier` for GPIO36 speaker PA
   - Test with `aplay` / `arecord`

4. **WiFi/BT**
   - Enable `wcnss` node with `qcom,pronto` compatible
   - Firmware: `msm-firmware-loader` extracts from modem partition
   - Test: `iw dev wlan0 scan`

5. **Modem (cellular data)**
   - Enable `mpss` node with `qcom,q6v5-mss`
   - BAM-DMUX for data path
   - ModemManager + libqmi for connection management
   - Test: `mmcli -m 0 --simple-connect="apn=..."`, `ping`

### Phase 3: postmarketOS device package (1-2 days)

**Goal**: Proper pmOS device package so anyone can `pmbootstrap install`.

1. **Create pmaports device package** (`device-udotech-bq268`)
   - `deviceinfo`: chassis, kernel, firmware deps, boot method
   - APKBUILD for device-specific configs
   - Firmware subpackage for WCNSS NV data

2. **Add to lk2nd device list**
   - PR to `msm8916-mainline/lk2nd` with BQ268 DTS

3. **Submit mainline DTS**
   - PR to `msm8916-mainline/linux` with `qcom-msm8909-udotech-bq268.dts`
   - Eventually upstream to `torvalds/linux`

### Phase 4: Application port (parallel)

Port the user application from Android to Linux:
- Display: LVGL or SDL2 on DRM/fbdev (128×160 @ 16-bit)
- Input: evdev from `/dev/input/event*` (keypad)
- Audio: ALSA
- Network: standard sockets over wlan0 or rmnet0
- Cellular: D-Bus to ModemManager, or direct QMI via libqmi

---

## 8. Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| ST7735S panel init sequence wrong | No display | Extract from CAF kernel source; test on 3.18 first |
| Audio codec mainline driver gaps | No sound | Fall back to 3.18 kernel for audio; test ALSA UCM |
| TFA98xx smart PA needs out-of-tree driver | Distorted audio | Check if basic audio works without smart PA (internal codec → speaker direct) |
| Modem BAM-DMUX flaky on MSM8909 | No cellular data | Nokia 8110 4G has it working; copy their DTS config |
| WCNSS firmware load fails | No WiFi/BT | msm-firmware-loader proven on MSM8909; check persist partition |
| lk2nd doesn't detect BQ268 board | Boot fails | Match on `qcom,msm-id` and `qcom,board-id` from stock; fall back to generic |
| 512 MB not enough with modem loaded | OOM | Modem uses shared DDR, not Linux RAM; budget is fine |

---

## 9. Key References

| Resource | URL / Path |
|----------|------------|
| msm8916-mainline kernel | `github.com/msm8916-mainline/linux` (branch `wip/msm8916/6.19`) |
| lk2nd bootloader | `github.com/msm8916-mainline/lk2nd` |
| Nokia 8110 4G pmOS wiki | `wiki.postmarketos.org/wiki/Nokia_8110_4G_(nokia-argon)` |
| Nokia 6300 mainline DTS | `qcom-msm8909-nokia-leo.dts` / `qcom-msm8909-nokia-leo-common.dtsi` |
| CAF BQ268 DTS (our source of truth) | `~/bq268-caf_msm-3.18/arch/arm/boot/dts/qcom/msm8909-bq268.dts` |
| Vendor blob audit | `docs/vendor_blobs.md` |
| Device hardware analysis | `docs/device_properties.md` |
| Partition layout | `docs/device_properties.md` (partition table section) |
| pmOS device packaging guide | `wiki.postmarketos.org/wiki/Device_specific_package` |
| panel-mipi-dbi binding | `Documentation/devicetree/bindings/display/panel/panel-mipi-dbi-spi.yaml` |
| msm-firmware-loader | `gitlab.com/postmarketOS/pmaports` (main/msm-firmware-loader) |
