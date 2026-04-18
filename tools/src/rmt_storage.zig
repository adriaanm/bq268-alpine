//! rmt_storage — Modem EFS storage daemon for BQ268 (MSM8909, CAF 4.4 kernel)
//!
//! Registers as QMI service 14 (RMTFS) on the IPC Router and serves modem
//! EFS partition read/write requests via shared memory (/dev/uioN).
//!
//! Partitions served (override files in /lib/firmware/ checked first):
//!   /boot/modem_fs1 → /dev/mmcblk0p26 (modemst1)
//!   /boot/modem_fs2 → /dev/mmcblk0p27 (modemst2)
//!   /boot/modem_fsg → /dev/mmcblk0p3  (fsg)
//!   /boot/modem_fsc → /dev/mmcblk0p29 (fsc)
//!
//! Protocol based on linux-msm/rmtfs (BSD-3-Clause, Linaro Ltd / Bjorn Andersson).
//! QMI wire format from qrtr/lib/qmi.c (BSD-3-Clause, The Linux Foundation).
//!
//! Differences from the original C version:
//!   * one pread/pwrite per iovec entry instead of one per sector
//!     (contiguous sectors → single syscall, big win for partition-sized writes)
//!   * no sector bounce buffer on the read path; pread directly into mmap'd shm,
//!     zero-fill the tail if the file is shorter than expected
//!   * raw linux.fd_t throughout; no std.fs.File, matches wata-metricsd idiom

const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;

// ───── IPC Router (AF_MSM_IPC) — from uapi/linux/msm_ipc.h ──────────────

const AF_MSM_IPC: u16 = 27;
const MSM_IPC_ADDR_NAME: u8 = 1;
const MSM_IPC_ADDR_ID: u8 = 2;

const MsmIpcPortAddr = extern struct {
    node_id: u32,
    port_id: u32,
};

const MsmIpcPortName = extern struct {
    service: u32,
    instance: u32,
};

const MsmIpcAddrU = extern union {
    port_addr: MsmIpcPortAddr,
    port_name: MsmIpcPortName,
};

const MsmIpcAddr = extern struct {
    addrtype: u8,
    addr: MsmIpcAddrU,
};

// Wire layout matching the CAF 4.4 kernel uapi/linux/msm_ipc.h. The C
// structs are NOT packed — natural alignment applies. Verified on device:
// sizeof=20, addrtype at offset 4, node_id at offset 8.
const SockaddrMsmIpc = extern struct {
    family: u16,
    address: MsmIpcAddr,
    reserved: u8,
};

// ───── QMI protocol constants ───────────────────────────────────────────

const QMI_REQUEST: u8 = 0x00;
const QMI_RESPONSE: u8 = 0x02;
const QMI_INDICATION: u8 = 0x04;

const RMTFS_QMI_SERVICE: u32 = 14;
const RMTFS_QMI_VERSION: u32 = 1;
const RMTFS_QMI_INSTANCE: u32 = 0;

const QMI_RMTFS_OPEN: u16 = 1;
const QMI_RMTFS_CLOSE: u16 = 2;
const QMI_RMTFS_RW_IOVEC: u16 = 3;
const QMI_RMTFS_ALLOC_BUFF: u16 = 4;
const QMI_RMTFS_GET_DEV_ERROR: u16 = 5;

const SECTOR_SIZE: usize = 512;
const MAX_CALLERS: usize = 10;
const BUF_SIZE: usize = 4096;

// ───── logging — bufPrint then write(2) to stderr ───────────────────────

var verbose: bool = false;

fn logMsg(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = linux.write(2, slice.ptr, slice.len);
}

fn vlog(comptime fmt: []const u8, args: anytype) void {
    if (verbose) logMsg(fmt, args);
}

fn hexDump(prefix: []const u8, data: []const u8) void {
    if (data.len == 0) return;
    var i: usize = 0;
    while (i < data.len) : (i += 16) {
        var line_buf: [256]u8 = undefined;
        var off: usize = 0;
        const row = @min(data.len - i, 16);
        if (std.fmt.bufPrint(line_buf[off..], "{s} {x:0>4}: ", .{ prefix, i })) |s| off += s.len else |_| {}
        for (data[i .. i + row]) |b| {
            if (std.fmt.bufPrint(line_buf[off..], "{x:0>2} ", .{b})) |s| off += s.len else |_| {}
        }
        for (row..16) |_| {
            if (std.fmt.bufPrint(line_buf[off..], "   ", .{})) |s| off += s.len else |_| {}
        }
        for (data[i .. i + row]) |b| {
            const c: u8 = if (b >= 0x20 and b < 0x7f) b else '.';
            if (off < line_buf.len) {
                line_buf[off] = c;
                off += 1;
            }
        }
        if (off < line_buf.len) {
            line_buf[off] = '\n';
            off += 1;
        }
        _ = linux.write(2, &line_buf, off);
    }
}

// ───── QMI wire format ──────────────────────────────────────────────────

// QMI header (7 bytes, LE): u8 type, u16 txn_id, u16 msg_id, u16 msg_len
const QMI_HDR_LEN: usize = 7;

fn writeQmiHdr(buf: []u8, msg_type: u8, txn_id: u16, msg_id: u16, msg_len: u16) void {
    buf[0] = msg_type;
    std.mem.writeInt(u16, buf[1..3], txn_id, .little);
    std.mem.writeInt(u16, buf[3..5], msg_id, .little);
    std.mem.writeInt(u16, buf[5..7], msg_len, .little);
}

const RespBuf = struct {
    data: [BUF_SIZE]u8 = undefined,
    len: usize = 0,

    fn init(self: *RespBuf, txn_id: u16, msg_id: u16) void {
        writeQmiHdr(self.data[0..7], QMI_RESPONSE, txn_id, msg_id, 0);
        self.len = QMI_HDR_LEN;
    }

    fn addTlv(self: *RespBuf, tlv_type: u8, payload: []const u8) !void {
        const need = 3 + payload.len;
        if (self.len + need > self.data.len) {
            logMsg("[rmt_storage] response buffer overflow ({d} + {d})\n", .{ self.len, need });
            return error.Overflow;
        }
        self.data[self.len] = tlv_type;
        std.mem.writeInt(u16, self.data[self.len + 1 ..][0..2], @intCast(payload.len), .little);
        @memcpy(self.data[self.len + 3 .. self.len + need], payload);
        self.len += need;
        // Update msg_len in header.
        const msg_len: u16 = @intCast(self.len - QMI_HDR_LEN);
        std.mem.writeInt(u16, self.data[5..7], msg_len, .little);
    }

    fn addResult(self: *RespBuf, result: u16, err: u16) void {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u16, buf[0..2], result, .little);
        std.mem.writeInt(u16, buf[2..4], err, .little);
        self.addTlv(2, &buf) catch {};
    }

    fn addU32(self: *RespBuf, tlv_type: u8, val: u32) void {
        var buf: [4]u8 = undefined;
        std.mem.writeInt(u32, &buf, val, .little);
        self.addTlv(tlv_type, &buf) catch {};
    }

    fn addU64(self: *RespBuf, tlv_type: u8, val: u64) void {
        var buf: [8]u8 = undefined;
        std.mem.writeInt(u64, &buf, val, .little);
        self.addTlv(tlv_type, &buf) catch {};
    }

    fn addU8(self: *RespBuf, tlv_type: u8, val: u8) void {
        const buf = [_]u8{val};
        self.addTlv(tlv_type, &buf) catch {};
    }
};

/// Locate a TLV by type. Returns the payload slice or null.
fn findTlv(data: []const u8, tlv_type: u8) ?[]const u8 {
    var off: usize = 0;
    while (off + 3 <= data.len) {
        const t = data[off];
        const l = std.mem.readInt(u16, data[off + 1 ..][0..2], .little);
        if (off + 3 + l > data.len) break;
        if (t == tlv_type) return data[off + 3 .. off + 3 + l];
        off += 3 + l;
    }
    return null;
}

// ───── Partition table ──────────────────────────────────────────────────

const Partition = struct {
    modem_path: []const u8,
    dev_path: [:0]const u8,
    override: ?[:0]const u8,
};

const partitions = [_]Partition{
    .{ .modem_path = "/boot/modem_fs1", .dev_path = "/dev/mmcblk0p26", .override = "/lib/firmware/modemst1.bin" },
    .{ .modem_path = "/boot/modem_fs2", .dev_path = "/dev/mmcblk0p27", .override = "/lib/firmware/modemst2.bin" },
    .{ .modem_path = "/boot/modem_fsg", .dev_path = "/dev/mmcblk0p3", .override = "/lib/firmware/fsg.bin" },
    .{ .modem_path = "/boot/modem_fsc", .dev_path = "/dev/mmcblk0p29", .override = "/lib/firmware/fsc.bin" },
};

fn findPartition(path: []const u8) ?*const Partition {
    for (&partitions) |*p| {
        if (std.mem.eql(u8, p.modem_path, path)) return p;
    }
    return null;
}

// ───── Caller (open file) management ────────────────────────────────────

const Caller = struct {
    fd: linux.fd_t = -1,
    dev_size: u64 = 0, // partition size in bytes (0 = unknown)
    node: u32 = 0,
    port: u32 = 0,
    part: ?*const Partition = null,
};

var callers: [MAX_CALLERS]Caller = @splat(Caller{});

fn callerOpen(node: u32, port: u32, path: []const u8) ?usize {
    const part = findPartition(path) orelse {
        logMsg("[rmt_storage] unknown partition: {s}\n", .{path});
        return null;
    };

    // Already open for this node?
    for (&callers, 0..) |*c, i| {
        if (c.fd >= 0 and c.node == node and c.part == part) return i;
    }

    // Find free slot.
    var slot: ?usize = null;
    for (&callers, 0..) |*c, i| {
        if (c.fd < 0) {
            slot = i;
            break;
        }
    }
    const s = slot orelse {
        logMsg("[rmt_storage] no free caller slots\n", .{});
        return null;
    };

    // Try override first, fall back to block device.
    var fd: linux.fd_t = -1;
    var actual_path: [:0]const u8 = part.dev_path;
    if (part.override) |ov| {
        fd = posix.openatZ(posix.AT.FDCWD, ov, .{ .ACCMODE = .RDWR }, 0) catch -1;
        if (fd >= 0) actual_path = ov;
    }
    if (fd < 0) {
        fd = posix.openatZ(posix.AT.FDCWD, part.dev_path, .{ .ACCMODE = .RDWR }, 0) catch {
            logMsg("[rmt_storage] open {s} failed\n", .{part.dev_path});
            return null;
        };
    }

    // Size via lseek(SEEK_END). On a regular file this is the file size;
    // on a block device this returns the partition size in bytes.
    // std.os.linux.lseek has a 64-bit/32-bit bitcast bug on ARM in Zig
    // 0.16, so we go direct with syscall3. Modem partitions are <2 MB
    // so 32-bit off_t is fine.
    const SEEK_END: usize = 2;
    const SEEK_SET: usize = 0;
    const end_rc = linux.syscall3(.lseek, @as(usize, @bitCast(@as(isize, fd))), 0, SEEK_END);
    const dev_size: u64 = switch (linux.errno(end_rc)) {
        .SUCCESS => @intCast(end_rc),
        else => 0,
    };
    _ = linux.syscall3(.lseek, @as(usize, @bitCast(@as(isize, fd))), 0, SEEK_SET);

    callers[s] = .{
        .fd = fd,
        .dev_size = dev_size,
        .node = node,
        .port = port,
        .part = part,
    };

    logMsg("[rmt_storage] Open {s} ({s}, {d} bytes) => caller {d}\n", .{ part.modem_path, actual_path, dev_size, s });
    return s;
}

fn callerClose(id: usize) void {
    if (id >= MAX_CALLERS) return;
    if (callers[id].fd < 0) return;
    _ = linux.close(callers[id].fd);
    callers[id] = .{};
}

fn callersCloseAll() void {
    for (0..MAX_CALLERS) |i| callerClose(i);
}

// ───── UIO shared memory ────────────────────────────────────────────────

const SharedMem = struct {
    base: []u8 = &.{},
    phys_addr: u64 = 0,
    size: u64 = 0,
    fd: linux.fd_t = -1,
};

var shmem: SharedMem = .{};

/// Read a small text file into a stack buffer.
fn readSmallFile(path: [:0]const u8, out: []u8) ?[]const u8 {
    const fd = posix.openatZ(posix.AT.FDCWD, path, .{ .ACCMODE = .RDONLY }, 0) catch return null;
    defer _ = linux.close(fd);
    const n = posix.read(fd, out) catch return null;
    if (n == 0) return null;
    var end: usize = n;
    while (end > 0 and (out[end - 1] == '\n' or out[end - 1] == '\r')) end -= 1;
    return out[0..end];
}

fn parseHex64(s: []const u8) ?u64 {
    var str = s;
    if (str.len >= 2 and str[0] == '0' and (str[1] == 'x' or str[1] == 'X')) str = str[2..];
    return std.fmt.parseUnsigned(u64, str, 16) catch null;
}

fn sharedmemOpen(sm: *SharedMem, uio_name: []const u8) !void {
    // Scan /sys/class/uio/ for a directory whose "name" matches uio_name.
    const dir_fd = posix.openatZ(posix.AT.FDCWD, "/sys/class/uio", .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
    }, 0) catch {
        logMsg("[rmt_storage] open /sys/class/uio failed\n", .{});
        return error.OpenUioDir;
    };
    defer _ = linux.close(dir_fd);

    var dirent_buf: [4096]u8 align(8) = undefined;
    var uio_num: i32 = -1;
    while (true) {
        const got = linux.getdents64(dir_fd, @ptrCast(&dirent_buf), dirent_buf.len);
        const n: isize = @bitCast(got);
        if (n <= 0) break;

        var off: usize = 0;
        while (off < @as(usize, @intCast(n))) {
            const d: *linux.dirent64 = @ptrCast(@alignCast(&dirent_buf[off]));
            off += d.reclen;

            // name_ptr is the start of d.name (flexible array)
            const name_ptr: [*:0]const u8 = @ptrCast(&d.name);
            const name = std.mem.span(name_ptr);
            if (!std.mem.startsWith(u8, name, "uio")) continue;

            // Read /sys/class/uio/<name>/name
            var path_buf: [256:0]u8 = undefined;
            const npath = std.fmt.bufPrintZ(&path_buf, "/sys/class/uio/{s}/name", .{name}) catch continue;
            var contents_buf: [64]u8 = undefined;
            const contents = readSmallFile(npath, &contents_buf) orelse continue;
            if (std.mem.eql(u8, contents, uio_name)) {
                uio_num = std.fmt.parseInt(i32, name[3..], 10) catch continue;
                break;
            }
        }
        if (uio_num >= 0) break;
    }
    if (uio_num < 0) {
        logMsg("[rmt_storage] UIO device '{s}' not found\n", .{uio_name});
        return error.UioNotFound;
    }

    // Read addr + size from sysfs maps/map0/.
    var pbuf: [256:0]u8 = undefined;
    var sbuf: [64]u8 = undefined;

    const addr_path = std.fmt.bufPrintZ(&pbuf, "/sys/class/uio/uio{d}/maps/map0/addr", .{uio_num}) catch return error.PathFmt;
    const addr_str = readSmallFile(addr_path, &sbuf) orelse {
        logMsg("[rmt_storage] read addr failed\n", .{});
        return error.ReadAddr;
    };
    sm.phys_addr = parseHex64(addr_str) orelse {
        logMsg("[rmt_storage] bad phys_addr: '{s}'\n", .{addr_str});
        return error.BadAddr;
    };

    const size_path = std.fmt.bufPrintZ(&pbuf, "/sys/class/uio/uio{d}/maps/map0/size", .{uio_num}) catch return error.PathFmt;
    const size_str = readSmallFile(size_path, &sbuf) orelse return error.ReadSize;
    sm.size = parseHex64(size_str) orelse {
        logMsg("[rmt_storage] bad size: '{s}'\n", .{size_str});
        return error.BadSize;
    };

    if (sm.phys_addr == 0 or sm.size == 0) {
        logMsg("[rmt_storage] bad sharedmem: addr=0x{x} size=0x{x}\n", .{ sm.phys_addr, sm.size });
        return error.BadSharedMem;
    }

    // mmap /dev/uioN.
    const dev_path = std.fmt.bufPrintZ(&pbuf, "/dev/uio{d}", .{uio_num}) catch return error.PathFmt;
    sm.fd = posix.openatZ(posix.AT.FDCWD, dev_path, .{ .ACCMODE = .RDWR }, 0) catch {
        logMsg("[rmt_storage] open {s} failed\n", .{dev_path});
        return error.OpenUioDev;
    };

    if (sm.size > std.math.maxInt(usize)) {
        logMsg("[rmt_storage] shm size {d} exceeds usize\n", .{sm.size});
        _ = linux.close(sm.fd);
        return error.SizeTooLarge;
    }
    const mapped = posix.mmap(
        null,
        @intCast(sm.size),
        .{ .READ = true, .WRITE = true },
        .{ .TYPE = .SHARED },
        sm.fd,
        0,
    ) catch {
        logMsg("[rmt_storage] mmap failed\n", .{});
        _ = linux.close(sm.fd);
        return error.Mmap;
    };
    sm.base = mapped;

    logMsg("[rmt_storage] shared memory: phys=0x{x} size=0x{x} ({d} KB) dev={s}\n", .{ sm.phys_addr, sm.size, sm.size / 1024, dev_path });
}

fn sharedmemClose(sm: *SharedMem) void {
    if (sm.base.len > 0) posix.munmap(@alignCast(sm.base));
    if (sm.fd >= 0) _ = linux.close(sm.fd);
    sm.* = .{};
}

/// Translate a physical address + len to a slice within the mmap'd region.
/// Returns null if the range is out of bounds.
fn shmSlice(sm: *const SharedMem, phys: u64, len: usize) ?[]u8 {
    if (sm.base.len == 0 or sm.size == 0) return null;
    if (len == 0 or len > sm.size) return null;
    if (phys < sm.phys_addr) return null;
    const offset = phys - sm.phys_addr;
    if (offset > sm.size - len) return null;
    const o: usize = @intCast(offset);
    return sm.base[o .. o + len];
}

// ───── response send helper ─────────────────────────────────────────────

fn respSend(sock: linux.fd_t, from: *const SockaddrMsmIpc, from_len: linux.socklen_t, r: *const RespBuf) void {
    if (r.len < QMI_HDR_LEN) {
        logMsg("[rmt_storage] BUG: resp_send with len={d} < hdr\n", .{r.len});
        return;
    }
    if (verbose) {
        const msg_id = std.mem.readInt(u16, r.data[3..5], .little);
        const txn = std.mem.readInt(u16, r.data[1..3], .little);
        logMsg("[rmt_storage] >> msg_id={d} txn={d} len={d}\n", .{ msg_id, txn, r.len });
        hexDump("[rmt_storage] >>", r.data[0..r.len]);
    }
    // Use the kernel-reported from_len (matches the C version). The
    // MSM IPC router on CAF 4.4 may fill in a different length than
    // sizeof(SockaddrMsmIpc), so we pass it through verbatim.
    const src = linux.sendto(
        sock,
        r.data[0..r.len].ptr,
        r.len,
        0,
        @ptrCast(from),
        from_len,
    );
    switch (linux.errno(src)) {
        .SUCCESS => {},
        else => |e| logMsg("[rmt_storage] sendto failed: {s}\n", .{@tagName(e)}),
    }
}

// ───── handlers ─────────────────────────────────────────────────────────

fn handleOpen(sock: linux.fd_t, from: *const SockaddrMsmIpc, from_len: linux.socklen_t, payload: []const u8, txn_id: u16) void {
    var resp: RespBuf = undefined;
    resp.init(txn_id, QMI_RMTFS_OPEN);

    const path = findTlv(payload, 1) orelse {
        logMsg("[rmt_storage] open: missing path TLV\n", .{});
        resp.addResult(1, 2);
        respSend(sock, from, from_len, &resp);
        return;
    };
    if (path.len == 0) {
        resp.addResult(1, 2);
        respSend(sock, from, from_len, &resp);
        return;
    }

    const id = callerOpen(
        from.address.addr.port_addr.node_id,
        from.address.addr.port_addr.port_id,
        path,
    ) orelse {
        resp.addResult(1, 3);
        respSend(sock, from, from_len, &resp);
        return;
    };

    resp.addResult(0, 0);
    resp.addU32(0x10, @intCast(id));
    respSend(sock, from, from_len, &resp);
}

fn handleClose(sock: linux.fd_t, from: *const SockaddrMsmIpc, from_len: linux.socklen_t, payload: []const u8, txn_id: u16) void {
    var resp: RespBuf = undefined;
    resp.init(txn_id, QMI_RMTFS_CLOSE);

    const tlv = findTlv(payload, 1) orelse {
        resp.addResult(1, 2);
        respSend(sock, from, from_len, &resp);
        return;
    };
    if (tlv.len < 4) {
        resp.addResult(1, 2);
        respSend(sock, from, from_len, &resp);
        return;
    }
    const caller_id = std.mem.readInt(u32, tlv[0..4], .little);
    if (caller_id >= MAX_CALLERS or callers[caller_id].fd < 0) {
        logMsg("[rmt_storage] close: bad caller {d}\n", .{caller_id});
        resp.addResult(1, 3);
        respSend(sock, from, from_len, &resp);
        return;
    }
    if (callers[caller_id].node != from.address.addr.port_addr.node_id) {
        logMsg("[rmt_storage] close: caller {d} owned by node {d}, not {d}\n", .{
            caller_id, callers[caller_id].node, from.address.addr.port_addr.node_id,
        });
        resp.addResult(1, 3);
        respSend(sock, from, from_len, &resp);
        return;
    }

    vlog("[rmt_storage] close caller {d}\n", .{caller_id});
    callerClose(caller_id);
    resp.addResult(0, 0);
    respSend(sock, from, from_len, &resp);
}

fn handleRwIovec(sock: linux.fd_t, from: *const SockaddrMsmIpc, from_len: linux.socklen_t, payload: []const u8, txn_id: u16) void {
    var resp: RespBuf = undefined;
    resp.init(txn_id, QMI_RMTFS_RW_IOVEC);

    // TLV 1: caller_id (u32)
    const tlv1 = findTlv(payload, 1) orelse {
        resp.addResult(1, 2);
        respSend(sock, from, from_len, &resp);
        return;
    };
    if (tlv1.len < 4) {
        resp.addResult(1, 2);
        respSend(sock, from, from_len, &resp);
        return;
    }
    const caller_id = std.mem.readInt(u32, tlv1[0..4], .little);
    if (caller_id >= MAX_CALLERS or callers[caller_id].fd < 0) {
        logMsg("[rmt_storage] iovec: bad caller {d}\n", .{caller_id});
        resp.addResult(1, 3);
        respSend(sock, from, from_len, &resp);
        return;
    }
    if (callers[caller_id].node != from.address.addr.port_addr.node_id) {
        logMsg("[rmt_storage] iovec: caller {d} owned by node {d}, not {d}\n", .{
            caller_id, callers[caller_id].node, from.address.addr.port_addr.node_id,
        });
        resp.addResult(1, 3);
        respSend(sock, from, from_len, &resp);
        return;
    }

    // TLV 2: direction (u8, 0=read, 1=write)
    const tlv2 = findTlv(payload, 2) orelse {
        resp.addResult(1, 2);
        respSend(sock, from, from_len, &resp);
        return;
    };
    if (tlv2.len < 1) {
        resp.addResult(1, 2);
        respSend(sock, from, from_len, &resp);
        return;
    }
    const is_write = tlv2[0] != 0;

    // TLV 3: iovec [u8 count][entries: 12 bytes each]
    const tlv3 = findTlv(payload, 3) orelse {
        resp.addResult(1, 2);
        respSend(sock, from, from_len, &resp);
        return;
    };
    if (tlv3.len < 1) {
        resp.addResult(1, 2);
        respSend(sock, from, from_len, &resp);
        return;
    }
    const count = tlv3[0];
    if (tlv3.len < 1 + @as(usize, count) * 12) {
        logMsg("[rmt_storage] iovec: truncated ({d} entries, tlv_len={d})\n", .{ count, tlv3.len });
        resp.addResult(1, 2);
        respSend(sock, from, from_len, &resp);
        return;
    }
    const entries = tlv3[1..];

    // TLV 4: is_force_sync (u8, informational)
    var force: u8 = 0;
    if (findTlv(payload, 4)) |tlv4| {
        if (tlv4.len >= 1) force = tlv4[0];
    }

    const fd = callers[caller_id].fd;
    const dev_size = callers[caller_id].dev_size;

    var ok = true;
    const err_code: u16 = 3;

    var i: usize = 0;
    while (i < count) : (i += 1) {
        const base = entries[i * 12 .. i * 12 + 12];
        const sector_addr = std.mem.readInt(u32, base[0..4], .little);
        const phys_offset = std.mem.readInt(u32, base[4..8], .little);
        const num_sector = std.mem.readInt(u32, base[8..12], .little);

        vlog("[rmt_storage]   {s} caller={d} sector={d}+{d} phys=0x{x}{s}\n", .{
            if (is_write) "write" else "read",
            caller_id,
            sector_addr,
            num_sector,
            phys_offset,
            if (force != 0) " (forced)" else "",
        });

        if (num_sector == 0) continue;

        // Overflow-safe sector range check.
        const end_sector: u64 = @as(u64, sector_addr) + @as(u64, num_sector);
        const end_byte: u64 = end_sector * SECTOR_SIZE;
        if (end_sector < sector_addr or end_byte / SECTOR_SIZE != end_sector) {
            logMsg("[rmt_storage] sector overflow: addr={d} count={d}\n", .{ sector_addr, num_sector });
            ok = false;
            break;
        }
        if (dev_size > 0 and end_byte > dev_size) {
            logMsg("[rmt_storage] sector range {d}+{d} exceeds partition ({d} bytes)\n", .{ sector_addr, num_sector, dev_size });
            ok = false;
            break;
        }

        // Batch the whole iovec entry (contiguous in both file and shm) into
        // one syscall. This is the main efficiency win over the C version.
        const file_off: u64 = @as(u64, sector_addr) * SECTOR_SIZE;
        // Compute io_len in u64 first — on 32-bit ARM, usize is u32 and
        // num_sector * 512 can overflow, which panics in ReleaseSafe.
        const io_len_64: u64 = @as(u64, num_sector) * SECTOR_SIZE;
        if (io_len_64 > std.math.maxInt(usize)) {
            logMsg("[rmt_storage] iovec too large: {d} sectors\n", .{num_sector});
            ok = false;
            break;
        }
        const io_len: usize = @intCast(io_len_64);
        const phys: u64 = shmem.phys_addr + phys_offset;

        const region = shmSlice(&shmem, phys, io_len) orelse {
            logMsg("[rmt_storage] phys 0x{x} out of shared memory range\n", .{phys});
            ok = false;
            break;
        };

        if (is_write) {
            // modem wrote to shm → flush to partition
            const wrc = linux.pwrite(fd, region.ptr, region.len, @intCast(file_off));
            switch (linux.errno(wrc)) {
                .SUCCESS => {
                    if (wrc != region.len) {
                        logMsg("[rmt_storage] short pwrite: {d}/{d}\n", .{ wrc, region.len });
                        ok = false;
                        break;
                    }
                },
                else => |e| {
                    logMsg("[rmt_storage] pwrite failed: {s}\n", .{@tagName(e)});
                    ok = false;
                    break;
                },
            }
        } else {
            // read partition → copy into shm for modem
            const rrc = linux.pread(fd, region.ptr, region.len, @intCast(file_off));
            switch (linux.errno(rrc)) {
                .SUCCESS => {},
                else => |e| {
                    logMsg("[rmt_storage] pread failed: {s}\n", .{@tagName(e)});
                    ok = false;
                    break;
                },
            }
            const nread: usize = @intCast(rrc);
            if (nread < region.len) {
                // Short read (override file shorter than partition). Zero
                // the tail so we don't leak stale shm contents to the modem.
                @memset(region[nread..], 0);
            }
        }
    }

    if (!ok) {
        resp.addResult(1, err_code);
        respSend(sock, from, from_len, &resp);
        return;
    }

    if (is_write) {
        _ = linux.fdatasync(fd);
    }

    resp.addResult(0, 0);
    respSend(sock, from, from_len, &resp);
}

fn handleAllocBuf(sock: linux.fd_t, from: *const SockaddrMsmIpc, from_len: linux.socklen_t, payload: []const u8, txn_id: u16) void {
    var resp: RespBuf = undefined;
    resp.init(txn_id, QMI_RMTFS_ALLOC_BUFF);

    var req_size: u32 = 0;
    if (findTlv(payload, 2)) |t| {
        if (t.len >= 4) req_size = std.mem.readInt(u32, t[0..4], .little);
    }
    if (req_size > shmem.size) {
        logMsg("[rmt_storage] alloc_buf: requested {d} > available {d}\n", .{ req_size, shmem.size });
        resp.addResult(1, 3);
        respSend(sock, from, from_len, &resp);
        return;
    }

    logMsg("[rmt_storage] Alloc buffer: req={d} avail={d} addr=0x{x}\n", .{ req_size, shmem.size, shmem.phys_addr });
    resp.addResult(0, 0);
    resp.addU64(0x10, shmem.phys_addr);
    respSend(sock, from, from_len, &resp);
}

fn handleGetDevError(sock: linux.fd_t, from: *const SockaddrMsmIpc, from_len: linux.socklen_t, txn_id: u16) void {
    var resp: RespBuf = undefined;
    resp.init(txn_id, QMI_RMTFS_GET_DEV_ERROR);
    resp.addResult(0, 0);
    resp.addU8(0x10, 0);
    respSend(sock, from, from_len, &resp);
}

// ───── signal handling ──────────────────────────────────────────────────

var running = std.atomic.Value(bool).init(true);

fn onSignal(_: linux.SIG) callconv(.c) void {
    running.store(false, .seq_cst);
}

// ───── main ─────────────────────────────────────────────────────────────

fn usage() void {
    logMsg(
        \\Usage: rmt_storage [-v] [-u uio_name] [-w seconds]
        \\  -v            verbose logging
        \\  -u name       UIO device name (default: rmtfs)
        \\  -w seconds    wait for UIO device (default: 10)
        \\
    , .{});
}

pub fn main(init: std.process.Init.Minimal) !u8 {
    var uio_name: []const u8 = "rmtfs";
    var wait_secs: u32 = 10;

    var it = init.args.iterate();
    _ = it.next(); // argv[0]
    while (it.next()) |arg| {
        if (std.mem.eql(u8, arg, "-v")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "-u")) {
            uio_name = it.next() orelse {
                usage();
                return 1;
            };
        } else if (std.mem.eql(u8, arg, "-w")) {
            const v = it.next() orelse {
                usage();
                return 1;
            };
            wait_secs = std.fmt.parseInt(u32, v, 10) catch {
                usage();
                return 1;
            };
        } else {
            usage();
            return 1;
        }
    }

    const sa = posix.Sigaction{
        .handler = .{ .handler = onSignal },
        .mask = posix.sigemptyset(),
        .flags = 0,
    };
    posix.sigaction(posix.SIG.INT, &sa, null);
    posix.sigaction(posix.SIG.TERM, &sa, null);

    // Wait for UIO device to appear. The modem DSP registers its rmtfs
    // shared memory region at boot, but ordering vs. our init script is
    // not guaranteed.
    var ok = false;
    var i: u32 = 0;
    while (i < wait_secs and running.load(.seq_cst)) : (i += 1) {
        sharedmemOpen(&shmem, uio_name) catch {
            if (i < wait_secs - 1) {
                logMsg("[rmt_storage] waiting for UIO device '{s}' ({d}/{d})...\n", .{ uio_name, i + 1, wait_secs });
                var ts = linux.timespec{ .sec = 1, .nsec = 0 };
                _ = linux.nanosleep(&ts, &ts);
            }
            continue;
        };
        ok = true;
        break;
    }
    if (!ok) {
        logMsg("[rmt_storage] shared memory not available, exiting\n", .{});
        return 1;
    }

    // Create IPC Router socket.
    const sock_rc = linux.socket(AF_MSM_IPC, linux.SOCK.DGRAM, 0);
    switch (linux.errno(sock_rc)) {
        .SUCCESS => {},
        else => |e| {
            logMsg("[rmt_storage] socket(AF_MSM_IPC) failed: {s}\n", .{@tagName(e)});
            sharedmemClose(&shmem);
            return 1;
        },
    }
    const sock: linux.fd_t = @intCast(sock_rc);

    // Register as QMI RMTFS service (service 14, version 1, instance 0).
    var addr = std.mem.zeroes(SockaddrMsmIpc);
    addr.family = AF_MSM_IPC;
    addr.address.addrtype = MSM_IPC_ADDR_NAME;
    addr.address.addr = .{ .port_name = .{
        .service = RMTFS_QMI_SERVICE,
        .instance = (RMTFS_QMI_VERSION & 0xFF) | ((RMTFS_QMI_INSTANCE & 0xFF) << 8),
    } };

    const bind_rc = linux.bind(sock, @ptrCast(&addr), @sizeOf(SockaddrMsmIpc));
    switch (linux.errno(bind_rc)) {
        .SUCCESS => {},
        else => |e| {
            logMsg("[rmt_storage] bind(RMTFS service) failed: {s}\n", .{@tagName(e)});
            _ = linux.close(sock);
            sharedmemClose(&shmem);
            return 1;
        },
    }

    logMsg("[rmt_storage] QMI service {d} registered, waiting for modem requests\n", .{RMTFS_QMI_SERVICE});

    // Main event loop.
    var buf: [BUF_SIZE]u8 = undefined;
    while (running.load(.seq_cst)) {
        var from = std.mem.zeroes(SockaddrMsmIpc);
        var from_len: linux.socklen_t = @sizeOf(SockaddrMsmIpc);

        const rc = linux.recvfrom(sock, &buf, buf.len, 0, @ptrCast(&from), &from_len);
        switch (linux.errno(rc)) {
            .SUCCESS => {},
            .INTR => continue,
            else => |e| {
                logMsg("[rmt_storage] recvfrom failed: {s}\n", .{@tagName(e)});
                break;
            },
        }
        const nu: usize = @intCast(rc);
        if (nu < QMI_HDR_LEN) {
            logMsg("[rmt_storage] runt packet ({d})\n", .{nu});
            continue;
        }

        if (from.address.addrtype != MSM_IPC_ADDR_ID) {
            vlog("[rmt_storage] skip addrtype={d}\n", .{from.address.addrtype});
            continue;
        }

        const msg_type = buf[0];
        if (msg_type != QMI_REQUEST) {
            vlog("[rmt_storage] skip type={d}\n", .{msg_type});
            continue;
        }
        const txn_id = std.mem.readInt(u16, buf[1..3], .little);
        const msg_id = std.mem.readInt(u16, buf[3..5], .little);
        // Trust the received length, not the declared msg_len in the hdr
        // (same as the C version — kernel frame length is authoritative).
        const payload = buf[QMI_HDR_LEN..nu];

        if (verbose) {
            logMsg("[rmt_storage] << msg_id={d} txn={d} len={d} from={d}:{d}\n", .{
                msg_id,                          txn_id, nu,
                from.address.addr.port_addr.node_id,
                from.address.addr.port_addr.port_id,
            });
            hexDump("[rmt_storage] <<", buf[0..nu]);
        }

        switch (msg_id) {
            QMI_RMTFS_OPEN => handleOpen(sock, &from, from_len, payload, txn_id),
            QMI_RMTFS_CLOSE => handleClose(sock, &from, from_len, payload, txn_id),
            QMI_RMTFS_RW_IOVEC => handleRwIovec(sock, &from, from_len, payload, txn_id),
            QMI_RMTFS_ALLOC_BUFF => handleAllocBuf(sock, &from, from_len, payload, txn_id),
            QMI_RMTFS_GET_DEV_ERROR => handleGetDevError(sock, &from, from_len, txn_id),
            else => logMsg("[rmt_storage] unknown msg_id {d}\n", .{msg_id}),
        }
    }

    logMsg("[rmt_storage] shutting down\n", .{});
    _ = linux.close(sock);
    callersCloseAll();
    sharedmemClose(&shmem);
    return 0;
}
