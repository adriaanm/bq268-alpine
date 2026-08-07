//! reboot-edl — Reboot into EDL (emergency download / 9008) mode.
//!
//! Calls reboot(RESTART2, "edl") so the MSM restart handler runs
//! enable_emergency_dload_mode(): it issues the SCM_EDLOAD_MODE call,
//! which on our board falls back to writing 0x01 to TCSR_BOOT_MISC_DETECT
//! (0x193d100, the PBL forced-download register — see the qcom,pshold node
//! in msm8909.dtsi), then the warm reset drops PBL into EDL.
//!
//! Note: msm8909.dtsi's qcom,msm-imem node has no emergency_download_mode
//! subnode, so the IMEM-magic path in enable_emergency_dload_mode() is
//! skipped; entry rides entirely on the TCSR write above.
//!
//! Unlike reboot-bootloader ("bootloader" → IMEM magic our own aboot reads),
//! this crosses into PBL/TZ. If it ever stops sticking, add the emergency
//! IMEM subnode to msm8909.dtsi.

const std = @import("std");
const linux = std.os.linux;

const LINUX_REBOOT_MAGIC1: u32 = 0xfee1dead;
const LINUX_REBOOT_MAGIC2: u32 = 0x28121969;
const LINUX_REBOOT_CMD_RESTART2: u32 = 0xa1b2c3d4;

pub fn main() u8 {
    _ = linux.syscall0(.sync);

    const arg = "edl";
    const rc = linux.syscall4(
        .reboot,
        LINUX_REBOOT_MAGIC1,
        LINUX_REBOOT_MAGIC2,
        LINUX_REBOOT_CMD_RESTART2,
        @intFromPtr(arg.ptr),
    );

    // reboot() does not return on success.
    const signed: isize = @bitCast(rc);
    const errno: linux.E = @enumFromInt(@as(u16, @intCast(-signed)));
    std.debug.print("reboot: {s}\n", .{@tagName(errno)});
    return 1;
}
