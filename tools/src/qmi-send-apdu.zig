//! qmi-send-apdu — Send APDUs via QMI UIM over AF_MSM_IPC
//!
//! Minimal QMI client that opens a logical channel (with short AID to
//! bypass ISD-R filter) and sends APDUs directly. Avoids the libqmi
//! dependency for testing different QMI message formats.
//!
//! Usage:
//!   qmi-send-apdu open [AID_HEX]      Open logical channel
//!   qmi-send-apdu apdu CH APDU_HEX    Send APDU on channel
//!   qmi-send-apdu close CH             Close logical channel
//!   qmi-send-apdu test                 Full ISD-R test sequence
//!   qmi-send-apdu daemon               Persistent line-based mode
//!   qmi-send-apdu lpac [lpac-args]    Spawn lpac with integrated APDU backend
//!   qmi-send-apdu lpac [lpac-args...]  Run lpac with QMI APDU backend

const std = @import("std");
const linux = std.os.linux;
const posix = std.posix;

// ───── IPC Router (AF_MSM_IPC) ──────────────────────────────────────────

const AF_MSM_IPC: u16 = 27;
const MSM_IPC_ADDR_NAME: u8 = 1;
const MSM_IPC_ADDR_ID: u8 = 2;

const MsmIpcPortAddr = extern struct { node_id: u32, port_id: u32 };
const MsmIpcPortName = extern struct { service: u32, instance: u32 };
const MsmIpcAddrU = extern union { port_addr: MsmIpcPortAddr, port_name: MsmIpcPortName };
const MsmIpcAddr = extern struct { addrtype: u8, addr: MsmIpcAddrU };
const SockaddrMsmIpc = extern struct { family: u16, address: MsmIpcAddr, reserved: u8 };

// IPC_ROUTER_IOCTL_LOOKUP_SERVER = _IOWR(0xC3, 2, struct sockaddr_msm_ipc)
// = (3<<30) | (0xC3<<8) | 2 | (20<<16) = 0xC014C302
const IPC_ROUTER_IOCTL_LOOKUP_SERVER: u32 = 0xC014C302;

const ServerInfo = extern struct {
    node_id: u32,
    port_id: u32,
    service: u32,
    instance: u32,
};

// The lookup ioctl arg is server_lookup_args followed by one ServerInfo.
// We define a concrete struct with exactly one entry (num_entries_in_array=1).
const ServerLookup = extern struct {
    port_name: MsmIpcPortName,
    num_entries_in_array: i32,
    num_entries_found: i32,
    lookup_mask: u32,
    info: ServerInfo,
};

// ───── QMI protocol ─────────────────────────────────────────────────────

const QMI_SVC_UIM: u32 = 0x0B;
const QMI_UIM_OPEN_LOGICAL_CHANNEL: u16 = 0x0042;
const QMI_UIM_CLOSE_LOGICAL_CHANNEL: u16 = 0x003F;
const QMI_UIM_SEND_APDU: u16 = 0x003B;

const QMI_HDR_LEN: usize = 7; // u8 flags + u16 txn + u16 msg_id + u16 tlv_length

// ───── logging ──────────────────────────────────────────────────────────

fn logMsg(comptime fmt: []const u8, args: anytype) void {
    var buf: [512]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = linux.write(2, slice.ptr, slice.len);
}

fn outMsg(comptime fmt: []const u8, args: anytype) void {
    var buf: [4096]u8 = undefined;
    const slice = std.fmt.bufPrint(&buf, fmt, args) catch return;
    _ = linux.write(1, slice.ptr, slice.len);
}

fn hexDump(label: []const u8, data: []const u8) void {
    var buf: [256]u8 = undefined;
    const cap = @min(data.len, 64);
    var off: usize = 0;
    if (std.fmt.bufPrint(buf[off..], "{s} ({d} bytes):", .{ label, data.len })) |s| off += s.len else |_| {}
    for (data[0..cap]) |b| {
        if (std.fmt.bufPrint(buf[off..], " {x:0>2}", .{b})) |s| off += s.len else |_| {}
    }
    if (data.len > cap) {
        if (std.fmt.bufPrint(buf[off..], " ...", .{})) |s| off += s.len else |_| {}
    }
    if (off < buf.len) {
        buf[off] = '\n';
        off += 1;
    }
    _ = linux.write(2, &buf, off);
}

// ───── hex parsing ──────────────────────────────────────────────────────

fn hexToByte(c: u8) ?u4 {
    return switch (c) {
        '0'...'9' => @intCast(c - '0'),
        'a'...'f' => @intCast(c - 'a' + 10),
        'A'...'F' => @intCast(c - 'A' + 10),
        else => null,
    };
}

fn hexToBytes(hex: []const u8, out: []u8) usize {
    var i: usize = 0;
    var o: usize = 0;
    while (i < hex.len and o < out.len) {
        // skip whitespace and colons
        while (i < hex.len and (hex[i] == ' ' or hex[i] == ':')) i += 1;
        if (i >= hex.len) break;
        const hi = hexToByte(hex[i]) orelse break;
        i += 1;
        if (i < hex.len) {
            if (hexToByte(hex[i])) |lo| {
                out[o] = (@as(u8, hi) << 4) | lo;
                i += 1;
            } else {
                out[o] = hi;
            }
        } else {
            out[o] = hi;
        }
        o += 1;
    }
    return o;
}

fn hexOut(data: []const u8) void {
    for (data) |b| outMsg("{X:0>2}", .{b});
}

// ───── globals ──────────────────────────────────────────────────────────

var uim_fd: linux.fd_t = -1;
var txn_id: u16 = 1;
var uim_node: u32 = 0;
var uim_port: u32 = 0;

// ───── IPC Router UIM lookup ────────────────────────────────────────────

fn lookupUimService() !void {
    const fd_rc = linux.socket(AF_MSM_IPC, linux.SOCK.DGRAM, 0);
    switch (linux.errno(fd_rc)) {
        .SUCCESS => {},
        else => |e| {
            logMsg("socket(AF_MSM_IPC) for lookup: {s}\n", .{@tagName(e)});
            return error.Socket;
        },
    }
    const fd: linux.fd_t = @intCast(fd_rc);
    defer _ = linux.close(fd);

    var lookup = std.mem.zeroes(ServerLookup);
    lookup.port_name.service = QMI_SVC_UIM;
    lookup.port_name.instance = 0;
    lookup.num_entries_in_array = 1;
    lookup.lookup_mask = 0;

    const rc = linux.ioctl(fd, IPC_ROUTER_IOCTL_LOOKUP_SERVER, @intFromPtr(&lookup));
    switch (linux.errno(rc)) {
        .SUCCESS => {},
        else => |e| {
            logMsg("ioctl(LOOKUP_SERVER): {s}\n", .{@tagName(e)});
            return error.Ioctl;
        },
    }

    if (lookup.num_entries_found < 1) {
        logMsg("UIM service not registered with IPC Router\n", .{});
        return error.NotFound;
    }

    uim_node = lookup.info.node_id;
    uim_port = lookup.info.port_id;
}

// ───── connect to UIM service ───────────────────────────────────────────

fn msmipcConnect() !void {
    try lookupUimService();

    const fd_rc = linux.socket(AF_MSM_IPC, linux.SOCK.DGRAM, 0);
    switch (linux.errno(fd_rc)) {
        .SUCCESS => {},
        else => |e| {
            logMsg("socket(AF_MSM_IPC): {s}\n", .{@tagName(e)});
            return error.Socket;
        },
    }
    uim_fd = @intCast(fd_rc);

    var addr = std.mem.zeroes(SockaddrMsmIpc);
    addr.family = AF_MSM_IPC;
    addr.address.addrtype = MSM_IPC_ADDR_ID;
    addr.address.addr = .{ .port_addr = .{
        .node_id = uim_node,
        .port_id = uim_port,
    } };

    const crc = linux.connect(uim_fd, @ptrCast(&addr), @sizeOf(SockaddrMsmIpc));
    switch (linux.errno(crc)) {
        .SUCCESS => {},
        else => |e| {
            logMsg("connect to UIM service: {s}\n", .{@tagName(e)});
            _ = linux.close(uim_fd);
            return error.Connect;
        },
    }

    logMsg("Connected to UIM service (node={d}, port={d})\n", .{ uim_node, uim_port });
}

// ───── QMI send / recv ──────────────────────────────────────────────────

fn qmiSend(msg_id: u16, tlvs: []const u8) !void {
    var buf: [4096]u8 = undefined;
    buf[0] = 0x00; // request
    std.mem.writeInt(u16, buf[1..3], txn_id, .little);
    std.mem.writeInt(u16, buf[3..5], msg_id, .little);
    std.mem.writeInt(u16, buf[5..7], @intCast(tlvs.len), .little);
    @memcpy(buf[QMI_HDR_LEN .. QMI_HDR_LEN + tlvs.len], tlvs);

    txn_id +%= 1;
    const total = QMI_HDR_LEN + tlvs.len;
    hexDump("  TX", buf[0..total]);

    const src = linux.sendto(uim_fd, &buf, total, 0, null, 0);
    switch (linux.errno(src)) {
        .SUCCESS => {},
        else => |e| {
            logMsg("send: {s}\n", .{@tagName(e)});
            return error.Send;
        },
    }
}

fn qmiRecv(out: []u8, timeout_ms: i32) ?[]u8 {
    var pfd = [_]posix.pollfd{.{ .fd = uim_fd, .events = posix.POLL.IN, .revents = 0 }};
    const pret = posix.poll(&pfd, timeout_ms) catch return null;
    if (pret <= 0) return null;

    const rc = linux.recvfrom(uim_fd, out.ptr, out.len, 0, null, null);
    switch (linux.errno(rc)) {
        .SUCCESS => {},
        else => return null,
    }
    const n: usize = @intCast(rc);
    return out[0..n];
}

// ───── TLV helpers ──────────────────────────────────────────────────────

fn findTlv(buf: []const u8, tlv_type: u8) ?[]const u8 {
    if (buf.len < QMI_HDR_LEN) return null;
    var off: usize = QMI_HDR_LEN;
    while (off + 3 <= buf.len) {
        const t = buf[off];
        const l = std.mem.readInt(u16, buf[off + 1 ..][0..2], .little);
        if (off + 3 + l > buf.len) break;
        if (t == tlv_type) return buf[off + 3 .. off + 3 + l];
        off += 3 + l;
    }
    return null;
}

/// Check QMI Result TLV (0x02). Returns true on success.
fn qmiCheckResult(buf: []const u8, op: []const u8) bool {
    const tlv = findTlv(buf, 0x02) orelse {
        logMsg("{s}: no result TLV in {d} bytes\n", .{ op, buf.len });
        return false;
    };
    if (tlv.len < 4) return false;
    const result = std.mem.readInt(u16, tlv[0..2], .little);
    if (result != 0) {
        const err = std.mem.readInt(u16, tlv[2..4], .little);
        logMsg("{s}: FAILED (QMI error={d})\n", .{ op, err });
        return false;
    }
    return true;
}

// ───── TLV builder (descending type-ID order) ───────────────────────────

const TlvBuf = struct {
    data: [1024]u8 = undefined,
    len: usize = 0,

    fn addRaw(self: *TlvBuf, tlv_type: u8, payload: []const u8) void {
        const need = 3 + payload.len;
        if (self.len + need > self.data.len) return;
        self.data[self.len] = tlv_type;
        std.mem.writeInt(u16, self.data[self.len + 1 ..][0..2], @intCast(payload.len), .little);
        @memcpy(self.data[self.len + 3 .. self.len + need], payload);
        self.len += need;
    }

    fn addU8(self: *TlvBuf, tlv_type: u8, val: u8) void {
        self.addRaw(tlv_type, &.{val});
    }

    /// Add APDU TLV (0x02): type + le16(2+N) + le16(N) + data[N]
    fn addApdu(self: *TlvBuf, apdu: []const u8) void {
        const total: u16 = @intCast(2 + apdu.len);
        const alen: u16 = @intCast(apdu.len);
        const need = 3 + total;
        if (self.len + need > self.data.len) return;
        self.data[self.len] = 0x02;
        std.mem.writeInt(u16, self.data[self.len + 1 ..][0..2], total, .little);
        std.mem.writeInt(u16, self.data[self.len + 3 ..][0..2], alen, .little);
        @memcpy(self.data[self.len + 5 .. self.len + 5 + apdu.len], apdu);
        self.len += need;
    }

    /// Add AID TLV (0x10): type + le16(1+N) + u8(N) + data[N]
    fn addAid(self: *TlvBuf, aid: []const u8) void {
        const total: u16 = @intCast(1 + aid.len);
        const need = 3 + total;
        if (self.len + need > self.data.len) return;
        self.data[self.len] = 0x10;
        std.mem.writeInt(u16, self.data[self.len + 1 ..][0..2], total, .little);
        self.data[self.len + 3] = @intCast(aid.len);
        @memcpy(self.data[self.len + 4 .. self.len + 4 + aid.len], aid);
        self.len += need;
    }

    /// Slot TLV (0x01): type=0x01 len=0x0001 slot=0x01
    fn addSlot(self: *TlvBuf) void {
        self.addU8(0x01, 0x01);
    }

    fn slice(self: *const TlvBuf) []const u8 {
        return self.data[0..self.len];
    }
};

// ───── ISD-R AID truncation ─────────────────────────────────────────────

const ISDR_PREFIX = "A0000005591010";

/// If aid starts with the ISD-R prefix, truncate to 6-byte prefix
/// "A00000055910" to bypass the modem's 7-byte filter.
fn maybeTruncateAid(aid: []const u8) []const u8 {
    if (aid.len >= ISDR_PREFIX.len and
        std.ascii.eqlIgnoreCase(aid[0..ISDR_PREFIX.len], ISDR_PREFIX))
    {
        return aid[0..12]; // "A00000055910"
    }
    return aid;
}

// ───── commands ─────────────────────────────────────────────────────────

fn cmdOpen(aid_hex: ?[]const u8) !void {
    var tlvs = TlvBuf{};

    // TLVs in DESCENDING type-ID order (modem rejects ascending with QMI error 50).
    if (aid_hex) |ah| {
        if (ah.len > 0) {
            var aid_bytes: [32]u8 = undefined;
            const aid_len = hexToBytes(ah, &aid_bytes);
            tlvs.addAid(aid_bytes[0..aid_len]);
        }
    }
    tlvs.addSlot();

    outMsg("Opening logical channel (AID={s})...\n", .{aid_hex orelse "none"});
    try qmiSend(QMI_UIM_OPEN_LOGICAL_CHANNEL, tlvs.slice());

    var rsp_buf: [512]u8 = undefined;
    const rsp = qmiRecv(&rsp_buf, 10000) orelse {
        outMsg("open channel: no response\n", .{});
        return error.NoResponse;
    };
    hexDump("  RSP", rsp);

    if (!qmiCheckResult(rsp, "open channel")) return error.QmiFailed;

    // Channel ID TLV (0x10)
    if (findTlv(rsp, 0x10)) |tv| {
        if (tv.len >= 1) outMsg("Channel ID: {d}\n", .{tv[0]});
    }
    // Select Response TLV (0x12)
    if (findTlv(rsp, 0x12)) |tv| {
        if (tv.len > 1) hexDump("  FCI", tv[1..]);
    }
    // Card Result TLV (0x11)
    if (findTlv(rsp, 0x11)) |tv| {
        if (tv.len >= 2) outMsg("SW: {X:0>2}{X:0>2}\n", .{ tv[0], tv[1] });
    }
}

fn cmdApdu(channel: u8, apdu_hex: []const u8, include_ch_tlv: bool) !void {
    var apdu: [512]u8 = undefined;
    const apdu_len = hexToBytes(apdu_hex, &apdu);

    var tlvs = TlvBuf{};
    // Descending TLV ID order.
    if (include_ch_tlv) tlvs.addU8(0x10, channel);
    tlvs.addApdu(apdu[0..apdu_len]);
    tlvs.addSlot();

    outMsg("Send APDU (ch={d}, ch_tlv={s}, {d} bytes)...\n", .{
        channel,
        if (include_ch_tlv) "yes" else "no",
        apdu_len,
    });
    hexDump("  APDU", apdu[0..apdu_len]);

    try qmiSend(QMI_UIM_SEND_APDU, tlvs.slice());

    var rsp_buf: [4096]u8 = undefined;
    const rsp = qmiRecv(&rsp_buf, 10000) orelse {
        outMsg("send APDU: no response\n", .{});
        return error.NoResponse;
    };
    hexDump("  RSP", rsp);

    if (!qmiCheckResult(rsp, "send APDU")) return error.QmiFailed;

    // APDU Response TLV (0x10): uint16 len + data
    if (findTlv(rsp, 0x10)) |tv| {
        if (tv.len > 2) hexDump("  APDU RSP", tv[2..]);
    }
    // Card Result TLV (0x11)
    if (findTlv(rsp, 0x11)) |tv| {
        if (tv.len >= 2) outMsg("SW: {X:0>2}{X:0>2}\n", .{ tv[0], tv[1] });
    }
}

fn cmdClose(channel: u8) !void {
    var tlvs = TlvBuf{};
    // Descending TLV ID order.
    tlvs.addU8(0x10, channel);
    tlvs.addSlot();

    outMsg("Closing channel {d}...\n", .{channel});
    try qmiSend(QMI_UIM_CLOSE_LOGICAL_CHANNEL, tlvs.slice());

    var rsp_buf: [256]u8 = undefined;
    const rsp = qmiRecv(&rsp_buf, 5000) orelse return error.NoResponse;
    if (!qmiCheckResult(rsp, "close channel")) return error.QmiFailed;
}

fn cmdTest() !void {
    outMsg("=== Opening ISD-R via short AID ===\n", .{});
    try cmdOpen("A00000055910");

    outMsg("\n=== GetEuiccInfo1 (STORE DATA BF20) ===\n", .{});
    cmdApdu(1, "81E2910003BF2000", true) catch {};
    outMsg("\n=== GET RESPONSE (56 bytes) ===\n", .{});
    cmdApdu(1, "01C0000038", true) catch {};

    outMsg("\n=== GetEuiccChallenge (STORE DATA BF2E) ===\n", .{});
    cmdApdu(1, "81E2910003BF2E00", true) catch {};
    outMsg("\n=== GET RESPONSE (21 bytes) ===\n", .{});
    cmdApdu(1, "01C0000015", true) catch {};

    outMsg("\n=== GetEuiccInfo2 (STORE DATA BF22) ===\n", .{});
    cmdApdu(1, "81E2910003BF2200", true) catch {};
    outMsg("\n=== GET RESPONSE (125 bytes) ===\n", .{});
    cmdApdu(1, "01C000007D", true) catch {};

    outMsg("\n=== Closing channel 1 ===\n", .{});
    cmdClose(1) catch {}; // modem often returns error 1 here, harmless
}

// ───── daemon mode ──────────────────────────────────────────────────────

/// Line-based protocol (legacy, kept for manual testing):
///   OPEN [AID_HEX]        → OK channel_id [FCI_HEX] | ERR msg
///   APDU channel APDU_HEX → OK response_hex | ERR msg
///   CLOSE channel          → OK | ERR msg
fn cmdDaemon() void {
    logMsg("qmi-send-apdu: daemon mode ready\n", .{});

    var read_buf: [8192]u8 = undefined;
    var buf_len: usize = 0;

    while (true) {
        // Read more data from stdin.
        if (buf_len >= read_buf.len) buf_len = 0; // overflow safety
        const rc = linux.read(0, read_buf[buf_len..].ptr, read_buf.len - buf_len);
        switch (linux.errno(rc)) {
            .SUCCESS => {},
            else => return,
        }
        const n: usize = @intCast(rc);
        if (n == 0) return; // EOF
        buf_len += n;

        // Process all complete lines.
        while (std.mem.indexOf(u8, read_buf[0..buf_len], "\n")) |nl| {
            var line = read_buf[0..nl];
            // Strip trailing \r
            if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];

            if (line.len > 0) {
                logMsg("qmi-send-apdu: << {s}\n", .{line});
                handleDaemonLine(line);
            }

            // Shift remaining data.
            const consumed = nl + 1;
            std.mem.copyForwards(u8, &read_buf, read_buf[consumed..buf_len]);
            buf_len -= consumed;
        }
    }
}

fn handleDaemonLine(line: []const u8) void {
    if (std.mem.startsWith(u8, line, "OPEN")) {
        const aid_raw: ?[]const u8 = if (line.len > 5) line[5..] else null;
        const aid = if (aid_raw) |a| maybeTruncateAid(a) else null;

        var tlvs = TlvBuf{};
        if (aid) |a| {
            if (a.len > 0) {
                var aid_bytes: [32]u8 = undefined;
                const aid_len = hexToBytes(a, &aid_bytes);
                tlvs.addAid(aid_bytes[0..aid_len]);
            }
        }
        tlvs.addSlot();

        qmiSend(QMI_UIM_OPEN_LOGICAL_CHANNEL, tlvs.slice()) catch {
            outMsg("ERR send failed\n", .{});
            return;
        };
        var rsp_buf: [512]u8 = undefined;
        const rsp = qmiRecv(&rsp_buf, 10000) orelse {
            outMsg("ERR open failed\n", .{});
            return;
        };
        if (!qmiCheckResult(rsp, "open")) {
            outMsg("ERR open failed\n", .{});
            return;
        }

        const ch_tlv = findTlv(rsp, 0x10);
        const ch: i16 = if (ch_tlv) |tv| (if (tv.len >= 1) @as(i16, tv[0]) else -1) else -1;
        outMsg("OK {d}", .{ch});

        // FCI from Select Response TLV (0x12), skip first byte (length prefix)
        if (findTlv(rsp, 0x12)) |tv| {
            if (tv.len > 1) {
                outMsg(" ", .{});
                hexOut(tv[1..]);
            }
        }
        outMsg("\n", .{});
    } else if (std.mem.startsWith(u8, line, "APDU ")) {
        // Parse "APDU <ch> <hex>"
        const rest = line[5..];
        const sp = std.mem.indexOf(u8, rest, " ") orelse {
            outMsg("ERR bad format\n", .{});
            return;
        };
        const ch = std.fmt.parseInt(u8, rest[0..sp], 10) catch {
            outMsg("ERR bad channel\n", .{});
            return;
        };
        const apdu_hex = rest[sp + 1 ..];

        var apdu: [512]u8 = undefined;
        const apdu_len = hexToBytes(apdu_hex, &apdu);

        // Descending TLV ID: Channel (0x10), APDU (0x02), Slot (0x01).
        var tlvs = TlvBuf{};
        tlvs.addU8(0x10, ch);
        tlvs.addApdu(apdu[0..apdu_len]);
        tlvs.addSlot();

        qmiSend(QMI_UIM_SEND_APDU, tlvs.slice()) catch {
            outMsg("ERR send failed\n", .{});
            return;
        };
        var rsp_buf: [4096]u8 = undefined;
        const rsp = qmiRecv(&rsp_buf, 10000) orelse {
            outMsg("ERR apdu failed\n", .{});
            return;
        };
        if (!qmiCheckResult(rsp, "apdu")) {
            outMsg("ERR apdu failed\n", .{});
            return;
        }

        // APDU response TLV (0x10): uint16 len + data
        if (findTlv(rsp, 0x10)) |tv| {
            if (tv.len > 2) {
                outMsg("OK ", .{});
                hexOut(tv[2..]);
                outMsg("\n", .{});
            } else {
                outMsg("ERR no apdu response\n", .{});
            }
        } else {
            outMsg("ERR no apdu response\n", .{});
        }
    } else if (std.mem.startsWith(u8, line, "CLOSE ")) {
        const ch = std.fmt.parseInt(u8, line[6..], 10) catch {
            outMsg("ERR bad channel\n", .{});
            return;
        };

        var tlvs = TlvBuf{};
        tlvs.addU8(0x10, ch);
        tlvs.addSlot();

        qmiSend(QMI_UIM_CLOSE_LOGICAL_CHANNEL, tlvs.slice()) catch {};
        var rsp_buf: [256]u8 = undefined;
        _ = qmiRecv(&rsp_buf, 5000);
        outMsg("OK\n", .{});
    } else {
        outMsg("ERR unknown command\n", .{});
    }
}

// ───── JSON helpers (minimal, for lpac stdio protocol) ─────────────────

/// Find `"key":"value"` or `"key": "value"` in a JSON line, return value.
fn jsonGetStr(line: []const u8, key: []const u8) ?[]const u8 {
    // Search for `"key"` then `:` then `"value"`
    var i: usize = 0;
    while (i + key.len + 2 < line.len) : (i += 1) {
        if (line[i] == '"' and i + 1 + key.len < line.len and
            std.mem.eql(u8, line[i + 1 .. i + 1 + key.len], key) and
            line[i + 1 + key.len] == '"')
        {
            var j = i + 1 + key.len + 1; // after closing quote
            // skip optional whitespace and colon
            while (j < line.len and (line[j] == ' ' or line[j] == ':')) j += 1;
            if (j < line.len and line[j] == '"') {
                const start = j + 1;
                const end = std.mem.indexOfScalar(u8, line[start..], '"') orelse return null;
                return line[start .. start + end];
            }
            // Could be a number value (no quotes) — skip
            return null;
        }
    }
    return null;
}

/// Write a full line to an fd, retrying on partial writes.
fn fdWrite(fd: linux.fd_t, data: []const u8) void {
    var off: usize = 0;
    while (off < data.len) {
        const rc = linux.write(fd, data[off..].ptr, data.len - off);
        switch (linux.errno(rc)) {
            .SUCCESS => off += @intCast(rc),
            else => return,
        }
    }
}

/// Read nameservers from /etc/resolv.conf, join with commas.
/// Returns the number of bytes written into `out`.
fn readDnsServers(out: []u8) usize {
    const fd_rc = linux.openat(-100, "/etc/resolv.conf", .{}, 0);
    switch (linux.errno(fd_rc)) {
        .SUCCESS => {},
        else => return 0,
    }
    const fd: linux.fd_t = @intCast(fd_rc);
    defer _ = linux.close(fd);

    var buf: [2048]u8 = undefined;
    var total: usize = 0;
    while (true) {
        const rc = linux.read(fd, buf[total..].ptr, buf.len - total);
        switch (linux.errno(rc)) {
            .SUCCESS => {},
            else => break,
        }
        const n: usize = @intCast(rc);
        if (n == 0) break;
        total += n;
        if (total >= buf.len) break;
    }

    const content = buf[0..total];
    var out_len: usize = 0;
    var pos: usize = 0;
    while (pos < content.len) {
        const nl = std.mem.indexOfScalar(u8, content[pos..], '\n') orelse (content.len - pos);
        const line = content[pos .. pos + nl];
        pos += nl + 1;

        const prefix = "nameserver";
        if (line.len > prefix.len and std.mem.eql(u8, line[0..prefix.len], prefix)) {
            var start = prefix.len;
            while (start < line.len and (line[start] == ' ' or line[start] == '\t')) start += 1;
            var end = start;
            while (end < line.len and line[end] != ' ' and line[end] != '\t' and line[end] != '\r') end += 1;
            if (end > start) {
                if (out_len > 0 and out_len < out.len) {
                    out[out_len] = ',';
                    out_len += 1;
                }
                const ns = line[start..end];
                const copy_len = @min(ns.len, out.len - out_len);
                @memcpy(out[out_len .. out_len + copy_len], ns[0..copy_len]);
                out_len += copy_len;
            }
        }
    }
    return out_len;
}

// ───── lpac mode ───────────────────────────────────────────────────────

fn lpacQmiOpen(aid_hex: []const u8) i16 {
    const aid = maybeTruncateAid(aid_hex);
    var tlvs = TlvBuf{};
    if (aid.len > 0) {
        var aid_bytes: [32]u8 = undefined;
        const aid_len = hexToBytes(aid, &aid_bytes);
        tlvs.addAid(aid_bytes[0..aid_len]);
    }
    tlvs.addSlot();

    qmiSend(QMI_UIM_OPEN_LOGICAL_CHANNEL, tlvs.slice()) catch return -1;
    var rsp_buf: [512]u8 = undefined;
    const rsp = qmiRecv(&rsp_buf, 10000) orelse return -1;
    if (!qmiCheckResult(rsp, "open")) return -1;

    const ch_tlv = findTlv(rsp, 0x10);
    if (ch_tlv) |tv| {
        if (tv.len >= 1) return @as(i16, tv[0]);
    }
    return -1;
}

fn lpacQmiClose(channel: u8) void {
    var tlvs = TlvBuf{};
    tlvs.addU8(0x10, channel);
    tlvs.addSlot();
    qmiSend(QMI_UIM_CLOSE_LOGICAL_CHANNEL, tlvs.slice()) catch {};
    var rsp_buf: [256]u8 = undefined;
    _ = qmiRecv(&rsp_buf, 5000);
}

/// Send APDU on channel, write hex response into `out`. Returns slice or null.
fn lpacQmiTransmit(channel: u8, apdu_hex: []const u8, out: []u8) ?[]const u8 {
    var apdu: [512]u8 = undefined;
    const apdu_len = hexToBytes(apdu_hex, &apdu);

    var tlvs = TlvBuf{};
    tlvs.addU8(0x10, channel);
    tlvs.addApdu(apdu[0..apdu_len]);
    tlvs.addSlot();

    qmiSend(QMI_UIM_SEND_APDU, tlvs.slice()) catch return null;
    var rsp_buf: [4096]u8 = undefined;
    const rsp = qmiRecv(&rsp_buf, 10000) orelse return null;
    if (!qmiCheckResult(rsp, "apdu")) return null;

    // APDU response TLV (0x10): uint16 len + data
    const tv = findTlv(rsp, 0x10) orelse return null;
    if (tv.len <= 2) return null;
    const payload = tv[2..];

    // Encode as hex into out
    var o: usize = 0;
    for (payload) |b| {
        if (o + 2 > out.len) break;
        const hex_chars = "0123456789ABCDEF";
        out[o] = hex_chars[b >> 4];
        out[o + 1] = hex_chars[b & 0x0F];
        o += 2;
    }
    return out[0..o];
}

fn cmdLpac(args: anytype) u8 {
    // Collect remaining args for lpac
    var lpac_argv_buf: [64]?[*:0]const u8 = undefined;
    lpac_argv_buf[0] = "/usr/bin/lpac";
    var argc: usize = 1;
    while (args.next()) |arg| {
        if (argc < lpac_argv_buf.len - 1) {
            lpac_argv_buf[argc] = arg.ptr;
            argc += 1;
        }
    }
    lpac_argv_buf[argc] = null;
    const lpac_argv: [*:null]const ?[*:0]const u8 = lpac_argv_buf[0..argc :null];

    // Read DNS servers for CURL_DNS_SERVERS
    var dns_buf: [256]u8 = undefined;
    const dns_len = readDnsServers(&dns_buf);

    // Build envp
    var curl_dns_env_buf: [280]u8 = undefined;
    const curl_dns_env: ?[*:0]const u8 = if (dns_len > 0) blk: {
        const prefix = "CURL_DNS_SERVERS=";
        @memcpy(curl_dns_env_buf[0..prefix.len], prefix);
        @memcpy(curl_dns_env_buf[prefix.len .. prefix.len + dns_len], dns_buf[0..dns_len]);
        curl_dns_env_buf[prefix.len + dns_len] = 0;
        break :blk @ptrCast(curl_dns_env_buf[0 .. prefix.len + dns_len :0]);
    } else null;

    const env_apdu: [*:0]const u8 = "LPAC_APDU=stdio";
    const env_http: [*:0]const u8 = "LPAC_HTTP=curl";
    var envp_buf: [4]?[*:0]const u8 = undefined;
    var envc: usize = 0;
    envp_buf[envc] = env_apdu;
    envc += 1;
    envp_buf[envc] = env_http;
    envc += 1;
    if (curl_dns_env) |e| {
        envp_buf[envc] = e;
        envc += 1;
    }
    envp_buf[envc] = null;
    const lpac_envp: [*:null]const ?[*:0]const u8 = envp_buf[0..envc :null];

    // Create pipes: parent writes to child stdin, reads from child stdout
    var stdin_pipe: [2]linux.fd_t = undefined; // [0]=read, [1]=write
    var stdout_pipe: [2]linux.fd_t = undefined;

    switch (linux.errno(linux.pipe2(&stdin_pipe, .{}))) {
        .SUCCESS => {},
        else => |e| {
            logMsg("pipe2(stdin): {s}\n", .{@tagName(e)});
            return 1;
        },
    }
    switch (linux.errno(linux.pipe2(&stdout_pipe, .{}))) {
        .SUCCESS => {},
        else => |e| {
            logMsg("pipe2(stdout): {s}\n", .{@tagName(e)});
            return 1;
        },
    }

    const pid_rc = linux.fork();
    switch (linux.errno(pid_rc)) {
        .SUCCESS => {},
        else => |e| {
            logMsg("fork: {s}\n", .{@tagName(e)});
            return 1;
        },
    }

    const pid: linux.pid_t = @intCast(pid_rc);
    if (pid == 0) {
        // Child: wire up pipes and exec lpac
        _ = linux.dup2(stdin_pipe[0], 0);
        _ = linux.dup2(stdout_pipe[1], 1);
        _ = linux.close(stdin_pipe[0]);
        _ = linux.close(stdin_pipe[1]);
        _ = linux.close(stdout_pipe[0]);
        _ = linux.close(stdout_pipe[1]);
        // Close the QMI socket in child
        _ = linux.close(uim_fd);
        _ = linux.execve("/usr/bin/lpac", lpac_argv, lpac_envp);
        // If execve fails, exit
        linux.exit(127);
    }

    // Parent: close unused pipe ends
    _ = linux.close(stdin_pipe[0]);
    _ = linux.close(stdout_pipe[1]);

    const child_stdout = stdout_pipe[0];
    const child_stdin = stdin_pipe[1];

    var current_channel: u8 = 0;

    // Read lines from child stdout
    var read_buf: [8192]u8 = undefined;
    var buf_len: usize = 0;

    outer: while (true) {
        if (buf_len >= read_buf.len) buf_len = 0;
        const rc = linux.read(child_stdout, read_buf[buf_len..].ptr, read_buf.len - buf_len);
        switch (linux.errno(rc)) {
            .SUCCESS => {},
            else => break,
        }
        const n: usize = @intCast(rc);
        if (n == 0) break; // EOF
        buf_len += n;

        // Process complete lines
        while (std.mem.indexOfScalar(u8, read_buf[0..buf_len], '\n')) |nl| {
            const line = read_buf[0..nl];
            const consumed = nl + 1;
            defer {
                std.mem.copyForwards(u8, &read_buf, read_buf[consumed..buf_len]);
                buf_len -= consumed;
            }

            if (line.len == 0) continue;

            const req_type = jsonGetStr(line, "type") orelse {
                // Unknown line, pass through to stdout
                fdWrite(1, line);
                fdWrite(1, "\n");
                continue;
            };

            if (std.mem.eql(u8, req_type, "lpa")) {
                // Result — pass through to stdout
                fdWrite(1, line);
                fdWrite(1, "\n");
                continue;
            }

            if (std.mem.eql(u8, req_type, "progress")) {
                // Progress — pass through to stderr
                fdWrite(2, line);
                fdWrite(2, "\n");
                continue;
            }

            if (!std.mem.eql(u8, req_type, "apdu")) {
                // Unknown type, pass through
                fdWrite(1, line);
                fdWrite(1, "\n");
                continue;
            }

            // Handle APDU request
            const func = jsonGetStr(line, "func") orelse continue;
            const param = jsonGetStr(line, "param");

            var resp_buf: [4200]u8 = undefined;

            if (std.mem.eql(u8, func, "connect") or std.mem.eql(u8, func, "disconnect")) {
                logMsg("eUICC: {s}\n", .{func});
                const resp = "{\"type\":\"apdu\",\"payload\":{\"ecode\":0}}\n";
                fdWrite(child_stdin, resp);
            } else if (std.mem.eql(u8, func, "logic_channel_open")) {
                const aid = param orelse "";
                logMsg("eUICC: open channel AID={s}\n", .{aid});
                const ch = lpacQmiOpen(aid);
                if (ch >= 0) {
                    current_channel = @intCast(ch);
                    logMsg("eUICC: channel {d} opened\n", .{ch});
                    const resp_len = std.fmt.bufPrint(&resp_buf, "{{\"type\":\"apdu\",\"payload\":{{\"ecode\":{d}}}}}\n", .{ch}) catch continue;
                    fdWrite(child_stdin, resp_len);
                } else {
                    fdWrite(child_stdin, "{\"type\":\"apdu\",\"payload\":{\"ecode\":-1}}\n");
                }
            } else if (std.mem.eql(u8, func, "logic_channel_close")) {
                const ch_str = param orelse "0";
                const ch = std.fmt.parseInt(u8, ch_str, 10) catch 0;
                logMsg("eUICC: close channel {d}\n", .{ch});
                lpacQmiClose(ch);
                fdWrite(child_stdin, "{\"type\":\"apdu\",\"payload\":{\"ecode\":0}}\n");
            } else if (std.mem.eql(u8, func, "transmit")) {
                const apdu_hex = param orelse {
                    fdWrite(child_stdin, "{\"type\":\"apdu\",\"payload\":{\"ecode\":-1}}\n");
                    continue :outer;
                };
                var hex_out: [2048]u8 = undefined;
                if (lpacQmiTransmit(current_channel, apdu_hex, &hex_out)) |hex_data| {
                    // Build response: {"type":"apdu","payload":{"ecode":0,"data":"<hex>"}}
                    const prefix = "{\"type\":\"apdu\",\"payload\":{\"ecode\":0,\"data\":\"";
                    const suffix = "\"}}\n";
                    const total = prefix.len + hex_data.len + suffix.len;
                    if (total <= resp_buf.len) {
                        @memcpy(resp_buf[0..prefix.len], prefix);
                        @memcpy(resp_buf[prefix.len .. prefix.len + hex_data.len], hex_data);
                        @memcpy(resp_buf[prefix.len + hex_data.len .. total], suffix);
                        fdWrite(child_stdin, resp_buf[0..total]);
                    } else {
                        fdWrite(child_stdin, "{\"type\":\"apdu\",\"payload\":{\"ecode\":-1}}\n");
                    }
                } else {
                    fdWrite(child_stdin, "{\"type\":\"apdu\",\"payload\":{\"ecode\":-1}}\n");
                }
            } else {
                logMsg("Unknown APDU func: {s}\n", .{func});
                fdWrite(child_stdin, "{\"type\":\"apdu\",\"payload\":{\"ecode\":-1}}\n");
            }
        }
    }

    _ = linux.close(child_stdin);
    _ = linux.close(child_stdout);

    // Wait for child
    var status: u32 = 0;
    _ = linux.waitpid(pid, &status, 0);
    if (linux.W.IFEXITED(status)) {
        return linux.W.EXITSTATUS(status);
    }
    return 1;
}

// ───── main ─────────────────────────────────────────────────────────────

fn usage() void {
    logMsg(
        \\Usage:
        \\  qmi-send-apdu open [AID_HEX]       Open logical channel
        \\  qmi-send-apdu apdu CH APDU_HEX     Send APDU on channel
        \\  qmi-send-apdu apdu0 CH APDU_HEX    Send APDU (no channel TLV)
        \\  qmi-send-apdu close CH             Close logical channel
        \\  qmi-send-apdu test                 Full ISD-R test sequence
        \\  qmi-send-apdu daemon               Persistent mode for lpac
        \\  qmi-send-apdu lpac [lpac-args...]  Run lpac with QMI APDU backend
        \\
    , .{});
}

pub fn main(init: std.process.Init.Minimal) !u8 {
    var it = init.args.iterate();
    _ = it.next(); // argv[0]
    const cmd = it.next() orelse {
        usage();
        return 1;
    };

    msmipcConnect() catch return 1;

    if (std.mem.eql(u8, cmd, "lpac")) {
        return cmdLpac(&it);
    } else if (std.mem.eql(u8, cmd, "daemon")) {
        cmdDaemon();
    } else if (std.mem.eql(u8, cmd, "open")) {
        cmdOpen(it.next()) catch return 1;
    } else if (std.mem.eql(u8, cmd, "apdu") or std.mem.eql(u8, cmd, "apdu0")) {
        const ch_str = it.next() orelse {
            usage();
            return 1;
        };
        const ch = std.fmt.parseInt(u8, ch_str, 10) catch {
            logMsg("bad channel: {s}\n", .{ch_str});
            return 1;
        };
        const apdu_hex = it.next() orelse {
            usage();
            return 1;
        };
        const include_ch = std.mem.eql(u8, cmd, "apdu");
        cmdApdu(ch, apdu_hex, include_ch) catch return 1;
    } else if (std.mem.eql(u8, cmd, "close")) {
        const ch_str = it.next() orelse {
            usage();
            return 1;
        };
        const ch = std.fmt.parseInt(u8, ch_str, 10) catch {
            logMsg("bad channel: {s}\n", .{ch_str});
            return 1;
        };
        cmdClose(ch) catch return 1;
    } else if (std.mem.eql(u8, cmd, "test")) {
        cmdTest() catch return 1;
    } else {
        logMsg("Unknown command: {s}\n", .{cmd});
        return 1;
    }

    _ = linux.close(uim_fd);
    return 0;
}
