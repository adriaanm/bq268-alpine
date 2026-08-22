# Charging telemetry & watchdog

Status: **planned** (2026-08-22). Motivation: the last remaining HW
stability issue before daily-driving. On 2026-08-22 the handset sat in
its cradle for 2+ hours discharging with every charger register reading
perfect; nobody noticed until the battery was nearly dead, and the
evidence needed a live debugging session to extract. This spec makes
charging failures (a) visible at cradle time and (b) diagnosable after
the fact from persistent logs.

Background from that session (full detail: root `CLAUDE.md` Learnings
2026-08-22): the PM8909 LBC's `fastchg` IRQ count in `/proc/interrupts`
is the only ground truth for "actually charging" — sysfs
`battery/current_now` is always 0 (VM-BMS has no current sense), and all
config registers can read correct while the FSM never runs. `usbin_valid`
IRQ deltas count VBUS bounces (cradle contact health). One bounce
misdetected the DCP cradle as SDP → 100 mA limit, a software-recoverable
failure. USB-C PD chargers can never work (no CC Rd pulldowns on the
board — hardware, out of scope here).

## 1. Charge-path fields in wata-metricsd

Add to the per-sample record (all cheap reads):

- `usb_online` (bool) — `/sys/class/power_supply/usb/online`
- `usb_ma` (int) — `usb/current_max` in mA
- `fastchg_irqs`, `usbin_irqs`, `chggone_irqs` (ints) — parsed from
  `/proc/interrupts` rows `fastchg` / `usbin_valid` / `chg_gone`
  (sum across CPUs; rows identified by trailing name, not IRQ number —
  numbering is probe-order dependent)

Consumers judge by **deltas**: fastchg advancing while docked = healthy;
usbin_valid advancing = bouncing contacts (trend over days = wear);
`usb_online && status != "Charging"` sustained = anomaly. JSONL already
persists to `/var/log/metrics/`; consider routing to `/data/log/` so
charge history survives reboots (it's exactly the pre-failure record we
want after an unexplained drain).

## 2. Surface "plugged but NOT charging" in wata-fb (wata-sgola side)

wata already reads battery sysfs for the percentage. Add: if
`usb/online == 1` and `battery/status != Charging` sustained ≥3 min,
render a visually distinct state (e.g. plug glyph with an X) instead of
the normal charge indicator. The owner sees the failure when cradling
the device, not the next morning. Track in wata-sgola's `TODO.jsonl`;
this doc is the rootfs-side spec only.

## 3. charge-nanny (conservative auto-remediation)

Small supervised service or a metricsd hook, checked every ~60 s. On
sustained anomaly (docked ≥3 min, not charging):

1. **BC1.2 misdetect recovery**: if a DCP (`wall charger`) detection has
   been seen this boot (dmesg) and `usb/current_max <= 100000`, rewrite
   `1500000`. This is the one failure with a proven software fix. Never
   raise the limit if only SDP has ever been seen this boot (could be a
   real computer port).
2. **One FSM kick per anomaly episode**: toggle
   `battery/charging_enabled` 0 → 1.
3. **If still not charging**: append a decoded snapshot to
   `/data/log/charge-anomaly.log` — timestamp, sysfs state, IRQ counts,
   and the key LBC regs via
   `/sys/kernel/debug/regmap/spmi0-00/{address,data}`:
   `0x1009` (CHG_STATUS; bit3=VINMIN loop), `0x1010` (CHGR INT_RT_STS;
   bit5=FAST_CHG_ON), `0x1049` (CHG_CTRL; 0x90=enabled),
   `0x1310` (USB RT_STS; 0x03=VBUS valid), `0x1044/0x1045` (IBAT),
   `0x1052` (VBAT_WEAK), `0x10EE` (COMP_OVR1; **0x02 is the correct
   charging-allowed state**). Rate-limit to one snapshot per episode.

No other automatic register writes — everything else observed so far
needs a human (or a reboot, which the owner can decide on).

## 4. `just chg-status` recipe

One-shot ssh dump for interactive sessions: battery/usb sysfs, the three
IRQ counts, last BC1.2 dmesg lines, and the decoded register set above.
Codifies the 2026-08-22 session's recipe so it never gets re-derived.

## 5. Shutdown attribution (extends reboot-forensics)

**RESOLVED 2026-08-22** — the "unknown initiator" of the PS_HOLD
software shutdown at ~3.27 V is our own `battmon.sh`: its
`BATTERY_VMIN=3400000` voltage floor fires
`graceful-shutdown.sh "battery critical (...)"`, which logged only via
`logger` to tmpfs `/var/log` — evidence gone at poweroff. Working as
designed; the gap was purely persistence of the attribution. (Note the
floor cannot bite a charging device: battmon classifies
`status==Charging/Full` before checking the floor.)

Implemented (narrowed from the original wrapper-scripts idea — the
initiator question is answered, so no generic `poweroff`/`reboot`
wrappers): `graceful-shutdown.sh` appends timestamp, reason, capacity,
`voltage_now` and `usb/online` to `/data/log/boot-reasons.log` (the same
file the per-boot PMIC PON/POFF reasons land in) before `poweroff`,
best-effort so attribution failure can never block the shutdown. battmon
additionally mirrors its state-change lines to `/data/log/battmon.log`
(64 KB rotate-to-`.old` guard).

## Verification

- Metricsd fixture test: `/proc/interrupts` parser against a BQ268-shaped
  fixture (incl. rows with different IRQ numbers).
- On-device: cradle the handset, confirm fastchg delta > 0 in the JSONL;
  yank/reseat to confirm usbin_valid delta increments.
- Nanny negative control: docked and charging normally → no writes, no
  snapshots (check log stays empty over an overnight charge).
- Misdetect drill: manually `echo 100000 > usb/current_max` while docked
  on DCP; nanny must restore 1500 mA within its check interval.
