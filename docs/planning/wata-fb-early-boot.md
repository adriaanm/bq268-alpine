# wata-fb as the boot-time UI (early boot)

Origin: the wata repo (`~/g/bq268/wata-sgola`, plan
`docs/plans/0003-parity-and-beyond.md`, item `[FB-EARLY-BOOT]`). This doc
is the alpine-side spec; wata tracks its own half there.

## Goal

The handset should boot straight into wata: power on, and the first
interactive thing on the LCD is the wata UI — not the kernel log, not the
system menu. Today `inittab` respawns `/usr/local/bin/system-menu` on
tty1 and a human picks "wata" from it; wata-fb therefore starts late and
only on request.

## What alpine changes

1. **tty1 runs wata directly**: the `tty1::respawn:` entry becomes
   `/opt/wata/start.sh` (which already `exec`s `/opt/wata/wata-fb ui`).
   `respawn` doubles as crash-restart supervision — that is the intended
   mechanism, no openrc service for the UI.
2. **Prerequisite audit, not reordering**: wata-fb needs `/dev/fb0` and
   the input event devices at start (kernel-provided, present by the time
   respawn entries run) and does NOT need the network, the modem, or a
   running wata-server — it owns the waiting state (see contract). Boot
   ordering only has to guarantee what it guarantees today for
   system-menu; nothing about network bringup moves. `audio-mixer` (in
   the default runlevel) may still be settling when the UI first paints —
   acceptable, since first playback/record is human-seconds away.
3. **Escape hatches stay**: the `ttyGS0` gadget-serial getty entry is
   untouched (it is the recovery path if wata-fb crash-loops), and
   `system-menu` stays installed and runnable from a shell until wata's
   settings applet fully subsumes it (wata tracks that as
   `[FB-SETTINGS-FULL]`).

## Sequencing gate (do not flip tty1 before this holds)

The system menu is currently the on-device path to power off / reboot /
reboot-to-bootloader/EDL. wata-fb's settings applet already renders and
arms those power actions, but they are **unverified on hardware**. Flip
`tty1` to wata only in the same change (or after) those actions are
verified on the device — otherwise a parent has no clean way to power
off. That verification is the wata repo's task; this spec's task should
sit blocked on a one-line "wata power actions verified on-device" signal
in the wata repo's queue.

## What alpine must NOT do

- No boot-splash / fbcon work here — that is `[FB-BOOT-LOGO]`, separate.
- No "waiting for network" UI anywhere in init: wata-fb presents its own
  calm starting-up/waiting state over its existing sync backoff. Init's
  only job is to start it early and restart it if it dies.
- No changes to wata-fb's flags or environment beyond what start.sh
  already does; if wata-fb needs to know it is the boot UI, that lands in
  start.sh via the wata repo's deploy, not in the rootfs build.

## Acceptance

Power-on to wata's first frame with no menu interaction; kill the wata-fb
process on a running device and see it respawn within a second or two;
wifi disabled at boot shows wata's waiting state (not an error screen)
and recovers when wifi comes up.
