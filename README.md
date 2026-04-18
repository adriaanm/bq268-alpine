# bq268-alpine

Alpine Linux rootfs for the BQ268 walkie-talkie (MSM8909/Snapdragon 210).

Single-app embedded device: fast boot, low RAM, CAF 4.4 kernel,
open source userspace.

## What works

- Alpine boots to login in ~5s (CAF 4.4, 4× Cortex-A7)
- ST7735S 128×160 SPI display with fbcon
- GPIO keypad (6-key matrix + PTT + 3 function keys)
- USB gadget serial + RNDIS ethernet
- WiFi (CAF WCNSS/WCN3620)
- LTE data (Hexagon DSP modem, PPP over SMD, roaming on Sunrise)
- eSIM provisioning (lpac via QMI UIM)
- Battery monitoring (VM-BMS) with low-battery shutdown
- Power toggle switch screen on/off
- Metrics sampling (wata-metricsd)

## Tool flows

### Cellular data

```
cell-data.sh  →  qmicli (libqmi)  →  AF_MSM_IPC  →  modem DSP
                     ↓
              pppd call cellular  →  /dev/smd7  →  PPP data path
```

`cell-data.sh` manages modem bringup (online, RAT preference, PS attach)
via `qmicli`, then hands off to `pppd` for the data connection.

- **qmicli** — stock tool from the libqmi project
- **libqmi** — [custom fork](../libqmi) with native `AF_MSM_IPC` transport
  (upstream only supports `AF_QIPCRTR`; MSM8909 CAF 4.4 predates QRTR)
- **cell-data.sh** — ours, in this repo

### eSIM provisioning

```
esim-provision.sh  →  qmi-send-apdu lpac  →  lpac (stdio driver)
                              ↓
                      QMI UIM (AF_MSM_IPC)  →  eUICC
```

`qmi-send-apdu lpac` spawns lpac as a child process, sets up the
environment (`LPAC_APDU=stdio`, `LPAC_HTTP=curl`, `CURL_DNS_SERVERS`),
and translates between lpac's JSON stdio protocol and raw QMI UIM
TLVs over `AF_MSM_IPC`. No shell wrapper or FIFOs needed.

- **lpac** — stock [lpac](../lpac) eSIM LPA, cross-compiled for ARM/musl
- **qmi-send-apdu** — ours (Zig 0.16), in this repo. Handles ISD-R AID
  truncation (6-byte prefix to bypass modem APDU filter), dynamic UIM
  port lookup via `IPC_ROUTER_IOCTL_LOOKUP_SERVER`, descending TLV order
- **esim-provision.sh** — ours, user-facing activation code handler

### Modem EFS storage

```
modem DSP  →  QMI service 14 (AF_MSM_IPC)  →  rmt_storage
                                                    ↓
                                          pread/pwrite eMMC partitions
                                          via /dev/uioN shared memory
```

`rmt_storage` is a daemon that registers as QMI RMTFS service 14 and
serves the modem's EFS partition read/write requests through mmap'd
shared memory. Runs at boot before the modem firmware loads.

- **rmt_storage** — ours (Zig 0.16), based on the
  [linux-msm/rmtfs](https://github.com/andersson/rmtfs) protocol

### DIAG (modem diagnostics)

Moved to [bq268-modem-diag](../bq268-modem-diag). Tools for subscribing
to LTE log packets, sending raw DIAG commands, and reading/writing the
modem's Embedded File System. Requires three kernel patches documented
in `docs/diag_kernel_fixes.md`.

## Building

Requires Zig 0.16.0 (`~/zig-x86_64-linux-0.16.0/zig`) and the CAF 4.4
kernel at `~/bq268-caf-4.4`.

```sh
just build-tools    # cross-compile tools/ (Zig + gcc)
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
tools/                   cross-compiled ARM utilities (Zig 0.16 + shell)
  src/                   Zig sources (rmt_storage, qmi-send-apdu, reboot-bootloader)
  build.zig              Zig build umbrella
  wata-metricsd/         metrics sampling daemon (separate Zig project)
  cell-data.sh           cellular data bringup script
  esim-provision.sh      eSIM activation code handler
firmware/                extracted device firmware (gitignored)
docs/                    hardware docs, roadmap, bringup guides
```

## License

[The Unlicense](UNLICENSE) -- public domain.
