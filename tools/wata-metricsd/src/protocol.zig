const std = @import("std");

pub const TICK_SIZE: usize = 16;
pub const SOCKET_PATH = "/run/wata.tick";

pub const Phase = enum(u8) {
    post_poll = 0,
    _,
};

pub const Tick = extern struct {
    ts_mono_ns: u64,
    seq: u32,
    phase: u8,
    _reserved: [3]u8 = .{ 0, 0, 0 },

    comptime {
        if (@sizeOf(Tick) != TICK_SIZE) @compileError("Tick must be 16 bytes");
    }

    pub fn decode(buf: []const u8) !Tick {
        if (buf.len != TICK_SIZE) return error.WrongSize;
        return .{
            .ts_mono_ns = std.mem.readInt(u64, buf[0..8], .little),
            .seq = std.mem.readInt(u32, buf[8..12], .little),
            .phase = buf[12],
        };
    }

    pub fn encode(self: Tick, buf: *[TICK_SIZE]u8) void {
        std.mem.writeInt(u64, buf[0..8], self.ts_mono_ns, .little);
        std.mem.writeInt(u32, buf[8..12], self.seq, .little);
        buf[12] = self.phase;
        buf[13] = 0;
        buf[14] = 0;
        buf[15] = 0;
    }
};

test "Tick size is exactly 16 bytes" {
    try std.testing.expectEqual(@as(usize, 16), @sizeOf(Tick));
    try std.testing.expectEqual(@as(usize, 16), TICK_SIZE);
}

test "Tick encode/decode roundtrip" {
    const original = Tick{
        .ts_mono_ns = 0x0123456789abcdef,
        .seq = 0xdeadbeef,
        .phase = @intFromEnum(Phase.post_poll),
    };
    var buf: [TICK_SIZE]u8 = undefined;
    original.encode(&buf);
    const decoded = try Tick.decode(&buf);
    try std.testing.expectEqual(original.ts_mono_ns, decoded.ts_mono_ns);
    try std.testing.expectEqual(original.seq, decoded.seq);
    try std.testing.expectEqual(original.phase, decoded.phase);
}

test "Tick decode rejects wrong size" {
    const short = [_]u8{0} ** 8;
    try std.testing.expectError(error.WrongSize, Tick.decode(&short));
    const long = [_]u8{0} ** 32;
    try std.testing.expectError(error.WrongSize, Tick.decode(&long));
}

test "Tick encode is little-endian" {
    const t = Tick{ .ts_mono_ns = 1, .seq = 1, .phase = 0 };
    var buf: [TICK_SIZE]u8 = undefined;
    t.encode(&buf);
    try std.testing.expectEqual(@as(u8, 1), buf[0]);
    try std.testing.expectEqual(@as(u8, 0), buf[1]);
    try std.testing.expectEqual(@as(u8, 1), buf[8]);
    try std.testing.expectEqual(@as(u8, 0), buf[9]);
}
