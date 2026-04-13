//! wata-metricsd event loop.
//!
//! Binds an AF_UNIX SOCK_DGRAM socket at /run/wata.tick, creates a
//! BOOTTIME timerfd as an idle watchdog, and poll()s on both. Each wake
//! drains the tick socket, samples sysfs sources, and appends one JSONL
//! line to /var/log/metrics/current.jsonl via the rotating file sink.
//!
//! All I/O uses std.posix and raw std.os.linux syscalls — the new std.Io
//! abstraction in Zig 0.16-dev is heavier than what this daemon needs.

const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;

const protocol = @import("protocol.zig");
const jsonl = @import("jsonl.zig");
const Sources = @import("sources.zig").Sources;
const Sink = @import("sink.zig").Sink;

const TICK_PATH: [:0]const u8 = "/run/wata.tick";
const LOG_DIR: [:0]const u8 = "/var/log/metrics";
const WATCHDOG_INTERVAL_SEC: isize = 30;
const SOCK_PERMS: linux.mode_t = 0o662;

pub fn main() !u8 {
    const info_msg = "wata-metricsd starting: tick=" ++ TICK_PATH ++
        " log=" ++ LOG_DIR ++ "\n";
    _ = linux.write(2, info_msg.ptr, info_msg.len);

    var sink = Sink.open(LOG_DIR, 1 << 20, 4) catch |err| {
        const m = "wata-metricsd: sink open failed\n";
        _ = linux.write(2, m.ptr, m.len);
        return @as(u8, switch (err) {
            error.MkdirFailed => 10,
            error.OpenFailed => 11,
            error.RotateFailed => 12,
        });
    };
    defer sink.close();

    const tick_fd = bindTickSocket(TICK_PATH) catch {
        const m = "wata-metricsd: tick socket bind failed\n";
        _ = linux.write(2, m.ptr, m.len);
        return 20;
    };
    defer _ = linux.close(tick_fd);

    const wd_fd = createWatchdog(WATCHDOG_INTERVAL_SEC) catch {
        const m = "wata-metricsd: timerfd create failed\n";
        _ = linux.write(2, m.ptr, m.len);
        return 21;
    };
    defer _ = linux.close(wd_fd);

    const sources = Sources{};
    return runLoop(&sink, sources, tick_fd, wd_fd);
}

fn bindTickSocket(path: [:0]const u8) !linux.fd_t {
    // Best-effort unlink — absence is normal, any other error is tolerated
    // at bind time.
    _ = linux.unlinkat(linux.AT.FDCWD, path, 0);

    const rc = linux.socket(
        linux.AF.UNIX,
        linux.SOCK.DGRAM | linux.SOCK.NONBLOCK | linux.SOCK.CLOEXEC,
        0,
    );
    switch (linux.errno(rc)) {
        .SUCCESS => {},
        else => return error.SocketFailed,
    }
    const fd: linux.fd_t = @intCast(rc);

    var addr = linux.sockaddr.un{ .family = linux.AF.UNIX, .path = undefined };
    @memset(&addr.path, 0);
    if (path.len >= addr.path.len) return error.PathTooLong;
    @memcpy(addr.path[0..path.len], path);

    const addr_len: linux.socklen_t = @intCast(
        @offsetOf(linux.sockaddr.un, "path") + path.len + 1,
    );
    const brc = linux.bind(fd, @ptrCast(&addr), addr_len);
    switch (linux.errno(brc)) {
        .SUCCESS => {},
        else => {
            _ = linux.close(fd);
            return error.BindFailed;
        },
    }

    // chmod so non-root wata can sendto().
    const crc = linux.fchmod(fd, SOCK_PERMS);
    switch (linux.errno(crc)) {
        .SUCCESS, .INVAL => {}, // some fs ignore fchmod on sockets; tolerate
        else => {},
    }

    return fd;
}

fn createWatchdog(interval_sec: isize) !linux.fd_t {
    const rc = linux.timerfd_create(.BOOTTIME, .{ .NONBLOCK = true, .CLOEXEC = true });
    switch (linux.errno(rc)) {
        .SUCCESS => {},
        else => return error.TimerfdCreateFailed,
    }
    const fd: linux.fd_t = @intCast(rc);

    const spec = linux.itimerspec{
        .it_interval = .{ .sec = interval_sec, .nsec = 0 },
        .it_value = .{ .sec = interval_sec, .nsec = 0 },
    };
    const srec = linux.timerfd_settime(fd, .{ .ABSTIME = false }, &spec, null);
    switch (linux.errno(srec)) {
        .SUCCESS => {},
        else => {
            _ = linux.close(fd);
            return error.TimerfdSetFailed;
        },
    }
    return fd;
}

fn runLoop(sink: *Sink, sources: Sources, tick_fd: linux.fd_t, wd_fd: linux.fd_t) !u8 {
    var fds = [_]linux.pollfd{
        .{ .fd = tick_fd, .events = linux.POLL.IN, .revents = 0 },
        .{ .fd = wd_fd, .events = linux.POLL.IN, .revents = 0 },
    };

    var seq: u32 = 0;
    var prev_mono: u64 = 0;
    var line_buf: [1024]u8 = undefined;

    while (true) {
        const pr = linux.poll(&fds, fds.len, -1);
        switch (linux.errno(pr)) {
            .SUCCESS => {},
            .INTR => continue,
            else => return 30,
        }

        var ticks: u32 = 0;
        var last_tick: ?protocol.Tick = null;
        if (fds[0].revents & linux.POLL.IN != 0) {
            while (true) {
                var rbuf: [protocol.TICK_SIZE]u8 = undefined;
                const r = linux.recvfrom(tick_fd, &rbuf, rbuf.len, 0, null, null);
                const e = linux.errno(r);
                if (e == .SUCCESS) {
                    if (r == protocol.TICK_SIZE) {
                        ticks += 1;
                        last_tick = protocol.Tick.decode(&rbuf) catch null;
                    }
                    continue;
                }
                if (e == .AGAIN or e == .INTR) break;
                break;
            }
        }

        var hit_watchdog = false;
        if (fds[1].revents & linux.POLL.IN != 0) {
            var wbuf: [8]u8 = undefined;
            _ = linux.read(wd_fd, &wbuf, wbuf.len);
            hit_watchdog = true;
        }

        const s = sources.sample();

        const src: jsonl.Source = if (ticks > 0 and hit_watchdog)
            .both
        else if (ticks > 0)
            .tick
        else
            .watchdog;

        const dt: u64 = if (prev_mono == 0 or s.ts_mono_ns <= prev_mono)
            0
        else
            s.ts_mono_ns - prev_mono;
        prev_mono = s.ts_mono_ns;

        const effective_seq: u32 = if (last_tick) |t| t.seq else seq;
        seq +%= 1;

        const rec = jsonl.Record{
            .sample = s,
            .src = src,
            .seq = effective_seq,
            .ticks_coalesced = ticks,
            .dt_ns = dt,
        };

        const line = jsonl.format(&line_buf, rec) catch continue;
        sink.write(line) catch continue;
    }
}
