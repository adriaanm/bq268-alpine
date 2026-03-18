# Roadmap — BQ268 Alpine Linux Walkie-Talkie

## Goal

Single-app walkie-talkie device running on Alpine Linux with mainline kernel.
Voice messaging over cellular data (4G) or WiFi.

## Current Status (2026-03-18)

Alpine Linux boots on BQ268 with CAF 3.18 kernel (stable) and mainline 6.19
kernel (development). Userspace infrastructure for a single-app device is
being built up.

**Working:**
- CAF 3.18 kernel boots (~5s to login), SMP (4 cores)
- Mainline 6.19 kernel also boots (1 core, SMP issue)
- USB gadget serial console (ttyGS0/ttyACM0)
- ST7735S 128x160 SPI display with fbcon
- GPIO matrix keypad (6 keys) + 4 GPIO keys
- GPIO LEDs (red, green, button backlight)
- eMMC storage
- Battery monitoring (charger + BMS sysfs + battmon daemon)
- Power button toggles screen on/off (keyd + screen-toggle)
- Screen auto-blank after 30s idle
- CPU frequency scaling (interactive governor)
- WiFi driver (CAF prima wlan.ko) — loads, needs network testing
- wpa_supplicant + DHCP ready (configure via wpa_cli)
- chrony NTP time sync
- Logging to tmpfs (eMMC-safe)

**Not working yet:**
- Audio (LPASS not in mainline MSM8909 DTSI — biggest gap)
- Modem (disabled in DTS — firmware + userspace needed)
- Bluetooth (btqcomsmd should work once WCNSS loads)
- SMP on mainline (only 1 CPU — qcom_scm boot address issue)
- Suspend-to-RAM (CAF kernel has CONFIG_SUSPEND=y, untested)

## DTS Status

The mainline DTS (`qcom-msm8909-udotech-bq268.dts`) is complete for all
working subsystems. Located in the kernel repo at
`arch/arm/boot/dts/qcom/qcom-msm8909-udotech-bq268.dts`.

| Subsystem | DTS Status | Runtime Status |
|-----------|-----------|----------------|
| Display (panel-mipi-dbi-spi) | Done | Working |
| GPIO keys + matrix keypad | Done | Working |
| GPIO LEDs | Done | Working |
| USB (gadget, peripheral mode) | Done | Working |
| eMMC | Done | Working |
| Battery (charger + BMS) | Done | Working |
| WiFi/BT (WCNSS + WCN3620) | Done | Needs testing |
| Modem (q6v5-mss) | Done (disabled) | Needs firmware + testing |
| Audio (LPASS) | Blocked | No mainline MSM8909 LPASS DTSI |
| PON keys (pm8909_resin) | Done | Working |
| Regulators | Done | Working |

## Remaining Work

### 0. Userspace infrastructure (in progress)

Power management, connectivity, and production hardening. Tracked in the
plan at `.claude/plans/cheeky-brewing-cookie.md`.

**Done (phases 1–3):**
- Battery monitor daemon with LED feedback + critical shutdown
- Device config (`/etc/bq268.conf`: backlight brightness, timeouts, thresholds)
- Power button screen toggle (evtest-based keyd)
- Screen idle blanker
- CPU interactive governor
- WiFi (wpa_supplicant + udhcpc)
- NTP (chrony)
- Logging to tmpfs, panic_on_oops, consoleblank

**Next (phases 4–5, blocked):**
- Cellular auto-connect + WiFi/cellular failover (needs modem DTS)
- Single-app boot, app watchdog, read-only rootfs, OTA, security (needs app)

### 1. Modem bringup (cellular data)

Enable `&mpss` in DTS, validate firmware loading, test with ModemManager.
See `docs/modem_bringup.md` for details.

### 2. Audio

**This is the critical blocker for the walkie-talkie use case.**

The mainline `qcom-msm8909.dtsi` has no LPASS (Low-Power Audio Subsystem)
nodes. Adding audio requires:

1. Adding SoC-level LPASS/codec nodes to `qcom-msm8909.dtsi`
2. Verifying MSM8909 LPASS register map matches MSM8916 (likely yes)
3. Testing `qcom,msm8916-wcd-analog` / `qcom,msm8916-wcd-digital` codecs
4. Adding speaker amplifier: `simple-audio-amplifier` on GPIO36

When LPASS is available, the BQ268 audio DTS:
```dts
/ {
    speaker-amp {
        compatible = "simple-audio-amplifier";
        enable-gpios = <&tlmm 36 GPIO_ACTIVE_HIGH>;
        sound-name-prefix = "Speaker Amp";
    };
};

&sound {
    model = "udotech-bq268";
    audio-routing =
        "Speaker Amp INL", "HPH_R_EXT",
        "AMIC1", "MIC BIAS Internal1",
        "AMIC3", "MIC BIAS Internal1";
    pinctrl-0 = <&cdc_pdm_default>;
    pinctrl-names = "default";
};
```

### 3. Walkie-talkie application

- Display: LVGL or SDL2 on DRM/fbdev (128x160 @ RGB565)
- Input: evdev from `/dev/input/event*` (keypad)
- Audio: ALSA (tinyalsa or alsa-lib)
- Network: standard sockets over wlan0 or wwan0
- Cellular: ModemManager via D-Bus, or direct QMI via libqmi
- Protocol: voice messaging over cellular data (Opus codec, software decode)

### 4. Upstream DTS

Submit `qcom-msm8909-udotech-bq268.dts` to:
1. `msm8916-mainline/linux` (community kernel)
2. `torvalds/linux` (mainline)

## Risk Register

| Risk | Impact | Mitigation |
|------|--------|------------|
| Audio LPASS not available for MSM8909 | No speaker/mic — walkie-talkie unusable | Contribute LPASS nodes upstream; worst case use CAF 3.18 for audio |
| Modem BAM-DMUX flaky on MSM8909 | No cellular data | Nokia 8110 4G has it working; copy their config |
| SMP broken (qcom_scm) | Single-core performance only | Investigate SCM firmware; may need TZ update |
| Battery OCV table inaccurate | Wrong percentage readings | Tune with real measurements |
