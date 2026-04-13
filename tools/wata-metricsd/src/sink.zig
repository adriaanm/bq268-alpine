//! JSONL file sink: append lines to `<dir>/current.jsonl`, rotate by size
//! into `current.jsonl.1` .. `.N` dropping the oldest. All file I/O uses
//! raw linux syscalls (via std.posix where available, std.os.linux
//! otherwise) — std.Io / std.Io.Dir in Zig 0.16-dev is heavier than what
//! this module needs.

const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;

pub const DEFAULT_MAX_BYTES: u64 = 1 * 1024 * 1024; // 1 MiB
pub const DEFAULT_KEEP: u8 = 4;

pub const Sink = struct {
    dir: [:0]const u8, // null-terminated dir path, caller-owned
    max_bytes: u64,
    keep: u8,
    fd: linux.fd_t,
    written: u64,

    pub const OpenError = error{
        MkdirFailed,
        OpenFailed,
        RotateFailed,
    };

    /// Ensure `dir` exists, rotate any existing `current.jsonl` into `.1`
    /// (shifting older files), and open a fresh `current.jsonl`.
    /// Rotating on startup keeps boot-cycle boundaries visible in the logs.
    pub fn open(dir: [:0]const u8, max_bytes: u64, keep: u8) OpenError!Sink {
        try mkdirP(dir);

        // Rotate on startup so the current boot starts with a clean file.
        rotate(dir, keep) catch return error.RotateFailed;

        const fd = openCurrent(dir) catch return error.OpenFailed;
        return .{
            .dir = dir,
            .max_bytes = max_bytes,
            .keep = keep,
            .fd = fd,
            .written = 0,
        };
    }

    pub fn close(self: *Sink) void {
        _ = linux.close(self.fd);
        self.fd = -1;
    }

    pub fn write(self: *Sink, line: []const u8) !void {
        try writeAll(self.fd, line);
        self.written += line.len;
        if (self.written >= self.max_bytes) {
            _ = linux.close(self.fd);
            rotate(self.dir, self.keep) catch {};
            self.fd = openCurrent(self.dir) catch return error.ReopenFailed;
            self.written = 0;
        }
    }
};

fn mkdirP(dir: [:0]const u8) Sink.OpenError!void {
    // Best-effort recursive mkdir — walk up components and create each.
    // For our use case `dir` is either /var/log/metrics or a test path,
    // at most 3-4 levels deep.
    var i: usize = 1;
    while (i <= dir.len) : (i += 1) {
        if (i == dir.len or dir[i] == '/') {
            if (i == 0) continue;
            var tmp: [256]u8 = undefined;
            if (i >= tmp.len) return error.MkdirFailed;
            @memcpy(tmp[0..i], dir[0..i]);
            tmp[i] = 0;
            const z: [*:0]const u8 = @ptrCast(&tmp);
            const rc = linux.mkdirat(linux.AT.FDCWD, z, 0o755);
            switch (linux.errno(rc)) {
                .SUCCESS, .EXIST => {},
                else => return error.MkdirFailed,
            }
        }
    }
}

fn openCurrent(dir: [:0]const u8) !linux.fd_t {
    var path_buf: [512]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&path_buf, "{s}/current.jsonl", .{dir});
    const fd = try posix.openatZ(
        posix.AT.FDCWD,
        path,
        .{
            .ACCMODE = .WRONLY,
            .CREAT = true,
            .APPEND = true,
            .CLOEXEC = true,
        },
        0o644,
    );
    return fd;
}

fn rotate(dir: [:0]const u8, keep: u8) !void {
    if (keep == 0) return;
    // Drop the oldest: unlink current.jsonl.<keep>
    try unlinkIfExists(dir, keep);

    // Shift: current.jsonl.<n-1> -> current.jsonl.<n> for n = keep..2
    var n: u8 = keep;
    while (n > 1) : (n -= 1) {
        try renameIfExists(dir, n - 1, n);
    }

    // current.jsonl -> current.jsonl.1
    try renameCurrentTo1(dir);
}

fn unlinkIfExists(dir: [:0]const u8, idx: u8) !void {
    var buf: [512]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&buf, "{s}/current.jsonl.{d}", .{ dir, idx });
    const rc = linux.unlinkat(linux.AT.FDCWD, path, 0);
    switch (linux.errno(rc)) {
        .SUCCESS, .NOENT => {},
        else => return error.UnlinkFailed,
    }
}

fn renameIfExists(dir: [:0]const u8, from_idx: u8, to_idx: u8) !void {
    var fb: [512]u8 = undefined;
    var tb: [512]u8 = undefined;
    const from = try std.fmt.bufPrintZ(&fb, "{s}/current.jsonl.{d}", .{ dir, from_idx });
    const to = try std.fmt.bufPrintZ(&tb, "{s}/current.jsonl.{d}", .{ dir, to_idx });
    const rc = linux.renameat(linux.AT.FDCWD, from, linux.AT.FDCWD, to);
    switch (linux.errno(rc)) {
        .SUCCESS, .NOENT => {},
        else => return error.RenameFailed,
    }
}

fn renameCurrentTo1(dir: [:0]const u8) !void {
    var fb: [512]u8 = undefined;
    var tb: [512]u8 = undefined;
    const from = try std.fmt.bufPrintZ(&fb, "{s}/current.jsonl", .{dir});
    const to = try std.fmt.bufPrintZ(&tb, "{s}/current.jsonl.1", .{dir});
    const rc = linux.renameat(linux.AT.FDCWD, from, linux.AT.FDCWD, to);
    switch (linux.errno(rc)) {
        .SUCCESS, .NOENT => {},
        else => return error.RenameFailed,
    }
}

fn writeAll(fd: linux.fd_t, bytes: []const u8) !void {
    var off: usize = 0;
    while (off < bytes.len) {
        const rc = linux.write(fd, bytes.ptr + off, bytes.len - off);
        switch (linux.errno(rc)) {
            .SUCCESS => off += rc,
            .INTR => continue,
            else => return error.WriteFailed,
        }
    }
}

fn fileSize(dir: [:0]const u8, name: []const u8) !u64 {
    var buf: [512]u8 = undefined;
    const path = try std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ dir, name });
    const fd = try posix.openatZ(posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0);
    defer _ = linux.close(fd);
    const end = linux.lseek(fd, 0, linux.SEEK.END);
    switch (linux.errno(end)) {
        .SUCCESS => return end,
        else => return error.SeekFailed,
    }
}

fn exists(dir: [:0]const u8, name: []const u8) bool {
    var buf: [512]u8 = undefined;
    const path = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ dir, name }) catch return false;
    const fd = posix.openatZ(posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch return false;
    _ = linux.close(fd);
    return true;
}

// --- tests ---

fn uniqueTmpDir(buf: *[256:0]u8) ![:0]const u8 {
    var ts: linux.timespec = undefined;
    _ = linux.clock_gettime(.REALTIME, &ts);
    const pid = linux.getpid();
    const slice = try std.fmt.bufPrintZ(
        buf,
        "/tmp/wata-metricsd-test-{d}-{d}",
        .{ pid, ts.nsec },
    );
    return slice;
}

fn rmTree(dir: [:0]const u8) void {
    var buf: [512]u8 = undefined;
    // Best-effort: unlink the files we know we might have created.
    const names = [_][]const u8{
        "current.jsonl",
        "current.jsonl.1",
        "current.jsonl.2",
        "current.jsonl.3",
        "current.jsonl.4",
    };
    for (names) |n| {
        const path = std.fmt.bufPrintZ(&buf, "{s}/{s}", .{ dir, n }) catch continue;
        _ = linux.unlinkat(linux.AT.FDCWD, path, 0);
    }
    _ = linux.unlinkat(linux.AT.FDCWD, dir, linux.AT.REMOVEDIR);
}

test "Sink: write then rotate on size threshold" {
    var dir_buf: [256:0]u8 = undefined;
    const dir = try uniqueTmpDir(&dir_buf);
    defer rmTree(dir);

    var sink = try Sink.open(dir, 40, 4);
    defer sink.close();

    // 20 bytes
    try sink.write("abcdefghijabcdefghij");
    try std.testing.expect(exists(dir, "current.jsonl"));
    try std.testing.expect(!exists(dir, "current.jsonl.1")); // rotate-on-startup cleared .1 if it existed

    // another 25 bytes → total 45, over 40 threshold
    try sink.write("0123456789012345678901234");

    // after rotation: current is empty, .1 has the 45 bytes
    try std.testing.expect(exists(dir, "current.jsonl"));
    try std.testing.expect(exists(dir, "current.jsonl.1"));
    const sz1 = try fileSize(dir, "current.jsonl.1");
    try std.testing.expectEqual(@as(u64, 45), sz1);
    const cur = try fileSize(dir, "current.jsonl");
    try std.testing.expectEqual(@as(u64, 0), cur);
}

test "Sink: open rotates existing current.jsonl on startup" {
    var dir_buf: [256:0]u8 = undefined;
    const dir = try uniqueTmpDir(&dir_buf);
    defer rmTree(dir);

    // First boot
    {
        var sink = try Sink.open(dir, 1 << 20, 4);
        defer sink.close();
        try sink.write("first-boot-line\n");
    }

    // Second boot — previous current.jsonl should become .1
    {
        var sink = try Sink.open(dir, 1 << 20, 4);
        defer sink.close();
        try sink.write("second-boot-line\n");
    }

    try std.testing.expect(exists(dir, "current.jsonl"));
    try std.testing.expect(exists(dir, "current.jsonl.1"));
    const sz1 = try fileSize(dir, "current.jsonl.1");
    try std.testing.expectEqual(@as(u64, "first-boot-line\n".len), sz1);
}
