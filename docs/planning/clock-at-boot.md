# A plausible wall clock before the network is used (spec handoff from wata)

From: wata-sgola (plan 0035, 2026-08-07). Status: open.

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

## What wata does on its side (already landed)

wata does not treat a dial failure as a server failure while the clock
is implausible: the boot screen stays on "starting up..." instead of
"can't reach server", and `/tmp/wata.log` carries one line per
connectivity change with the clock's state
(`net: +47s pipe=wifi conn=connecting clock=UNSET`). That is honest
presentation, not a fix — with the clock stuck, the handset stays calmly
unusable. The fix is here.

Detail: wata-sgola `docs/plans/0035-boot-truthfulness.md`.
