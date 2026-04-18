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
  - [x] On-device cellular validation — **done in session 8** once LTE attach was unblocked. `wata-metricsd` run against a live `ppp0` on Sunrise LTE showed `cell_up=true` and `cell_rx`/`cell_tx` populating and growing (1740→2044 bytes over two samples during a ping -I ppp0 test). Fix: `readOperstate` now falls back to `/sys/class/net/ppp0/carrier` when operstate is `unknown`, because `ppp_generic.c` never calls `netif_carrier_on/off` so operstate is permanently `unknown` on PPP interfaces — the old code silently reported `cell_up=false` even with a fully-established link. Two new fixture tests cover `unknown+carrier=1 → true` and `unknown+carrier=0 → false`.
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
- [x] eSIM provisioning — **Complete on unpatched firmware.** Full pipeline: lpac → qmi-send-apdu lpac mode → QMI UIM → eUICC. Eskimo eSIM provisioned, modem registered. Works on golden modem firmware once `qmi-send-apdu` was fixed (TLV order + dynamic UIM port lookup, see commit on 2026-04-15). The ISD-R AID filter is bypassed by truncating to the 6-byte prefix `a00000055910`.
- [ ] Walkie-talkie app — The actual application. LVGL or SDL2 on fbdev, ALSA audio, Opus codec, evdev input, QMI/ModemManager for cellular.

### Cellular data

LTE data works on golden (unpatched) modem firmware via Sunrise (228/02) roaming. `cell-data.sh` handles bringup, RAT preference, and PPP.

- [x] **Force LTE-preferred mode at cellular bringup** — `cell-data wake` calls `ensure_lte_prefs` which idempotently applies `lte|umts,automatic`. Stored in modem NV, survives reboots.
- [x] **Robust modem state-machine in `cell-data.sh`** — bounded 2-minute budget, handles `shutting-down`/`resetting` states, escalates to `dms reset` on timeout.
- [x] **Roaming detection and logging** — `log_serving` records PLMN, RAT, roaming status to `/var/log/cellular.log` on every attach.
- [x] **`just smoke-cellular`** — end-to-end test: `cell-data wake && up && ping -I ppp0 8.8.8.8 && down`.
- [x] **Approved roaming partners list** — `/etc/cellular/roaming-partners` auto-generated by `tools/gen-roaming-partners.py` (wired as `just gen-roaming-partners`), joining `eskimo_roaming.md` against `tools/data/mcc-mnc-list.json` (vendored pbakondy/mcc-mnc-list, ~3000 operators). Fuzzy-matches brand names with parent-brand aliases. 118/139 Eskimo entries → 154 MCC/MNC pairs. **Re-run after updating `eskimo_roaming.md`** (new partners or switching eSIM provider).
- [x] **eSIM provisioning** — lpac → qmi-send-apdu lpac mode → QMI UIM → eUICC. Works on golden firmware. ISD-R AID filter bypassed by truncating to 6-byte prefix.
- [ ] **QMI-proxy boot-time orphan subscriptions + modem restart reboots** — `qmi-proxy` as persistent multiplexer halved leak rate, but 4 `kworker/u8:N` still pile up in `D` state after every boot and `send_filled_buffers_to_user: Send Failed -3 drop_count=...` grows at ~10/min, pinning load average around 4. Suspect: modem init retry loop hammers QMI while Q6 DSP isn't ready. Fix: wait for Q6 readiness via sysfs state before issuing QMI.
  - **2026-04-18 finding:** `rc-service rmt-storage restart` (cascades to modem+qmi-proxy) triggers a device reboot ~60s later. qmi-proxy stale PID + Q6 `shutting-down` state → hardware watchdog fires. Boot-time init works fine.

### Zig 0.16 tool ports

Porting C tools to Zig 0.16.0 (release, `~/zig-x86_64-linux-0.16.0/zig`). Build umbrella at `tools/build.zig`, cross-compile via `just build-zig-tools`. Patterns established in wata-metricsd: raw `linux.fd_t`, `linux.errno()` switch, `init.args.iterate()`, `posix.openatZ(AT.FDCWD, ...)`.

- [x] `reboot-bootloader` — trivial syscall, 24→25 LOC. Commit `6ac8401`.
- [x] `rmt_storage` — 1013 LOC daemon. Verified on device: cold reboot → UIO discovery → modem EFS boot → LTE attach on Sunrise. Earlier reboots were caused by `rc-service modem restart` races, not the daemon itself.
- [x] `qmi-send-apdu` — 665 LOC QMI UIM client. Verified: byte-identical wire format to C, full eUICC test pass, daemon mode works with lpac.
- [x] `libqipcrtr4msmipc` — deleted (commit `7a77f3e`), custom libqmi has native AF_MSM_IPC.
- DIAG tools (`cell-diag`, `diag-apdu`, `diag-efs-write`) moved to `~/bq268-modem-diag`.

## Backlog

- [ ] Read-only rootfs — Production hardening. Prevents eMMC wear and corruption from hard power-off. overlayfs on tmpfs for /var, /tmp.
- [ ] OTA updates — Mechanism for deploying rootfs updates over cellular/WiFi. Dual-partition (A/B) or full-image reflash.
- [ ] Watchdog timer — Hardware watchdog (QCOM WDT) to auto-reboot on hang. Critical for unattended field device.
- [ ] Unused service cleanup — Remove acpid, machine-id, watchdog services pulled in by Alpine defaults. Reduces boot noise and attack surface.
- [x] Power switch screen on/off — DTS updated to SW_LID, keyd wired to screen-on/screen-off via fb0 blank + governor switch.
- [ ] Kernel module trimming — Strip unused modules from rootfs to save space and boot time. Only load what's needed.
- [ ] Security hardening — Drop to non-root for the app. Disable root login over cellular. Firewall (nftables) to restrict outbound to app traffic only.
- [ ] Modem DIAG logging — tools moved to `~/bq268-modem-diag`. Zig port pending there.
