# bq268-alpine

Alpine Linux rootfs for the BQ268 walkie-talkie (MSM8909/Snapdragon 210).

Single-app embedded device: fast boot, low RAM, mainline-friendly kernel,
open source userspace. Runs on a CAF 3.18 kernel with mainline 6.x as
the development target.

## What works

- Alpine boots to login in ~5s (CAF 3.18, 4 cores)
- ST7735S 128x160 SPI display with fbcon
- GPIO keypad (6-key matrix + PTT + 3 function keys)
- USB gadget serial + ECM ethernet
- WiFi (CAF prima/WCNSS)
- Battery monitoring with low-battery shutdown
- Power button screen toggle, auto-blank on idle
- TUI settings and system info menus (F3/F6)
- CPU frequency scaling (interactive governor)
- NTP time sync (chrony)

## Building

Requires an ARM cross-compiler and a built CAF 4.4 kernel at
`~/bq268-caf-4.4`.

```sh
just build-tools    # cross-compile tools/
just build-rootfs   # build rootfs image (needs sudo)
```

WiFi credentials: create `wifi.conf` (gitignored) with
wpa_supplicant network blocks.

## Flashing

```sh
fastboot flash userdata out/rootfs.img
fastboot flash boot out/boot.img
fastboot reboot
```

## Project structure

```
build-rootfs.sh          scaffold: image creation, chroot, source loop
rootfs/                  feature modules (sourced in order)
  00-packages.sh         Alpine packages
  01-system.sh           hostname, inittab, fstab, services
  02-kernel.sh           kernel + modules install
  03-firmware.sh         WiFi/modem/GPU firmware
  04-usb-gadget.sh       USB ACM serial + ECM ethernet
  05-wifi.sh             wpa_supplicant + DHCP
  06-timesync.sh         chrony NTP
  07-battery.sh          battery monitor daemon
  08-screen.sh           power button, screen idle, keyd
  09-cpufreq.sh          CPU governor
  10-menus.sh            TUI settings + sysinfo menus
  11-debug.sh            diagnostic init
tools/                   cross-compiled ARM utilities
firmware/                extracted device firmware (gitignored)
docs/                    hardware docs, roadmap, bringup guides
```

## License

[The Unlicense](UNLICENSE) -- public domain.
