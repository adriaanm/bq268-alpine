# net-watchdog: real supervision

Status: DONE — live on the handset 2026-08-16; acceptance passed
(kill -9 respawn within respawn_delay, truthful status, survives a
clean reboot). Installed by pushing the init file over ssh; the rw
rootfs made a reflash unnecessary.

Origin: the wata repo (`~/g/bq268/wata-sgola`, queue key
`NET-WATCHDOG-SUPERVISION`). Wata's iroh roaming (its plan 0013,
milestone 4) leans on wifi/cellular failover actually running; today its
supervision both lies and does nothing.

## Symptom

`rc-service net-watchdog status` reports **crashed** while
`/usr/sbin/net-watchdog` is demonstrably running, and if the process
does die nothing restarts it. The failover a roaming handset depends on
is therefore unsupervised in exactly the situations it exists for.

## Cause

`/etc/init.d/net-watchdog` uses the `command_background=true` +
`pidfile=/run/net-watchdog.pid` pattern: start-stop-daemon backgrounds
the shell script and writes the pidfile once. That pattern has no
supervision at all (nothing watches the PID), and status is only as good
as the pidfile — a removed/stale `/run` entry, or the script
re-execing, leaves OpenRC comparing against a PID that no longer
matches: "crashed".

## Fix (recommended)

Convert the service to OpenRC's built-in supervisor:

```
supervisor=supervise-daemon
command="/usr/sbin/net-watchdog"
respawn_delay=5
respawn_max=0        # retry forever; the daemon is the failover
```

Drop `command_background` and `pidfile` (supervise-daemon owns both
concerns). Status then reflects the supervisor's actual child, and a
dead watchdog respawns. No change to the watchdog script itself is
required; keep its `logger` lines as the restart evidence.

## Acceptance

On the device: `rc-service net-watchdog status` says started while it
runs; `kill -9` the watchdog process and see it respawned within
`respawn_delay` with a syslog line; status stays truthful across a
`rc-service restart` and a reboot.

## What not to do

Don't move the failover logic into wata — network interface failover is
the OS's job; wata only *renders* connectivity (its FB-CONN-STATUS
element).
