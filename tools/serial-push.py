#!/usr/bin/env python3
"""Copy a file to the device over the USB gadget serial console.

    tools/serial-push.py rootfs/files/etc/init.d/wifi /etc/init.d/wifi

For the case scp cannot serve: the boot that lost wifi is exactly the boot
whose wifi script you need to replace. The file goes over as base64 in small
printf chunks (the console's line discipline will not take a long line), is
decoded on the device, and the md5 is printed for you to compare — always
compare it, a dropped chunk is silent otherwise.

Slow by design (~10 KB in a few seconds). For anything big, fix the network
first.
"""

import argparse
import base64
import os
import sys
import time

DEFAULT_PORT = "/dev/cu.usbmodem000000001"
CHUNK = 200          # base64 chars per printf — well inside the line limit


def open_port(path: str) -> int:
    import termios
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    a = termios.tcgetattr(fd)
    a[0] = a[1] = a[3] = 0
    a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    a[4] = a[5] = termios.B115200
    a[6][termios.VMIN] = 0
    a[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, a)
    return fd


def write(fd: int, s: str) -> None:
    for i in range(0, len(s), 128):
        os.write(fd, s[i:i + 128].encode())
        time.sleep(0.03)


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
    ap.add_argument("src")
    ap.add_argument("dst")
    ap.add_argument("--port", default=os.environ.get("BQ268_SERIAL", DEFAULT_PORT))
    args = ap.parse_args()

    data = base64.b64encode(open(args.src, "rb").read()).decode()
    fd = open_port(args.port)
    write(fd, "\n")
    read_for(fd, 1)
    write(fd, ": > /tmp/push.b64\n")
    read_for(fd, 0.5)
    for i in range(0, len(data), CHUNK):
        write(fd, f"printf %s '{data[i:i + CHUNK]}' >> /tmp/push.b64\n")
        read_for(fd, 0.25)
    write(fd, f"base64 -d /tmp/push.b64 > {args.dst} && echo PUSH-OK && md5sum {args.dst}\n")
    print(read_for(fd, 4))
    print("compare with: md5 -q " + args.src)


if __name__ == "__main__":
    main()
