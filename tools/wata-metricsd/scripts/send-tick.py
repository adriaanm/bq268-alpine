#!/usr/bin/env python3
"""Send wata-metricsd heartbeat ticks to /run/wata.tick.

Useful for on-device smoke testing without wata running. Mimics the
contract from ~/wata/docs/planning/metrics-heartbeat-tick.md:

    16-byte little-endian packed payload:
        u64 ts_mono_ns | u32 seq | u8 phase | 3 bytes reserved

Usage:
    send-tick.py [--count N] [--interval-ms MS] [--path PATH] [--start-seq N]
"""
import argparse
import socket
import struct
import sys
import time


def mono_ns() -> int:
    return time.clock_gettime_ns(time.CLOCK_BOOTTIME)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--count", type=int, default=1)
    ap.add_argument("--interval-ms", type=int, default=0)
    ap.add_argument("--path", default="/run/wata.tick")
    ap.add_argument("--start-seq", type=int, default=1)
    args = ap.parse_args()

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    sock.setblocking(False)

    seq = args.start_seq
    sent = 0
    for _ in range(args.count):
        payload = struct.pack("<QIBxxx", mono_ns(), seq & 0xFFFFFFFF, 0)
        try:
            sock.sendto(payload, args.path)
            sent += 1
        except (FileNotFoundError, ConnectionRefusedError, BlockingIOError) as e:
            print(f"send {seq}: {type(e).__name__}: {e}", file=sys.stderr)
        seq += 1
        if args.interval_ms > 0:
            time.sleep(args.interval_ms / 1000.0)

    print(f"sent {sent}/{args.count} ticks to {args.path}")
    return 0 if sent == args.count else 1


if __name__ == "__main__":
    sys.exit(main())
