# consoleblank=0 on the kernel cmdline (spec handoff from wata)

From: wata-sgola (FB-FIRST-FRAME-WHITE, 2026-08-06). Status: open.

## Problem

The "white screen until first keypress" on wata-fb respawn was
root-caused to **kernel framebuffer blanking**: the kernel's
console-blank timer blanks the fbdev, and a blanked ST7735S panel
displays white with the backlight on while writes to the mmap'd
`/dev/fb0` never reach the glass. A keypress unblanks via the VT path,
which is why the app "drew on first key". Proven live on-device:
`echo 1 > /sys/class/graphics/fb0/blank` reproduces it,
`echo 0 > ...` cures it.

wata-fb now unblanks itself at startup and on screensaver wake (writes
`0` to `/sys/class/graphics/fb0/blank`; wata-sgola
`docs/design/wata-fb.md`, "Kernel framebuffer blanking"). The boot-side
half belongs here: with the console-blank timer armed, any window where
wata-fb is not running (before its first respawn, between respawns)
can land on a freshly blanked panel.

## Ask

Add `consoleblank=0` to the kernel cmdline handoff so the timer never
arms. Note the live boot partition's cmdline was last patched IN PLACE
(page-0 dd to `/dev/mmcblk0p5`, backup in `out/`, method in this repo's
CLAUDE.md — the flashed boot.img matches no in-tree artifact), so this
is both an in-tree cmdline change for future images and, if wanted
before the next full flash, another in-place patch. Current in-place
cmdline additions: `quiet logo.nologo vt.global_cursor_default=0`.

## Verification

Boot the device, leave it idle past the old blank timeout (10 min
default) with wata-fb stopped: the console must not blank
(`cat /sys/class/graphics/fb0/blank` stays 0).
