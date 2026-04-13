# Modem Data Path — Investigation Plan

## Goal

Establish IP data transfer over the cellular modem (MSM8909 Hexagon DSP).
The modem is registered on Orange France (208/01) with Eskimo eSIM, CS+PS
attached. Control plane (QMI over SMD IPCRTR) works. Data plane is blocked.

## Current State

- **Modem**: online, registered, PS attached
- **QMI**: working over AF_MSM_IPC (IPCRTR SMD channel)
- **BAM DMUX**: driver probed, SMSM callbacks registered, but modem SMSM
  state `0x08000009` never sets A2_POWER_CONTROL (bit 1 = 0x02)
- **No rmnet interfaces**: BAM DMUX never calls `bam_init()` so no
  network devices are created
- **WDS start-network**: returns `InvalidOperation` (0x46) regardless of
  APN, profile, or IP type
- **WDA set-data-format**: also returns `InvalidOperation`
- **DPM service**: exists, `dpm-noop` succeeds, `dpm-open-port` with
  ctrl endpoint succeeds but doesn't trigger A2

## SMD Channel State

Modem has opened these channels (APPS side = CLOSED, MDMSW = OPENING):

| Channel | Name | Type | Notes |
|---------|------|------|-------|
| 0 | DS | Stream | Data services (AT?) |
| 2 | SSM_RTR_MODEM_APPS | Packet | Security |
| 4 | apr_apps2 | Packet | Audio |
| 10 | DATA1 | Packet | smdtty |
| 11 | DATA2 | Packet | smdtty |
| 12 | DATA3 | Packet | smdtty |
| 13 | DATA4 | Packet | smdtty |
| 14 | DATA11 | Stream | smdtty |

Already opened (both sides):
- IPCRTR (QMI), DIAG, DIAG_CNTL, DIAG_CMD, DIAG_2, DIAG_2_CMD, apr_audio_svc

NOT present (expected by DTS smdpkt entries):
- DATA5_CNTL (smdcntl0) — QMI control for data
- DATA22 (smd22)
- DATA40_CNTL (smdcntl8)

## Stock Android Reference

From `vendor.bin:/etc/data/netmgr_config.xml` (MSM section):
- `qmi_dpm_enabled = 0`
- `wda_data_format_enabled = 0`
- `rmnet_data_enabled = 0`
- `phys_net_dev = rmnet0`
- No MAP aggregation, no QMAP, plain BAM DMUX

From `init.qcom.rc`:
- `qmuxd` service (QMI multiplexer over SMD)
- `netmgrd` service (network manager daemon)
- USB config: `rmnet_qti_bam`

## Hypotheses

### H1: Modem needs DATA5_CNTL / QMUX channel opened first

The modem may wait for the apps to open the QMI control SMD channel
(DATA5_CNTL → smdcntl0) before activating the data plane. On Android,
`qmuxd` opens this channel. The channel doesn't exist in the SMD
allocation table yet — it may only be created when the apps side
requests it.

**Status**: NOT TESTED — smdcntl0 device node exists but libqmi can't
use it (it's smd_pkt, not a QMI transport). Need to try opening it
from userspace.

### H2: BAM DMUX address wrong / BAM hardware doesn't exist on this SoC

DTS says `0x4044000`. `/proc/iomem` doesn't show this address. The
BAM DMUX hardware may not exist on this MSM8909 variant, or may be at
a different address.

**Status**: Kernel agent investigating. DTS address is only used after
A2_POWER_CONTROL is set (in `bam_init()`), so wrong address wouldn't
prevent the SMSM signal — it would cause `bam_init()` to fail later.
This is a secondary concern.

### H3: Data path uses SMD channels directly (not BAM DMUX)

On some MSM8909 configurations, the data path goes through SMD DATA
channels (DATA1-4) directly, not through BAM DMUX. The rmnet driver
would be `rmnet_smd` (not present in this kernel tree).

**Status**: NOT TESTED. DATA1-4 are in OPENING state from modem side.
Could try opening them to see if data flows through SMD.

### H4: WDS InvalidOperation means no data bearer is bound

The modem's WDS service may require a data port binding (via DPM or
WDS bind-data-port) before it can start a network. Without a bound
transport, it returns InvalidOperation.

**Status**: PARTIALLY TESTED. DPM open-port with ctrl endpoint alone
didn't help. Need to try with full hw-data and sw-data endpoints.
WDS bind-data-port syntax was wrong in our attempts.

### H5: QMUX/QMI path matters — WDS may need to come through SMD QMUX

Our QMI goes through IPCRTR (IPC Router). On Android, QMI goes through
QMUX (qmuxd → smdcntl0 → DATA5_CNTL). The modem's WDS service might
only accept data call requests from the QMUX path, not IPCRTR.

**Status**: NOT TESTED. Would need to either run qmuxd or implement a
minimal QMUX client. libqmi's msmipc backend uses IPCRTR.

### H6: Modem firmware simply doesn't support on-device data

The BQ268 is a walkie-talkie — the stock firmware might only support
voice (VoLTE/IMS) and not general-purpose PS data. The eSIM registered
and PS attached, but the modem may not have a data call handler.

**Status**: UNLIKELY — WDS service responds to queries, profiles exist,
channel rates show max 42.2 Mbps DL. Modem clearly has data capability.

## Test Log

### 2026-04-03 — Initial investigation

| # | Test | Result |
|---|------|--------|
| 1 | `qmicli --wds-start-network="apn=internet,ip-type=4"` | InvalidOperation |
| 2 | `qmicli --wds-start-network="3gpp-profile=1,ip-type=4"` | InvalidOperation |
| 3 | `qmicli --wds-start-network="ip-type=4"` | InvalidOperation |
| 4 | `qmicli --wds-start-network="apn=globaldata,ip-type=4"` | InvalidOperation |
| 5 | `qmicli --wda-set-data-format="link-layer-protocol=raw-ip"` | InvalidOperation |
| 6 | `qmicli --wda-set-data-format="link-layer-protocol=802-3"` | InvalidOperation |
| 7 | `qmicli --wda-get-data-format` | InvalidArgument |
| 8 | `qmicli --dpm-noop` | SUCCESS |
| 9 | `qmicli --dpm-open-port` (ctrl-only, bam-dmux endpoints) | SUCCESS (no effect) |
| 10 | `qmi-network msmipc://0 start` (apn=internet) | InvalidOperation |
| 11 | Check SMSM after DPM open-port | No change (0x08000009) |
| 12 | `qmicli --wds-get-packet-service-status` | disconnected |
| 13 | `qmicli --wds-get-channel-rates` | max TX=5.7M, RX=42.2M |
| 14 | `qmicli --wds-get-profile-list=3gpp` | 3 profiles (empty APN, ims, sos) |
| 15 | `qmicli --wds-get-default-settings=3gpp` | empty APN, ipv4-or-ipv6 |
| 16 | `qmicli --wds-get-autoconnect-settings` | InvalidOperation |

## Discovery process

After exhausting the QMI WDS path (every `start-network` variant
returned `InvalidOperation`), the key insight was to bypass QMI
entirely and try the AT command interface on `/dev/smd7` (the DATA1
SMD channel, which acts as an AT port on this firmware).

The standard 3GPP AT command sequence for PDP activation worked on the
first try: `AT+CGDCONT` to define the context, `AT+CGACT` to activate
it (the modem returned OK and the network assigned IP 10.156.46.161
via `AT+CGPADDR`). This proved the modem's data stack was functional —
the problem was entirely in how we were trying to talk to it.

With the PDP context active, `AT+CGDATA="PPP",1` returned
`CONNECT 150000000`, switching the serial channel into PPP data mode.
This is classic dial-up style: the modem presents raw PPP frames on
the serial device, and the host runs `pppd` to negotiate IPCP and
create a `ppp0` network interface. The modem never needed BAM DMUX,
A2_POWER_CONTROL, or rmnet — it's a serial PPP device, not a hardware
DMA engine.

In retrospect, the clues were there: the SMD channel table showed
DATA1-4 as simple serial/packet channels with no hardware backing, the
A2 BAM address (`0x4044000`) wasn't in `/proc/iomem`, and the modem's
WDS/WDA services rejected all data format configuration. The modem
firmware was designed for PPP-over-AT on a low-end MSM8909 walkie-talkie
platform, not for the high-throughput BAM DMA path used on smartphones.

## BREAKTHROUGH: PPP over SMD works (2026-04-03)

The data path is **PPP over SMD**, not BAM DMUX.

```
AT+CGDCONT=1,"IP","globaldata"  → OK
AT+CGACT=1,1                    → OK
AT+CGPADDR=1                    → 10.156.46.161 (IP assigned!)
AT+CGDATA="PPP",1               → CONNECT 150000000
```

The modem enters PPP data mode on `/dev/smd7` (DATA1 AT channel).
BAM DMUX / A2_POWER_CONTROL is a **dead end** — this MSM8909 firmware
uses SMD + PPP for the data path, not hardware DMA.

### What's needed

1. **Kernel**: `CONFIG_PPP=y`, `CONFIG_PPP_ASYNC=y`, `CONFIG_PPP_DEFLATE=y`
2. **Device node**: `mknod /dev/ppp c 108 0`
3. **pppd**: `apk add ppp` (already installed)
4. **Chat script**: AT+CGDCONT to set APN, ATD*99***1# to dial
5. **pppd config**: noauth, usepeerdns, defaultroute, ipcp-accept-local

### pppd config (tested, waiting for kernel PPP support)

```
# /etc/ppp/peers/cellular
/dev/smd7
115200
noauth
defaultroute
usepeerdns
nodetach
noipdefault
novj
novjccomp
noccp
ipcp-accept-local
ipcp-accept-remote
connect "/usr/sbin/chat -v -f /etc/ppp/cellular-chat"
```

```
# /etc/ppp/cellular-chat
ABORT "ERROR"
ABORT "NO CARRIER"
TIMEOUT 30
"" AT
OK AT+CGDCONT=1,"IP","globaldata"
OK ATD*99***1#
CONNECT ""
```

### Impact on architecture

- **BAM DMUX is unused** — the modem never sets A2_POWER_CONTROL. Data
  goes through PPP over SMD, not hardware DMA.
- **rmnet interfaces won't exist** — data goes through `ppp0`
- **Failover** works: ppp0 gets a default route with high metric
- **APN**: "globaldata" works for Eskimo eSIM

### Status (2026-04-03)

**Working.** `pppd call cellular` establishes PPP over UMTS on
/dev/smd7. Verified: ping 8.8.8.8 succeeds (439-1240ms, roaming).
PPP config at `/etc/ppp/peers/cellular`, chat script at
`/etc/ppp/cellular-chat`. CHAP auth required (dummy user "guest").

Kernel requirements: CONFIG_PPP, CONFIG_PPP_ASYNC (added in kernel #66).

## Bringup chain (2026-04-13)

`cell-data up` (see `tools/cell-data.sh`) is the single entry point.
It performs, in order:

1. **Enforce QMI prefs** (`ensure_lte_prefs`) — idempotent check that
   `Mode preference = lte` and `Network selection preference = automatic`.
   These settings are stored in modem NV and **persist across reboots
   and `dms` resets**, so this is usually a no-op after the first
   application. When it does change prefs, `qmicli` prints "replug your
   device"; the following `set_online` → reset escalation picks up the
   new config.
2. **Drive modem to `online`** (`set_online`) — handles `low-power`,
   `offline`, `persistent-low-power`, and transient `shutting-down` /
   `resetting` states. Bounded at `WAKE_BUDGET=20s`; on timeout escalates
   to `dms-set-operating-mode=reset` + `RESET_SETTLE=10s` and retries
   once. Returns non-zero if the modem cannot be driven online.
3. **Wait for PS attach** (`wait_ps_attached`) — polls
   `nas-get-serving-system` for `PS: 'attached'` on a
   `ATTACH_BUDGET=90s` budget. Total wake wall-time is ≤2 minutes.
4. **Log serving PLMN + roaming** (`log_serving`) — appends MCC/MNC,
   RAT, roaming bool (derived by comparing serving PLMN to
   `nas-get-home-network`), and QMI's own roaming status to
   `/var/log/cellular.log` for correlation with data usage.
5. **`pppd call cellular`** — daemonizes pppd and waits ≤30 s for
   `ppp0` to acquire an IPv4 address. Kills pppd on timeout so we don't
   leak a half-up session.

### Required QMI preferences

Expected output of `qmicli -d msmipc://0 --nas-get-system-selection-preference`:

```
Mode preference: 'lte'
Network selection preference: 'automatic'
Acquisition order preference: 'lte, ...'
```

The default acquisition order on this firmware puts CDMA/GSM/UMTS
ahead of LTE, which means the modem finds UMTS first and parks on it
with `WCDMA Status: limited` (the Singtel SIM is not allowed PS attach
on roamed WCDMA). Forcing `lte,automatic` is what makes attach possible
on foreign LTE networks. The setting is non-volatile — we apply it
once and it survives reboots.

### Recovery from stuck modem states

| Observed state | Meaning | Action |
|---|---|---|
| `mode=shutting-down` (persistent) | Modem crashed mid-transition, usually after a failed `online` ↔ `offline` sequence. `set-operating-mode=online` succeeds with no effect. | `dms-set-operating-mode=reset`, then retry online after ≥10 s. If still stuck, reboot the device. |
| `mode=offline` + `InvalidTransition` on `online` | Known deadlock — the modem rejects transitions out of offline. | Same as above: issue `reset` and wait ≥10 s. Reboot if reset also fails. |
| `Registration state: not-registered-searching`, radio oscillating between `none` and `umts` | No compatible LTE cell visible / roaming not permitted at current location | Not a state-machine bug. Run `qmicli --nas-network-scan=lte` to confirm LTE coverage. If coverage exists but attach fails, check SIM roaming agreements for the visited PLMN. |
| `Registration state: not-registered` + `Status: power-save` | Modem gave up searching and is in dormant mode. | `dms-set-operating-mode=reset` forces a fresh scan cycle. |

All of these are handled automatically by `cell-data wake` within its
2-minute budget; on failure it returns exit code 2 (PS not attached)
vs 1 (modem could not be brought online) so callers can distinguish
a coverage problem from a firmware/state problem.

### Smoke test

`just smoke-cellular` runs the full chain against the live device and
verifies a ping through `ppp0`. Useful after kernel changes, firmware
patches, or physical moves.

## Next Steps

1. **WiFi/cellular failover testing** — test net-watchdog with actual
   WiFi drops and cellular PPP failover
2. **Suspend integration** — modem low-power mode when idle
