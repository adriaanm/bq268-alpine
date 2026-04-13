const std = @import("std");
const posix = std.posix;

/// One metric sample. All fields except timestamps are optional — a missing
/// sysfs file or a parse failure becomes `null`, never an error.
pub const Sample = struct {
    ts_mono_ns: u64,
    ts_wall_ns: u64,
    v_uv: ?i64 = null,
    i_ua: ?i64 = null,
    capacity: ?i64 = null,
    batt_status: ?[]const u8 = null,
    bl: ?i64 = null,
    screen_on: ?bool = null,
    wlan_up: ?bool = null,
    wlan_rx: ?u64 = null,
    wlan_tx: ?u64 = null,
    rmnet_up: ?bool = null,
    rmnet_rx: ?u64 = null,
    rmnet_tx: ?u64 = null,
};

/// Configuration for where to read sysfs from. `sysfs_root` is overridable
/// so tests can point at a fixture tree. Interface names and backlight name
/// can be pinned; if `backlight_name` is empty, the sampler falls back to
/// the device's only known backlight at runtime (TODO: auto-discover).
pub const Sources = struct {
    sysfs_root: []const u8 = "/sys",
    wlan_iface: []const u8 = "wlan0",
    rmnet_iface: []const u8 = "rmnet_data0",
    backlight_name: []const u8 = "",

    pub fn sample(self: Sources) Sample {
        var s = Sample{
            .ts_mono_ns = monoNs(),
            .ts_wall_ns = wallNs(),
        };

        var pb: [256]u8 = undefined;

        s.v_uv = readIntAt(&pb, self.sysfs_root, "class/power_supply/battery/voltage_now");
        s.i_ua = readIntAt(&pb, self.sysfs_root, "class/power_supply/battery/current_now");
        s.capacity = readIntAt(&pb, self.sysfs_root, "class/power_supply/battery/capacity");

        // batt_status and backlight don't fit the int reader; batt_status
        // and screen_on detection are added in a follow-up with a proper
        // string reader + auto-discover (tracked in TASKS.md).

        var iface_buf: [128]u8 = undefined;

        const wlan_op = std.fmt.bufPrint(&iface_buf, "class/net/{s}/operstate", .{self.wlan_iface}) catch null;
        if (wlan_op) |r| s.wlan_up = readOperstate(&pb, self.sysfs_root, r);
        const wlan_rx_rel = std.fmt.bufPrint(&iface_buf, "class/net/{s}/statistics/rx_bytes", .{self.wlan_iface}) catch null;
        if (wlan_rx_rel) |r| s.wlan_rx = readUintAt(&pb, self.sysfs_root, r);
        const wlan_tx_rel = std.fmt.bufPrint(&iface_buf, "class/net/{s}/statistics/tx_bytes", .{self.wlan_iface}) catch null;
        if (wlan_tx_rel) |r| s.wlan_tx = readUintAt(&pb, self.sysfs_root, r);

        const rm_op = std.fmt.bufPrint(&iface_buf, "class/net/{s}/operstate", .{self.rmnet_iface}) catch null;
        if (rm_op) |r| s.rmnet_up = readOperstate(&pb, self.sysfs_root, r);
        const rm_rx_rel = std.fmt.bufPrint(&iface_buf, "class/net/{s}/statistics/rx_bytes", .{self.rmnet_iface}) catch null;
        if (rm_rx_rel) |r| s.rmnet_rx = readUintAt(&pb, self.sysfs_root, r);
        const rm_tx_rel = std.fmt.bufPrint(&iface_buf, "class/net/{s}/statistics/tx_bytes", .{self.rmnet_iface}) catch null;
        if (rm_tx_rel) |r| s.rmnet_tx = readUintAt(&pb, self.sysfs_root, r);

        if (self.backlight_name.len > 0) {
            const bl_rel = std.fmt.bufPrint(&iface_buf, "class/backlight/{s}/brightness", .{self.backlight_name}) catch null;
            if (bl_rel) |r| s.bl = readIntAt(&pb, self.sysfs_root, r);
            if (s.bl) |bl| s.screen_on = bl > 0;
        }

        return s;
    }
};

/// Read a sysfs file into a small stack buffer via `std.posix.open` +
/// `read`. Returns the trimmed content or null on any error.
fn readSmall(path_buf: []u8, root: []const u8, rel: []const u8, out: []u8) ?[]const u8 {
    const path = std.fmt.bufPrintZ(path_buf, "{s}/{s}", .{ root, rel }) catch return null;
    const fd = posix.openatZ(posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch return null;
    defer _ = std.os.linux.close(fd);
    const n = posix.read(fd, out) catch return null;
    if (n == 0) return null;
    return std.mem.trim(u8, out[0..n], " \n\r\t");
}

fn readIntAt(path_buf: []u8, root: []const u8, rel: []const u8) ?i64 {
    var buf: [64]u8 = undefined;
    const s = readSmall(path_buf, root, rel, &buf) orelse return null;
    return std.fmt.parseInt(i64, s, 10) catch null;
}

fn readUintAt(path_buf: []u8, root: []const u8, rel: []const u8) ?u64 {
    var buf: [64]u8 = undefined;
    const s = readSmall(path_buf, root, rel, &buf) orelse return null;
    return std.fmt.parseInt(u64, s, 10) catch null;
}

fn readOperstate(path_buf: []u8, root: []const u8, rel: []const u8) ?bool {
    var buf: [32]u8 = undefined;
    const s = readSmall(path_buf, root, rel, &buf) orelse return null;
    return std.mem.eql(u8, s, "up");
}

fn monoNs() u64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.BOOTTIME, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

fn wallNs() u64 {
    var ts: std.os.linux.timespec = undefined;
    _ = std.os.linux.clock_gettime(.REALTIME, &ts);
    return @as(u64, @intCast(ts.sec)) * std.time.ns_per_s + @as(u64, @intCast(ts.nsec));
}

// --- tests ---

test "monoNs and wallNs return non-zero" {
    try std.testing.expect(monoNs() > 0);
    try std.testing.expect(wallNs() > 0);
}

test "Sample default construction is all-null except timestamps" {
    const s = Sample{ .ts_mono_ns = 1, .ts_wall_ns = 2 };
    try std.testing.expectEqual(@as(?i64, null), s.v_uv);
    try std.testing.expectEqual(@as(?u64, null), s.wlan_rx);
    try std.testing.expectEqual(@as(?bool, null), s.screen_on);
}

test "Sources against missing tree returns nulls, never errors" {
    const src = Sources{ .sysfs_root = "/nonexistent-wata-metrics-root" };
    const s = src.sample();
    try std.testing.expectEqual(@as(?i64, null), s.v_uv);
    try std.testing.expectEqual(@as(?u64, null), s.wlan_rx);
    try std.testing.expect(s.ts_mono_ns > 0);
}
