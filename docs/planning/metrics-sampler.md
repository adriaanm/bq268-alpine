# Metrics Sampler — Design Exploration

**Status**: scaffold landed, iterating. Working document — update as the design evolves. Becomes a reference guide once implemented.

## Progress log

- **2026-04-13**: Scaffold committed (`tools/wata-metricsd/`). `protocol.zig`, `sources.zig`, `jsonl.zig`, `sink.zig`, and an event-loop `main.zig` that binds `/run/wata.tick` (`AF_UNIX SOCK_DGRAM`, `fchmod 0662`), creates a 30-second BOOTTIME `timerfd` watchdog, `poll()`s both, drains the socket on wake (coalescing bursts), samples sysfs sources, and appends one JSONL line via the rotating file sink. `dt_ns` is computed as the delta from the previous sample's `ts_mono_ns`; `src` is `tick` / `watchdog` / `both` depending on which fd(s) were ready; `seq` uses the last tick's sequence when available, else an internal counter. Native and `arm-linux-musleabihf` ReleaseSafe builds both green, 12 unit tests passing (protocol × 4, sources × 3, jsonl × 3, sink × 2). The event loop itself is not unit-tested — it's verified end-to-end on device. **Not yet implemented**: `batt_status` string reader, backlight auto-discovery, OpenRC service, `build-rootfs.sh` wiring, on-device smoke test.
- **Zig 0.16-dev gotcha**: `timespec.sec` is `isize` (so `i32` on 32-bit ARM). Watchdog interval constant is typed `isize`, not `i64`, to cross-compile to `arm-linux-musleabihf` cleanly.
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
| `rmnet_up`     | `/sys/class/net/rmnet_data0/operstate`             | exact iface name TBC |
| `rmnet_rx/tx`  | same pattern                                       | cumulative |
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
 "rmnet_up":true, "rmnet_rx":9876, "rmnet_tx":4321}
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

- Exact rmnet interface name — check on a device with PPP up.
- Do we want `phase=1` (post-render) ticks from wata later? Defer until v1 data shows whether the post-poll-only cadence smears render-vs-network too much.
- If wata starts *before* the sampler, its `sendto()` gets `ECONNREFUSED` and drops ticks until the sampler is up. Acceptable for v1; the sampler should start early in the OpenRC ordering regardless.

## Cross-references

- Heartbeat contract: `~/wata/docs/planning/metrics-heartbeat-tick.md`
- Existing *Battery stats daemon* task in `TASKS.md` — this planning doc **supersedes** it; the sampler is the battery stats daemon, generalized.
- Existing *Battery OCV table* task — blocks meaningful energy integration but not v1 data collection.
- fbclient Zig 0.16-dev setup as reference: `~/wata/src/fbclient/build.zig`, `build.zig.zon`.
