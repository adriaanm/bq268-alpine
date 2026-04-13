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

const DEFAULT_TICK_PATH: [:0]const u8 = "/run/wata.tick";
const DEFAULT_LOG_DIR: [:0]const u8 = "/var/log/metrics";
const WATCHDOG_INTERVAL_SEC: isize = 30;
const SOCK_PERMS: linux.mode_t = 0o662;

var tick_path_buf: [256:0]u8 = undefined;
var log_dir_buf: [256:0]u8 = undefined;

pub fn main(init: std.process.Init.Minimal) !u8 {
    var tick_path: [:0]const u8 = DEFAULT_TICK_PATH;
    var log_dir: [:0]const u8 = DEFAULT_LOG_DIR;
    var max_iters: u64 = 0; // 0 = unlimited

    var it = init.args.iterate();
    _ = it.next(); // skip argv[0]
    while (it.next()) |arg| {
        if (parseFlag(arg, "--tick=")) |val| {
            tick_path = copyZ(&tick_path_buf, val) orelse return 2;
        } else if (parseFlag(arg, "--log=")) |val| {
            log_dir = copyZ(&log_dir_buf, val) orelse return 2;
        } else if (parseFlag(arg, "--max-iters=")) |val| {
            max_iters = std.fmt.parseInt(u64, val, 10) catch return 2;
        } else if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            const help =
                "wata-metricsd [--tick=PATH] [--log=DIR] [--max-iters=N]\n" ++
                "  --tick PATH       AF_UNIX SOCK_DGRAM heartbeat socket (default /run/wata.tick)\n" ++
                "  --log DIR         JSONL output directory (default /var/log/metrics)\n" ++
                "  --max-iters N     stop after N event-loop iterations (0 = unlimited, default)\n";
            _ = linux.write(1, help.ptr, help.len);
            return 0;
        }
    }

    var msg_buf: [512]u8 = undefined;
    if (std.fmt.bufPrint(&msg_buf, "wata-metricsd: tick={s} log={s}\n", .{ tick_path, log_dir })) |m| {
        _ = linux.write(2, m.ptr, m.len);
    } else |_| {}

    var sink = Sink.open(log_dir, 1 << 20, 4) catch |err| {
        const m = "wata-metricsd: sink open failed\n";
        _ = linux.write(2, m.ptr, m.len);
        return @as(u8, switch (err) {
            error.MkdirFailed => 10,
            error.OpenFailed => 11,
            error.RotateFailed => 12,
        });
    };
    defer sink.close();

    const tick_fd = bindTickSocket(tick_path) catch {
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

    const sig_fd = installSignalfd() catch {
        const m = "wata-metricsd: signalfd setup failed\n";
        _ = linux.write(2, m.ptr, m.len);
        return 22;
    };
    defer _ = linux.close(sig_fd);

    const sources = Sources{};
    return runLoop(&sink, sources, tick_fd, wd_fd, sig_fd, max_iters);
}

/// Block SIGTERM/SIGINT and route them to a signalfd so the event loop
/// wakes cleanly via poll() instead of via an async signal handler.
fn installSignalfd() !linux.fd_t {
    var mask = posix.sigemptyset();
    posix.sigaddset(&mask, .TERM);
    posix.sigaddset(&mask, .INT);
    posix.sigprocmask(linux.SIG.BLOCK, &mask, null);
    return try posix.signalfd(-1, &mask, linux.SFD.CLOEXEC | linux.SFD.NONBLOCK);
}

fn parseFlag(arg: []const u8, prefix: []const u8) ?[]const u8 {
    if (!std.mem.startsWith(u8, arg, prefix)) return null;
    return arg[prefix.len..];
}

fn copyZ(buf: *[256:0]u8, src: []const u8) ?[:0]const u8 {
    if (src.len >= buf.len) return null;
    @memcpy(buf[0..src.len], src);
    buf[src.len] = 0;
    return buf[0..src.len :0];
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

fn runLoop(
    sink: *Sink,
    sources: Sources,
    tick_fd: linux.fd_t,
    wd_fd: linux.fd_t,
    sig_fd: linux.fd_t,
    max_iters: u64,
) !u8 {
    var fds = [_]linux.pollfd{
        .{ .fd = tick_fd, .events = linux.POLL.IN, .revents = 0 },
        .{ .fd = wd_fd, .events = linux.POLL.IN, .revents = 0 },
        .{ .fd = sig_fd, .events = linux.POLL.IN, .revents = 0 },
    };

    var seq: u32 = 0;
    var prev_mono: u64 = 0;
    var line_buf: [1024]u8 = undefined;
    var iters: u64 = 0;

    while (true) {
        const pr = linux.poll(&fds, fds.len, -1);
        switch (linux.errno(pr)) {
            .SUCCESS => {},
            .INTR => continue,
            else => return 30,
        }

        if (fds[2].revents & linux.POLL.IN != 0) {
            const m = "wata-metricsd: caught signal, exiting cleanly\n";
            _ = linux.write(2, m.ptr, m.len);
            return 0;
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

        iters += 1;
        if (max_iters != 0 and iters >= max_iters) return 0;
    }
}
