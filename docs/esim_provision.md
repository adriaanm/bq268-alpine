# eSIM Provisioning — BQ268

## Status (2026-03-31)

**Tooling ready, blocked on hardware.** lpac cross-compiled and verified on
device. QMI APDU wrapper tested (connect succeeds, open_channel correctly
returns AccessDenied with empty SIM slot). Waiting for easyuicc eSIM adapter.

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

## Test Plan (when adapter arrives)

1. **Card detection**: `qmicli -d msmipc://0 --uim-get-card-status` should show `Card state: 'present'`
2. **eUICC info**: `lpac-qmi-wrapper chip info` — returns EID, firmware version
3. **Channel test**: wrapper opens logical channel to ISD-R AID
4. **Test profile**: use a test SM-DP+ (e.g., `rsp.truphone.com` or GSMA test server at `testrootsmds.gsma.com`) to download a trial profile
5. **Full provision**: `esim-provision` end-to-end with a real carrier code

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
