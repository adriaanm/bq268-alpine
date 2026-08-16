# Reboot forensics: keep enough evidence to name every reboot's cause

Status: proposed (spec handoff from wata-sgola, 2026-08-16)

## Why

The handset rebooted mid-use on 2026-08-16 and the cause was nearly
lost: `/tmp/wata.log` and dmesg are tmpfs, `/var/log/messages` had only
the new boot. The one survivor was the PMIC's own record, printed by
qpnp-power-on early in every boot — that event read **power-off: UVLO,
power-on: SMPL** — a brownout (transient rail collapse; the device was
on cell data, whose PA bursts are the classic trigger, possibly stacked
on speaker load), auto-restarted by the PMIC. Diagnosis one-liner,
now in the top-level bq268 CLAUDE.md learnings:
`dmesg | grep -i 'Power-o'`.

The PMIC record only covers the LAST transition and only power-class
causes. Three cheap changes make every future reboot attributable.

## What

1. **Log the boot reason persistently, every boot.** An openrc script
   (or a line in an existing one) appends to `/var/log/boot-reasons`:
   timestamp + the two `qpnp-power-on … Power-o…` dmesg lines + uptime
   of the previous record if derivable. One line per boot, rotated at
   some small size. This turns "it rebooted last night" into a greppable
   history, and a cluster of UVLO entries into a battery/contacts
   verdict.

2. **Persist a tail of the app log.** `/tmp/wata.log` dies with the
   rail. A tiny cron/loop (or wata-metricsd, which already ticks) copies
   the last ~50 lines to `/var/log/wata.last` every ~30s — bounded eMMC
   wear, and after a reboot the pre-crash context (net transitions,
   sends, notify lines) survives.

3. **(Kernel, optional, bigger)** pstore/ramoops for the panic class:
   the CAF 4.4 config has no PSTORE/RAMOOPS (no /proc/config.gz on
   device; verify in bq268-caf-4.4). A reserved-memory ramoops node +
   CONFIG_PSTORE_RAM would preserve oops/panic logs across warm resets.
   Only worth it if reboots ever recur with a non-power PON reason —
   the 2026-08-16 event did not need it.

Guard that must hold regardless:
`/sys/module/qpnp_power_on/parameters/dload_on_uvlo` stays `0` — set,
a brownout would drop the handset into EDL (screen dark, needs a host)
instead of rebooting into the app.

## Out of scope

Brownout mitigation itself (battery health, contacts, PA/speaker load
shaping) — first get the history from (1) to see how often and under
what pipe it happens.
