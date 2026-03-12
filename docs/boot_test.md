# Boot Test Procedure — BQ268 postmarketOS (Phase 1)

## Prerequisites

- lk2nd built: `out/lk2nd.img` (339K)
- rootfs built: `out/rootfs.img` (256M, Alpine Linux + CAF 3.18 kernel)
- USB cable connected
- Serial adapter on ttyMSM0 (optional but recommended)

## Flash

1. Enter fastboot mode (stock aboot): `adb reboot bootloader` or hold Vol Down at power-on
2. Flash lk2nd: `just flash-lk2nd`
3. Flash rootfs: `just flash-rootfs`
4. Reboot: `fastboot reboot`

## lk2nd Verification

After flashing lk2nd, hold **Volume Down** during boot to enter lk2nd fastboot mode.
Verify with `fastboot getvar version` — should show lk2nd version string.

lk2nd OEM debug commands:
- `fastboot oem dtb` — dump device tree
- `fastboot oem log` — show boot log
- `fastboot oem reboot-edl` — enter EDL mode (emergency recovery)

## Boot Sequence

```
SBL1 → RPM → TZ → stock aboot → lk2nd → reads extlinux.conf → loads zImage + DTB → Alpine boots
```

## Verification Checklist

### Must-have (boot confirmed)
- [ ] **Serial console** — `picocom -b 115200 /dev/ttyUSB0` shows kernel boot log
- [ ] **Login prompt** — root / bq268
- [ ] **Kernel version** — `uname -a` shows 3.18.140-perf

### Core hardware
- [ ] **USB gadget serial** — `picocom -b 115200 /dev/ttyACM0` (backup console)
- [ ] **USB RNDIS** — `usb0` interface appears on host, can SSH to device
- [ ] **SSH** — `ssh root@<ip>` via USB RNDIS
- [ ] **Display** — ST7735S 128x160 framebuffer (`/dev/fb0` exists, `cat /dev/urandom > /dev/fb0` shows noise)
- [ ] **Keypad** — `evtest /dev/input/event0` registers key presses
- [ ] **LEDs** — `echo 1 > /sys/class/leds/*/brightness` (GPIO68 red, GPIO69 green)

### Peripherals
- [ ] **WiFi** — `modprobe pronto_wlan && iw dev wlan0 scan`
- [ ] **Audio** — `cat /proc/asound/cards` shows codec
- [ ] **eMMC** — `lsblk` shows mmcblk0 with all partitions
- [ ] **Battery** — `cat /sys/class/power_supply/*/capacity`

## Troubleshooting

### No serial output at all
- Check UART wiring (TX/RX/GND on BLSP1 UART2)
- Try lk2nd fastboot: hold Vol Down, check `fastboot devices`
- If no fastboot either: lk2nd may not match the device. Try EDL recovery

### lk2nd boots but kernel doesn't
- Enter lk2nd fastboot (Vol Down), check `fastboot oem log`
- Verify extlinux.conf paths: `fastboot oem get-cmdline`
- Try booting kernel directly: `fastboot boot out/rootfs-boot.img` (if available)

### Kernel boots but no rootfs
- Wrong root= device: check `PARTUUID` matches system partition
- Try `root=/dev/mmcblk0pN` with the correct partition number
- Check kernel log: `dmesg | grep -i "root\|mount\|ext4"`

### Display blank
- Check `/dev/fb0` exists: `ls -la /dev/fb*`
- Check DRM: `ls /sys/class/drm/`
- SPI display may need specific driver init — check `dmesg | grep -i spi`

### WiFi fails to scan
- Check module loaded: `lsmod | grep wlan`
- Check firmware: `dmesg | grep -i wcnss`
- Verify NV data: `ls /lib/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin`

## Record Results

```bash
just note "BOOT TEST: PASS"
# or
just note "BOOT TEST: FAIL (no serial output, lk2nd fastboot works)"
```
