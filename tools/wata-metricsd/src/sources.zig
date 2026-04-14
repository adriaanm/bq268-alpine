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
    cell_up: ?bool = null,
    cell_rx: ?u64 = null,
    cell_tx: ?u64 = null,

    pub fn battStatus(self: *const Sample) ?[]const u8 {
        if (self.batt_status_len == 0) return null;
        return self.batt_status_buf[0..self.batt_status_len];
    }
};

/// Configuration for where to read sysfs from. `sysfs_root` is overridable
/// so tests can point at a fixture tree. Defaults match BQ268:
///   - cellular is PPP over SMD (see docs/modem_data.md), so `ppp0` when
///     up; there's no rmnet on this hardware
///   - the LCD backlight is exposed as a LED at
///     `/sys/class/leds/lcd-bl/brightness` (the same path used by
///     `screen-on.sh` / `screen-off.sh`), since this kernel has no
///     `/sys/class/backlight/` device for the panel
pub const Sources = struct {
    sysfs_root: []const u8 = "/sys",
    wlan_iface: []const u8 = "wlan0",
    cell_iface: []const u8 = "ppp0",
    /// Explicit /sys/class/backlight/<name> entry. Empty = auto-discover.
    backlight_name: []const u8 = "",
    /// Fallback LED path (under /sys/class/leds/<name>/brightness) when
    /// no /sys/class/backlight/ entry is found. Empty disables the fallback.
    led_backlight_name: []const u8 = "lcd-bl",

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

        const cl_op = std.fmt.bufPrint(&iface_buf, "class/net/{s}/operstate", .{self.cell_iface}) catch null;
        if (cl_op) |r| s.cell_up = readOperstate(&pb, self.sysfs_root, r);
        const cl_rx_rel = std.fmt.bufPrint(&iface_buf, "class/net/{s}/statistics/rx_bytes", .{self.cell_iface}) catch null;
        if (cl_rx_rel) |r| s.cell_rx = readUintAt(&pb, self.sysfs_root, r);
        const cl_tx_rel = std.fmt.bufPrint(&iface_buf, "class/net/{s}/statistics/tx_bytes", .{self.cell_iface}) catch null;
        if (cl_tx_rel) |r| s.cell_tx = readUintAt(&pb, self.sysfs_root, r);

        // Backlight: prefer /sys/class/backlight/, fall back to a LED path.
        // BQ268 has no backlight class device — the LCD backlight is wired
        // as /sys/class/leds/lcd-bl/brightness on this kernel.
        var bl_name_buf: [64]u8 = undefined;
        const bl_name: ?[]const u8 = if (self.backlight_name.len > 0)
            self.backlight_name
        else
            findFirstBacklight(&pb, self.sysfs_root, &bl_name_buf);
        if (bl_name) |name| {
            const bl_rel = std.fmt.bufPrint(&iface_buf, "class/backlight/{s}/brightness", .{name}) catch null;
            if (bl_rel) |r| s.bl = readIntAt(&pb, self.sysfs_root, r);
        }
        if (s.bl == null and self.led_backlight_name.len > 0) {
            const led_rel = std.fmt.bufPrint(&iface_buf, "class/leds/{s}/brightness", .{self.led_backlight_name}) catch null;
            if (led_rel) |r| s.bl = readIntAt(&pb, self.sysfs_root, r);
        }
        if (s.bl) |bl| s.screen_on = bl > 0;

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

    var dbuf: [1024]u8 align(@alignOf(linux.dirent64)) = undefined;
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
    if (std.mem.eql(u8, s, "up")) return true;
    // ppp_generic.c doesn't call netif_carrier_on/off so ppp0's
    // operstate is always "unknown" even when the link is fully up
    // and packets are flowing. Fall back to the carrier file — which
    // for PPP is set to 1 by ppp_channel_push once LCP completes and
    // the unit is attached to a channel. We derive the carrier path
    // from the operstate path by replacing "operstate" with "carrier".
    if (std.mem.eql(u8, s, "unknown") and std.mem.endsWith(u8, rel, "/operstate")) {
        const base = rel[0 .. rel.len - "operstate".len];
        var carrier_rel_buf: [256]u8 = undefined;
        const carrier_rel = std.fmt.bufPrint(&carrier_rel_buf, "{s}carrier", .{base}) catch return false;
        var cbuf: [8]u8 = undefined;
        const cs = readSmall(path_buf, root, carrier_rel, &cbuf) orelse return false;
        return std.mem.eql(u8, cs, "1");
    }
    return false;
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
    try std.testing.expectEqual(@as(?u64, null), s.cell_rx);
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

// --- fixture-based tests against a populated /tmp tree ---

const TestFixture = struct {
    root_buf: [256:0]u8 = undefined,
    root: [:0]const u8 = undefined,

    fn init(self: *TestFixture) !void {
        var ts: linux.timespec = undefined;
        _ = linux.clock_gettime(.REALTIME, &ts);
        const pid = linux.getpid();
        self.root = try std.fmt.bufPrintZ(
            &self.root_buf,
            "/tmp/wata-metricsd-fixture-{d}-{d}",
            .{ pid, ts.nsec },
        );
        try mkdirAt(self.root);
    }

    fn writeFile(self: *TestFixture, rel: []const u8, content: []const u8) !void {
        var pb: [512]u8 = undefined;
        // Make parent dirs.
        var i: usize = 0;
        while (i < rel.len) : (i += 1) {
            if (rel[i] == '/') {
                const dir_path = try std.fmt.bufPrintZ(
                    &pb,
                    "{s}/{s}",
                    .{ self.root, rel[0..i] },
                );
                try mkdirAt(dir_path);
            }
        }
        const full = try std.fmt.bufPrintZ(&pb, "{s}/{s}", .{ self.root, rel });
        const fd = try posix.openatZ(
            posix.AT.FDCWD,
            full,
            .{ .ACCMODE = .WRONLY, .CREAT = true, .TRUNC = true },
            0o644,
        );
        defer _ = linux.close(fd);
        var off: usize = 0;
        while (off < content.len) {
            const w = linux.write(fd, content.ptr + off, content.len - off);
            switch (linux.errno(w)) {
                .SUCCESS => off += w,
                .INTR => continue,
                else => return error.WriteFailed,
            }
        }
    }

    fn deinit(self: *TestFixture) void {
        // Best-effort: walk known files and remove, then the dirs we created.
        // Tests use a unique root so leaks from one test don't affect another.
        cleanup(self.root) catch {};
    }
};

fn mkdirAt(path: [*:0]const u8) !void {
    const rc = linux.mkdirat(linux.AT.FDCWD, path, 0o755);
    switch (linux.errno(rc)) {
        .SUCCESS, .EXIST => {},
        else => return error.MkdirFailed,
    }
}

fn cleanup(root: [:0]const u8) !void {
    // Walk root via getdents64 recursively; on this filesystem-tree size
    // (a handful of files) a small fixed buffer is plenty.
    try rmTreeRec(root);
    _ = linux.unlinkat(linux.AT.FDCWD, root, linux.AT.REMOVEDIR);
}

fn rmTreeRec(dir: [:0]const u8) !void {
    const fd = posix.openatZ(
        posix.AT.FDCWD,
        dir,
        .{ .ACCMODE = .RDONLY, .DIRECTORY = true },
        0,
    ) catch return;
    defer _ = linux.close(fd);

    var dbuf: [4096]u8 align(@alignOf(linux.dirent64)) = undefined;
    while (true) {
        const rc = linux.getdents64(fd, &dbuf, dbuf.len);
        switch (linux.errno(rc)) {
            .SUCCESS => {},
            else => return,
        }
        if (rc == 0) return;
        var off: usize = 0;
        while (off < rc) {
            const ent: *const linux.dirent64 = @ptrCast(@alignCast(&dbuf[off]));
            const name_off = @offsetOf(linux.dirent64, "name");
            const name_ptr: [*:0]const u8 = @ptrCast(&dbuf[off + name_off]);
            const name = std.mem.span(name_ptr);
            off += ent.reclen;
            if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

            var pb: [512]u8 = undefined;
            const child = try std.fmt.bufPrintZ(&pb, "{s}/{s}", .{ dir, name });
            // Try as file first; if EISDIR, recurse.
            const u = linux.unlinkat(linux.AT.FDCWD, child, 0);
            switch (linux.errno(u)) {
                .SUCCESS, .NOENT => {},
                .ISDIR, .PERM => {
                    try rmTreeRec(child);
                    _ = linux.unlinkat(linux.AT.FDCWD, child, linux.AT.REMOVEDIR);
                },
                else => {},
            }
        }
    }
}

test "Sources fixture: full BQ268-shaped tree populates all fields" {
    var fx = TestFixture{};
    try fx.init();
    defer fx.deinit();

    try fx.writeFile("class/power_supply/battery/voltage_now", "3821000\n");
    try fx.writeFile("class/power_supply/battery/current_now", "0\n");
    try fx.writeFile("class/power_supply/battery/capacity", "67\n");
    try fx.writeFile("class/power_supply/battery/status", "Discharging\n");
    try fx.writeFile("class/net/wlan0/operstate", "up\n");
    try fx.writeFile("class/net/wlan0/statistics/rx_bytes", "1234567\n");
    try fx.writeFile("class/net/wlan0/statistics/tx_bytes", "89012\n");
    try fx.writeFile("class/net/ppp0/operstate", "down\n");
    try fx.writeFile("class/net/ppp0/statistics/rx_bytes", "9876\n");
    try fx.writeFile("class/net/ppp0/statistics/tx_bytes", "4321\n");
    try fx.writeFile("class/backlight/panel0/brightness", "40\n");

    const sources = Sources{ .sysfs_root = fx.root };
    const s = sources.sample();

    try std.testing.expectEqual(@as(?i64, 3821000), s.v_uv);
    try std.testing.expectEqual(@as(?i64, 0), s.i_ua);
    try std.testing.expectEqual(@as(?i64, 67), s.capacity);
    try std.testing.expect(s.battStatus() != null);
    try std.testing.expectEqualStrings("Discharging", s.battStatus().?);
    try std.testing.expectEqual(@as(?i64, 40), s.bl);
    try std.testing.expectEqual(@as(?bool, true), s.screen_on);
    try std.testing.expectEqual(@as(?bool, true), s.wlan_up);
    try std.testing.expectEqual(@as(?u64, 1234567), s.wlan_rx);
    try std.testing.expectEqual(@as(?u64, 89012), s.wlan_tx);
    try std.testing.expectEqual(@as(?bool, false), s.cell_up);
    try std.testing.expectEqual(@as(?u64, 9876), s.cell_rx);
    try std.testing.expectEqual(@as(?u64, 4321), s.cell_tx);
}

test "Sources fixture: ppp0 operstate=unknown + carrier=1 → cell_up=true" {
    var fx = TestFixture{};
    try fx.init();
    defer fx.deinit();

    // ppp_generic.c leaves operstate at "unknown" even when the link is
    // fully up. cell_up should fall back to the carrier file.
    try fx.writeFile("class/net/ppp0/operstate", "unknown\n");
    try fx.writeFile("class/net/ppp0/carrier", "1\n");
    try fx.writeFile("class/net/ppp0/statistics/rx_bytes", "111\n");
    try fx.writeFile("class/net/ppp0/statistics/tx_bytes", "222\n");
    try fx.writeFile("class/leds/lcd-bl/brightness", "20\n");

    const sources = Sources{ .sysfs_root = fx.root };
    const s = sources.sample();
    try std.testing.expectEqual(@as(?bool, true), s.cell_up);
    try std.testing.expectEqual(@as(?u64, 111), s.cell_rx);
    try std.testing.expectEqual(@as(?u64, 222), s.cell_tx);
}

test "Sources fixture: ppp0 operstate=unknown + carrier=0 → cell_up=false" {
    var fx = TestFixture{};
    try fx.init();
    defer fx.deinit();

    try fx.writeFile("class/net/ppp0/operstate", "unknown\n");
    try fx.writeFile("class/net/ppp0/carrier", "0\n");
    try fx.writeFile("class/leds/lcd-bl/brightness", "20\n");

    const sources = Sources{ .sysfs_root = fx.root };
    const s = sources.sample();
    try std.testing.expectEqual(@as(?bool, false), s.cell_up);
}

test "Sources fixture: falls back to /sys/class/leds/lcd-bl when no backlight class" {
    var fx = TestFixture{};
    try fx.init();
    defer fx.deinit();

    // No /sys/class/backlight/ at all — only the LED path (matches BQ268).
    try fx.writeFile("class/leds/lcd-bl/brightness", "20\n");

    const sources = Sources{ .sysfs_root = fx.root };
    const s = sources.sample();

    try std.testing.expectEqual(@as(?i64, 20), s.bl);
    try std.testing.expectEqual(@as(?bool, true), s.screen_on);
}

test "Sources fixture: backlight auto-discovery picks first non-dotfile entry" {
    var fx = TestFixture{};
    try fx.init();
    defer fx.deinit();

    try fx.writeFile("class/backlight/fancy-pwm/brightness", "22\n");

    const sources = Sources{ .sysfs_root = fx.root }; // no explicit backlight_name
    const s = sources.sample();

    try std.testing.expectEqual(@as(?i64, 22), s.bl);
    try std.testing.expectEqual(@as(?bool, true), s.screen_on);
}

test "Sources fixture: bl=0 → screen_on=false" {
    var fx = TestFixture{};
    try fx.init();
    defer fx.deinit();

    try fx.writeFile("class/backlight/panel0/brightness", "0\n");

    const sources = Sources{ .sysfs_root = fx.root, .backlight_name = "panel0" };
    const s = sources.sample();

    try std.testing.expectEqual(@as(?i64, 0), s.bl);
    try std.testing.expectEqual(@as(?bool, false), s.screen_on);
}
