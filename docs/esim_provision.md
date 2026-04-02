# eSIM Provisioning — BQ268

## Status (2026-04-02)

**Blocked on modem APDU access control.** easyuicc adapter inserted and
detected (card present, USIM ready, PIN disabled). All APDU paths to the
eUICC's ISD-R are blocked by the modem firmware's security restrictions
(NV item 67312). See "APDU Access Attempts" below for full details.

Next: either provision on Android first, or fix the kernel DIAG SMD
channels to write the NV item directly.

## Overview

The BQ268 uses an easyuicc removable eSIM adapter in the standard SIM slot.
Provisioning downloads a carrier profile from an SM-DP+ server over WiFi and
installs it onto the eUICC chip via QMI APDU commands through the modem.

Single-profile use case — one eSIM, one carrier, no profile switching.

## Architecture

```
esim-provision (user script)
      |
lpac-qmi-wrapper (stdio JSON <-> qmicli translation)
      |
lpac (LPA, SGP.22 v2.2.2)   <--- HTTPS/TLS --->  SM-DP+ server
      |
LPAC_APDU=stdio driver
      |
qmicli --uim-{open-logical-channel,send-apdu,close-logical-channel}
      |
libqmi (AF_MSM_IPC backend)
      |
IPC Router kernel driver --> Modem Q6 DSP --> eUICC chip
```

## Provisioning Flow

### What the user does

1. Get activation code from carrier (QR code or text)
2. QR contains a string like: `LPA:1$smdp.example.com$K2-1A2B3C-ABCDEF`
3. Scan QR on phone/computer, copy the string
4. SSH into BQ268 and run:
   ```
   esim-provision 'LPA:1$smdp.example.com$K2-1A2B3C-ABCDEF'
   ```

### What happens under the hood

1. **Parse** — script extracts SM-DP+ address, matching ID, optional confirmation code
2. **Preflight** — checks WiFi up, SM-DP+ server reachable, modem UIM accessible, card present
3. **Connect** — lpac opens a logical channel to the eUICC's ISD-R (root security domain, AID `A0000005591010FFFFFFFF8900000D00`)
4. **Authenticate** — mutual TLS authentication between eUICC and SM-DP+ server (GSMA PKI, certificates stored on eUICC)
5. **Download** — SM-DP+ sends encrypted Bound Profile Package (BPP) containing IMSI, Ki, APN config, PLMN list
6. **Install** — lpac sends APDUs to eUICC to decrypt and install profile into a new ISD-P (profile container)
7. **Enable** — lpac enables the profile (one active profile at a time)
8. **Notify** — lpac sends confirmation back to SM-DP+ that download succeeded

## Components

### lpac (v2.3.0)

Cross-platform C-based LPA. Cross-compiled for ARM/musl in Alpine chroot.

- **Repo**: https://github.com/estkme-group/lpac
- **Local clone**: `~/lpac`
- **Build**: `just build-lpac` (uses `build-lpac.sh`, builds in Alpine ARM chroot)
- **Binary**: `tools/lpac-esim/lpac` (30KB) + shared libs (~88KB)
- **Runtime deps**: `libcurl` (HTTPS), `cjson` (JSON parsing) — both from Alpine repos
- **Drivers**: `stdio` for APDU (our wrapper), `curl` for HTTP (SM-DP+ communication)

lpac v2.x uses a plugin driver system. The `stdio` driver communicates via JSON
on stdin/stdout:

```
lpac -> wrapper:  {"type":"apdu","payload":{"func":"transmit","param":"00A40400..."}}
wrapper -> lpac:  {"type":"apdu","payload":{"ecode":0,"data":"6F00..."}}
lpac -> stdout:   {"type":"lpa","payload":{"code":0,"message":"success","data":{...}}}
```

APDU functions: `connect`, `disconnect`, `logic_channel_open`, `logic_channel_close`, `transmit`.

### lpac-qmi-wrapper

Pure POSIX shell script translating lpac's stdio JSON protocol to qmicli UIM
commands. Uses named pipes for bidirectional communication.

- **Reference**: https://github.com/z3ntu/lpac-libqmi-wrapper (Python, used as design reference)
- **Our implementation**: `tools/lpac-qmi-wrapper.sh` (shell, no Python dependency)
- **Installed at**: `/usr/bin/lpac-qmi-wrapper`

Translation table:

| lpac func              | qmicli command                                  |
|------------------------|-------------------------------------------------|
| `connect`              | (no-op, returns success)                        |
| `disconnect`           | (no-op, returns success)                        |
| `logic_channel_open`   | `qmicli --uim-open-logical-channel=SLOT,AID`   |
| `logic_channel_close`  | `qmicli --uim-close-logical-channel=SLOT,CID`  |
| `transmit`             | `qmicli --uim-send-apdu=SLOT,CID,APDU`         |

Environment variables:
- `LPAC_QMI_DEVICE` — QMI device path (default: `msmipc://0`)
- `LPAC_QMI_SLOT` — UIM slot number (default: `1`)
- `DEBUG=1` — verbose logging to stderr

### esim-provision

User-facing script. Parses activation codes, runs preflight checks, orchestrates lpac.

- **Installed at**: `/usr/bin/esim-provision`
- **Source**: `tools/esim-provision.sh`

```
esim-provision 'LPA:1$smdp.example.com$MATCHING-ID'
esim-provision -f /path/to/code.txt
esim-provision                          # prompts for input
```

### Rootfs integration

`rootfs/14-esim.sh` installs all components and Alpine packages (`libcurl`, `cjson`).

## Activation Code Format

eSIM QR codes encode a string in this format:

```
LPA:1$<smdp-address>$<matching-id>[$<confirmation-code>]
```

| Field             | Example                   | Required |
|-------------------|---------------------------|----------|
| SM-DP+ address    | `smdp.example.com`        | yes      |
| Matching ID       | `K2-1A2B3C-ABCDEF`        | yes      |
| Confirmation code | `1234`                    | no       |

The `LPA:1$` prefix is the standard defined by GSMA SGP.22.

## QMI UIM APDU Path

The modem's QMI UIM service (service ID 11) provides the APDU transport to the
SIM slot. Key operations:

- **Open Logical Channel** (0x0042) — opens a channel to an applet by AID
- **Send APDU** (0x003B) — transmits a raw APDU on an open channel
- **Close Logical Channel** (0x003F) — closes a channel
- **Get Card Status** (0x002F) — checks if a card is present and its state

On the BQ268, QMI runs over AF_MSM_IPC sockets (family 27) via the IPC Router
kernel driver, not the more common /dev/cdc-wdm or QRTR paths. Our custom
libqmi build supports this natively with `-d msmipc://0`.

## eUICC Internal Structure

```
eUICC Secure Element
├── ISD-R (Issuer Security Domain Root)
│   ├── Profile management (download, enable, disable, delete)
│   ├── SM-DP+ authentication (GSMA PKI certificates)
│   └── AID: A0000005591010FFFFFFFF8900000D00
├── ISD-P #1 (Profile Container — carrier profile)
│   ├── IMSI + Ki (authentication credentials)
│   ├── APN configuration
│   └── PLMN list (home/roaming networks)
└── ECASD (eUICC Controlling Authority Security Domain)
    └── Root certificates for profile verification
```

## APDU Access Attempts (2026-04-02)

The modem firmware (CAF/Android stock) enforces APDU security restrictions
controlled by **NV item 67312** at EFS path
`/nv/item_files/modem/qmi/uim/apdu_security_restrictions`. Setting this
to `0x00` disables the restrictions. Every approach to either bypass the
restriction or write this NV item was blocked:

### 1. QMI UIM logical channel — AccessDenied

```
qmicli -d msmipc://0 --uim-open-logical-channel=1,a0000005591010ffffffff8900000100
→ QMI protocol error (82): 'AccessDenied'
```

The modem checks NV 67312 before allowing logical channel operations.
This is the restriction we need to disable.

`--uim-send-apdu=1,0,0070000001` (raw MANAGE CHANNEL APDU) also failed
with `InvalidArgument` — the modem rejects channel 0 for this command.

### 2. AT+CSIM — not implemented

AT commands work on `/dev/smd7` (DATA1 channel). `AT+CLAC` returned a
full command list. However:

- `AT+CSIM` — returns `+CME ERROR: operation not supported` for all APDUs
  (including basic GET RESPONSE). The command is advertised but not
  functional on this firmware.
- `AT+CCHO` / `AT+CGLA` — not in the AT command list at all.
- `AT$QCDGEN` (DIAG-over-AT passthrough) — returns `ERROR`.

The modem's AT+CUAD command works and shows the USIM application:
```
+CUAD: "61184F10A0000000871002FFFFFFFF890305000150045553494D..."
```
ISD-R doesn't appear in CUAD (normal — it's a GlobalPlatform security
domain, not a telecom app).

### 3. DIAG EFS write — kernel SMD channels not open

Tool written: `tools/diag-efs-write.c` (cross-compiled for ARM/musl).
Uses DIAG EFS2 subsystem (0x4B 0x13) to write files to modem EFS via
`/dev/diag`.

The DIAG session initializes correctly:
- `open("/dev/diag")` → OK
- `ioctl(DIAG_IOCTL_SWITCH_LOGGING, MEMORY_DEVICE_MODE)` → OK
- `ioctl(DIAG_IOCTL_HDLC_TOGGLE, disable=1)` → OK

But EFS2 commands are silently dropped (`write()` returns 0). Root cause:

The kernel DIAG driver uses **glink** transport (which fails on MSM8909 —
it only supports SMD). The SMD fallback requires **platform device
registrations** with names `"DIAG"`, `"DIAG_CNTL"`, `"DIAG_CMD"` and
`id=SMD_APPS_MODEM`. These are missing from the MSM8909 board code/DTS.

dmesg confirms:
```
diag: In __diag_glink_init, unable to register for glink channel DIAG_CMD
diag: In diag_send_feature_mask_update, control channel is not open, p: 0
```

Without the SMD DIAG control channel, the modem never registers its DIAG
commands with the kernel, so `diag_process_apps_pkt()` finds no match in
the command table and drops EFS2 packets.

**Fix**: add platform device entries to the kernel DTS/board code. ~10 lines.
This also enables DIAG F3 logging (`tools/diag_read.c`) for the BAM DMUX
debug task.

Relevant source:
- `drivers/char/diag/diagfwd_smd.c:352-413` — platform driver registration
- `drivers/char/diag/diagfwd_smd.c:240-308` — `smd_channel_probe()` opens channels
- `drivers/char/diag/diagfwd_peripheral.c:479-482` — transport init order

### 4. QMI PDC (modem config MBN) — firmware rejects EFS-NV items

Tool written: `tools/gen-mcfg-mbn.py` — generates MCFG MBN files with
custom NV items, wrapped in ELF32 with SHA256 hash segment.

Fixed a **segfault bug in qmicli** `--pdc-load-config`: `qmicli-pdc.c`
called `g_free()` on a `g_mapped_file_get_contents()` pointer (mmapped
memory, not glib-allocated). The `g_free()` read a heap header at
`ptr - 4`, hitting unmapped memory before the mmap region.

After fixing, PDC loading works — reference MBN files from the modem
firmware load successfully:
```
qmicli --pdc-load-config=/tmp/ref_mcfg.mbn → "Finished loading"
qmicli --pdc-list-configs=software → Brazil_Commercial (inactive)
```

However, **the modem's MCFG parser crashes on NV_FILE (type=2) and FILE
(type=4) items** — the item types needed for EFS-path-based NV items like
67312 (which is > 65535 and can't use type=1 uint16 NV IDs). Adding any
path-based item to a working MBN causes the modem's PDC service to
disconnect.

The modem firmware only supports type=1 NV items in MCFG. Dead end for
NV 67312 via this path.

### 5. Card detection (working)

```
qmicli -d msmipc://0 --uim-get-card-status
→ Card state: 'present'
→ Application type: 'usim (2)', state: 'ready'
→ AID: A0:00:00:00:87:10:02:FF:FF:FF:FF:89:03:05:00:01
→ PIN1: disabled, PIN2: enabled-not-verified
```

## Unblocking — Two Paths

### Path A: Provision on Android first (immediate)

1. Install OpenEUICC (F-Droid) on any Android phone
2. Insert easyuicc adapter, download carrier profile
3. Move adapter back to BQ268
4. `rc-service modem restart` → modem uses provisioned USIM for data

This works because normal USIM operation (auth, registration, data) does
not require logical channel access — only profile management does.

### Path B: Fix kernel DIAG SMD channels (permanent)

Add platform device registrations for DIAG SMD channels to the MSM8909
kernel. This enables:
- `diag-efs-write` to set NV 67312 = 0 (disables APDU restrictions)
- DIAG F3 logging for BAM DMUX debugging
- Full on-device eSIM provisioning via lpac

After the NV item is set, the existing lpac + lpac-qmi-wrapper pipeline
works end-to-end.

## Test Plan (after APDU access is unblocked)

1. **eUICC info**: `lpac-qmi-wrapper chip info` — returns EID, firmware version
2. **Channel test**: wrapper opens logical channel to ISD-R AID
3. **Test profile**: use a test SM-DP+ to download a trial profile
4. **Full provision**: `esim-provision` end-to-end with a real carrier code

## Repos

| Repo | Path | Purpose |
|------|------|---------|
| lpac | `~/lpac` | LPA implementation (SGP.22) |
| lpac-libqmi-wrapper | `~/lpac-libqmi-wrapper` | Reference Python wrapper (design reference only) |
| libqmi | `~/libqmi` | QMI library with AF_MSM_IPC support |

## References

- [GSMA SGP.22 v3.0](https://www.gsma.com/solutions-and-impact/technologies/esim/wp-content/uploads/2022/10/SGP.22-v3.0-1.pdf) — consumer eSIM remote provisioning spec
- [lpac GitHub](https://github.com/estkme-group/lpac) — the LPA tool
- [lpac-libqmi-wrapper](https://github.com/z3ntu/lpac-libqmi-wrapper) — reference qmicli APDU backend
- [eUICC Manual (Osmocom)](https://euicc-manual.osmocom.org/) — practical eSIM guide
- [Luca Weiss: eSIM Manager for Mobile Linux](https://lucaweiss.eu/post/2024-06-24-esim-manager-for-mobile-linux/) — lpa-gtk writeup, good context on the Linux mobile eSIM landscape
- [postmarketOS QMI wiki](https://wiki.postmarketos.org/wiki/QMI) — QMI/libqmi reference
