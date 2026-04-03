# Tasks

## Active

- [x] Modem data path — **PPP over SMD working.** `pppd call cellular` establishes data over UMTS. Ping 8.8.8.8 verified. BAM DMUX is unused on this firmware. See `docs/modem_data.md`.
- [ ] Bluetooth — WCNSS firmware loads (WiFi works), BT untested. btqcomsmd + BlueZ should work.
- [ ] fbcon/display stability — rapid redraws on VT2 (dmesg scroll viewer) cause kernel crash. Likely fbcon or SPI display driver issue with the ST7735S 27 Hz panel. May need rate-limiting in userspace or a kernel fix.
- [ ] Suspend-to-RAM — CONFIG_SUSPEND=y, completely untested. Needed for battery life.
- [ ] Battery OCV table — Current table is estimated. Calibrate with real discharge measurements.
- [ ] Battery stats daemon — Track voltage, capacity, charge status over time. The kernel reports `current_now=0` because the charger driver has no USB PSY to enable current tracking (known kernel limitation). A userspace daemon can poll `voltage_now`, `capacity`, `status` from `/sys/class/power_supply/battery/` and log to a file or SQLite for charge/discharge curve analysis. Could also estimate current from dV/dt. Consider integrating with `battmon` if it already runs.
- [x] eSIM provisioning — **Complete.** Full pipeline: lpac → lpac-qmi-wrapper → qmi-send-apdu → QMI UIM → eUICC. Eskimo eSIM provisioned, modem registered. All 3 firmware patches required (`tools/patch-modem-b12.py`). See `docs/esim_provision.md`.
- [ ] Walkie-talkie app — The actual application. LVGL or SDL2 on fbdev, ALSA audio, Opus codec, evdev input, QMI/ModemManager for cellular.

## Backlog

- [ ] Read-only rootfs — Production hardening. Prevents eMMC wear and corruption from hard power-off. overlayfs on tmpfs for /var, /tmp.
- [ ] OTA updates — Mechanism for deploying rootfs updates over cellular/WiFi. Dual-partition (A/B) or full-image reflash.
- [ ] Watchdog timer — Hardware watchdog (QCOM WDT) to auto-reboot on hang. Critical for unattended field device.
- [ ] Unused service cleanup — Remove acpid, machine-id, watchdog services pulled in by Alpine defaults. Reduces boot noise and attack surface.
- [ ] Graceful shutdown on long-press — Power button long-press currently hard-resets. Should trigger clean unmount + poweroff.
- [ ] Kernel module trimming — Strip unused modules from rootfs to save space and boot time. Only load what's needed.
- [ ] Security hardening — Drop to non-root for the app. Disable root login over cellular. Firewall (nftables) to restrict outbound to app traffic only.
- [ ] Modem DIAG logging — DIAG fully functional (SMD channels open). Useful for debugging modem issues.
