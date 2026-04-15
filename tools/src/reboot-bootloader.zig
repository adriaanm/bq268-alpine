//! reboot-bootloader — Reboot into fastboot/bootloader mode.
//!
//! Calls reboot(RESTART2, "bootloader") so the MSM restart handler
//! writes the IMEM magic (0x77665500) and does a warm reset.

const std = @import("std");
const linux = std.os.linux;

const LINUX_REBOOT_MAGIC1: u32 = 0xfee1dead;
const LINUX_REBOOT_MAGIC2: u32 = 0x28121969;
const LINUX_REBOOT_CMD_RESTART2: u32 = 0xa1b2c3d4;

pub fn main() u8 {
    _ = linux.syscall0(.sync);

    const arg = "bootloader";
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
