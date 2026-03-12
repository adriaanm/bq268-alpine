# Vendor Blob Audit — BQ268

This document classifies every blob in `proprietary-files.txt` for the BQ268's actual use case: a data-only walkie-talkie running a single Matrix voice messaging app over WiFi or 4G. No voice calls, no VoLTE/IMS, no video playback, no camera, no GPS, no touchscreen, no sensors.

## Use-case summary

| Feature | Needed | Notes |
|---------|--------|-------|
| Display / GPU | Yes | UI rendering on ST7735S 128x160 SPI LCD |
| Audio | Yes | Speaker output for voice messages (Opus, software decode) |
| WiFi | Yes | Primary data path (local network) |
| 4G modem (data only) | Yes | Mobile data via QMI/RmNet, basic SIM/UIM |
| Bluetooth | Yes | Headset audio, BLE provisioning |
| TrustZone / Keymaster | Yes | Boot chain, disk encryption |
| Thermal | Yes | Prevents SoC overheating |
| Camera | No | No hardware |
| GPS / GNSS | No | No hardware |
| Sensors | No | No hardware |
| Touchscreen | No | No hardware |
| IMS / VoLTE | No | Data-only, no voice calls |
| Video codecs (HW) | No | No video playback on 128x160 screen |
| FM Radio | No | No tuner |
| ANT+ / WiPower / VR | No | No hardware or use case |
| HDCP / DRM (Widevine) | No | No media playback |

---

## KEEP — Irreplaceable (Qualcomm proprietary, no open-source alternative)

### GPU firmware (Adreno 304)

Only `a300_pfp.fw` and `a300_pm4.fw` are used by this SoC. The rest are bundled BSP extras for other Adreno generations.

```
vendor/firmware/a300_pfp.fw                     # Adreno 3xx PFP microcode — actually used
vendor/firmware/a300_pm4.fw                     # Adreno 3xx PM4 microcode — actually used
```

Bundled but unused (can prune later, harmless to keep):
```
vendor/firmware/a225_pfp.fw
vendor/firmware/a225_pm4.fw
vendor/firmware/a225p5_pm4.fw
vendor/firmware/a330_pfp.fw
vendor/firmware/a330_pm4.fw
vendor/firmware/a420_pfp.fw
vendor/firmware/a420_pm4.fw
vendor/firmware/a530_gpmu.fw2
vendor/firmware/a530_pfp.fw
vendor/firmware/a530_pm4.fw
vendor/firmware/a530v1_pfp.fw
vendor/firmware/a530v1_pm4.fw
vendor/firmware/a530v2_seq.fw2
vendor/firmware/a530v3_gpmu.fw2
vendor/firmware/a530v3_seq.fw2
vendor/firmware/a540_gpmu.fw2
vendor/firmware/leia_pfp_470.fw
vendor/firmware/leia_pm4_470.fw
```

### GPU userspace (Adreno)

Proprietary Qualcomm GPU driver stack. No open-source Adreno 304 userspace exists (freedreno targets newer Adreno and still needs firmware).

```
vendor/lib/egl/eglsubAndroid.so
vendor/lib/egl/libEGL_adreno.so
vendor/lib/egl/libGLESv1_CM_adreno.so
vendor/lib/egl/libGLESv2_adreno.so
vendor/lib/egl/libq3dtools_adreno.so
vendor/lib/libadreno_utils.so
vendor/lib/libC2D2.so
vendor/lib/libc2d30-a3xx.so                    # C2D for Adreno 3xx — actually used
vendor/lib/libCB.so
vendor/lib/libgsl.so                            # Graphics System Layer — Adreno kernel interface
vendor/lib/libllvm-qcom.so                     # Qualcomm LLVM for shader compilation
vendor/lib/libOpenCL.so
vendor/lib/libRSDriver_adreno.so
vendor/lib/libbccQTI.so
vendor/lib/librs_adreno.so
vendor/lib/librs_adreno_sha1.so
vendor/lib/libsc-a3xx.so                       # Adreno 3xx shader compiler — actually used
vendor/lib/libUBWC.so
```

Bundled but unused (other Adreno generations):
```
vendor/lib/libc2d30-a4xx.so
vendor/lib/libc2d30-a5xx.so
vendor/lib/libsc-a2xx.so
```

### Display / HWComposer (Qualcomm MDP)

Tightly coupled to the MSM8909 MDP display pipeline and Adreno gralloc.

```
vendor/lib/hw/gralloc.msm8909.so
vendor/lib/hw/hwcomposer.msm8909.so
vendor/lib/hw/android.hardware.graphics.allocator@2.0-impl.so
vendor/lib/hw/android.hardware.graphics.composer@2.1-impl.so
vendor/lib/hw/android.hardware.graphics.mapper@2.0-impl.so
vendor/bin/hw/android.hardware.graphics.allocator@2.0-service
vendor/bin/hw/android.hardware.graphics.composer@2.1-service
vendor/lib/libgpu_tonemapper.so
vendor/lib/libgrallocutils.so
vendor/lib/libqdutils.so
vendor/lib/libqdMetaData.so
vendor/lib/libqservice.so
vendor/lib/libsdmcore.so
vendor/lib/libsdmutils.so
vendor/lib/libsdm-color.so
vendor/lib/libsdm-disp-vndapis.so
vendor/lib/libsdmextension.so
vendor/lib/libscalar.so
vendor/lib/libhdr_tm.so
vendor/lib/libhwc2on1adapter.so
vendor/lib/vendor.display.config@1.0_vendor.so
vendor/lib/vendor.display.config@1.1_vendor.so
vendor/lib/hw/gralloc.default.so
```

### Audio platform (Qualcomm ACDB)

The primary audio HAL encodes msm8909-specific mixer routing, codec programming, and ACDB (Audio Calibration Database) handling. Cannot be replaced without reverse-engineering the calibration data format.

```
vendor/lib/hw/audio.primary.msm8909.so
vendor/lib/hw/android.hardware.audio@2.0-impl.so
vendor/lib/libacdbloader.so
vendor/lib/libacdb-fts.so
vendor/lib/libacdbmapper.so
vendor/lib/libacdbrtac.so
vendor/lib/libadiertac.so
vendor/lib/libadm.so
vendor/lib/libaudcal.so
vendor/lib/libaudioalsa.so
vendor/lib/libaudio_log_utils.so
vendor/lib/libalsautils.so
vendor/lib/libtinycompress_vendor.so
```

### Modem / RIL / QMI (data-only subset)

The QMI stack is needed for 4G data bearers. `rild` + `qmuxd` + `netmgrd` form the core data path. The rest are QMI framework libraries.

```
vendor/bin/hw/rild
vendor/bin/qmuxd                               # QMI multiplexer — bridges userspace to modem shared memory
vendor/bin/netmgrd                              # network manager — data connection setup/teardown
vendor/bin/qti                                  # QTI data services
vendor/bin/port-bridge                          # serial port bridge for modem AT commands
vendor/bin/irsc_util                            # IPC router security config for QMI
vendor/bin/tftp_server                          # TFTP for modem EFS access
vendor/bin/rmt_storage                          # remote storage — modem EFS partition access
vendor/lib/libril.so
vendor/lib/libreference-ril.so
vendor/lib/libril-qc-hal-qmi.so
vendor/lib/libril-qc-qmi-1.so
vendor/lib/libril-qc-radioconfig.so
vendor/lib/libril-qcril-hook-oem.so
vendor/lib/librilqmiservices.so
vendor/lib/librilutils.so
vendor/lib/libqcrilFramework.so
vendor/lib/libqmi.so
vendor/lib/libqmi_cci.so
vendor/lib/libqmi_client_helper.so
vendor/lib/libqmi_client_qmux.so
vendor/lib/libqmi_common_so.so
vendor/lib/libqmi_csi.so
vendor/lib/libqmi_encdec.so
vendor/lib/libqmiservices.so
vendor/lib/libdsi_netctrl.so                   # data services interface — data bearer setup
vendor/lib/libdsutils.so
vendor/lib/libnetmgr.so
vendor/lib/librmnetctl.so                      # RmNet control — manages 4G data interfaces
vendor/lib/libqdi.so
vendor/lib/libqdp.so
vendor/lib/libqcmaputils.so
vendor/lib/liblqe.so                           # link quality estimation
vendor/lib/libidl.so
vendor/lib/libconfigdb.so
vendor/lib/libmdmdetect.so
vendor/lib/libperipheral_client.so             # PIL — modem subsystem loading
vendor/lib/libsmemlog.so                       # shared memory logging (modem IPC)
vendor/lib/libdiag.so                          # Qualcomm DIAG protocol
vendor/lib/libtime_genoff.so                   # time sync with modem
vendor/lib/libpdmapper.so                      # protection domain mapper
vendor/lib/libqcci_legacy.so
vendor/lib/libsubsystem_control.so             # subsystem restart control
vendor/lib/libsystem_health_mon.so             # modem watchdog
vendor/lib/vendor.qti.hardware.radio.qcrilhook@1.0_vendor.so
vendor/lib/vendor.qti.hardware.radio.qtiradio@1.0_vendor.so
vendor/lib/vendor.qti.hardware.radio.uim@1.0_vendor.so
vendor/lib/vendor.qti.hardware.radio.uim@1.1_vendor.so
```

### TrustZone / Keymaster / Gatekeeper

Required by the boot chain. Keymaster provides hardware-backed key storage for disk encryption. All backed by signed TrustZone firmware — cannot be replaced.

```
vendor/bin/qseecomd                            # QSEE communication daemon — loads trustlets into TZ
vendor/bin/init.qti.qseecomd.sh
vendor/bin/hw/android.hardware.keymaster@3.0-service-qti
vendor/bin/hw/android.hardware.gatekeeper@1.0-service-qti
vendor/bin/hw/vendor.qti.hardware.qteeconnector@1.0-service
vendor/lib/hw/android.hardware.keymaster@3.0-impl-qti.so
vendor/lib/hw/android.hardware.gatekeeper@1.0-impl-qti.so
vendor/lib/hw/keystore.msm8909.so
vendor/lib/hw/gatekeeper.msm8909.so
vendor/lib/hw/vendor.qti.hardware.qteeconnector@1.0-impl.so
vendor/lib/libQSEEComAPI.so
vendor/lib/libQTEEConnector_vendor.so
vendor/lib/libGPTEE_vendor.so
vendor/lib/libGPreqcancel.so
vendor/lib/libGPreqcancel_svc.so
vendor/lib/libkeymasterdeviceutils.so
vendor/lib/libkeymasterprovision.so
vendor/lib/libkeymasterutils.so
vendor/lib/librpmb.so                          # replay-protected memory block (secure storage)
vendor/lib/libssd.so
vendor/lib/vendor.qti.hardware.qteeconnector@1.0_vendor.so
vendor/lib/vendor.qti.esepowermanager@1.0_vendor.so
vendor/lib/hw/vendor.qti.esepowermanager@1.0-impl.so
vendor/bin/hw/vendor.qti.esepowermanager@1.0-service
```

### WiFi (Prima/Pronto WLAN)

Vendor-specific HAL interfacing with the wcnss/Prima kernel driver. The actual WLAN firmware is loaded from `/lib/firmware` by the kernel, not listed here.

```
vendor/bin/wcnss_service                       # configures Pronto subsystem, loads NV data
vendor/bin/hw/android.hardware.wifi@1.0-service
vendor/bin/hw/wpa_supplicant                   # Qualcomm-patched wpa_supplicant for wcnss
vendor/bin/init.qcom.wifi.sh
vendor/lib/libwifi-hal-qcom.so
vendor/lib/libwifi-hal.so
vendor/lib/libcld80211.so                      # CLD80211 netlink interface
vendor/lib/libwpa_client.so
vendor/lib/vendor.qti.hardware.wifi.supplicant@1.0_vendor.so
vendor/lib/vendor.qti.hardware.wifi.supplicant@1.1_vendor.so
vendor/lib/libkeystore-engine-wifi-hidl.so     # keystore for WiFi cert auth
vendor/lib/libkeystore-wifi-hidl.so
```

### Bluetooth (Qualcomm SMD)

Qualcomm-specific BT implementation using SMD (Shared Memory Driver) transport to the Pronto subsystem. Needed for headset audio and BLE provisioning.

```
vendor/bin/hw/android.hardware.bluetooth@1.0-service-qti
vendor/bin/hci_qcomm_init                      # BT firmware download
vendor/bin/btnvtool                            # reads BT MAC from NV
vendor/bin/wcnss_filter                        # HCI filter for BT over SMD
vendor/lib/hw/android.hardware.bluetooth@1.0-impl-qti.so
vendor/lib/libbt-vendor.so
vendor/lib/libbt-hidlclient.so
vendor/lib/libbthost_if.so
vendor/lib/libbtnv.so
vendor/lib/com.qualcomm.qti.bluetooth_audio@1.0_vendor.so
```

### Thermal

Prevents SoC overheating. Reads thermal sensors, throttles CPU/GPU.

```
vendor/bin/thermal-engine
vendor/lib/libthermalclient.so
vendor/lib/libthermalioctl.so
```

### Qualcomm init scripts

Shell scripts encoding SoC-specific boot sequencing, sysfs configuration, and register settings. Technically readable/replaceable but encode critical platform knowledge.

```
vendor/bin/init.qcom.sh
vendor/bin/init.qcom.early_boot.sh
vendor/bin/init.qcom.post_boot.sh
vendor/bin/init.qcom.efs.sync.sh
vendor/bin/init.mdm.sh
vendor/bin/init.qcom.class_core.sh
vendor/bin/init.class_main.sh
vendor/bin/init.class_late.sh
vendor/bin/init.qcom.usb.sh
vendor/bin/init.qcom.crashdata.sh
vendor/bin/init.qcom.syspart_fixup.sh
```

### Connectivity engine (CNE)

Qualcomm network selection/management. May be needed for seamless WiFi↔4G handoff.

```
vendor/bin/cnd
vendor/lib/libcne.so
vendor/lib/libcneapiclient.so
vendor/lib/libcneoplookup.so
vendor/lib/libcneqmiutils.so
vendor/lib/com.quicinc.cne.api@1.0.so
vendor/lib/com.quicinc.cne.constants@1.0.so
vendor/lib/com.quicinc.cne.constants@2.0.so
vendor/lib/com.quicinc.cne.server@1.0.so
vendor/lib/com.quicinc.cne.server@2.0.so
```

### ADSP RPC

Communication with the Hexagon ADSP. Used by audio pipeline.

```
vendor/bin/adsprpcd
vendor/lib/libadsprpc.so
vendor/lib/libadsp_default_listener.so
```

### Data power manager (DPM)

Qualcomm data power management for 4G connections.

```
vendor/bin/dpmQmiMgr
vendor/lib/libdpmqmihal.so
vendor/lib/com.qualcomm.qti.dpm.api@1.0_vendor.so
vendor/lib/vendor.qti.hardware.data.latency@1.0_vendor.so
```

### Framework / HIDL infrastructure

```
vendor/lib/android.hidl.base@1.0.so
vendor/bin/hw/android.hardware.configstore@1.0-service
vendor/bin/hw/hal-server
vendor/bin/vndservice
vendor/bin/vndservicemanager
vendor/lib/liboemaids_vendor.so
vendor/lib/libselinux_vendor.so
```

### Subsystem restart / debugging

```
vendor/bin/ssr_diag
vendor/bin/ssr_setup
vendor/bin/subsystem_ramdump
vendor/bin/vm_bms                              # battery management service
vendor/bin/hvdcp_opti                          # high-voltage charger optimization
vendor/lib/libSubSystemShutdown.so
```

### Firmware partitions

Signed, run on co-processors. Cannot be reimplemented.

```
|RADIO:modem.bin:RADIO/modem.bin               # baseband firmware (Hexagon DSP)
|RADIO:tz.bin:RADIO/tz.bin                     # TrustZone firmware (ARM secure world)
|RADIO:rpm.bin:RADIO/rpm.bin                   # Resource Power Manager (Cortex-M3)
|RADIO:cmnlib.bin:RADIO/cmnlib.bin             # QSEE common library
|RADIO:devcfg.bin:RADIO/devcfg.bin             # device config for TZ/PIL
|RADIO:keymaster.bin:RADIO/keymaster.bin       # keymaster trustlet
```

---

## KEEP — Replaceable (AOSP/open-source alternatives exist, but low priority)

These could be replaced with open-source implementations eventually, but the stock blobs work and the effort isn't justified yet.

```
vendor/lib/hw/android.hardware.audio.effect@2.0-impl.so   # AOSP reference effects
vendor/lib/hw/android.hardware.health@1.0-impl.so         # AOSP health HAL
vendor/bin/hw/android.hardware.health@1.0-service
vendor/lib/hw/android.hardware.light@2.0-impl.so          # trivial sysfs GPIO — easy to rewrite
vendor/bin/hw/android.hardware.light@2.0-service
vendor/lib/hw/android.hardware.memtrack@1.0-impl.so       # AOSP stub
vendor/bin/hw/android.hardware.memtrack@1.0-service
vendor/lib/hw/android.hardware.power@1.0-impl.so          # sysfs governor control
vendor/bin/hw/android.hardware.power@1.0-service
vendor/lib/hw/android.hardware.renderscript@1.0-impl.so   # CPU fallback available
vendor/lib/hw/audio.primary.default.so                    # AOSP default audio
vendor/lib/hw/audio.r_submix.default.so                   # AOSP remote submix
vendor/lib/hw/power.default.so
vendor/lib/hw/power.qcom.so
vendor/lib/hw/local_time.default.so
vendor/lib/hw/memtrack.msm8909.so
vendor/lib/hw/lights.msm8909.so                           # GPIO sysfs — trivial
vendor/lib/libperfgluelayer.so                            # perf tuning — can stub
vendor/lib/libqti-gt-prop.so
vendor/lib/libqti-perfd-client.so
vendor/lib/libqti-perfd.so
vendor/lib/hw/vendor.qti.hardware.iop@1.0-impl.so
vendor/lib/vendor.qti.hardware.iop@1.0_vendor.so
vendor/lib/vendor.qti.hardware.iop@2.0_vendor.so
vendor/lib/vendor.qti.hardware.perf@1.0_vendor.so
vendor/bin/hw/vendor.qti.hardware.perf@1.0-service
vendor/lib/vendor.qti.hardware.alarm@1.0.so
vendor/lib/libalarmservice_jni.so
vendor/lib/vendor.qti.hardware.limits@1.0_vendor.so
vendor/lib/libqti-util.so
vendor/lib/libqti-utils.so
vendor/lib/libjson.so
vendor/lib/libtinyxml.so
vendor/lib/libtinyxml2_1.so
vendor/lib/libxml.so
vendor/lib/libsettings.so
vendor/lib/libfeedbackhandler.so
vendor/lib/libnbaio_mono.so
vendor/lib/libhwminijail.so
vendor/lib/libminijail_vendor.so
vendor/lib/libavservices_minijail_vendor.so
vendor/lib/libdrc.so
vendor/lib/libsmwrapper.so
vendor/lib/librecovery_updater_msm.so
vendor/lib/libevent_observer.so
vendor/lib/libdataitems.so
vendor/lib/libhypv_intercept.so
vendor/lib/libpvr.so
vendor/lib/libwms.so
vendor/lib/libwqe.so
vendor/lib/libqisl.so
vendor/lib/libstreamparser.so
```

### Vendor toybox/coreutils

These are vendor-partition copies of standard Unix utilities. AOSP provides them already. Harmless to keep, waste of space to ship.

```
vendor/bin/toolbox_vendor
vendor/bin/toybox_vendor
vendor/bin/acpi
vendor/bin/base64
vendor/bin/basename
vendor/bin/blockdev
vendor/bin/cal
vendor/bin/cat
vendor/bin/chcon
vendor/bin/chgrp
vendor/bin/chmod
vendor/bin/chown
vendor/bin/chroot
vendor/bin/chrt
vendor/bin/cksum
vendor/bin/clear
vendor/bin/cmp
vendor/bin/comm
vendor/bin/cp
vendor/bin/cpio
vendor/bin/cut
vendor/bin/date
vendor/bin/dd
vendor/bin/df
vendor/bin/diff
vendor/bin/dirname
vendor/bin/dmesg
vendor/bin/dos2unix
vendor/bin/du
vendor/bin/echo
vendor/bin/egrep
vendor/bin/env
vendor/bin/expand
vendor/bin/expr
vendor/bin/fallocate
vendor/bin/false
vendor/bin/fgrep
vendor/bin/file
vendor/bin/find
vendor/bin/flock
vendor/bin/free
vendor/bin/getenforce
vendor/bin/getevent
vendor/bin/getprop
vendor/bin/grep
vendor/bin/groups
vendor/bin/gunzip
vendor/bin/gzip
vendor/bin/head
vendor/bin/hostname
vendor/bin/id
vendor/bin/ifconfig
vendor/bin/inotifyd
vendor/bin/insmod
vendor/bin/ionice
vendor/bin/iorenice
vendor/bin/kill
vendor/bin/killall
vendor/bin/ln
vendor/bin/load_policy
vendor/bin/log
vendor/bin/logname
vendor/bin/losetup
vendor/bin/ls
vendor/bin/lsmod
vendor/bin/lsof
vendor/bin/lspci
vendor/bin/lsusb
vendor/bin/md5sum
vendor/bin/microcom
vendor/bin/mkdir
vendor/bin/mkfifo
vendor/bin/mknod
vendor/bin/mkswap
vendor/bin/mktemp
vendor/bin/modinfo
vendor/bin/modprobe
vendor/bin/more
vendor/bin/mount
vendor/bin/mountpoint
vendor/bin/mv
vendor/bin/netstat
vendor/bin/newfs_msdos
vendor/bin/nice
vendor/bin/nl
vendor/bin/nohup
vendor/bin/od
vendor/bin/paste
vendor/bin/patch
vendor/bin/pgrep
vendor/bin/pidof
vendor/bin/pkill
vendor/bin/pmap
vendor/bin/printenv
vendor/bin/printf
vendor/bin/ps
vendor/bin/pwd
vendor/bin/readlink
vendor/bin/realpath
vendor/bin/renice
vendor/bin/restorecon
vendor/bin/rm
vendor/bin/rmdir
vendor/bin/rmmod
vendor/bin/runcon
vendor/bin/sed
vendor/bin/sendevent
vendor/bin/seq
vendor/bin/setenforce
vendor/bin/setprop
vendor/bin/setsid
vendor/bin/sh
vendor/bin/sha1sum
vendor/bin/sha224sum
vendor/bin/sha256sum
vendor/bin/sha384sum
vendor/bin/sha512sum
vendor/bin/sleep
vendor/bin/sort
vendor/bin/split
vendor/bin/start
vendor/bin/stat
vendor/bin/stop
vendor/bin/strings
vendor/bin/swapoff
vendor/bin/swapon
vendor/bin/sync
vendor/bin/sysctl
vendor/bin/tac
vendor/bin/tail
vendor/bin/tar
vendor/bin/taskset
vendor/bin/tee
vendor/bin/time
vendor/bin/timeout
vendor/bin/top
vendor/bin/touch
vendor/bin/tr
vendor/bin/true
vendor/bin/truncate
vendor/bin/tty
vendor/bin/ulimit
vendor/bin/umount
vendor/bin/uname
vendor/bin/uniq
vendor/bin/unix2dos
vendor/bin/uptime
vendor/bin/usleep
vendor/bin/uudecode
vendor/bin/uuencode
vendor/bin/vmstat
vendor/bin/wc
vendor/bin/which
vendor/bin/whoami
vendor/bin/xargs
vendor/bin/xxd
vendor/bin/yes
vendor/bin/zcat
vendor/bin/hwclock
```

---

## DROP — Unnecessary for this device

### IMS / VoLTE (no voice calls)

```
vendor/bin/ims_rtp_daemon
vendor/bin/imsdatadaemon
vendor/bin/imsqmidaemon
vendor/bin/imsrcsd
vendor/bin/init.qti.ims.sh
vendor/lib/com.qualcomm.qti.imscmservice@1.0_vendor.so
vendor/lib/com.qualcomm.qti.imscmservice@1.1_vendor.so
vendor/lib/lib-dplmedia.so
vendor/lib/lib-imsSDP.so
vendor/lib/lib-imscmservice.so
vendor/lib/lib-imsdpl.so
vendor/lib/lib-imsqimf.so
vendor/lib/lib-imsrcs-v2.so
vendor/lib/lib-imsxml.so
vendor/lib/lib-rtpcommon.so
vendor/lib/lib-rtpcore.so
vendor/lib/lib-rtpdaemoninterface.so
vendor/lib/lib-rtpsl.so
vendor/lib/lib-siputility.so
vendor/lib/lib-uceservice.so
vendor/lib/vendor.qti.hardware.radio.am@1.0_vendor.so
vendor/lib/vendor.qti.hardware.radio.ims@1.0_vendor.so
vendor/lib/vendor.qti.hardware.radio.lpa@1.0_vendor.so
vendor/lib/vendor.qti.hardware.radio.uim_remote_client@1.0_vendor.so
vendor/lib/vendor.qti.hardware.radio.uim_remote_server@1.0_vendor.so
vendor/lib/vendor.qti.imsrtpservice@1.0-service-Impl.so
vendor/lib/vendor.qti.imsrtpservice@1.0_vendor.so
vendor/lib/lib_remote_simlock.so
|system/app/QtiTelephonyService/QtiTelephonyService.apk
```

### Video / media codecs (no video playback)

```
vendor/bin/hw/android.hardware.media.omx@1.0-service
vendor/lib/libOmxCore.so
vendor/lib/libOmxVdec.so
vendor/lib/libOmxVenc.so
vendor/lib/libOmxSwVdec.so
vendor/lib/libOmxSwVencMpeg4.so
vendor/lib/libOmxVpp.so
vendor/lib/libOmxAacDec.so
vendor/lib/libOmxAacEnc.so
vendor/lib/libOmxAlacDecSw.so
vendor/lib/libOmxAmrEnc.so
vendor/lib/libOmxApeDecSw.so
vendor/lib/libOmxDsdDec.so
vendor/lib/libOmxEvrcDec.so
vendor/lib/libOmxEvrcEnc.so
vendor/lib/libOmxG711Enc.so
vendor/lib/libOmxQcelp13Dec.so
vendor/lib/libOmxQcelp13Enc.so
vendor/lib/libMpeg4SwEncoder.so
vendor/lib/libstagefrighthw.so
vendor/lib/libmm-omxcore.so
vendor/lib/libc2dcolorconvert.so
vendor/lib/libI420colorconvert.so
vendor/lib/libmm-color-convertor.so
vendor/lib/libmediacodecservice.so
vendor/lib/libvideoutils.so
vendor/lib/libvpplibrary.so
vendor/lib/libvqzip.so
vendor/lib/libswvdec.so
vendor/lib/libAlacSwDec.so
vendor/lib/libApeSwDec.so
vendor/lib/libFlacSwDec.so
vendor/lib/libadpcmdec.so
vendor/lib/libdsd2pcm.so
vendor/bin/mm-vidc-omx-test
vendor/bin/mm-audio-ftm
vendor/bin/cplay
vendor/bin/audioflacapp
```

### DRM / HDCP (no media playback)

```
vendor/lib/hw/android.hardware.drm@1.0-impl.so
vendor/lib/libdrm.so
vendor/lib/libdrmfs.so
vendor/lib/libdrmtime.so
vendor/lib/libdrmutils.so
vendor/lib/libDRPlugin.so
vendor/lib/lib_drplugin_server.so
vendor/lib/libdrplugin_client.so
vendor/bin/DR_AP_Service
vendor/lib/libhdcp1prov.so
vendor/lib/libhdcp2p2prov.so
vendor/lib/libmm-hdcpmgr.so
vendor/bin/hdcp1prov
vendor/bin/hdcp2p2prov
vendor/lib/libSecureUILib.so
vendor/lib/libsecureui.so
vendor/lib/libsecureui_svcsock.so
vendor/lib/libStDrvInt.so
vendor/bin/secure_ui_sample_client
vendor/bin/qseecom_sample_client
vendor/bin/KmInstallKeybox
vendor/bin/tbaseLoader
```

### Camera (no hardware)

```
vendor/lib/libchromaflash.so
vendor/lib/liboptizoom.so
vendor/lib/libtrueportrait.so
vendor/lib/libubifocus.so
vendor/lib/libjpegdhw.so
vendor/lib/libjpegehw.so
vendor/lib/libmmjpeg.so
vendor/lib/libmmjpeg_interface.so
vendor/lib/libmmosal_proprietary.so
vendor/lib/libmmqjpeg_codec.so
vendor/lib/libqomx_core.so
vendor/lib/libqomx_jpegdec.so
vendor/lib/libqomx_jpegenc.so
vendor/lib/libmmipl.so
vendor/lib/libfastcvadsp_stub.so
vendor/lib/libfastcvopt.so
vendor/lib/libfastcrc.so
vendor/lib/libcalmodule_common.so
vendor/lib/libqtigef.so
```

All chromatix tuning libraries (~170 blobs):
```
vendor/lib/libchromatix_*                      # ISP tuning for cameras that don't exist
```

All actuator libraries (~30 blobs):
```
vendor/lib/libactuator_*                       # lens actuators for cameras that don't exist
```

### GPS / GNSS / Location (no hardware)

```
vendor/bin/hw/vendor.qti.gnss@1.0-service
vendor/bin/loc_launcher
vendor/bin/lowi-server
vendor/bin/xtra-daemon
vendor/bin/garden_app
vendor/bin/slim_daemon
vendor/lib/hw/android.hardware.gnss@1.0-impl-qti.so
vendor/lib/hw/vendor.qti.gnss@1.0-impl.so
vendor/lib/vendor.qti.gnss@1.0_vendor.so
vendor/lib/libflp.so
vendor/lib/libgeofence.so
vendor/lib/libgnss.so
vendor/lib/libgnsspps.so
vendor/lib/libgps.utils.so
vendor/lib/libgdtap.so
vendor/lib/libizat_client_api.so
vendor/lib/libizat_core.so
vendor/lib/liblbs_core.so
vendor/lib/libloc_api_v02.so
vendor/lib/libloc_core.so
vendor/lib/libloc_ds_api.so
vendor/lib/libloc_externalDr.so
vendor/lib/libloc_pla.so
vendor/lib/libloc_stub.so
vendor/lib/liblocation_api.so
vendor/lib/liblocationservice.so
vendor/lib/liblocationservice_glue.so
vendor/lib/liblowi_client.so
vendor/lib/liblowi_wifihal.so
vendor/lib/libquipc_os_api.so
vendor/lib/libslimclient.so
vendor/lib/libulp2.so
vendor/lib/libxtadapter.so
vendor/lib/libxtwifi_ulp_adaptor.so
```

### Sensors (no hardware)

```
vendor/bin/hal_proxy_daemon
vendor/bin/init.qcom.sensors.sh
vendor/lib/hw/android.hardware.sensors@1.0-impl.so
vendor/lib/sensor_calibrate.so
vendor/lib/sensors.native.so
vendor/lib/vendor.qti.hardware.sensorscalibrate@1.0.so
```

### Touchscreen (no hardware)

```
vendor/bin/hbtp_daemon
vendor/lib/libhbtpclient.so
vendor/lib/libhbtpdsp.so
vendor/lib/libhbtpfrmwk.so
vendor/lib/vendor.qti.hardware.improvetouch.blobmanager@1.0-service.so
vendor/lib/vendor.qti.hardware.improvetouch.blobmanager@1.0_vendor.so
vendor/lib/vendor.qti.hardware.improvetouch.gesturemanager@1.0-service.so
vendor/lib/vendor.qti.hardware.improvetouch.gesturemanager@1.0_vendor.so
vendor/lib/vendor.qti.hardware.improvetouch.touchcompanion@1.0-service.so
vendor/lib/vendor.qti.hardware.improvetouch.touchcompanion@1.0_vendor.so
```

### FM Radio (no hardware)

```
vendor/lib/hw/android.hardware.broadcastradio@1.0-impl.so
vendor/lib/vendor.qti.hardware.fm@1.0_vendor.so
vendor/bin/init.qti.fm.sh
```

### Sound trigger (no use case)

```
vendor/lib/hw/android.hardware.soundtrigger@2.0-impl.so
vendor/lib/hw/sound_trigger.primary.msm8909.so
vendor/lib/libsurround_3mic_proc.so
vendor/lib/libwebrtc_audio_preprocessing.so
```

### ANT+ / WiPower / VR / WiFi Display / Game mode

```
vendor/lib/hw/com.qualcomm.qti.ant@1.0-impl.so
vendor/lib/com.qualcomm.qti.ant@1.0_vendor.so
vendor/lib/vendor.qti.hardware.wipower@1.0_vendor.so
vendor/lib/libqvrservice_client.so
vendor/lib/com.qualcomm.qti.wifidisplayhal@1.0-impl.so
vendor/lib/com.qualcomm.qti.wifidisplayhal@1.0_vendor.so
vendor/lib/vendor.qti.voiceprint@1.0.so
vendor/bin/gamed
```

### Misc test/debug tools (not needed in production)

```
vendor/bin/PktRspTest
vendor/bin/WifiLogger_app
vendor/bin/athdiag
vendor/bin/diag_callback_sample
vendor/bin/diag_dci_sample
vendor/bin/diag_klog
vendor/bin/diag_mdlog
vendor/bin/diag_socket_log
vendor/bin/diag_uart_log
vendor/bin/e_loop
vendor/bin/fstman
vendor/bin/ftmdaemon
vendor/bin/icm
vendor/bin/qmi_simple_ril_test
vendor/bin/sigma_dut
vendor/bin/test_diag
vendor/bin/vendor_cmd_tool
vendor/bin/wdsdaemon
vendor/bin/init.crda.sh
vendor/bin/init.qcom.coex.sh
vendor/bin/init.qcom.sdio.sh
vendor/bin/qca6234-service.sh
vendor/bin/pm-proxy
vendor/bin/pm-service
vendor/lib/libdiagjni.so
vendor/lib/libril-qc-ltedirectdisc.so
vendor/lib/librmp.so
vendor/lib/libcdsprpc.so
vendor/lib/libmdsprpc.so
vendor/lib/libsdsprpc.so
vendor/lib/libfastrpc_utf_stub.so
```
