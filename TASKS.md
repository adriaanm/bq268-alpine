# Tasks

## Active

- [x] Modem data path — **PPP over SMD working.** `pppd call cellular` establishes data over UMTS. Ping 8.8.8.8 verified. BAM DMUX is unused on this firmware. See `docs/modem_data.md`.
- [ ] Bluetooth — WCNSS firmware loads (WiFi works), BT untested. btqcomsmd + BlueZ should work.
- [ ] fbcon/display stability — rapid redraws on VT2 (dmesg scroll viewer) cause kernel crash. Likely fbcon or SPI display driver issue with the ST7735S 27 Hz panel. May need rate-limiting in userspace or a kernel fix.
- [x] Power saving (screen off) — SW_LID switches CPU governor to powersave + fb0 blank. CPU hotplug crashes on re-online (CAF 4.4 SPM bug), suspend-to-RAM unlikely to work for same reason. powersave governor is the safe path.
- [ ] Battery OCV table — Current table is estimated. Calibrate with real discharge measurements.
- [ ] Battery stats daemon — **Superseded** by the metrics sampler task below; delete once `wata-metricsd` v1 lands.
- [ ] Metrics sampler (`wata-metricsd`) — Zig 0.16-dev daemon that ingests a heartbeat from wata on `/run/wata.tick`, samples battery/backlight/wifi/cellular sysfs, and writes JSONL to `/var/log/metrics/`. Aligns wakeups with wata's matrix long-poll so we don't introduce a new tick source on a device that can't suspend. Planning doc: [docs/planning/metrics-sampler.md](docs/planning/metrics-sampler.md) — treat as working document, becomes reference once implemented. Paired spec for wata: `~/wata/docs/planning/metrics-heartbeat-tick.md`. Subtasks:
  - [x] Scaffold project, protocol module with Tick datagram + tests
  - [x] Sources module: battery int fields, net operstate + counters, backlight brightness
  - [x] Sources: `batt_status` inline string reader (`[16]u8` + len, no allocator) and backlight auto-discovery via `getdents64` on `/sys/class/backlight/`
  - [x] JSONL formatter: pure `format(out, Record)` with tests for mandatory + optional fields
  - [x] Sink module: file-level open/append + size-based rotation with startup rotation for boot-cycle boundaries
  - [x] Event loop in main.zig: SOCK_DGRAM bind on `/run/wata.tick`, `timerfd` 30s watchdog, `poll()` on both, drain + sample + append
  - [x] Host-side smoke test (`just smoke-wata-metricsd`) — builds native, runs daemon on a temp dir, sends 3 ticks via `scripts/send-tick.py`, asserts JSONL output. End-to-end loop validated without root or device.
  - [x] Clean shutdown: SIGTERM/SIGINT routed through `signalfd` so OpenRC `stop` exits 0 cleanly; `--max-iters=N` flag bounds the loop for tests (smoke test now uses `--max-iters=3` instead of racing `kill`)
  - [x] Cross-compile with `-Doptimize=ReleaseSmall`: 65 KB stripped ARM binary instead of ~11 MB ReleaseSafe-with-debug. Validated burst coalescing too (10 back-to-back ticks → 2 samples with `ticks_coalesced` 4+6, all `seq`s accounted for).
  - [x] On-device smoke test: scp + `send-tick.py` against the live BQ268, JSONL populated with real battery/wlan/backlight values. Two path corrections fell out of this: backlight is `/sys/class/leds/lcd-bl/brightness` (no `backlight/` class device), and cellular is `ppp0` not rmnet (PPP over SMD per `docs/modem_data.md`). Renamed fields `rmnet_*` → `cell_*`.
  - [ ] On-device cellular validation: requires `cell-data up` to actually attach (modem was `not-registered-searching` during initial test). When `ppp0` exists, re-run smoke and confirm `cell_up`/`cell_rx`/`cell_tx` populate and grow under traffic.
  - [x] OpenRC service `rootfs/files/etc/init.d/wata-metricsd`
  - [x] Wire into rootfs build: `rootfs/16-wata-metricsd.sh` installs the binary + service, and `just build-tools` now depends on `build-wata-metricsd` so a full rebuild picks it up automatically
  - [ ] Verify `/sys/class/net/rmnet_data0` is the right iface name on device (planning doc had it as TBC)
  - [x] Fixture-based integration tests for `sources.zig` (3 tests under `/tmp`, exercising the full BQ268-shaped sysfs tree, backlight auto-discovery, and `bl=0 → screen_on=false`). Caught and fixed a latent alignment bug in `findFirstBacklight`'s `getdents64` buffer.
- [ ] Dedicated `wata` user — wata currently runs as root via system-menu → `/opt/wata/start.sh`. Create an unprivileged `wata` user in the rootfs build and drop privs before `exec`-ing `wata-fb`. Dependency audit for group membership:
  - `video` — `/dev/fb0` (framebuffer writes)
  - `input` — `/dev/input/event*` (keypad + PTT)
  - `audio` — `/dev/snd/*` (ALSA capture/playback)
  - fbcon unbind (`/sys/class/vtconsole/vtcon1/bind`) stays at system-menu, which remains root and hands off to wata after unbinding — wata itself does not need that privilege
  - `/run/wata.tick` is `0662`, so any uid can write the heartbeat
  - Verify before dropping privs: backlight, governor switching, and SW_LID handling all live in keyd/system-menu, not wata
  - Home dir: `/var/lib/wata` (matrix state, tokens), owned `wata:wata`, mode `0700`.
- [x] eSIM provisioning — **Complete.** Full pipeline: lpac → lpac-qmi-wrapper → qmi-send-apdu → QMI UIM → eUICC. Eskimo eSIM provisioned, modem registered. All 3 firmware patches required (`tools/patch-modem-b12.py`). See `docs/esim_provision.md`.
- [ ] Walkie-talkie app — The actual application. LVGL or SDL2 on fbdev, ALSA audio, Opus codec, evdev input, QMI/ModemManager for cellular.

### Cellular data hardening / optimization

Discovered while validating `wata-metricsd` cellular field reads (2026-04-13). The modem hardware and SIM are fine — Swiss LTE coverage is excellent (Swisscom/Salt/Sunrise all `available, roaming, not-forbidden` on a network scan, RSSI -77 dBm on UMTS-900) — but the modem takes minutes-to-never to attach because of how it's configured.

**Root cause**: the modem's default `system-selection-preference` has acquisition order `cdma-1x, cdma-1xevdo, gsm, umts, lte, td-scdma` — **LTE is last**. The modem finds UMTS-900 first (Salt, MCC=228 MNC=03), gets `WCDMA Status: limited` because the SIM (Singtel, MCC=525 MNC=1) isn't allowed PS attach there, and parks on it without ever trying LTE. The CLAUDE.md hardware spec says "4G LTE data-only" but the actual config doesn't enforce that.

- [ ] **Force LTE-only mode at cellular bringup** — `qmicli -d msmipc://0 --nas-set-system-selection-preference='lte,automatic'` puts mode-pref=lte and acquisition order with LTE first. Tested live: prefs apply immediately but the modem needs a reset for it to take effect (qmicli prints "replug your device"). Wire this into `tools/cell-data.sh` `do_wake` so every wake configures it before waiting for PS attach.
- [ ] **Persist mode preference across modem resets** — investigate whether mode-pref survives a `dms-set-operating-mode=reset` cycle and across full device reboots, or whether we need to re-apply it every boot from a systemd/openrc oneshot. The "replug your device" hint suggests the QMI setting is volatile until a power cycle.
- [ ] **Robust modem state-machine in `cell-data.sh`** — `do_wake` got into a `mode=offline / InvalidTransition` corner during testing where `--dms-set-operating-mode=online` kept failing. The script needs: a) detect modem is in `offline` and retry with backoff, b) escalate to `--dms-set-operating-mode=reset` and wait long enough (≥10s) for the modem subsystem to come back, c) bail with a useful error after a bounded attempt count instead of returning a confusing state.
- [ ] **Roaming detection and logging** — when registered, log MCC/MNC + home network + roaming bool to `/var/log/cellular.log` so we can correlate cellular data-bytes-per-day with roaming periods. The HPLMN check is `nas-get-home-network` vs `nas-get-serving-system MCC/MNC`.
- [ ] **LTE band preference review** — current default is `1, 3, 5, 7, 8, 20, 28, 39, 40` (+ extended `66, 71, 252, 255`). For European/Swiss roaming the critical bands are B3 (1800), B7 (2600), B20 (800), B28 (700) — all present. For US travel B12/B13/B17/B66 matter; B66 is in the extended list. Consider whether dropping unused bands (e.g. 39, 40 = TD-LTE Asia, 252/255 = misc) speeds up scan time.
- [ ] **Cellular bringup smoke test** — script: ensure modem online, set mode-pref=lte, wait for `Registration state: registered` + `PS: attached` with a 90 s budget, then `pppd call cellular`, then ping. Run from `just smoke-cellular` against the device. Include in CI for the cellular-ppp branch.
- [ ] **Document the cellular bringup chain** — `docs/modem_data.md` describes the data path but not the registration prerequisites. Add a section: required QMI prefs, expected serving-system fields, recovery steps when stuck `not-registered-searching` or `WCDMA limited`.

## Backlog

- [ ] Read-only rootfs — Production hardening. Prevents eMMC wear and corruption from hard power-off. overlayfs on tmpfs for /var, /tmp.
- [ ] OTA updates — Mechanism for deploying rootfs updates over cellular/WiFi. Dual-partition (A/B) or full-image reflash.
- [ ] Watchdog timer — Hardware watchdog (QCOM WDT) to auto-reboot on hang. Critical for unattended field device.
- [ ] Unused service cleanup — Remove acpid, machine-id, watchdog services pulled in by Alpine defaults. Reduces boot noise and attack surface.
- [x] Power switch screen on/off — DTS updated to SW_LID, keyd wired to screen-on/screen-off via fb0 blank + governor switch.
- [ ] Kernel module trimming — Strip unused modules from rootfs to save space and boot time. Only load what's needed.
- [ ] Security hardening — Drop to non-root for the app. Disable root login over cellular. Firewall (nftables) to restrict outbound to app traffic only.
- [ ] Modem DIAG logging — DIAG fully functional (SMD channels open). Useful for debugging modem issues.
