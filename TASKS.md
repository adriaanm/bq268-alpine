# Tasks

## Active

- [ ] Modem data path — **PPP over SMD confirmed working.** AT+CGACT gets IP (10.156.46.161), AT+CGDATA="PPP" returns CONNECT on /dev/smd7. BAM DMUX is a dead end on this firmware. Need kernel PPP support (CONFIG_PPP, CONFIG_PPP_ASYNC) + pppd. See `docs/modem_data.md`.
- [ ] Bluetooth — WCNSS firmware loads (WiFi works), BT untested. btqcomsmd + BlueZ should work.
- [ ] Suspend-to-RAM — CONFIG_SUSPEND=y, completely untested. Needed for battery life.
- [ ] Battery OCV table — Current table is estimated. Calibrate with real discharge measurements.
- [ ] Battery stats daemon — Track voltage, capacity, charge status over time. The kernel reports `current_now=0` because the charger driver has no USB PSY to enable current tracking (known kernel limitation). A userspace daemon can poll `voltage_now`, `capacity`, `status` from `/sys/class/power_supply/battery/` and log to a file or SQLite for charge/discharge curve analysis. Could also estimate current from dV/dt. Consider integrating with `battmon` if it already runs.
- [x] eSIM provisioning — **Complete.** Full pipeline working: lpac → lpac-qmi-wrapper → qmi-send-apdu → QMI UIM → eUICC. Eskimo eSIM provisioned, modem registered on Orange France. UIM power cycle needed after profile switch. See `docs/esim_provision.md`.
- [ ] Walkie-talkie app — The actual application. LVGL or SDL2 on fbdev, ALSA audio, Opus codec, evdev input, QMI/ModemManager for cellular.

## Backlog

- [ ] Read-only rootfs — Production hardening. Prevents eMMC wear and corruption from hard power-off. overlayfs on tmpfs for /var, /tmp.
- [ ] OTA updates — Mechanism for deploying rootfs updates over cellular/WiFi. Dual-partition (A/B) or full-image reflash.
- [ ] Watchdog timer — Hardware watchdog (QCOM WDT) to auto-reboot on hang. Critical for unattended field device.
- [ ] Unused service cleanup — Remove acpid, machine-id, watchdog services pulled in by Alpine defaults. Reduces boot noise and attack surface.
- [ ] Graceful shutdown on long-press — Power button long-press currently hard-resets. Should trigger clean unmount + poweroff.
- [ ] Kernel module trimming — Strip unused modules from rootfs to save space and boot time. Only load what's needed.
- [ ] Security hardening — Drop to non-root for the app. Disable root login over cellular. Firewall (nftables) to restrict outbound to app traffic only.
- [ ] Modem DIAG logging — If SIM test doesn't unblock BAM DMUX, need to capture modem DIAG logs to identify A2 precondition. Requires DIAG port over USB or SMD.
