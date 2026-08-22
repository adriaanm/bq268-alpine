const std = @import("std");
const Sample = @import("sources.zig").Sample;

pub const Source = enum {
    tick,
    watchdog,
    both,

    pub fn str(self: Source) []const u8 {
        return switch (self) {
            .tick => "tick",
            .watchdog => "watchdog",
            .both => "both",
        };
    }
};

pub const Record = struct {
    sample: Sample,
    src: Source,
    seq: u32,
    ticks_coalesced: u32,
    dt_ns: u64,
};

const BufWriter = struct {
    buf: []u8,
    len: usize = 0,

    fn print(self: *BufWriter, comptime fmt: []const u8, args: anytype) !void {
        const slice = try std.fmt.bufPrint(self.buf[self.len..], fmt, args);
        self.len += slice.len;
    }
    fn writeAll(self: *BufWriter, bytes: []const u8) !void {
        if (self.len + bytes.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.len..][0..bytes.len], bytes);
        self.len += bytes.len;
    }
};

/// Format a record as a single line of JSONL (including the trailing '\n').
/// Returns a slice into `out` on success, or `error.NoSpaceLeft`.
/// Pure — no allocation, no I/O. `out` should be at least 512 bytes.
pub fn format(out: []u8, rec: Record) ![]const u8 {
    var w = BufWriter{ .buf = out };
    try w.writeAll("{");
    try w.print("\"ts_mono_ns\":{d}", .{rec.sample.ts_mono_ns});
    try w.print(",\"ts_wall_ns\":{d}", .{rec.sample.ts_wall_ns});
    try w.print(",\"src\":\"{s}\"", .{rec.src.str()});
    try w.print(",\"seq\":{d}", .{rec.seq});
    try w.print(",\"ticks_coalesced\":{d}", .{rec.ticks_coalesced});
    try w.print(",\"dt_ns\":{d}", .{rec.dt_ns});
    try writeOptI64(&w, "v_uv", rec.sample.v_uv);
    try writeOptI64(&w, "i_ua", rec.sample.i_ua);
    try writeOptI64(&w, "capacity", rec.sample.capacity);
    try writeOptStr(&w, "batt_status", rec.sample.battStatus());
    try writeOptI64(&w, "bl", rec.sample.bl);
    try writeOptBool(&w, "screen_on", rec.sample.screen_on);
    try writeOptBool(&w, "wlan_up", rec.sample.wlan_up);
    try writeOptU64(&w, "wlan_rx", rec.sample.wlan_rx);
    try writeOptU64(&w, "wlan_tx", rec.sample.wlan_tx);
    try writeOptBool(&w, "cell_up", rec.sample.cell_up);
    try writeOptU64(&w, "cell_rx", rec.sample.cell_rx);
    try writeOptU64(&w, "cell_tx", rec.sample.cell_tx);
    try writeOptBool(&w, "usb_online", rec.sample.usb_online);
    try writeOptI64(&w, "usb_ma", rec.sample.usb_ma);
    try writeOptU64(&w, "fastchg_irqs", rec.sample.fastchg_irqs);
    try writeOptU64(&w, "usbin_irqs", rec.sample.usbin_irqs);
    try writeOptU64(&w, "chggone_irqs", rec.sample.chggone_irqs);
    try w.writeAll("}\n");
    return w.buf[0..w.len];
}

fn writeOptI64(w: *BufWriter, key: []const u8, v: ?i64) !void {
    if (v) |x| try w.print(",\"{s}\":{d}", .{ key, x });
}
fn writeOptU64(w: *BufWriter, key: []const u8, v: ?u64) !void {
    if (v) |x| try w.print(",\"{s}\":{d}", .{ key, x });
}
fn writeOptBool(w: *BufWriter, key: []const u8, v: ?bool) !void {
    if (v) |x| try w.print(",\"{s}\":{s}", .{ key, if (x) "true" else "false" });
}
fn writeOptStr(w: *BufWriter, key: []const u8, v: ?[]const u8) !void {
    if (v) |x| try w.print(",\"{s}\":\"{s}\"", .{ key, x }); // no escaping: sysfs values are ASCII-safe
}

// --- tests ---

test "format emits mandatory fields and trailing newline" {
    var buf: [512]u8 = undefined;
    const rec = Record{
        .sample = .{ .ts_mono_ns = 123, .ts_wall_ns = 456 },
        .src = .tick,
        .seq = 42,
        .ticks_coalesced = 3,
        .dt_ns = 987,
    };
    const line = try format(&buf, rec);
    try std.testing.expect(std.mem.endsWith(u8, line, "}\n"));
    try std.testing.expect(std.mem.indexOf(u8, line, "\"ts_mono_ns\":123") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"src\":\"tick\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"seq\":42") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"dt_ns\":987") != null);
    // optional fields omitted when null
    try std.testing.expect(std.mem.indexOf(u8, line, "v_uv") == null);
    try std.testing.expect(std.mem.indexOf(u8, line, "screen_on") == null);
}

test "format emits optional fields when present" {
    var buf: [1024]u8 = undefined;
    var sample = Sample{
        .ts_mono_ns = 1,
        .ts_wall_ns = 2,
        .v_uv = 3821000,
        .i_ua = 0,
        .capacity = 67,
        .bl = 40,
        .screen_on = true,
        .wlan_up = true,
        .wlan_rx = 1234567,
        .wlan_tx = 89012,
        .cell_up = false,
        .cell_rx = 9876,
        .cell_tx = 4321,
        .usb_online = true,
        .usb_ma = 1500,
        .fastchg_irqs = 7,
        .usbin_irqs = 13,
        .chggone_irqs = 0,
    };
    const status = "Discharging";
    @memcpy(sample.batt_status_buf[0..status.len], status);
    sample.batt_status_len = status.len;
    const rec = Record{
        .sample = sample,
        .src = .watchdog,
        .seq = 0,
        .ticks_coalesced = 0,
        .dt_ns = 30000000000,
    };
    const line = try format(&buf, rec);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"v_uv\":3821000") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"i_ua\":0") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"batt_status\":\"Discharging\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"screen_on\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"cell_up\":false") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"src\":\"watchdog\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"wlan_rx\":1234567") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"usb_online\":true") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"usb_ma\":1500") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"fastchg_irqs\":7") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"usbin_irqs\":13") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "\"chggone_irqs\":0") != null);
}

test "format omits charge-path fields when null" {
    var buf: [512]u8 = undefined;
    const rec = Record{
        .sample = .{ .ts_mono_ns = 1, .ts_wall_ns = 2 },
        .src = .tick,
        .seq = 1,
        .ticks_coalesced = 1,
        .dt_ns = 1,
    };
    const line = try format(&buf, rec);
    try std.testing.expect(std.mem.indexOf(u8, line, "usb_online") == null);
    try std.testing.expect(std.mem.indexOf(u8, line, "usb_ma") == null);
    try std.testing.expect(std.mem.indexOf(u8, line, "fastchg_irqs") == null);
}

test "format returns BufferTooSmall on undersized buffer" {
    var tiny: [16]u8 = undefined;
    const rec = Record{
        .sample = .{ .ts_mono_ns = 1, .ts_wall_ns = 2 },
        .src = .tick,
        .seq = 1,
        .ticks_coalesced = 1,
        .dt_ns = 1,
    };
    try std.testing.expectError(error.NoSpaceLeft, format(&tiny, rec));
}
