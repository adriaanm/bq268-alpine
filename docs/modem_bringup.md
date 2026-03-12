# Modem & Connectivity Bringup — BQ268

## Architecture

```
[Modem firmware on Hexagon DSP]
        |
  [BAM-DMUX] ---- data plane (IP packets) --> rmnet_bam0 network interface
        |
  [SMD channels] - control plane (QMI)    --> /dev/smdcntl0 (/dev/modem)
        |
  [PIL] ---------- firmware loading        --> modem.mdt + modem.b00-b25, mba.mbn
```

## CAF 3.18 Kernel (Phase 1)

### Kernel configs (all enabled in bq268_defconfig)

- `CONFIG_MSM_PIL=y` — Peripheral Image Loader
- `CONFIG_MSM_PIL_MSS_QDSP6V5=y` — modem subsystem PIL
- `CONFIG_MSM_SUBSYSTEM_RESTART=y` — subsystem restart
- `CONFIG_MSM_BAM_DMUX=y` — BAM-DMUX data plane
- `CONFIG_MSM_RMNET_BAM=y` — rmnet network interfaces
- `CONFIG_RMNET_DATA=y` — rmnet data transport
- `CONFIG_MSM_QMI_INTERFACE=y` — QMI messaging
- `CONFIG_QMI_ENCDEC=y` — QMI encode/decode
- `CONFIG_MSM_SMD=y` — Shared Memory Device
- `CONFIG_MSM_SMD_PKT=y` — SMD packet interface
- `CONFIG_WCNSS_CORE=y` — WCNSS remoteproc
- `CONFIG_WCNSS_CORE_PRONTO=y` — Pronto WiFi

### Firmware files needed

| File | Location in rootfs | Source |
|------|-------------------|--------|
| `mba.mbn` | `/lib/firmware/mba.mbn` | modem partition (FAT16) |
| `modem.mdt` + `.b00-.b25` | `/lib/firmware/modem.*` | modem partition |
| `wcnss.mdt` + `.b00-.b12` | `/lib/firmware/wcnss.*` | modem partition |
| `WCNSS_qcom_wlan_nv.bin` | `/lib/firmware/wlan/prima/` | persist partition |
| `WCNSS_cfg.dat` | `/lib/firmware/wlan/prima/` | system partition |

### Boot sequence

1. **PIL auto-loads modem firmware** on kernel boot — no userspace action needed
2. **WCNSS (Pronto) loads** — PIL loads `wcnss.mdt` + segments
3. Device nodes appear: `/dev/smdcntl0`, `rmnet_bam0`

### Userspace stack for cellular data

#### Required packages (Alpine)
- `modemmanager` — modem management daemon
- `libqmi` — QMI protocol library (used by ModemManager)

#### Optional but important
- `rmtfs` — Remote Filesystem Service (modem EFS access via modemst1/modemst2 partitions)
  - Source: https://github.com/linux-msm/rmtfs
  - On CAF kernels: needs `LD_PRELOAD=/usr/lib/libqipcrtr4msmipc.so`
  - The modem may not fully initialize without rmtfs
- `libsmdpkt-wrapper` — workaround for CAF smd_pkt driver bug
  - Without it, QMI reads/writes to `/dev/smdcntl0` may hang
  - Usage: `LD_PRELOAD=/usr/lib/preload/libsmdpkt_wrapper.so ModemManager`

#### udev rule
```
# /etc/udev/rules.d/90-modem.rules
KERNEL=="smdcntl0", SYMLINK+="modem"
```

### Bringing up cellular data

```sh
# 1. Check modem loaded (should happen automatically)
dmesg | grep -i "pil\|modem\|mss"

# 2. Check QMI device exists
ls -la /dev/smdcntl0   # should exist
ls -la /dev/modem      # symlink from udev rule

# 3. Start ModemManager
ModemManager --debug &

# 4. List modems
mmcli -L

# 5. Connect to cellular data
mmcli -m 0 --simple-connect="apn=your.apn"

# 6. Check data interface
ip addr show rmnet_bam0

# 7. Set up routing
ip route add default dev rmnet_bam0
echo "nameserver 8.8.8.8" > /etc/resolv.conf

# 8. Test
ping -I rmnet_bam0 8.8.8.8
```

### Troubleshooting

- **ModemManager hangs**: likely the smd_pkt bug. Use `LD_PRELOAD=/usr/lib/preload/libsmdpkt_wrapper.so`
- **Modem not initializing**: check `dmesg | grep pil` — may need rmtfs running
- **No rmnet_bam0**: BAM-DMUX not initialized. Check `dmesg | grep bam`
- **qmicli test**: `qmicli -d /dev/modem --get-service-version-info`
- **Alternative to ModemManager**: ofono with QMI plugin also works

---

## WiFi (CAF 3.18)

### Boot sequence
1. PIL loads WCNSS firmware (`wcnss.mdt` + segments)
2. WCNSS core initializes, downloads NV binary to Pronto processor
3. Load Prima module: `modprobe pronto_wlan`
4. `wlan0` interface appears

### Commands
```sh
modprobe pronto_wlan
iw dev wlan0 scan
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
udhcpc -i wlan0
```

### Required firmware files
- `/lib/firmware/wcnss.mdt` + segments (WCNSS processor firmware)
- `/lib/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin` (calibration data)
- `/lib/firmware/wlan/prima/WCNSS_cfg.dat` (WiFi config)

---

## Bluetooth (CAF 3.18)

### Status: Likely non-functional without extra work

The CAF 3.18 kernel uses SMD TTY channels (`APPS_RIVA_BT_ACL`, `APPS_RIVA_BT_CMD`) for BT, but lacks an in-tree `hci_smd` driver. Stock Android used a proprietary `libbt-vendor.so`. BlueZ cannot directly use the SMD TTY devices without a transport driver.

**Options:**
1. Backport `btqcomsmd` from mainline (best approach)
2. Use a custom `hci_smd` driver from Qualcomm (out-of-tree)
3. Skip BT on Phase 1, get it on Phase 2 (mainline) where btqcomsmd works natively

---

## Mainline Kernel (Phase 2) — Cleaner Stack

On mainline, the modem/WiFi/BT stack is significantly simpler:

| Component | CAF 3.18 | Mainline |
|-----------|----------|----------|
| Modem PIL | `qcom,pil-q6v55-mss` | `qcom,msm8909-mss-pil` |
| Data interface | `rmnet_bam0` | `wwan0` (BAM-DMUX upstream driver) |
| QMI transport | SMD (`/dev/smdcntl0`) | rpmsg |
| rmtfs | needs LD_PRELOAD | native QRTR, no workarounds |
| libsmdpkt_wrapper | needed | not needed |
| WiFi driver | Prima (out-of-tree) | wcn36xx (in-tree) |
| BT driver | missing hci_smd | btqcomsmd (in-tree) |
| ModemManager | works with workarounds | works natively |

### Mainline DTS (just enable the nodes)
```dts
&mpss { status = "okay"; };
&wcnss { status = "okay"; };
&wcnss_iris { compatible = "qcom,wcn3620"; };
```
