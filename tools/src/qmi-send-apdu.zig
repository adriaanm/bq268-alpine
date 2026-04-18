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
//!   qmi-send-apdu daemon               Persistent mode for lpac-qmi-wrapper

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

/// Line-based protocol for lpac-qmi-wrapper:
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

    if (std.mem.eql(u8, cmd, "daemon")) {
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
