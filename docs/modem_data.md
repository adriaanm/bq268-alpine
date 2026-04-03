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

- **BAM DMUX is not needed** — can be disabled in defconfig
- **rmnet interfaces won't exist** — data goes through `ppp0`
- **cell-data script** needs updating: use `pppd call cellular` instead
  of `qmicli --wds-start-network`
- **Failover** still works: ppp0 gets a default route with high metric
- **APN**: need to determine correct APN for Eskimo (tried "globaldata",
  got IP — might be correct or might be a default)

## Next Steps

1. **Add PPP to kernel defconfig** — CONFIG_PPP, CONFIG_PPP_ASYNC,
   CONFIG_PPP_DEFLATE, CONFIG_PPP_MPPE (for encrypted PPP if needed)
2. **Rebuild kernel and flash**
3. **Test pppd** — run the chat script + pppd, verify ppp0 interface
4. **Test connectivity** — ping, DNS, curl over ppp0
5. **Update cell-data script** — replace WDS/rmnet with pppd/ppp0
6. **Determine correct APN** — check Eskimo's APN settings
