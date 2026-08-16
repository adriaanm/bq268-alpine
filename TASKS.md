# Tasks

## Active

- [ ] /data partition — repurpose the dead Android `system` partition (p6, 921 MB) as persistent device state, so a rootfs reflash stops destroying wata's identity/config/outbox, ssh host keys, wifi creds; also what unblocks reboot-forensics logging and the persisted clock. Spec: [docs/planning/data-partition.md](docs/planning/data-partition.md).

- [ ] Reboot forensics — persist the PMIC boot reason per boot + a tail of wata's log; optional ramoops later. The 2026-08-16 spontaneous reboot was UVLO/SMPL (brownout on cell data). Spec: [docs/planning/reboot-forensics.md](docs/planning/reboot-forensics.md) (handoff from wata-sgola).

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
  - **2026-07-05 partial fix landed** (`f633e56`): modem init gates on subsys ONLINE + non-mutating DMS read, sets mode online exactly once. Verified on device: DMS stays `online` (no more `shutting-down` wedge), drop rate 10/min → 2/min. **Still open:** 4 kworkers in D on the DIAG path (diag_socket_read / diag_cntl_process_read_data), load still ~4 — residual DIAG-side leak independent of the DMS retry loop.
  - **2026-04-18 finding:** `rc-service rmt-storage restart` (cascades to modem+qmi-proxy) triggers a device reboot ~60s later. qmi-proxy stale PID + Q6 `shutting-down` state → hardware watchdog fires. Boot-time init works fine.
  - **2026-07-05 finding:** this instability is now the leading cause of the **silent-audio regression** — audio's AFE/APR shares the Q6 with the modem, so the wedged Q6 (`shutting-down`) degrades audio. Fix spec (init-ordering only, no security scope): [docs/planning/qmi-q6-readiness-gating.md](docs/planning/qmi-q6-readiness-gating.md). Verify with both stability metrics and an on-device audio test.
  - **2026-07-05 session 2:** Q6→audio hypothesis **disproven** — Q6 healthy after the fix, stream clean full-duration, still silent. `Playback 0 Volume` only applies to an open substream (wata volume-probe). Full log: `~/g/bq268/audio_experiments.md`.
  - **2026-07-05 RESOLVED TO KERNEL:** stock 3.18 RAM-boot (`fastboot boot bq268-edl/dump/boot.bin`, framework stopped, same mixer recipe, tinyplay) plays a **loud clean tone** — hardware fine, userspace recipe correct. **The silence is a bug in our CAF 4.4 kernel port.** Captures in `docs/stock-audio-capture-2026-07-05/`.
  - **2026-07-05 session 3 — fault isolated to RX-only DSP path.** Alpine `/d/asoc` dump during silent aplay is byte-for-byte identical to stock (DPCM FE→BE `MSM8952 Media1`→`PRI_MI2S_RX`, both mono S16/48k `start`; DAPM power identical). MI2S clock math + codec DAI binding correct; clock API version not the fault (**capture works**, shares MCLK). AFE topology cal missing but non-fatal (q6afe falls back to passthrough). Capture working ⇒ codec+MCLK+I2S alive ⇒ fault is RX-only (DSP ADM routing to primary-MI2S AFE port, or the RX port not rendering), invisible from debugfs.
  - **2026-07-05 RESOLVED — root cause found.** Codec regmap register cache. The 3.18→4.4 port (`bq268-caf-4.4` `d86b83b`) gave msm8x16-wcd a `REGCACHE_FLAT` regmap pre-seeded from `reset_reg_defaults`; regcache drops writes matching the cache, but the codec soft-resets during init/enable → cache≠hardware → RX config never reaches silicon (cache read back correct, fooling every DAPM/mixer/clock/ACDB check; capture worked because TX writes diverged). Proven on-device via regmap `cache_bypass=Y` (440Hz noise-floor→audible, confirmed by ear).
  - **2026-07-06 FIX FLASHED & VERIFIED.** First attempt `78535d2` (REGCACHE_FLAT→REGCACHE_NONE) was **wrong**: the codec's `adsp_state_callback`→`msm8x16_wcd_device_up`→`snd_soc_cache_sync`→`regcache_sync()` `BUG_ON()`s with no cache (`regcache.c:320`); the NONE kernel hard-oopsed at every ADSP power-up, wedging codec bring-up (silent/weak, stuck `kworker/u8`). **Correct fix: `bq268-caf-4.4` `bb662b69`** — keep `REGCACHE_FLAT`, add `regcache_cache_bypass(codec->component.regmap, true)` in `device_up` right after the one-time sync (replicates the proven `cache_bypass=Y`). Built + flashed from debian; clean-boot Yeti **440Hz=52 steady** (noise floor 1.5, stock 189), survived a power cycle. NB CPU is 95% idle — the D-state DIAG `kworker/u8` inflate loadavg only. **Mac bare repo still on wrong NONE `78535d2` — sync to debian `bb662b69`.** wata-side playback (giant pcm_writei ETIMEDOUT, stream stays PREPARED) is a separate open issue tracked in wata.
  - **2026-07-05 session 3 — ACDB ruled out empirically.** Built a bionic-on-Alpine harness (stock linker + lib closure + MTP acdbdata from `~/g/bq268/edl-dump/{system,vendor}.bin`; drove stock `libacdbloader.so` via an `LD_PRELOAD` shim into stock `toybox`). Loaded real stock cal (`init_v2=0`), pushed RX cal to `/dev/msm_audio_cal` (fds confirmed) both before COPP open and injected into the live stream — **zero change, still silent**, kernel still logs `AFE_TOPOLOGY_CAL not initialized for port 4096` / `no matching cal_block`. Calibration is not the cause (matches source: missing AFE topology → q6afe passthrough). **Next: diff `afe_port_start` + MI2S audioif port config for port 0x1000 between our 4.4 q6afe/msm8952 and pristine CAF 3.18 on debian.** Harness left at `/system`+`/vendor` on device (~5MB; removable — disk 94%). Full log: `~/g/bq268/audio_experiments.md`.

### Zig 0.16 tool ports

Porting C tools to Zig 0.16.0 (release, `~/zig-x86_64-linux-0.16.0/zig`). Build umbrella at `tools/build.zig`, cross-compile via `just build-zig-tools`. Patterns established in wata-metricsd: raw `linux.fd_t`, `linux.errno()` switch, `init.args.iterate()`, `posix.openatZ(AT.FDCWD, ...)`.

- [x] `reboot-bootloader` — trivial syscall, 24→25 LOC. Commit `6ac8401`.
- [x] `rmt_storage` — 1013 LOC daemon. Verified on device: cold reboot → UIO discovery → modem EFS boot → LTE attach on Sunrise. Earlier reboots were caused by `rc-service modem restart` races, not the daemon itself.
- [x] `qmi-send-apdu` — 665 LOC QMI UIM client. Verified: byte-identical wire format to C, full eUICC test pass, daemon mode works with lpac.
- [x] `libqipcrtr4msmipc` — deleted (commit `7a77f3e`), custom libqmi has native AF_MSM_IPC.
- DIAG tools (`cell-diag`, `diag-apdu`, `diag-efs-write`) moved to `~/bq268-modem-diag`.

## Backlog

- [x] net-watchdog supervision — switch the service to supervise-daemon (status lies + no respawn today); failover must be supervised before wata's roaming leans on it. Spec: [docs/planning/net-watchdog-supervision.md](docs/planning/net-watchdog-supervision.md). 2026-08-16: LIVE and accepted on-device — the init file was pushed over ssh (rootfs is rw; the one-file fix needed no reflash), kill -9 respawned in seconds with truthful status, and it survives reboot (clean PS_HOLD reboot, no fastboot stall).
- [x] wifi-join helper — `/usr/local/bin/wifi-join <ssid>` (PSK on stdin, never argv): replace-or-append the wpa_supplicant block, hashed psk, atomic 0600 write, live `wpa_cli reconfigure`; wata-fb's wifi_join op already calls exactly this and reports "helper missing" until it lands. Spec: [docs/planning/wifi-join-helper.md](docs/planning/wifi-join-helper.md). 2026-08-06: landed (`rootfs/files/usr/local/bin/wifi-join`, installed via 05-wifi.sh; checks `just test-wifi-join`) and hand-installed on the live device; on-device verification was arg-validation + dry-run only (handset mid-field-test, real conf untouched).
- [ ] wata-fb as the boot-time UI — flip the tty1 respawn from system-menu to `/opt/wata/start.sh`; gated on wata verifying its power actions on-device. Spec: [docs/planning/wata-fb-early-boot.md](docs/planning/wata-fb-early-boot.md).
- [x] A wall clock before the network is used — the handset boots at 1970 and STAYS there (chronyd runs as user `chrony` and udhcpc writes `/etc/resolv.conf` `0600 root:root`, so the pool never resolves). At 1970 every TLS handshake fails, so wata cannot reach its server at all on a perfectly good wifi. Fixed 2026-08-07: resolv.conf mode (pppd's umask, self-perpetuating through ip-down), swclock restoring the clock at boot + a 15-min save, and `clock-kick` from the wifi/ppp up-actions. Verified over five cold boots incl. a hard reboot with the saved clock deleted. Same pass: parallel runlevel start and a backgrounded audio-mixer card wait (wifi sorted last behind hardware polls — the app now syncs ~16-24s after userspace instead of ~41s), and qmi-proxy under supervise-daemon. Spec + results: [docs/planning/clock-at-boot.md](docs/planning/clock-at-boot.md).
- [ ] `consoleblank=0` on the kernel cmdline — the console-blank timer blanks the fbdev (white panel, fb writes invisible) in any window where wata-fb is not running; wata-fb unblanks itself, the cmdline half is ours. Spec: [docs/planning/consoleblank-cmdline.md](docs/planning/consoleblank-cmdline.md).

- [ ] Read-only rootfs — Production hardening. Prevents eMMC wear and corruption from hard power-off. overlayfs on tmpfs for /var, /tmp.
- [ ] OTA updates — Mechanism for deploying rootfs updates over cellular/WiFi. Dual-partition (A/B) or full-image reflash.
- [ ] Watchdog timer — Hardware watchdog (QCOM WDT) to auto-reboot on hang. Critical for unattended field device.
- [ ] Unused service cleanup — Remove acpid, machine-id, watchdog services pulled in by Alpine defaults. Reduces boot noise and attack surface.
- [x] Power switch screen on/off — DTS updated to SW_LID, keyd wired to screen-on/screen-off via fb0 blank + governor switch.
- [ ] Kernel module trimming — Strip unused modules from rootfs to save space and boot time. Only load what's needed.
- [ ] Security hardening — Drop to non-root for the app. Disable root login over cellular. Firewall (nftables) to restrict outbound to app traffic only.
- [ ] Modem DIAG logging — tools moved to `~/bq268-modem-diag`. Zig port pending there.
