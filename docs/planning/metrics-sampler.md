# Metrics Sampler — Design Exploration

**Status**: scaffold landed, iterating. Working document — update as the design evolves. Becomes a reference guide once implemented.

## Progress log

- **2026-04-13**: Scaffold committed (`tools/wata-metricsd/`). `protocol.zig`, `sources.zig`, `jsonl.zig`, `sink.zig`, and an event-loop `main.zig` that binds `/run/wata.tick` (`AF_UNIX SOCK_DGRAM`, `fchmod 0662`), creates a 30-second BOOTTIME `timerfd` watchdog, `poll()`s both, drains the socket on wake (coalescing bursts), samples sysfs sources, and appends one JSONL line via the rotating file sink. `dt_ns` is computed as the delta from the previous sample's `ts_mono_ns`; `src` is `tick` / `watchdog` / `both` depending on which fd(s) were ready; `seq` uses the last tick's sequence when available, else an internal counter. Native and `arm-linux-musleabihf` ReleaseSafe builds both green, 12 unit tests passing (protocol × 4, sources × 3, jsonl × 3, sink × 2). The event loop itself is not unit-tested — it's verified end-to-end on device. **Not yet implemented**: `batt_status` string reader, backlight auto-discovery, OpenRC service, `build-rootfs.sh` wiring, on-device smoke test.
- **Zig 0.16-dev gotcha**: `timespec.sec` is `isize` (so `i32` on 32-bit ARM). Watchdog interval constant is typed `isize`, not `i64`, to cross-compile to `arm-linux-musleabihf` cleanly.
- **Rootfs wiring landed**: `rootfs/16-wata-metricsd.sh` installs `wata-metricsd` to `/usr/sbin/` and the OpenRC service to `/etc/init.d/`, and `rc-update add wata-metricsd default`. The service `start_pre` creates `/var/log/metrics` with `checkpath`. `just build-wata-metricsd` cross-compiles with Zig 0.16-dev, and `just build-tools` depends on it so `just build-rootfs` automatically picks up the latest binary.
- **`batt_status` + backlight auto-discovery**: `Sample` now stores `batt_status` inline (`[16]u8` buffer + `u8` length, exposed via `battStatus()`) so there's no allocator path. Backlight auto-discovery uses `getdents64` on `/sys/class/backlight/` to find the first non-dotfile entry; `Sources.backlight_name = ""` (the default) triggers it. 13 tests passing. **Open**: fixture-based tests for `findFirstBacklight` would need a populated `/tmp` dir tree — deferred to a follow-up since on-device verification is the more useful next signal.
- **CLI flags + host smoke test**: `main` now accepts `--tick=PATH` and `--log=DIR` via `std.process.Init.Minimal.args`, defaulting to `/run/wata.tick` and `/var/log/metrics`. Added `tools/wata-metricsd/scripts/send-tick.py` (a 50-line stdlib-only Python script that sends 16-byte heartbeats matching the wata spec) and `just smoke-wata-metricsd`, which builds native, spins the daemon on a temp dir, sends 3 ticks at 50ms intervals, and asserts `current.jsonl` has 3 lines. The end-to-end loop is now CI-able on the buildbox without root or device.
- **Clean shutdown via signalfd + `--max-iters` for tests**: `main` blocks SIGTERM/SIGINT via `sigprocmask` and routes them through a `signalfd` that's added to the same `poll()` set as the tick socket and watchdog. On wake the loop sees the signal fd ready, logs `caught signal, exiting cleanly`, and returns 0 — defers fire so OpenRC `stop` does the right thing without leaving stale `/run/wata.tick` (well, actually the unix socket file isn't removed on close — see *Open* below). Adds `--max-iters=N` to bound the loop for tests; the smoke test now uses `--max-iters=3` and `wait $PID` instead of `kill`, which removes a race window. **Open**: socket file isn't unlinked on shutdown (close drops the binding but leaves the inode), so a fresh start re-binds it via the unconditional `unlinkat` in `bindTickSocket`. That's fine in practice but worth noting.
- **ReleaseSmall + coalescing validated**: `just build-wata-metricsd` now uses `-Doptimize=ReleaseSmall`, producing a stripped 65 KB statically-linked ARM binary (down from ~11 MB ReleaseSafe with debug info — Zig's debug info is the bulk). For a daemon that wakes every 30 s and reads sysfs, ReleaseSafe perf is wasted; the eMMC space matters more. Also exercised the burst-coalescing path: sending 10 back-to-back ticks against a daemon with `--max-iters=2` produced two JSONL records with `ticks_coalesced` = 4 and 6 respectively, `seq` advancing 1→4→10 — confirming the recv-until-EAGAIN drain handles bursts correctly without dropping ticks across iterations.
- **Fixture-based source tests + alignment fix**: 3 new tests use a unique `/tmp` tree to exercise `Sources.sample()` end-to-end against a populated BQ268-shaped sysfs layout. They caught a latent alignment bug in the production `findFirstBacklight` path: the `getdents64` buffer was `[N]u8` without explicit alignment, but `dirent64` has `u64` fields so `@alignCast` would panic on a misaligned stack slot. Fixed by adding `align(@alignOf(linux.dirent64))` to both the production call site and the new test recursive-cleanup helper. **Tests now: 16/16 passing.**
- **On-device run + path corrections from real sysfs layout**: scp'd the 65 KB ARM binary to BQ268, ran with `--max-iters=3` against the heartbeat from `send-tick.py`. v1 result on device:
  ```json
  {"v_uv":3805407,"i_ua":0,"capacity":49,"batt_status":"Discharging",
   "wlan_up":true,"wlan_rx":28211868,"wlan_tx":1264937}
  ```
  Battery and wlan populate; `i_ua` is 0 as expected (CAF charger driver lacks USB PSY — see *Battery OCV table* in TASKS.md). Two surfaces were missing because the v1 defaults didn't match the actual hardware:
  1. **No `/sys/class/backlight/`** on this kernel — the LCD backlight is exposed at `/sys/class/leds/lcd-bl/brightness` (the same path `screen-on.sh`/`screen-off.sh` already write). Added a LED fallback with `led_backlight_name = "lcd-bl"` as the new default; `bl` and `screen_on` now populate from there. Verified: brightness=0 → `screen_on=false`; mid-test the screen woke up via the keypad and the next sample showed `bl=40, screen_on=true`, confirming reads are fresh per iteration.
  2. **No rmnet on this hardware** — cellular is PPP over SMD (`docs/modem_data.md`), so the iface is `ppp0`. Renamed the field and config from `rmnet_*` to `cell_*` (no historical samples to break) and changed the default `cell_iface` to `ppp0`. The cellular read path is identical helper code to wlan (which is verified working), so it'll populate as soon as `pppd call cellular` brings the iface up. Couldn't validate live: the modem is online but `not-registered-searching` after 50 s during this run; ppp0 verification is queued for whenever cellular registers. Added a fixture test for the LED fallback path (`/sys/class/leds/lcd-bl/brightness` only, no `/sys/class/backlight/`).
- **17 unit tests**, all paths verified end-to-end on host smoke test, and v1 verified on the actual BQ268 with real battery/wlan/backlight values.
- **Sink write-failure handling**: per the *Error handling* spec, `main` now catches `sink.write` errors, writes a single `wata-metricsd: sink.write failed, continuing\n` line to stderr (captured by OpenRC's `error_log` to `/var/log/wata-metricsd.log`), and latches a `sink_warned` flag so it stays silent until the next successful write. One log line per eMMC blip instead of a crash or a log flood. Tests and the ARM ReleaseSmall build are both still green.
- **Zig 0.16-dev API notes** — the new `std.Io` abstraction (Io.Dir, File operations taking an `Io` arg) is what `fbclient` uses for higher-level IO. For sysfs reads we stay at `std.posix.openatZ` / `posix.read` / `std.os.linux.close` — sysfs files are tiny and the posix layer is stable. Clocks use `std.os.linux.clock_gettime` directly because `std.posix.clock_gettime` is gone in this dev version.

## Goal

Gather on-device metrics that let us correlate **energy usage** with **screen time, wifi time, and cellular activity** on BQ268. Metrics are written to a local JSONL log; shipping off-device to a backend is a later phase and explicitly out of scope for v1.

## Constraints

- **MSM8909 can't suspend** (CAF 4.4 SPM/power-collapse bug). Any independent periodic sampler keeps the SoC warm on its own schedule, fighting the walkie-talkie app for wakeups. The sampler must coalesce its wakeups with existing activity rather than introduce a new tick source.
- **`current_now` is unreliable**: the CAF charger driver reports `0` because it has no USB PSY to enable current tracking. Energy has to be estimated from `voltage_now` + `capacity` deltas and an OCV table (see the existing *Battery OCV table* task in `TASKS.md`). The sampler logs `current_now` anyway in case it's ever fixed.
- **Single-app device**: wata is the only foreground workload worth aligning to.

## Architecture

Two processes, loosely coupled via a unix datagram socket:

```
  wata (C, ~/wata)                    wata-metricsd (Zig, this repo)
  ┌──────────────────────┐            ┌───────────────────────────────┐
  │ matrix long-poll     │            │ poll(socket, timerfd)         │
  │   ↓ returns          │            │   ↓ wake                      │
  │ sendto(/run/wata.tick)├──datagram─▶│ drain socket (coalesce)       │
  │ render / other work  │            │ read sysfs sources            │
  │ ↑ loop               │            │ append JSONL                  │
  └──────────────────────┘            │ rearm watchdog (30s)          │
                                      └───────────────────────────────┘
```

**Why the wata heartbeat drives sampling**: wata's matrix poll is already the dominant wakeup source on an idle device. Ticking once per iteration means the sampler burns CPU and reads sysfs in the same window where wata is already doing work and the radio is already hot. When wata's long-poll is slow (idle user, no events), sampling slows with it automatically — exactly the behaviour we want.

The heartbeat protocol is documented as a spec handed to the wata repo:
[`~/wata/docs/planning/metrics-heartbeat-tick.md`](../../../wata/docs/planning/metrics-heartbeat-tick.md).

## Implementation: `wata-metricsd` (Zig 0.16-dev)

Match the fbclient setup in wata: Zig 0.16-dev, musl target, `minimum_zig_version = "0.16.0"` in `build.zig.zon`. Cross-compile to `arm-linux-musleabihf` for the device; native build for the buildbox as a sanity target.

### Layout

```
tools/wata-metricsd/
├── build.zig
├── build.zig.zon
├── src/
│   ├── main.zig           # event loop: poll(socket, timerfd)
│   ├── sources.zig        # sysfs readers (battery, backlight, net)
│   ├── sink.zig           # JSONL writer + rotation
│   └── protocol.zig       # tick datagram layout (matches wata spec)
└── README.md
```

Install as `/usr/sbin/wata-metricsd` via `build-rootfs.sh`. OpenRC service in `rootfs/files/etc/init.d/wata-metricsd`.

### Event loop

1. `socket(AF_UNIX, SOCK_DGRAM|SOCK_NONBLOCK|SOCK_CLOEXEC)`, `bind("/run/wata.tick")`, `fchmod(0662)`.
2. `timerfd_create(CLOCK_BOOTTIME)`, armed at 30s interval (idle watchdog).
3. `poll()` on both fds indefinitely.
4. On wake:
   - Drain the socket via non-blocking `recv()` loop until `EAGAIN`. Remember tick count, first and last `ts_mono_ns`, highest `seq`.
   - Sample all sources (see below).
   - Write one JSONL line.
   - Rearm watchdog.

### Sources (all sysfs, no ioctls in v1)

| Field          | Source                                             | Notes |
|----------------|----------------------------------------------------|-------|
| `v_uv`         | `/sys/class/power_supply/battery/voltage_now`      | primary energy signal |
| `i_ua`         | `/sys/class/power_supply/battery/current_now`      | logged but expected `0` on current kernel |
| `capacity`     | `/sys/class/power_supply/battery/capacity`         | % SoC |
| `batt_status`  | `/sys/class/power_supply/battery/status`           | Discharging/Charging/Full |
| `bl`           | `/sys/class/backlight/*/brightness`                | 0 means screen off in practice |
| `screen_on`    | derived: `bl > 0 && bl_power == 0`                 |  |
| `wlan_up`      | `/sys/class/net/wlan0/operstate == "up"`           |  |
| `wlan_rx/tx`   | `/sys/class/net/wlan0/statistics/{rx,tx}_bytes`    | cumulative |
| `cell_up`      | `/sys/class/net/ppp0/operstate == "up"`            | PPP over SMD, not rmnet |
| `cell_rx/tx`   | `/sys/class/net/ppp0/statistics/{rx,tx}_bytes`     | cumulative |
| `ts_mono_ns`   | `clock_gettime(CLOCK_BOOTTIME)`                    | for dt integration |
| `ts_wall`      | `clock_gettime(CLOCK_REALTIME)`                    | for human correlation |

Byte counters are logged raw and cumulative; the analyzer computes per-interval deltas. Same for capacity/voltage — no smoothing in the sampler.

### JSONL schema (one line per sample)

```json
{"ts_mono_ns":123456789, "ts_wall":1760000000.123, "src":"tick",
 "seq":42, "ticks_coalesced":3, "dt_ns":987654321,
 "v_uv":3821000, "i_ua":0, "capacity":67, "batt_status":"Discharging",
 "bl":40, "screen_on":true,
 "wlan_up":true, "wlan_rx":1234567, "wlan_tx":89012,
 "cell_up":true, "cell_rx":9876, "cell_tx":4321}
```

- `src`: `"tick"` when woken by wata, `"watchdog"` when woken by timerfd, `"both"` if both fds were ready in the same `poll()`.
- `ticks_coalesced`: number of wata datagrams collapsed into this sample. Always `0` for pure watchdog wakeups.
- `dt_ns`: delta from the previous sample's `ts_mono_ns`. The integrand for energy estimation.

### Output rotation

- Active file: `/var/log/metrics/current.jsonl`
- Rotate at 1 MiB → `current.jsonl.1`, keep `.1`–`.4`. Drop older.
- Rotation is size-based and checked after each write. No timers.
- `/var/log/metrics/` lives on tmpfs if the read-only rootfs task lands; otherwise on eMMC with the rotation cap as the wear limit.

### Error handling

- Any sysfs read failure: log field as `null` for that sample, continue.
- `/run/wata.tick` bind failure at startup: fatal, exit with error. OpenRC will not restart-loop (respawn cap).
- `write()` to JSONL failure: log to syslog once, continue. Never crash on log-sink errors.

## Phasing

**v1** (this task):
- Daemon, heartbeat ingestion, sysfs sample, JSONL output, rotation, OpenRC service.
- Analysis is offline on the buildbox (`just pull-metrics` → scp). No backend.

**v2** (separate task, not now):
- Ship JSONL off-device (probably over the matrix backhaul wata already has, piggybacking on an existing connection to avoid a second TLS session).
- OCV-based energy integration.
- Backlight + governor correlation dashboards.

## Open questions

- ~~Exact rmnet interface name~~ — resolved: **no rmnet on this hardware**. Cellular is PPP over SMD (see `docs/modem_data.md`), iface is `ppp0`. Sources default `cell_iface = "ppp0"`.
- Do we want `phase=1` (post-render) ticks from wata later? Defer until v1 data shows whether the post-poll-only cadence smears render-vs-network too much.
- If wata starts *before* the sampler, its `sendto()` gets `ECONNREFUSED` and drops ticks until the sampler is up. Acceptable for v1; the sampler should start early in the OpenRC ordering regardless.

## Cross-references

- Heartbeat contract: `~/wata/docs/planning/metrics-heartbeat-tick.md`
- Existing *Battery stats daemon* task in `TASKS.md` — this planning doc **supersedes** it; the sampler is the battery stats daemon, generalized.
- Existing *Battery OCV table* task — blocks meaningful energy integration but not v1 data collection.
- fbclient Zig 0.16-dev setup as reference: `~/wata/src/fbclient/build.zig`, `build.zig.zon`.
