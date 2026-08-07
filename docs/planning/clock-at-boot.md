# A plausible wall clock before the network is used (spec handoff from wata)

From: wata-sgola (plan 0035, 2026-08-07). Status: DONE — landed and
verified on-device 2026-08-07; see "What landed" at the bottom.

## Problem

The handset boots with its clock at **Jan 1 1970** and, on the runs
measured here, never leaves it. That single fact takes the whole app
down: at 1970 every TLS handshake fails certificate validation, and
wata's transport (iroh) needs TLS for both its relay connections and its
pkarr/DNS address discovery. A handset with perfect wifi therefore
cannot reach its server at all.

Measured on-device 2026-08-07, cold boot:

```
# wget -q -T8 -O- https://euw1-1.relay.iroh.network/
error:0A000086:SSL routines:...:certificate verify failed
# date
Thu Jan  1 00:30:21 UTC 1970          <- 8 minutes into the boot
# chronyc sources
MS Name/IP address  Stratum Poll Reach LastRx Last sample
===========================================================
                                       (empty — no sources at all)
# chronyc activity
8 sources with unknown address
```

Setting the clock by hand healed it in seconds: wata's running client
(no restart) went `error -> connecting -> connected -> syncing` within
33s of the step, with no other change.

## Root cause of the stuck clock

**chronyd cannot read `/etc/resolv.conf`.** udhcpc writes it mode
`0600 root:root`:

```
# ls -la /etc/resolv.conf
-rw-------    1 root     root            25 Jan  1  1970 /etc/resolv.conf
# ps aux | grep chronyd
 2454 chrony    0:00 /usr/sbin/chronyd -f /etc/chrony/chrony.conf
```

chronyd drops privileges to user `chrony`, so `pool pool.ntp.org` never
resolves — not at startup, not on any retry, not even minutes later with
DNS demonstrably working (`nslookup pool.ntp.org` from a root shell
answers instantly). Hence "8 sources with unknown address" forever.

NTP itself is fine. Given a literal address, chronyd steps the clock in
four seconds:

```
# rc-service chronyd stop
# chronyd -q -t 25 "server 195.141.190.190 iburst"
System clock wrong by 1786090281.263610 seconds (step)
```

Nothing about `makestep 1 3` or the pool choice is wrong; the resolver
is simply unreachable to the daemon.

## Ask

1. **Make `/etc/resolv.conf` world-readable** (`0644`) — the udhcpc
   script writes it, so fix it there rather than with a one-off chmod, or
   it comes back at the next lease. This is the actual fix; everything
   else below is belt-and-braces.
2. **Persist the clock across boots** (fake-hwclock style): save the
   time on shutdown and on a slow timer, restore it at boot before the
   network services start. A restored timestamp from the last shutdown
   is days old at worst, which is inside every certificate's validity —
   so the app works from the first second of a boot instead of waiting
   on NTP at all. This board has no battery-backed RTC, so nothing else
   provides it.
3. **Step the clock when the network arrives**, rather than only at
   chronyd start: a `wpa_cli` action hook (there is already one at
   `/etc/wpa_supplicant/wpa_cli.sh`) or the net-watchdog is the natural
   place — `chronyc burst`/`chronyc makestep`, or a one-shot
   `chronyd -q`. Ordering, not just reachability, is the boot-time
   hazard: chronyd starts before wifi.

Worth a look while in there (seen on the same boots, not diagnosed):
`rc-status` reports **`net-watchdog [crashed]`** and
**`qmi-proxy [crashed]`**.

## What landed (2026-08-07, verified on-device)

- **`/etc/resolv.conf` stays world-readable.** The 0600 came from pppd's
  umask through `ip-up`'s temp file, and `ip-down` restoring that saved
  copy made it self-perpetuating across boots. Both scripts now set
  `umask 022` and `chmod 644` the result.
- **swclock replaces hwclock** (`rc-update add swclock boot`): the clock
  is restored at boot from `/var/lib/misc/openrc-shutdowntime`, so a
  device that was shut down cleanly starts with a plausible clock and
  never waits for NTP at all. `/etc/periodic/15min/save-clock` re-saves
  it every 15 minutes, bounding what a battery pull can lose; the image
  build seeds the file with its own build date.
- **`clock-kick`** (new, `/usr/local/bin`) runs from wpa_cli's CONNECTED
  action and pppd's `ip-up`: with the clock below the 2025 floor it
  restarts chronyd — which is what makes it resolve its pool NOW rather
  than on its own minutes-long retry — then steps and banks the result.
- **The hardware waits moved into the background.** `audio-mixer` and
  `wifi` both return immediately and do their readiness polling in a
  subshell, so nothing behind them in the runlevel waits on the Q6.
  Each then gates on what it actually needs and verifies the result —
  `audio-mixer` on the modem subsystem being ONLINE and on reading its
  route back, `wifi` on the same ONLINE state before the wlan chip's NV
  download, retrying the module load if calibration failed.
- **qmi-proxy is supervised** (`supervise-daemon`), so `rc-status` stops
  calling a healthy proxy "crashed" off the wrapper's pid.

### What did NOT land: a parallel runlevel

`rc_parallel="YES"` was tried the same day and reverted. It does cut the
boot, but on this board the two radios cannot come up together: WCNSS
pushes the wlan chip's NV calibration blob over the same SMD transport
the Q6's firmware load saturates, and overlapping them makes cold-boot
calibration fail —

    wlan: [F :HDD] hdd_driver_init:CBC not completed

after which the driver loads, `wlan0` comes up, and `wpa_supplicant`
sits in `SCANNING` with an empty result list forever. Indistinguishable
from "no APs in range" from userspace, and it cost the device its wifi
on roughly one boot in three. The same overlap silences the speaker (the
codec resets `RX2 MIX1 INP1` to zero when the Q6 comes up under a route
written too early).

So the ordering stays serial and wifi stays behind the modem. The boot
is ~42s to `syncing` rather than the ~16-24s the parallel runlevel got;
a handset that keeps its wifi is worth the twenty seconds. Five
consecutive cold boots after the revert: wlan0 up with an address every
time, zero CBC failures, the speaker route verified with zero re-applies,
and `speaker-check.py` hearing the tone on all five.

Verified across five cold boots, including a hard `reboot -f` with the
saved clock deleted (the battery-pull case): `clock-kick` logged
`clock is 1728470800 (below 1735689600) — restarting chronyd` and then
`clock set` three seconds after the interface came up, and wata reached
`syncing` three seconds after that. `chronyc sources` now shows four
reachable pool servers where it showed none.

## What wata does on its side (already landed)

wata does not treat a dial failure as a server failure while the clock
is implausible: the boot screen stays on "starting up..." instead of
"can't reach server", and `/tmp/wata.log` carries one line per
connectivity change with the clock's state
(`net: +47s pipe=wifi conn=connecting clock=UNSET`). That is honest
presentation, not a fix — with the clock stuck, the handset stays calmly
unusable. The fix is here.

Detail: wata-sgola `docs/plans/0035-boot-truthfulness.md`.
