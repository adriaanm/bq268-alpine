# Roadmap — BQ268 Alpine Linux Walkie-Talkie

## Goal

Single-app walkie-talkie device running on Alpine Linux with CAF 4.4 kernel.
Voice messaging over cellular data (4G) or WiFi.

> **Why not mainline?** A mainline 6.19 kernel was tested but abandoned — DDR
> writes caused PMIC brownouts (likely missing bus bandwidth voting via RPM).
> CAF 4.4 has all the vendor drivers (bus scaling, modem, audio, WCNSS) that
> MSM8909 needs.

## Current Status (2026-03-23)

Alpine Linux boots on BQ268 with CAF 4.4 kernel. Modem, audio, WiFi, and SMP
all working. Userspace infrastructure for a single-app device is being built up.

**Working:**
- CAF 4.4 kernel boots, SMP (4 cores)
- USB gadget serial console (ttyGS0/ttyACM0)
- ST7735S 128x160 SPI display with fbcon
- GPIO matrix keypad (6 keys) + 4 GPIO keys
- GPIO LEDs (red, green, button backlight)
- LCD backlight control via qpnp-leds (`/sys/class/leds/lcd-bl/`)
- eMMC storage (HS200)
- Battery monitoring (charger + BMS sysfs + battmon daemon)
- Power toggle switch controls screen on/off (SW_LID + keyd + fb0 blank)
- Screen auto-blank after 30s idle
- CPU frequency scaling (interactive governor)
- WiFi (CAF prima wlan.ko) — wlan0 up, IPv4+IPv6, internet confirmed
- wpa_supplicant + DHCP ready (configure via wpa_cli)
- chrony NTP time sync
- Logging to tmpfs (eMMC-safe)
- Modem Q6 DSP boots and completes initialization (rmt_storage + subsys_modem)
- Modem EFS partitions served via rmt_storage daemon (QMI service 14 over IPC Router)
- Modem RF online (`qmicli --dms-set-operating-mode=online`), sees cellular networks
- Audio speaker playback (CAF 4.4: WCD codec → HPHR PA → GPIO36 ext amp)
- Volume potentiometer

**Not working yet:**
- Modem data path — BAM DMUX ported but A2_POWER_CONTROL handshake not triggered by modem. RF works (sees networks), needs SIM card to test PS-attach → A2 activation.
- Bluetooth (WiFi/WCNSS works, BT untested)
- Suspend-to-RAM (CONFIG_SUSPEND=y, untested)

## Subsystem Status

| Subsystem | Status |
|-----------|--------|
| Display (ST7735S SPI + fbcon) | Working |
| GPIO keys + matrix keypad | Working |
| GPIO LEDs | Working |
| LCD backlight (qpnp-leds) | Working |
| USB (gadget, peripheral mode) | Working |
| eMMC (HS200) | Working |
| Battery (charger + BMS) | Working |
| WiFi (WCNSS + prima wlan.ko) | Working (IPv4+IPv6) |
| Bluetooth (WCN3620) | Untested |
| Modem (MSS PIL + rmt_storage) | Q6 boots, EFS served, RF online, sees networks |
| Modem data path (BAM DMUX) | Open — A2 handshake not triggered |
| Audio (WCD codec + Q6 DSP) | Working (speaker playback + volume) |
| Power toggle switch (KEY_F10 on gpio-keys) | Working |
| Regulators (SPMI + PM8909) | Working |
| SMP (4× Cortex-A7) | Working |

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

**Next (phases 4–5):**
- Cellular auto-connect + WiFi/cellular failover (modem boots + RF works, blocked on BAM DMUX data path)
- Single-app boot, app watchdog, read-only rootfs, OTA, security (needs app)

### 1. Modem data path (cellular data)

Modem Q6 DSP boots fully with rmt_storage, RF is online (sees cellular
networks after `qmicli --dms-set-operating-mode=online`). BAM DMUX driver
ported from 3.18, `msm_rmnet_bam.c` ported for rmnet interfaces. BAM hardware
confirmed working (0x04044000, 6 pipes). However, modem never sets
SMSM A2_POWER_CONTROL — forcing it crashes modem (`A2 Assertion Failed`).

**Next:** Test with SIM card inserted — A2 may require PS-attached state.
If that doesn't work, modem DIAG logs needed to identify A2 precondition.
See `docs/modem_bringup.md` and kernel `LEARNINGS.md` for full investigation.

### 2. Audio — done

Speaker playback and volume control confirmed working on CAF 4.4.

Path: WCD msm8x16 codec (regmap wrapper added for 4.4 ASoC) → HPHR PA →
GPIO36 external amplifier → speaker. Q6 ACDB calibration missing but
non-fatal. Mixer path: `RX2 MIX1 INP1=RX1`, `RDAC2 MUX=RX2`, `HPHR=Switch`,
`Ext Spk Switch=On`.

### 3. Walkie-talkie application

- Display: LVGL or SDL2 on DRM/fbdev (128x160 @ RGB565)
- Input: evdev from `/dev/input/event*` (keypad)
- Audio: ALSA (tinyalsa or alsa-lib)
- Network: standard sockets over wlan0 or wwan0
- Cellular: ModemManager via D-Bus, or direct QMI via libqmi
- Protocol: voice messaging over cellular data (Opus codec, software decode)

## Risk Register

| Risk | Impact | Mitigation | Status |
|------|--------|------------|--------|
| Modem BAM-DMUX A2 handshake | No cellular data | Test with SIM card; get modem DIAG logs for A2 precondition | **Open** — RF works, BAM HW works, but modem won't activate A2 |
| Battery OCV table inaccurate | Wrong percentage readings | Tune with real measurements | Open |
| CPU hotplug crashes on re-online | No suspend, no CPU offlining | Use powersave governor instead; all 4 cores stay online | **Won't fix** — CAF 4.4 SPM/power-collapse bug |
