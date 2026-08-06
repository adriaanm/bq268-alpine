#!/usr/bin/env python3
"""Host-side checks for rootfs/files/usr/local/bin/wifi-join.

Runs the helper against a temp wpa_supplicant.conf (WIFI_JOIN_CONF) with
fake wpa_passphrase/wpa_cli/rc-service stubs on PATH — the fake
wpa_passphrase computes the same PBKDF2 the real one does, so the
"never plaintext" check is meaningful. Spec: the verification section of
docs/planning/wifi-join-helper.md.
"""

import os
import re
import stat
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HELPER = os.path.join(REPO, "rootfs", "files", "usr", "local", "bin", "wifi-join")

FAKE_WPA_PASSPHRASE = """#!/usr/bin/env python3
import sys, hashlib
ssid = sys.argv[1]
psk = sys.stdin.buffer.read().rstrip(b"\\n")
if not 8 <= len(psk) <= 63: sys.exit(1)
h = hashlib.pbkdf2_hmac("sha1", psk, ssid.encode(), 4096, 32).hex()
print('network={\\n\\tssid="%s"\\n\\t#psk="%s"\\n\\tpsk=%s\\n}'
      % (ssid, psk.decode(), h))
"""

failures = []


def check(name, cond):
    print(("ok   " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


def wifi_join(env, ssid, psk, extra_env=None):
    e = dict(env)
    e.update(extra_env or {})
    return subprocess.run([HELPER, ssid] if ssid is not None else [HELPER],
                         input=psk, capture_output=True, env=e, timeout=30)


def blocks_for(conf, ssid):
    text = open(conf).read()
    return [b for b in re.findall(r"network=\{.*?\}", text, re.S)
            if f'ssid="{ssid}"' in b]


def main():
    with tempfile.TemporaryDirectory() as td:
        stubs = os.path.join(td, "bin")
        os.mkdir(stubs)
        with open(os.path.join(stubs, "wpa_passphrase"), "w") as f:
            f.write(FAKE_WPA_PASSPHRASE)
        with open(os.path.join(stubs, "wpa_cli"), "w") as f:
            f.write("#!/bin/sh\necho OK\n")
        with open(os.path.join(stubs, "rc-service"), "w") as f:
            f.write("#!/bin/sh\nexit 0\n")
        for s in os.listdir(stubs):
            os.chmod(os.path.join(stubs, s), 0o755)

        conf = os.path.join(td, "wpa_supplicant.conf")
        with open(conf, "w") as f:
            f.write("ctrl_interface=/var/run/wpa_supplicant\nupdate_config=1\n"
                    'network={\n\tssid="existing"\n\tpsk=' + "ab" * 32
                    + "\n\tpriority=3\n}\n")
        env = {"PATH": stubs + os.pathsep + os.environ["PATH"],
               "WIFI_JOIN_CONF": conf}

        # Bad args refused before touching anything
        check("no-args is a usage error", wifi_join(env, None, b"").returncode != 0)
        check("overlong ssid refused",
              wifi_join(env, "x" * 33, b"password1").returncode != 0)
        check("short psk refused", wifi_join(env, "net1", b"short").returncode != 0)
        check("conf untouched by refusals", len(blocks_for(conf, "net1")) == 0)

        # Join, then re-join with a new psk: ONE block, hashed, priority on top
        r1 = wifi_join(env, "net1", b"password-one")
        check("join exits 0", r1.returncode == 0)
        check("one stdout detail line", len(r1.stdout.decode().splitlines()) == 1)
        r2 = wifi_join(env, "net1", b"password-two\n")
        check("re-join exits 0", r2.returncode == 0)
        text = open(conf).read()
        check("two joins leave ONE block", len(blocks_for(conf, "net1")) == 1)
        check("psk never plaintext in conf",
              b"password-one" not in text.encode() and b"password-two" not in text.encode())
        check("psk is 64-hex", re.search(r"^\tpsk=[0-9a-f]{64}$", text, re.M) is not None)
        check("priority above existing blocks",
              "priority=4" in blocks_for(conf, "net1")[0])
        check("existing block preserved", len(blocks_for(conf, "existing")) == 1)
        check("header preserved", text.startswith("ctrl_interface="))
        check("conf mode 0600",
              stat.S_IMODE(os.stat(conf).st_mode) == 0o600)

        # Open network
        r3 = wifi_join(env, "cafe", b"")
        check("open join exits 0", r3.returncode == 0)
        check("open network gets key_mgmt=NONE",
              "key_mgmt=NONE" in blocks_for(conf, "cafe")[0])
        check("open block has no psk", "psk=" not in blocks_for(conf, "cafe")[0])

        # Dry-run touches nothing
        before = open(conf).read()
        r4 = wifi_join(env, "dry", b"password-dry", {"WIFI_JOIN_DRY_RUN": "1"})
        check("dry-run exits 0 and reports",
              r4.returncode == 0 and b"dry-run" in r4.stdout)
        check("dry-run touches nothing", open(conf).read() == before)

    if failures:
        print(f"\n{len(failures)} FAILED")
        sys.exit(1)
    print("\nall checks passed")


if __name__ == "__main__":
    main()
