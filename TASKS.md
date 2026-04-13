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
  - [x] ~~Verify `/sys/class/net/rmnet_data0` is the right iface name on device~~ — resolved: no rmnet on this hardware, cellular is PPP over SMD (`ppp0`). `cell_iface` default is `ppp0`; planning doc + code + schema updated.
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

- [x] **Force LTE-only mode at cellular bringup** — `cell-data wake` now calls `ensure_lte_prefs` which idempotently applies `lte,automatic` if not already set. Acquisition order becomes `lte, umts, gsm, …` so LTE is tried first.
- [x] **Persist mode preference across modem resets** — verified: the QMI NAS preference is stored in modem NV and survives both `dms-set-operating-mode=reset` and full device reboots. `ensure_lte_prefs` is therefore a no-op after the first application. No oneshot service needed.
- [x] **Robust modem state-machine in `cell-data.sh`** — rewritten with a bounded 2-minute budget: `set_online` handles `online`/`low-power`/`offline`/`shutting-down`/`resetting` and escalates to `dms reset` + 10 s settle once on timeout. `do_wake` returns exit 1 for unreachable-online and exit 2 for PS-attach timeout, so callers (and `smoke-cellular`) can distinguish firmware deadlock from coverage/roaming problems.
- [x] **Roaming detection and logging** — `log_serving` records `plmn`, `rat`, `roaming` bool (MCC/MNC mismatch vs `nas-get-home-network`), home PLMN, and QMI's own roaming status to `/var/log/cellular.log` on every successful attach.
- [x] **`just smoke-cellular` end-to-end recipe** — runs `cell-data wake && up && ping -I ppp0 8.8.8.8 && down` against the live device. `just push-cell-data` scp's the current script in-place for quick iteration without a rootfs rebuild.
- [x] **Document the cellular bringup chain** — `docs/modem_data.md` now has a "Bringup chain (2026-04-13)" section with the sequence, expected prefs, recovery table, and smoke-test pointer.
- [x] **Approved roaming partners list** — `/etc/cellular/roaming-partners` is a human-editable allowlist (MCC MNC COUNTRY OPERATOR PRIORITY, one per line) covering Singtel ReadyRoam partners across EU/US/APAC. `cell-data wake` now uses it as a two-phase fallback: (1) try automatic attach for ATTACH_BUDGET=45s, (2) if that fails, `nas-network-scan=lte`, filter to approved partners, sort by priority, and manually attach to each for PARTNER_BUDGET=30s until one takes. Non-partner networks are never tried. **Always update this file before a trip** — agreements change. Source: verify at https://www.singtel.com/.
- [ ] **Live LTE attach still failing** — on 2026-04-13, with `lte|umts,automatic` + Sunrise (228/02) in the partners file, neither automatic nor manual partner attach succeeds. Scan sees all 5–6 visible networks; qmicli accepts `manual=22802`; but `PS: attached` never comes through within the 75s budget. SIM is ready, prefs are correct. Hypothesis: location-specific roaming block or poor reception at the test bench. Retest at a different physical location before assuming a firmware bug. If the problem persists everywhere, DIAG logs on the NAS layer would show the reject cause.
- [ ] ~~LTE band preference review~~ — dropped: `qmicli` has no flag for setting the LTE band list (only mode + network-selection), and the current default (B1/3/5/7/8/20/28 + extended B66/71) already covers EU + common travel. Would require raw QMI TLV construction, not worth it.

## Backlog

- [ ] Read-only rootfs — Production hardening. Prevents eMMC wear and corruption from hard power-off. overlayfs on tmpfs for /var, /tmp.
- [ ] OTA updates — Mechanism for deploying rootfs updates over cellular/WiFi. Dual-partition (A/B) or full-image reflash.
- [ ] Watchdog timer — Hardware watchdog (QCOM WDT) to auto-reboot on hang. Critical for unattended field device.
- [ ] Unused service cleanup — Remove acpid, machine-id, watchdog services pulled in by Alpine defaults. Reduces boot noise and attack surface.
- [x] Power switch screen on/off — DTS updated to SW_LID, keyd wired to screen-on/screen-off via fb0 blank + governor switch.
- [ ] Kernel module trimming — Strip unused modules from rootfs to save space and boot time. Only load what's needed.
- [ ] Security hardening — Drop to non-root for the app. Disable root login over cellular. Firewall (nftables) to restrict outbound to app traffic only.
- [ ] Modem DIAG logging — DIAG fully functional (SMD channels open). Useful for debugging modem issues.
