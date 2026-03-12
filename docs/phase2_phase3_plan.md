# Phase 2 & 3 Implementation Plan — BQ268 postmarketOS

## Status

- **Phase 1** (CAF 3.18 + Alpine rootfs): Built, ready to flash.
- **Phase 2** (mainline kernel DTS): This document.
- **Phase 3** (pmOS device package): This document.

---

## Phase 2: Mainline Kernel DTS Port

### 2.1 Overview

Port `msm8909-bq268.dts` (CAF 3.18 bindings) to mainline bindings as
`qcom-msm8909-udotech-bq268.dts`. The file targets the msm8916-mainline
kernel tree (`github.com/msm8916-mainline/linux`, branch `wip/msm8916/6.19+`).

Base includes:
```
#include "qcom-msm8909-pm8909.dtsi"
```

Primary reference: `qcom-msm8909-nokia-leo.dts` (Nokia 6300 4G — same SoC,
SPI display, keypad, WCNSS, modem).

### 2.2 DTS Skeleton

```dts
// SPDX-License-Identifier: GPL-2.0-only
/dts-v1/;

#include "qcom-msm8909-pm8909.dtsi"

#include <dt-bindings/gpio/gpio.h>
#include <dt-bindings/input/input.h>
#include <dt-bindings/leds/common.h>
#include <dt-bindings/pinctrl/qcom,pmic-mpp.h>

/ {
	model = "Udotech BQ268";
	compatible = "udotech,bq268", "qcom,msm8909";
	chassis-type = "handset";

	aliases {
		serial0 = &blsp_uart1;
	};

	chosen {
		stdout-path = "serial0";
	};

	/* Sections below filled in per subsystem */
};
```

### 2.3 Reserved Memory

The BQ268 uses a slightly larger modem allocation than the SoC default.

```dts
&mpss_mem {
	reg = <0x0 0x88000000 0x0 0x05300000>;
};

&wcnss_mem {
	reg = <0x0 0x8d300000 0x0 0x0700000>;
};
```

If `qcom-msm8909.dtsi` already defines `mpss_mem` and `wcnss_mem` in the
`reserved-memory` node, override with the above. If not, add them. Also
ensure an `rmtfs` region exists (check Nokia Leo for the pattern — it
typically uses `qcom,rmtfs-mem`).

**Effort**: 15 minutes. **Risk**: Low.

---

### 2.4 Display (ST7735S 128x160 SPI)

This is the single hardest subsystem to port. CAF uses a proprietary
`qcom,mdss-spi-display` framework. Mainline uses the `panel-mipi-dbi-spi`
DRM tiny driver with an external firmware blob containing the init sequence.

#### 2.4.1 DTS Node

```dts
&blsp_spi5 {
	status = "okay";

	panel@0 {
		compatible = "shenzhen,bq268-st7735s", "panel-mipi-dbi-spi";
		reg = <0>;

		spi-max-frequency = <16000000>;
		dc-gpios = <&tlmm 3 GPIO_ACTIVE_HIGH>;
		reset-gpios = <&tlmm 2 GPIO_ACTIVE_LOW>;

		vdd-supply = <&pm8909_l17>;   /* 2.85V */
		vddio-supply = <&pm8909_l6>;  /* 1.8V */

		backlight = <&backlight>;

		width-mm = <26>;   /* measure physical panel */
		height-mm = <33>;

		panel-init-sequence = <&st7735s_panel_fw>;
	};
};
```

The `blsp_spi5` controller node should already be defined in
`qcom-msm8909.dtsi` (address 0x78b9000). If it is not, it needs to be
added — check the base DTSI. It needs pinctrl for GPIOs 16-19:

```dts
&blsp_spi5 {
	pinctrl-0 = <&spi5_default>;
	pinctrl-1 = <&spi5_sleep>;
	pinctrl-names = "default", "sleep";
};

&tlmm {
	spi5_default: spi5-default-state {
		spi-pins {
			pins = "gpio16", "gpio17", "gpio19";
			function = "blsp_spi5";
			drive-strength = <12>;
			bias-disable;
		};
		cs-pin {
			pins = "gpio18";
			function = "blsp_spi5";
			drive-strength = <2>;
			bias-pull-up;
		};
	};

	spi5_sleep: spi5-sleep-state {
		spi-pins {
			pins = "gpio16", "gpio17", "gpio18", "gpio19";
			function = "gpio";
			drive-strength = <2>;
			bias-pull-down;
		};
	};
};
```

> **Note**: If `blsp_spi5` is not in the base DTSI, it must be added there
> (or in an msm8909 common DTSI patch). The Nokia Leo DTS shows the
> pattern for `blsp_spi5` on this SoC.

#### 2.4.2 Panel Init Firmware Blob

The `panel-mipi-dbi-spi` driver loads a firmware file at runtime. The
firmware format is:

```
Bytes 0-14:  "MIPI DBI\0\0\0\0\0\0\0"  (15-byte magic)
Byte 15:     0x01                        (version)
Byte 16+:    command stream
```

Command stream encoding:
- `<cmd> <num_params> <param1> <param2> ...` for regular commands
- `0x00 0x01 <delay_ms>` for delays (delay capped at 255ms per entry)

For the pmOS device package, the firmware is built from a text source file
using the `mipi-dbi-cmd` tool (provided by the `mipi-dbi-cmd` Alpine
package). The source file format is one command per line:

```
command <hex_cmd> [param1 param2 ...]
delay <ms>
```

Create `udotech,bq268-st7735s-panel.txt`:

```
# ST7735S 128x160 panel init for BQ268
# Decoded from CAF qcom,mdss-spi-on-command blob

command 11
delay 120
command B1 05 3C 3C
command B2 05 3C 3C
command B3 05 3C 3C 05 3C 3C
command B4 03
command C0 28 08 04
command C1 C0
command C2 0D 00
command C3 8D 2A
command C4 8D EE
command C5 1A
command 36 00
command 35 00
command E0 04 22 07 0A 2E 30 25 2A 28 26 2E 3A 00 01 03 13
command E1 04 16 06 0D 2D 26 23 27 27 25 2D 3B 00 01 04 13
command 3A 05
command 29
```

The `mipi-dbi-cmd` tool compiles this into the binary firmware blob that
goes to `/lib/firmware/udotech,bq268-st7735s-panel.bin`.

> **CASET (0x2A) and RASET (0x2B)**: Omitted from the firmware blob — the
> `panel-mipi-dbi-spi` driver handles column/row address setting itself.
> The CAF blob includes them but they are not needed in the mainline
> firmware.

> **RAMWR (0x2C)**: Also omitted — the driver sends this before each
> frame.

#### 2.4.3 Backlight

CAF uses PM8909 MPP4 as a current sink at 20mA. Mainline options:

**Option A — PWM backlight (preferred, matches Nokia Leo pattern):**
```dts
/ {
	backlight: backlight {
		compatible = "pwm-backlight";
		pwm = <&pm8909_pwm 0 100000>;
		brightness-levels = <0 255>;
		num-interpolated-steps = <255>;
		default-brightness-level = <128>;
	};
};
```

This requires the PM8909 PWM driver to be functional on MPP4. Check
whether `qcom-msm8909-pm8909.dtsi` exposes a `pm8909_pwm` phandle.

**Option B — Simple GPIO on/off (fallback):**
```dts
/ {
	backlight: backlight {
		compatible = "gpio-backlight";
		gpios = <&pm8909_mpps 4 GPIO_ACTIVE_HIGH>;
		default-on;
	};
};
```

**Effort**: 2-4 hours for display + backlight combined.
**Risk**: Medium — the `panel-mipi-dbi-spi` driver path is proven on Nokia
Leo, but the ST7735S init sequence needs verification on real hardware.

---

### 2.5 GPIO Keys

Direct port. Changes: `&msm_gpio` becomes `&tlmm`, use `GPIO_ACTIVE_LOW` /
`GPIO_ACTIVE_HIGH` macros, add `wakeup-source` instead of `gpio-key,wakeup`.

```dts
/ {
	gpio-keys {
		compatible = "gpio-keys";

		pinctrl-0 = <&gpio_keys_default>;
		pinctrl-names = "default";

		key-ptt {
			label = "PTT";
			gpios = <&tlmm 91 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_F1>;
			wakeup-source;
		};

		key-headset-ptt {
			label = "Headset PTT";
			gpios = <&tlmm 92 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_F2>;
			wakeup-source;
		};

		key-f3 {
			label = "F3";
			gpios = <&tlmm 90 GPIO_ACTIVE_LOW>;
			linux,code = <KEY_F3>;
			wakeup-source;
		};

		key-f6 {
			label = "F6";
			gpios = <&tlmm 112 GPIO_ACTIVE_HIGH>;
			linux,code = <KEY_F6>;
			wakeup-source;
		};
	};
};

&tlmm {
	gpio_keys_default: gpio-keys-default-state {
		key-pins {
			pins = "gpio90", "gpio91", "gpio92";
			function = "gpio";
			drive-strength = <2>;
			bias-pull-up;
		};
		key-f6-pin {
			pins = "gpio112";
			function = "gpio";
			drive-strength = <2>;
			bias-pull-down;
		};
	};
};
```

**Effort**: 30 minutes. **Risk**: Low.

---

### 2.6 Matrix Keypad

Same `gpio-matrix-keypad` compatible in mainline. Only change is
`&msm_gpio` to `&tlmm` and use proper GPIO flag macros.

```dts
/ {
	matrix-keypad {
		compatible = "gpio-matrix-keypad";

		debounce-delay-ms = <5>;
		col-scan-delay-us = <2>;
		gpio-activelow;
		wakeup-source;

		pinctrl-0 = <&matrix_keypad_default>;
		pinctrl-names = "default";

		row-gpios = <&tlmm 98 GPIO_ACTIVE_LOW>,
			    <&tlmm 110 GPIO_ACTIVE_LOW>;

		col-gpios = <&tlmm 95 GPIO_ACTIVE_LOW>,
			    <&tlmm 96 GPIO_ACTIVE_LOW>,
			    <&tlmm 97 GPIO_ACTIVE_LOW>;

		linux,keymap = <
			MATRIX_KEY(0, 0, KEY_SELECT)
			MATRIX_KEY(0, 1, KEY_UP)
			MATRIX_KEY(0, 2, KEY_BACK)
			MATRIX_KEY(1, 0, KEY_LEFT)
			MATRIX_KEY(1, 1, KEY_DOWN)
			MATRIX_KEY(1, 2, KEY_RIGHT)
		>;
	};
};

&tlmm {
	matrix_keypad_default: matrix-keypad-default-state {
		row-pins {
			pins = "gpio98", "gpio110";
			function = "gpio";
			drive-strength = <2>;
			bias-pull-up;
		};
		col-pins {
			pins = "gpio95", "gpio96", "gpio97";
			function = "gpio";
			drive-strength = <2>;
			bias-pull-up;
		};
	};
};
```

> **Note**: Need `MATRIX_KEY` macro from `<dt-bindings/input/input.h>`. If
> not available, use raw hex values: `0x00000161` for `MATRIX_KEY(0,0,KEY_SELECT)`, etc.

**Effort**: 30 minutes. **Risk**: Low.

---

### 2.7 GPIO LEDs

```dts
/ {
	leds {
		compatible = "gpio-leds";

		led-button-backlight {
			gpios = <&tlmm 1 GPIO_ACTIVE_HIGH>;
			color = <LED_COLOR_ID_WHITE>;
			function = LED_FUNCTION_KBD_BACKLIGHT;
			default-state = "off";
			retain-state-suspend;
		};

		led-red {
			gpios = <&tlmm 68 GPIO_ACTIVE_HIGH>;
			color = <LED_COLOR_ID_RED>;
			function = LED_FUNCTION_INDICATOR;
			default-state = "off";
			retain-state-suspend;
		};

		led-green {
			gpios = <&tlmm 69 GPIO_ACTIVE_HIGH>;
			color = <LED_COLOR_ID_GREEN>;
			function = LED_FUNCTION_INDICATOR;
			default-state = "off";
			retain-state-suspend;
		};
	};
};
```

**Effort**: 15 minutes. **Risk**: None.

---

### 2.8 Battery (Charger + BMS)

CAF uses `qcom,qpnp-linear-charger` and `qcom,qpnp-vm-bms`. Mainline
equivalents: `qcom,pm8916-lbc` and `qcom,pm8916-bms-vm`.

Key conversion: CAF `qcom,ibatsafe-ma = <800>` becomes mainline
`qcom,ibat-safe-ua = <800000>` (milliamps to microamps).

```dts
/ {
	battery: battery {
		compatible = "simple-battery";
		voltage-min-design-microvolt = <3300000>;
		voltage-max-design-microvolt = <4300000>;
		energy-full-design-microwatt-hours = <8740000>; /* 2300mAh * 3.8V */
		charge-full-design-microamp-hours = <2300000>;
		charge-term-current-microamp = <100000>;
		constant-charge-current-max-microamp = <800000>;
		constant-charge-voltage-max-microvolt = <4300000>;

		ocv-capacity-celsius = <25>;
		ocv-capacity-table-0 =
			<4208000 100>,
			<4178000 95>,
			<4066000 90>,
			<3966000 85>,
			<3948000 80>,
			<3910000 75>,
			<3885000 70>,
			<3858000 65>,
			<3830000 60>,
			<3807000 55>,
			<3787000 50>,
			<3767000 45>,
			<3745000 40>,
			<3720000 35>,
			<3690000 30>,
			<3643000 25>,
			<3572000 20>,
			<3500000 15>,
			<3442000 10>,
			<3428000 9>,
			<3414000 8>,
			<3400000 7>,
			<3383000 6>,
			<3366000 5>,
			<3342000 4>,
			<3309000 3>,
			<3267000 2>,
			<3194000 1>,
			<3000000 0>;
	};
};

&pm8909_lbc {
	monitored-battery = <&battery>;
	qcom,ibat-safe-ua = <800000>;
	qcom,thermal-mitigation-ua = <800000 720000 630000 0>;
	status = "okay";
};

&pm8909_bms {
	monitored-battery = <&battery>;
	qcom,force-s2-in-charging;
	status = "okay";
};
```

> **OCV table**: Extracted from the CAF `batterydata-qrd-skui-4v2-3000mah.dtsi`
> `pc-temp-ocv-lut`, column index 2 (25 degrees C). Values converted from
> raw ADC counts to microvolts (they are already in microvolts in the CAF
> DTSI).

**Effort**: 1 hour. **Risk**: Low — PM8916 LBC driver is well-tested on
MSM8909 devices.

---

### 2.9 Audio

**THIS IS NOT SUPPORTED on mainline MSM8909.**

The `qcom-msm8909.dtsi` in the msm8916-mainline kernel does NOT contain
LPASS (Low-Power Audio Subsystem) nodes — no `&sound`, no `&lpass`, no
codec nodes. The GCC clock header does define audio clocks, and the MSM8916
DTSI shows the register layout, but adding audio support requires:

1. Adding SoC-level LPASS/codec DTSI nodes to `qcom-msm8909.dtsi`
2. Verifying the MSM8909 LPASS register map matches MSM8916 (likely yes)
3. Testing the `qcom,msm8916-wcd-analog` / `qcom,msm8916-wcd-digital`
   codec drivers

This is a significant effort and should be deferred. For the BQ268, audio
is critical (walkie-talkie), so this gap must be addressed before Phase 2
can fully replace Phase 1.

**Workaround**: Stay on CAF 3.18 kernel for audio-critical use cases until
LPASS support is added to the mainline MSM8909 DTSI.

**If/when LPASS is available**, the BQ268 audio DTS would look like:
```dts
/* Placeholder — requires LPASS nodes in qcom-msm8909.dtsi first */
/ {
	speaker-amp {
		compatible = "simple-audio-amplifier";
		enable-gpios = <&tlmm 36 GPIO_ACTIVE_HIGH>;
		sound-name-prefix = "Speaker Amp";
	};
};

&sound {
	model = "udotech-bq268";
	audio-routing =
		"Speaker Amp INL", "HPH_R_EXT",
		"AMIC1", "MIC BIAS Internal1",
		"AMIC3", "MIC BIAS Internal1";

	pinctrl-0 = <&cdc_pdm_default>;
	pinctrl-names = "default";
};
```

**Effort**: 0 hours now (blocked). 8-16 hours if adding LPASS to base DTSI.
**Risk**: High — this is the biggest gap.

---

### 2.10 WiFi/BT (WCNSS Pronto + WCN3620)

```dts
&wcnss {
	status = "okay";
};

&wcnss_iris {
	compatible = "qcom,wcn3620";
};
```

Firmware: `wcnss.mdt` + segments go to `/lib/firmware/qcom/msm8909/`.
The `WCNSS_qcom_wlan_nv.bin` goes to `/lib/firmware/wlan/prima/` (or
wherever the wcn36xx driver expects it — check Nokia Leo).

**Effort**: 15 minutes. **Risk**: Low.

---

### 2.11 Modem (Hexagon DSP, data-only)

```dts
&mpss {
	status = "okay";
};
```

BAM-DMUX is already defined in the base `qcom-msm8909.dtsi`. The modem
firmware (`modem.mdt` + segments) goes to `/lib/firmware/qcom/msm8909/`.

Userspace: ModemManager + libqmi over the BAM-DMUX data channel.

**Effort**: 15 minutes for DTS. Userspace config in Phase 3.
**Risk**: Low — proven on Nokia 8110/6300.

---

### 2.12 USB

```dts
&usb {
	extcon = <&pm8909_lbc>;
	status = "okay";
};

&usb_hs_phy {
	extcon = <&pm8909_lbc>;
};
```

> **Note**: The extcon source is the charger node, which provides VBUS
> detection. Check Nokia Leo for the exact pattern — some devices use
> `&pm8909_charger`, others `&pm8909_lbc`.

**Effort**: 15 minutes. **Risk**: Low.

---

### 2.13 eMMC

```dts
&sdhc_1 {
	status = "okay";
};
```

No SD card slot, so `sdhc_2` stays disabled (default).

**Effort**: 5 minutes. **Risk**: None.

---

### 2.14 PMIC PON (Power-On) Keys

```dts
&pm8909_resin {
	linux,code = <KEY_DOT>;
	status = "okay";
};
```

**Effort**: 5 minutes. **Risk**: None.

---

### 2.15 Regulators

The display regulators need to be enabled:

```dts
&pm8909_l6 {
	/* VDDIO for display */
	regulator-min-microvolt = <1800000>;
	regulator-max-microvolt = <1800000>;
};

&pm8909_l17 {
	/* VDD for display */
	regulator-min-microvolt = <2850000>;
	regulator-max-microvolt = <2850000>;
};
```

Check whether `qcom-msm8909-pm8909.dtsi` already defines these with
correct voltage ranges. Override only if needed.

**Effort**: 15 minutes. **Risk**: None.

---

### 2.16 Disabled Peripherals

Explicitly disable unused hardware to prevent probe failures:

```dts
&sdhc_2 { status = "disabled"; };  /* No SD card */

/* No camera, GPS, sensors, touchscreen */
```

The base DTSI should have most of these disabled by default (no
`status = "okay"`).

**Effort**: 10 minutes. **Risk**: None.

---

### 2.17 Complete DTS Assembly Checklist

| # | Section | File Location | Status |
|---|---------|--------------|--------|
| 1 | Header + model/compatible | Top of DTS | TODO |
| 2 | Reserved memory (mpss, wcnss) | DTS | TODO |
| 3 | Display (SPI panel + pinctrl) | DTS + firmware blob | TODO |
| 4 | Backlight | DTS | TODO |
| 5 | GPIO keys + pinctrl | DTS | TODO |
| 6 | Matrix keypad + pinctrl | DTS | TODO |
| 7 | GPIO LEDs | DTS | TODO |
| 8 | Battery + charger + BMS | DTS | TODO |
| 9 | Audio (BLOCKED) | Deferred | BLOCKED |
| 10 | WiFi/BT | DTS | TODO |
| 11 | Modem | DTS | TODO |
| 12 | USB | DTS | TODO |
| 13 | eMMC | DTS | TODO |
| 14 | PON keys | DTS | TODO |
| 15 | Regulators | DTS | TODO |
| 16 | Disabled peripherals | DTS | TODO |

**Total estimated effort for DTS**: 4-6 hours (excluding audio).

---

## Phase 3: pmOS Device Package

### 3.1 Overview

Create a proper postmarketOS device package so the device can be built
with `pmbootstrap`. This goes in the pmaports repository under
`device/testing/device-udotech-bq268/`.

### 3.2 Package Directory Structure

```
device/testing/device-udotech-bq268/
├── APKBUILD
├── deviceinfo
├── modules-initfs
├── kernel-cmdline.conf
├── udotech,bq268-st7735s-panel.txt
└── 00-udotech-bq268-display.files
```

### 3.3 APKBUILD

```bash
# Maintainer: Your Name <email@example.com>
# Reference: Nokia 6300 4G (nokia-leo) device package
pkgname=device-udotech-bq268
pkgdesc="Udotech BQ268 walkie-talkie"
pkgver=1
pkgrel=0
url="https://postmarketos.org"
license="MIT"
arch="armv7"
options="!check !archcheck"
depends="
	linux-postmarketos-qcom-msm8916
	mkbootimg
	postmarketos-base
	soc-qcom-msm8909
	soc-qcom-msm8916-rproc
"
makedepends="
	devicepkg-dev
	mipi-dbi-cmd
"
subpackages="$pkgname-nonfree-firmware:nonfree_firmware"
source="
	deviceinfo
	modules-initfs
	kernel-cmdline.conf
	udotech,bq268-st7735s-panel.txt
	00-udotech-bq268-display.files
"

build() {
	devicepkg_build $startdir $pkgname

	# Compile panel init firmware blob
	mkdir -p "$builddir"
	mipi-dbi-cmd \
		"$builddir"/udotech,bq268-st7735s-panel.bin \
		"$srcdir"/udotech,bq268-st7735s-panel.txt
}

package() {
	devicepkg_package $startdir $pkgname

	# Install panel firmware
	install -Dm644 "$builddir"/udotech,bq268-st7735s-panel.bin \
		"$pkgdir"/lib/firmware/udotech,bq268-st7735s-panel.bin

	# Install mkinitfs display file list
	install -Dm644 "$srcdir"/00-udotech-bq268-display.files \
		"$pkgdir"/usr/share/mkinitfs/files/00-udotech-bq268-display.files
}

nonfree_firmware() {
	pkgdesc="Firmware for GPU, WiFi, and modem"
	depends="
		firmware-qcom-adreno-a300
		msm-firmware-loader
		firmware-udotech-bq268-wcnss-nv
	"
	mkdir -p "$subpkgdir"
}

sha512sums="<generated by abuild>"
```

> **Note on kernel**: Until the BQ268 DTS is merged into
> `msm8916-mainline/linux` and the shared kernel
> `linux-postmarketos-qcom-msm8916` includes the DTB, you need either:
> (a) a device-specific kernel package `linux-udotech-bq268`, or
> (b) a patch to the shared kernel package adding the DTS file.
> Option (b) is preferred — add the DTS as a patch in the shared kernel
> APKBUILD. Once upstream accepts it, the patch is dropped.

### 3.4 deviceinfo

```bash
# Reference: device-nokia-leo/deviceinfo
deviceinfo_format_version="0"
deviceinfo_name="Udotech BQ268"
deviceinfo_manufacturer="Udotech"
deviceinfo_codename="udotech-bq268"
deviceinfo_year="2023"
deviceinfo_dtb="qcom-msm8909-udotech-bq268"
deviceinfo_append_dtb="true"
deviceinfo_arch="armv7"
deviceinfo_chassis="handset"

# Display
deviceinfo_screen_width="128"
deviceinfo_screen_height="160"

# Boot
deviceinfo_flash_method="fastboot"
deviceinfo_generate_bootimg="true"
deviceinfo_generate_extlinux_config="true"
deviceinfo_kernel_cmdline=""
deviceinfo_bootimg_qcdt="false"
deviceinfo_bootimg_dtb_second="false"

# Flash offsets (same as Nokia Leo / MSM8909 standard)
deviceinfo_flash_offset_base="0x80000000"
deviceinfo_flash_offset_kernel="0x00008000"
deviceinfo_flash_offset_ramdisk="0x02000000"
deviceinfo_flash_offset_second="0x00f00000"
deviceinfo_flash_offset_tags="0x01e00000"
deviceinfo_flash_pagesize="2048"
deviceinfo_flash_sparse="true"

# Storage
deviceinfo_external_storage="false"

# USB
deviceinfo_usb_idVendor="0x18d1"
deviceinfo_usb_idProduct="0xd001"
```

### 3.5 modules-initfs

Kernel modules needed in the initramfs for early boot (display, input,
battery):

```
# Display
panel-mipi-dbi

# Input (matrix keypad for recovery/unlock)
matrix_keypad
matrix_keymap

# Battery
pm8916_lbc
pm8916_bms_vm
```

### 3.6 kernel-cmdline.conf

```
# BQ268: display rotation if needed
# fbcon=rotate:1
```

Keep minimal. The main kernel cmdline comes from lk2nd or extlinux.conf.

### 3.7 00-udotech-bq268-display.files

mkinitfs file list to include the panel firmware in initramfs:

```
/lib/firmware/udotech,bq268-st7735s-panel.bin
```

### 3.8 Panel Init Source File

`udotech,bq268-st7735s-panel.txt` — same content as in section 2.4.2:

```
# ST7735S 128x160 panel init for Udotech BQ268
# Decoded from CAF qcom,mdss-spi-on-command blob

command 11
delay 120
command B1 05 3C 3C
command B2 05 3C 3C
command B3 05 3C 3C 05 3C 3C
command B4 03
command C0 28 08 04
command C1 C0
command C2 0D 00
command C3 8D 2A
command C4 8D EE
command C5 1A
command 36 00
command 35 00
command E0 04 22 07 0A 2E 30 25 2A 28 26 2E 3A 00 01 03 13
command E1 04 16 06 0D 2D 26 23 27 27 25 2D 3B 00 01 04 13
command 3A 05
command 29
```

### 3.9 WCNSS NV Firmware Subpackage

Create a separate package for device-specific WiFi NV data:

```
device/testing/firmware-udotech-bq268-wcnss-nv/
├── APKBUILD
└── WCNSS_qcom_wlan_nv.bin
```

APKBUILD:
```bash
pkgname=firmware-udotech-bq268-wcnss-nv
pkgdesc="WiFi NV data for Udotech BQ268"
pkgver=1
pkgrel=0
url="https://postmarketos.org"
license="proprietary"
arch="armv7"
options="!check !strip !archcheck !tracedeps pmb:cross-native"
source="WCNSS_qcom_wlan_nv.bin"

package() {
	install -Dm644 "$srcdir"/WCNSS_qcom_wlan_nv.bin \
		"$pkgdir"/lib/firmware/wlan/prima/WCNSS_qcom_wlan_nv.bin
}

sha512sums="<generated by abuild>"
```

The `WCNSS_qcom_wlan_nv.bin` file is extracted from the `persist` partition
EDL dump (already done by `just extract-firmware`).

### 3.10 soc-qcom-msm8909 Package

If this package does not already exist in pmaports, create it:

```
device/community/soc-qcom-msm8909/
├── APKBUILD
└── soc-qcom-msm8909-modem.initd
```

This is a thin wrapper:
```bash
pkgname=soc-qcom-msm8909
pkgdesc="Common package for Qualcomm MSM8909 devices"
pkgver=1
pkgrel=0
url="https://postmarketos.org"
license="MIT"
arch="armv7"
options="!check"
depends="soc-qcom-msm8916"
subpackages="$pkgname-modem"
source="soc-qcom-msm8909-modem.initd"

package() {
	mkdir -p "$pkgdir"
}

modem() {
	pkgdesc="Modem init for MSM8909 (BAM-DMUX/QMI)"
	depends="qmi-utils"
	install -Dm755 "$srcdir"/soc-qcom-msm8909-modem.initd \
		"$subpkgdir"/etc/init.d/soc-qcom-msm8909-modem
}

sha512sums="<generated by abuild>"
```

> Check pmaports `main/` and `device/community/` first — this package may
> already exist. If `soc-qcom-msm8916` already covers MSM8909 adequately,
> skip this step.

### 3.11 pmbootstrap Workflow

Step-by-step to build and flash:

```bash
# 1. Clone pmaports (if not already)
git clone https://gitlab.com/postmarketOS/pmaports.git
cd pmaports

# 2. Create device directory
mkdir -p device/testing/device-udotech-bq268
# Copy files from sections 3.3-3.8 above

# 3. Create firmware package directory
mkdir -p device/testing/firmware-udotech-bq268-wcnss-nv
# Copy APKBUILD + NV binary

# 4. Initialize pmbootstrap
pmbootstrap init
# Select: vendor=udotech, device=bq268, channel=edge

# 5. Build
pmbootstrap build device-udotech-bq268
pmbootstrap build firmware-udotech-bq268-wcnss-nv

# 6. Install (generates rootfs)
pmbootstrap install

# 7. Export flashable images
pmbootstrap export

# 8. Flash (device in fastboot mode via lk2nd)
pmbootstrap flasher flash_kernel
pmbootstrap flasher flash_rootfs

# Alternative: manual flash
fastboot flash boot /tmp/postmarketOS-export/boot.img
fastboot flash system /tmp/postmarketOS-export/udotech-bq268.img
```

---

## Risk and Gap Analysis

### Critical Gaps

| Gap | Impact | Mitigation | Phase |
|-----|--------|------------|-------|
| **Audio not supported on mainline MSM8909** | No speaker/mic — walkie-talkie is unusable | Stay on CAF 3.18 for audio; contribute LPASS nodes upstream | 2 |
| **BQ268 DTS not in shared kernel** | Cannot use `linux-postmarketos-qcom-msm8916` directly | Patch shared kernel APKBUILD or use device-specific kernel | 2/3 |
| **`blsp_spi5` may not be in base DTSI** | Display node has no parent controller | Add SPI5 node to `qcom-msm8909.dtsi` (upstream patch) | 2 |

### Medium Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Panel init sequence incorrect | White/blank screen | Verified against CAF blob; test with 3.18 first |
| `panel-mipi-dbi-spi` driver timing issues | Display artifacts | Compare SPI clock, try different `spi-max-frequency` |
| PWM backlight on MPP4 not working | No backlight | Fall back to GPIO on/off backlight |
| Battery OCV table inaccurate | Wrong percentage readings | Table from stock; tune later with real measurements |
| Modem firmware path mismatch | No cellular data | Check `msm-firmware-loader` vs manual `/lib/firmware/` path |

### Low Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| GPIO key polarity wrong | Keys inverted | Swap `GPIO_ACTIVE_LOW`/`HIGH`; test with `evtest` |
| Matrix keymap wrong | Wrong key assignments | Verified from CAF DTS; test with `evtest` |
| eMMC boot failure | No rootfs | Standard `sdhci-msm`; proven on all MSM8909 devices |

---

## Dependency Graph

```
Phase 1 (CAF 3.18 + Alpine)     [DONE — ready to flash]
   │
   ├── Validate boot chain ──────────────────────┐
   │   Verify: serial, display, keys, USB        │
   │                                              │
   ▼                                              │
Phase 2 (Mainline DTS)                            │
   │                                              │
   ├── 2.4 Display ◄── Needs blsp_spi5 in        │
   │       │            base DTSI (may need       │
   │       │            upstream patch)            │
   │       │                                      │
   │       ├── Panel firmware blob                │
   │       │   (mipi-dbi-cmd compile)             │
   │       │                                      │
   │       └── Backlight (PWM or GPIO)            │
   │                                              │
   ├── 2.5-2.7 Keys + LEDs (no deps)             │
   │                                              │
   ├── 2.8 Battery (no deps)                      │
   │                                              │
   ├── 2.9 Audio ◄── BLOCKED on LPASS in         │
   │                  qcom-msm8909.dtsi           │
   │                                              │
   ├── 2.10-2.13 WiFi/Modem/USB/eMMC (no deps)   │
   │                                              │
   └── Submit DTS to msm8916-mainline ────────────┤
                                                  │
                                                  ▼
Phase 3 (pmOS device package)                     │
   │                                              │
   ├── 3.3 APKBUILD ◄── Needs DTS in shared      │
   │                     kernel (or patch)        │
   │                                              │
   ├── 3.4-3.8 deviceinfo + modules + firmware    │
   │   (can be written before DTS is upstream)    │
   │                                              │
   ├── 3.9 WCNSS NV firmware package              │
   │   (independent, can be done anytime)         │
   │                                              │
   └── 3.11 pmbootstrap build + test ◄── Needs    │
              all above                           │
                                                  │
                                                  ▼
                                         Flash + validate
```

---

## Effort Summary

| Task | Estimated Time | Blocked By |
|------|---------------|------------|
| **Phase 2 total** | **6-8 hours** | Phase 1 validation |
| DTS skeleton + reserved memory | 30 min | — |
| Display (SPI panel + pinctrl + firmware) | 2-4 hours | blsp_spi5 in base DTSI |
| Backlight | 30 min | — |
| GPIO keys + matrix keypad | 1 hour | — |
| GPIO LEDs | 15 min | — |
| Battery (charger + BMS + OCV) | 1 hour | — |
| Audio | 0 (blocked) | LPASS in qcom-msm8909.dtsi |
| WiFi/BT + Modem + USB + eMMC | 30 min | — |
| Regulators + misc | 15 min | — |
| **Phase 3 total** | **3-4 hours** | Phase 2 DTS |
| APKBUILD + deviceinfo | 1 hour | — |
| modules-initfs + display files | 15 min | — |
| Panel init source file | 15 min | Already decoded |
| WCNSS NV firmware package | 30 min | — |
| soc-qcom-msm8909 (if needed) | 30 min | — |
| pmbootstrap build + test cycle | 1-2 hours | All above |
| **Grand total** | **9-12 hours** | — |

---

## Recommended Execution Order

1. **Flash Phase 1** — validate the boot chain works with CAF 3.18.
2. **Write the mainline DTS** — start with the easy parts (keys, LEDs,
   eMMC, USB) to get a booting mainline kernel, then add display.
3. **Build panel firmware blob** — test display separately with a
   quick-and-dirty boot.
4. **Create pmOS device package** — once display + keys work on mainline.
5. **Submit DTS upstream** — to `msm8916-mainline/linux` first, then
   to `torvalds/linux`.
6. **Address audio** — contribute LPASS nodes to `qcom-msm8909.dtsi`
   or wait for someone else to do it. This is the long pole.
