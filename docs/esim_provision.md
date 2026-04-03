# eSIM Provisioning — BQ268

## Status (2026-04-03)

**lpac fully working.** `lpac chip info` returns complete eUICC data
through the full pipeline: lpac → lpac-qmi-wrapper → qmi-send-apdu →
QMI UIM → eUICC. The modem's APDU restrictions are bypassed using a
**short AID prefix** (`A00000055910`, 6 bytes) for open_logical_channel.

**Truphone Speedtest profile downloaded and enabled** using activation code
`LPA:1$rsp.truphone.com$QRF-SPEEDTEST` (no signup required, production PKI).
This profile validates the full provisioning chain but has no active MNO
subscription — it won't attach to a real network.

Next: get a paid data-only eSIM (Airalo, LycaMobile, etc.) to test PS-attach
and the cellular data path.

## eUICC Info (from `lpac chip info`)

| Property | Value |
|----------|-------|
| EID | `89086030202200000026000048925914` |
| Firmware | 4.2.0 |
| SGP.22 version (svn) | 2.2.2 |
| Profile version | 2.3.1 |
| GlobalPlatform version | 2.3.0 |
| TS 102.241 version | 9.2.0 |
| PP version | 1.0.0 |
| SAS accreditation | ED-ZI-UP-0826 |
| Root SM-DS | `testrootsmds.gsma.com` |
| Default SM-DP+ | (none) |
| Installed profiles | 0 |
| Free NVM | 444,350 bytes (~434 KB) |
| Free volatile memory | 9,878 bytes |

**UICC capabilities**: usimSupport, isimSupport, csimSupport,
akaMilenage, akaCave, akaTuak128, akaTuak256, gbaAuthenUsim,
gbaAuthenISim, mbmsAuthenUsim, eapClient, javacard,
berTlvFileSupport, dfLinkSupport, catTp, getIdentity,
profile-a-x25519, profile-b-p256

**RSP capabilities**: additionalProfile, testProfileSupport

**CI PKI (verification + signing)**:
`81370f5125d0b1d408d4c3b232e6d25e795bebfb`
(GSMA CI root — standard production PKI)

## Overview

The BQ268 uses an easyuicc removable eSIM adapter in the standard SIM slot.
Provisioning downloads a carrier profile from an SM-DP+ server over WiFi and
installs it onto the eUICC chip via QMI APDU commands through the modem.

Single-profile use case — one eSIM, one carrier, no profile switching.

## Architecture

```
esim-provision (user script)
      |
lpac-qmi-wrapper.sh (stdio JSON <-> daemon line protocol)
      |                                          |
lpac (LPA, SGP.22 v2.2.2)  <-- HTTPS/TLS -->  SM-DP+ server
      |
LPAC_APDU=stdio driver (JSON on stdin/stdout)
      |
qmi-send-apdu daemon (persistent AF_MSM_IPC session)
      |
      |  open_logical_channel — uses short AID A00000055910
      |  send_apdu — raw APDU on open channel
      |  close_logical_channel
      |
AF_MSM_IPC socket (family 27) → IPC Router → Modem Q6 DSP → eUICC
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

POSIX shell script bridging lpac's stdio JSON protocol to the
`qmi-send-apdu` daemon's line-based protocol. Uses named pipes for
bidirectional communication with both lpac and the daemon.

- **Reference**: https://github.com/z3ntu/lpac-libqmi-wrapper (Python, used as design reference)
- **Our implementation**: `tools/lpac-qmi-wrapper.sh` (shell, no Python dependency)
- **Installed at**: `/usr/bin/lpac-qmi-wrapper`

Translation table:

| lpac func              | daemon command                          |
|------------------------|-----------------------------------------|
| `connect`              | (no-op, returns success)                |
| `disconnect`           | (no-op, returns success)                |
| `logic_channel_open`   | `OPEN AID` (auto-truncates ISD-R AIDs)  |
| `logic_channel_close`  | `CLOSE channel_id`                      |
| `transmit`             | `APDU channel_id apdu_hex`              |

Environment variables:
- `DEBUG=1` — verbose logging to stderr

### qmi-send-apdu

Minimal QMI UIM client that connects directly to the modem's UIM service
via AF_MSM_IPC. Maintains a **persistent session** (required because QMI
logical channels are per-client — separate qmicli invocations can't
share channels).

- **Source**: `tools/qmi-send-apdu.c` (static ARM/musl binary, ~52KB)
- **Installed at**: `/usr/bin/qmi-send-apdu`

**ISD-R AID auto-truncation**: when the requested AID starts with
`A0000005591010` (the ISD-R prefix), the daemon truncates it to
`A00000055910` (6 bytes) to bypass the modem's 7-byte filter.

Modes:
- `qmi-send-apdu test` — open ISD-R, send eUICC commands, print results
- `qmi-send-apdu daemon` — persistent stdin/stdout mode for the wrapper
- `qmi-send-apdu open/apdu/close` — one-shot commands (separate sessions)

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

**Fix committed**: `034ada814c88` in `~/bq268-caf-4.4` pre-registers all
DIAG SMD channels during init and adds `.poll` support. The root cause was
a transport negotiation system that assumes multiple transports compete —
on SMD-only MSM8909, negotiation never fires, leaving all non-CNTL channels
unregistered (fwd_ctxt=NULL). The fix calls `smd_late_init()` for all
channel types during `diag_smd_init()`.

**Status**: committed, awaiting kernel build + flash to boot partition.

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

### 5. DIAG EFS write — file creation blocked

With the kernel DIAG fix (tested before reboot), DIAG EFS2 commands reach
the modem. Verified:
- **MKDIR**: works (creates directories, returns EEXIST for existing)
- **OPEN (read)**: works (returns fd for existing files)
- **READ**: works (read `lte_bandpref` = 8 bytes)
- **WRITE to existing file**: works (after SPC unlock, cmd 0x41 "000000")
- **OPEN with O_CREAT**: **blocked** — returns DIAG_CMD_ERROR (0x13) for
  any flags including O_CREAT. File creation is disabled in firmware.
- **PUT (cmd 0x1A)**: returns ENOENT for non-existent files, even with
  O_CREAT flag. Modem's DIAG EFS blocks all file creation.
- **SPC unlock**: accepted (cmd 0x41, SPC "000000"), but does not enable
  file creation.

The NV file `/nv/item_files/modem/qmi/uim/apdu_security_restrictions`
does not exist in the factory EFS. It needs to be created, but DIAG can't
create files on this firmware.

### 6. rmt_storage file-backed overrides

Modified `rmt_storage` to serve from files in `/lib/firmware/` instead of
eMMC block devices. If `/lib/firmware/modemst1.bin` (etc.) exists,
rmt_storage opens it; otherwise falls through to `/dev/mmcblk0pN`.

Override files deployed:
- `modemst1.bin` — empty (0xFF), triggers modem to init fresh EFS
- `modemst2.bin` — empty (backup copy, must also be empty)
- `fsg.bin` — modified FSG with our NV file added to the tar archive
- `fsc.bin` — empty (absorbs filesystem cookie writes)

**Result**: modem creates fresh EFS in modemst1.bin (IMGEFS1 header
written), but **ignores the modified FSG**. Even with a zeroed FSG, the
modem creates a valid EFS from firmware defaults. The modem's EFS init
is self-contained — it does not need FSG to create a working filesystem.

The FSG golden copy may only be used during factory provisioning or via a
specific modem command, not automatically on empty modemst1.

### 7. EFS encryption

modemst1/modemst2 are **encrypted** (AES, Shannon entropy = 8.000 bits/byte).
The modem encrypts EFS data inside the Hexagon DSP before writing through
rmt_storage. We cannot parse, modify, or inject files at the sector level.

The FSG golden copy is **not encrypted** — it's a gzip tar at offset 0x228,
but it's signed (`SIGNED_IMAGE` with Qualcomm development certificates).
The modem may validate the signature during restore, which would explain
why our modified FSG was ignored.

### 9. Short AID bypass — WORKING (2026-04-03)

#### Discovery process

After Patch 1 (bitmask bypass) made non-ISD-R AIDs work, the ISD-R
AID specifically still returned AccessDenied. Patch 3 (corrupting the
ISD-R AID in the b14 data segment from A0→00) was applied and tested:

```
qmicli --uim-open-logical-channel=1,00000005591010FFFFFFFF8900000100
→ SimFileNotFound  (reached card — Patch 3 worked, LPA registered for wrong AID)

qmicli --uim-open-logical-channel=1,A0000005591010FFFFFFFF8900000100
→ AccessDenied     (STILL blocked — a second filter exists)
```

Patch 3 successfully corrupted the LPA's registration, but ISD-R was
still blocked. There was a **second filter** somewhere. Searching all
25 firmware segments found no other copy of the AID bytes — so the
filter had to be hardcoded in Hexagon instruction immediates.

To find the filter boundary, progressively longer AIDs were tested:

```
A000000559       (5 bytes) → channel opens (card selects something)
A00000055910     (6 bytes) → channel opens
A0000005591010   (7 bytes) → AccessDenied ← filter triggers here
A0000005591010FF (8 bytes) → AccessDenied
```

The filter matches the 7-byte prefix `A0000005591010` (GSMA RID +
first 2 bytes of ISD-R PIX). Below 7 bytes, the request passes.

#### The bypass

ISO 7816-4 allows partial AID selection — the card matches the longest
AID prefix. Since the ISD-R is the only applet on the easyuicc adapter
whose AID starts with `A00000055910`, the 6-byte AID selects it:

```
qmicli --uim-open-logical-channel=1,A00000055910
→ Open Logical Channel operation successfully completed: 1
→ FCI: 84 10 A0000005591010FFFFFFFF8900000100 (full ISD-R AID!)
→ SW: 9000
```

#### Persistent QMI session

`qmicli --uim-send-apdu` returned InvalidArgument even after opening a
channel. Root cause: each qmicli invocation creates a new QMI client,
and logical channels are per-client. The modem rejects send-apdu from
a different client than the one that opened the channel.

Solution: `qmi-send-apdu` (`tools/qmi-send-apdu.c`) opens an
AF_MSM_IPC socket directly to the UIM service (node=0, port=39),
skipping the QMUX framing layer (msmipc sends raw QMI service headers,
not QMUX-framed messages — discovered by reading libqmi's
`qmi-endpoint-msmipc.c`). All operations share the same socket.

#### Verified APDU exchange

```
STORE DATA (BF20 GetEuiccInfo1)     → 61 38 → GET RESPONSE → eUICC info
STORE DATA (BF2E GetEuiccChallenge) → 61 15 → 16-byte challenge
STORE DATA (BF22 GetEuiccInfo2)     → 61 7D → firmware/GP versions
lpac chip info                      → full JSON with EID, capabilities, NVM
```

**Requirements**: Patch 1 (APDU restriction bypass in modem.b12) must
be applied. Patches 2 and 3 are not needed for this bypass.

### 8. Card detection (working)

```
qmicli -d msmipc://0 --uim-get-card-status
→ Card state: 'present'
→ Application type: 'usim (2)', state: 'ready'
→ AID: A0:00:00:00:87:10:02:FF:FF:FF:FF:89:03:05:00:01
→ PIN1: disabled, PIN2: enabled-not-verified
```

## Current Plan

### DIAG kernel status

Kernel #55 has three fixes for DIAG on MSM8909 (see
`docs/modem_patch_plan.md` "DIAG kernel fixes" section):
1. SMD channel pre-registration (commit `034ada814c88`)
2. Direct feature mask send (workqueue bypass)
3. Modem command fallback forwarding

**DIAG is fully functional.** Subsystem commands reach the modem and
get responses. EFS2 works (MKDIR, OPEN, READ, WRITE, PUT). PEEKD/POKED
disabled in firmware. MMGSDI/UIM subsystems respond (need correct cmds).

### NV file approach — blocked

EFS PUT to protected NV paths still silently discards (confirmed twice
with kernel #52 and #55). The modem's EFS security policy cannot be
bypassed from the AP, even with SPC unlock.

### Firmware patch approach — Patch 1 + short AID bypass = WORKING

Patch 1 (APDU restriction bypass) lifts the global bitmask check.
Non-ISD-R AIDs reach the card. The ISD-R AID is blocked by a **second
7-byte prefix filter** that matches `A0000005591010` (the GSMA ISD-R
AID prefix). This filter is hardcoded in the firmware code (not in the
data segment we patched with Patch 3).

**Bypass**: Use a **6-byte truncated AID** `A00000055910` for
`open_logical_channel`. The modem's filter requires 7+ bytes to trigger.
The card does ISO 7816-4 partial AID matching and selects the ISD-R
applet. FCI response confirms the full ISD-R AID
`A0000005591010FFFFFFFF8900000100`.

Patches 2 and 3 were tested but are not needed — the short AID bypass
is sufficient. Patch 1 is still required (without it, all AIDs are
blocked).

### QMI UIM Send APDU — works within same session

`qmicli --uim-send-apdu` returns InvalidArgument because each qmicli
invocation creates a new QMI client (channels are per-client). The
`qmi-send-apdu` tool (`tools/qmi-send-apdu.c`) connects directly to
the UIM service via AF_MSM_IPC and keeps a persistent session.

Verified APDU exchange:
- STORE DATA (GetEuiccInfo1, BF20) → 61 38 → GET RESPONSE → full TLV
- STORE DATA (GetEuiccChallenge, BF2E) → 61 15 → 16-byte challenge
- STORE DATA (GetEuiccInfo2, BF22) → 61 7D → firmware/GP versions

### MMGSDI DIAG — dead end

All MMGSDI subsystem (0x19) commands return 0x13 (bad mode). The NV item
`/nv/item_files/modem/uim/mmgsdi/mmgsdi_diag_support` exists (value
0x02) and can be written via EFS OPEN+WRITE, but changing it to 0x01
did not enable DIAG commands. The mode gate is something else.

### EFS OPEN+WRITE to existing NV files — works

DIAG EFS `OPEN(O_WRONLY)` + `WRITE` works for existing files (after SPC
unlock), even on protected NV paths. Only file CREATION (O_CREAT, PUT)
is blocked. The `mmgsdi_diag_support` file was successfully modified.

### c-ares DNS workaround

Alpine's libcurl is built with c-ares (async DNS resolver). c-ares
doesn't reliably read `/etc/resolv.conf` on musl, causing DNS resolution
timeouts during SM-DP+ HTTP calls. `lpac-qmi-wrapper` works around this
by extracting nameservers from `/etc/resolv.conf` and setting
`CURL_DNS_SERVERS` for libcurl.

### Free test profiles (no signup)

| Code | Provider | Notes |
|------|----------|-------|
| `LPA:1$rsp.truphone.com$QRF-SPEEDTEST` | Truphone/1Global | Production PKI, no data |
| `LPA:1$rsp.truphone.com$QRF-BETTERROAMING-PMRDGIR2EARDEIT5` | BetterRoaming | Production PKI, no data |

These profiles exercise the full provisioning pipeline (SM-DP+ auth, BPP
download, install, enable) but are not backed by an MNO subscription —
they won't register on any network.

sysmocom (`smdpp.test.rsp.sysmocom.de`) uses SGP.26 test PKI and is
rejected by this eUICC (only has production GSMA CI certificates).

### Next steps

1. **Paid data eSIM** — get a cheap data-only eSIM (Airalo ~$5/1GB,
   LycaMobile, etc.) to test actual cellular data. The provisioning
   pipeline is proven; this just needs a real MNO subscription.

2. **Modem attach** — after installing a real profile, test PS-attach
   and data transfer (this also unblocks the BAM DMUX / A2 data path task).

## Test Plan

1. **eUICC APDU access**: `qmi-send-apdu test` ✓
2. **Logical channel to ISD-R**: short AID bypass ✓
3. **lpac chip info**: full eUICC data returned ✓
4. **Profile download**: Truphone Speedtest via `lpac-qmi-wrapper` ✓
5. **Profile enable**: `lpac-qmi-wrapper profile enable ICCID` ✓
6. **Data transfer**: modem PS-attach + ping / speed test (needs paid eSIM)

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
