const std = @import("std");
const protocol = @import("protocol.zig");

pub fn main() !void {
    const stderr = std.debug;
    stderr.print("wata-metricsd v0.1.0 starting\n", .{});
    stderr.print("  tick socket: {s}\n", .{protocol.SOCKET_PATH});
    stderr.print("  tick size:   {d} bytes\n", .{protocol.TICK_SIZE});
    stderr.print("not yet implemented: event loop\n", .{});
    return error.NotImplemented;
}
