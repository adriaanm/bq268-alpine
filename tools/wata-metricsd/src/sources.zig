const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;

/// One metric sample. All numeric/bool fields are optional — a missing
/// sysfs file or a parse failure becomes `null`, never an error.
/// `batt_status` is stored inline (no allocator) and exposed via
/// `battStatus()` which returns null when empty.
pub const Sample = struct {
    ts_mono_ns: u64,
    ts_wall_ns: u64,
    v_uv: ?i64 = null,
    i_ua: ?i64 = null,
    capacity: ?i64 = null,
    batt_status_buf: [16]u8 = undefined,
    batt_status_len: u8 = 0,
    bl: ?i64 = null,
    screen_on: ?bool = null,
    wlan_up: ?bool = null,
    wlan_rx: ?u64 = null,
    wlan_tx: ?u64 = null,
    rmnet_up: ?bool = null,
    rmnet_rx: ?u64 = null,
    rmnet_tx: ?u64 = null,

    pub fn battStatus(self: *const Sample) ?[]const u8 {
        if (self.batt_status_len == 0) return null;
        return self.batt_status_buf[0..self.batt_status_len];
    }
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
        s.batt_status_len = readStrInto(
            &pb,
            self.sysfs_root,
            "class/power_supply/battery/status",
            &s.batt_status_buf,
        );

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

        var bl_name_buf: [64]u8 = undefined;
        const bl_name: ?[]const u8 = if (self.backlight_name.len > 0)
            self.backlight_name
        else
            findFirstBacklight(&pb, self.sysfs_root, &bl_name_buf);
        if (bl_name) |name| {
            const bl_rel = std.fmt.bufPrint(&iface_buf, "class/backlight/{s}/brightness", .{name}) catch null;
            if (bl_rel) |r| s.bl = readIntAt(&pb, self.sysfs_root, r);
            if (s.bl) |bl| s.screen_on = bl > 0;
        }

        return s;
    }
};

/// Read the first directory entry under `<root>/class/backlight/` whose
/// name doesn't start with '.'. Copies the name into `name_buf` and
/// returns a slice of it, or null if the dir is missing or empty.
fn findFirstBacklight(path_buf: []u8, root: []const u8, name_buf: []u8) ?[]const u8 {
    const dir_path = std.fmt.bufPrintZ(path_buf, "{s}/class/backlight", .{root}) catch return null;
    const fd = posix.openatZ(
        posix.AT.FDCWD,
        dir_path,
        .{ .ACCMODE = .RDONLY, .DIRECTORY = true },
        0,
    ) catch return null;
    defer _ = linux.close(fd);

    var dbuf: [1024]u8 = undefined;
    const rc = linux.getdents64(fd, &dbuf, dbuf.len);
    switch (linux.errno(rc)) {
        .SUCCESS => {},
        else => return null,
    }
    if (rc == 0) return null;

    var off: usize = 0;
    while (off < rc) {
        const ent: *const linux.dirent64 = @ptrCast(@alignCast(&dbuf[off]));
        const name_off = @offsetOf(linux.dirent64, "name");
        const name_ptr: [*:0]const u8 = @ptrCast(&dbuf[off + name_off]);
        const name = std.mem.span(name_ptr);
        off += ent.reclen;
        if (name.len == 0 or name[0] == '.') continue;
        if (name.len > name_buf.len) continue;
        @memcpy(name_buf[0..name.len], name);
        return name_buf[0..name.len];
    }
    return null;
}

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

/// Read a sysfs string into `out`, returning the number of bytes copied
/// (after trimming). Returns 0 on any error.
fn readStrInto(path_buf: []u8, root: []const u8, rel: []const u8, out: []u8) u8 {
    var tmp: [64]u8 = undefined;
    const s = readSmall(path_buf, root, rel, &tmp) orelse return 0;
    const n = @min(s.len, out.len);
    @memcpy(out[0..n], s[0..n]);
    return @intCast(n);
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
    try std.testing.expectEqual(@as(?[]const u8, null), s.battStatus());
    try std.testing.expect(s.ts_mono_ns > 0);
}

test "Sample.battStatus returns null when empty, slice when populated" {
    var s = Sample{ .ts_mono_ns = 1, .ts_wall_ns = 2 };
    try std.testing.expectEqual(@as(?[]const u8, null), s.battStatus());

    const v = "Charging";
    @memcpy(s.batt_status_buf[0..v.len], v);
    s.batt_status_len = v.len;
    try std.testing.expect(s.battStatus() != null);
    try std.testing.expectEqualStrings("Charging", s.battStatus().?);
}
