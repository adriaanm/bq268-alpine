# Modem & Connectivity Bringup — BQ268

## Architecture (mainline kernel)

```
[Modem firmware on Hexagon DSP]
        |
  [BAM-DMUX] ---- data plane (IP packets) --> wwan0 network interface
        |
  [rpmsg] -------- control plane (QMI)    --> ModemManager via QRTR
        |
  [q6v5-mss] ----- firmware loading       --> modem.mdt + modem.b00-b25, mba.mbn
```

## DTS (already in mainline DTS)

```dts
&mpss { status = "okay"; };          /* currently disabled — enable when ready */
&wcnss { status = "okay"; };
&wcnss_iris { compatible = "qcom,wcn3620"; };
```

Modem is disabled (`status = "disabled"`) until firmware and userspace are validated.

## Firmware files

| File | Location in rootfs | Source |
|------|-------------------|--------|
| `mba.mbn` | `/lib/firmware/mba.mbn` | modem partition (FAT16) |
| `modem.mdt` + `.b00-.b25` | `/lib/firmware/modem.*` | modem partition |
| `wcnss.mdt` + `.b00-.b12` | `/lib/firmware/wcnss.*` | modem partition |
| `WCNSS_qcom_wlan_nv.bin` | `/lib/firmware/wlan/prima/` | persist partition |
| `WCNSS_cfg.dat` | `/lib/firmware/wlan/prima/` | system partition |

All extracted by `just extract-firmware` from EDL dumps.

## Mainline stack (vs stock Android)

| Component | Stock Android | Mainline Linux |
|-----------|--------------|----------------|
| Modem PIL | `qcom,pil-q6v55-mss` | `qcom,msm8909-mss-pil` (q6v5-mss) |
| Data interface | `rmnet_bam0` | `wwan0` (BAM-DMUX) |
| QMI transport | SMD (`/dev/smdcntl0`) | rpmsg / QRTR |
| rmtfs | needs LD_PRELOAD hacks | native QRTR, no workarounds |
| WiFi driver | Prima (out-of-tree) | wcn36xx (in-tree) |
| BT driver | missing hci_smd | btqcomsmd (in-tree) |
| ModemManager | needs workarounds | works natively |

## Bringing up cellular data

```sh
# 1. Check modem loaded
dmesg | grep -i "q6v5\|mss\|modem"

# 2. Start ModemManager
rc-service modemmanager start

# 3. List modems
mmcli -L

# 4. Connect
mmcli -m 0 --simple-connect="apn=your.apn"

# 5. Check data interface
ip addr show wwan0

# 6. Route + test
ip route add default dev wwan0
echo "nameserver 8.8.8.8" > /etc/resolv.conf
ping 8.8.8.8
```

## WiFi

```sh
# wcn36xx loads automatically via wcnss remoteproc
iw dev wlan0 scan
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant/wpa_supplicant.conf
udhcpc -i wlan0
```

## Bluetooth

btqcomsmd driver (in-tree) provides HCI over SMD transport to the WCN3620.
BlueZ should work out of the box once WCNSS firmware is loaded.

## Troubleshooting

- **No wwan0**: Check `dmesg | grep bam` — BAM-DMUX may not have initialized
- **ModemManager can't find modem**: Check `dmesg | grep q6v5` — firmware load may have failed
- **WiFi scan fails**: Check `dmesg | grep wcn` and verify NV data at `/lib/firmware/wlan/prima/`
- **rmtfs**: May be needed for modem EFS access — install `rmtfs` package if modem won't fully initialize
