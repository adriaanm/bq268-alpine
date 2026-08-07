#!/usr/bin/env python3
"""Run commands on the device over the USB gadget serial console.

    tools/serial-run.py "uptime" "ip -br addr"
    tools/serial-run.py --port /dev/cu.usbmodem000000002 "dmesg | tail"

The console is the way in when the network is not: a boot that lost wifi, a
stale DHCP lease, a wpa_supplicant stuck in SCANNING. No dependencies — a
termios setup and read/write — so it works from a bare checkout.

The port is a USB CDC-ACM device (/dev/cu.usbmodem* on macOS, /dev/ttyACM* on
Linux) that appears when the gadget is up. The login is root/bq268, but a
console left logged in from an earlier session just runs the commands.
"""

import argparse
import os
import sys
import termios
import time

DEFAULT_PORT = "/dev/cu.usbmodem000000001"


def open_port(path: str) -> int:
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    a = termios.tcgetattr(fd)
    a[0] = a[1] = a[3] = 0                                   # raw
    a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    a[4] = a[5] = termios.B115200
    a[6][termios.VMIN] = 0
    a[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, a)
    return fd


def write(fd: int, s: str) -> None:
    os.write(fd, s.encode())


def read_for(fd: int, secs: float) -> str:
    out = b""
    end = time.time() + secs
    while time.time() < end:
        try:
            chunk = os.read(fd, 4096)
            if chunk:
                out += chunk
        except BlockingIOError:
            pass
        time.sleep(0.05)
    return out.decode("utf-8", "replace")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default=os.environ.get("BQ268_SERIAL", DEFAULT_PORT))
    ap.add_argument("--wait", type=float, default=4.0, help="seconds to read per command")
    ap.add_argument("commands", nargs="*", default=["uptime", "ip -br addr"])
    args = ap.parse_args()

    if not os.path.exists(args.port):
        sys.exit(f"serial-run: no {args.port} — is the USB cable in and the gadget up?")
    fd = open_port(args.port)
    write(fd, "\n")
    banner = read_for(fd, 2)
    if "login:" in banner:
        write(fd, "root\n")
        time.sleep(1)
        write(fd, "bq268\n")
        read_for(fd, 3)
    for c in args.commands:
        write(fd, c + "\n")
        print(read_for(fd, args.wait), end="")


if __name__ == "__main__":
    main()
