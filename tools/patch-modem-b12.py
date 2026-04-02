#!/usr/bin/env python3
"""
Patch modem.b12 for eSIM provisioning and update hash in b01/mdt.

Two patches applied to modem.b12:
  1. APDU restriction bypass (offset 0x121DCC)
     r0 = memw(r1+#0x7B8) → r0 = #0x0
     Disables the QMI UIM APDU security restriction bitmask.

  2. LPA ISD-R disable (offset 0x618F7C)
     if (p0.new) r17 = #0x1 → r17 = #0x1  (unconditional)
     Prevents the modem's built-in LPA from registering as the handler
     for the ISD-R AID (A0000005591010...), so open_logical_channel
     requests reach the SIM card instead of being intercepted.

After patching b12, updates hash[12] in modem.b01 (the hash segment)
and modem.mdt (which embeds b01 at offset 884).

MBA only checks SHA-256 hashes, not the RSA signature, so no re-signing
is needed. See docs/modem_patch_plan.md for full analysis.

Usage:
    python3 tools/patch-modem-b12.py firmware/modem
    # Patches modem.b12, modem.b01, modem.mdt in-place

    python3 tools/patch-modem-b12.py firmware/modem --check
    # Just report patch status without modifying anything
"""
import hashlib
import shutil
import struct
import sys
from pathlib import Path

PATCHES = [
    {
        "name": "APDU restriction bypass",
        "offset": 0x121DCC,
        "original": bytes.fromhex("c07d8191"),
        "patched": bytes.fromhex("00400078"),
        "desc": "r0 = memw(r1+#0x7B8) → r0 = #0x0",
    },
    {
        "name": "LPA ISD-R disable",
        "offset": 0x619014,
        "original": bytes.fromhex("b879ff5b"),
        "patched": bytes.fromhex("20400078"),
        "desc": "call lpa_register → r0 = #0x1 (skip ISD-R AID registration)",
    },
]

HASH_HEADER_SIZE = 40   # hash segment header
HASH_SIZE = 32           # SHA-256
HASH_INDEX = 12          # segment index for b12
MDT_B01_OFFSET = 884     # where b01 is embedded in mdt
B01_TOTAL_SIZE = 7272    # 40 + 26*32 + 256 + 6144


def check_patches(b12_data):
    """Report patch status for each patch."""
    results = []
    for p in PATCHES:
        current = b12_data[p["offset"]:p["offset"] + 4]
        if current == p["patched"]:
            status = "PATCHED"
        elif current == p["original"]:
            status = "ORIGINAL"
        else:
            status = f"UNKNOWN ({current.hex()})"
        results.append((p["name"], status, p["offset"], p["desc"]))
    return results


def apply_patches(b12_data):
    """Apply all patches to b12 data. Returns modified data."""
    data = bytearray(b12_data)
    for p in PATCHES:
        current = data[p["offset"]:p["offset"] + 4]
        if current == p["patched"]:
            print(f"  {p['name']}: already patched, skipping")
            continue
        if current != p["original"]:
            print(f"  ERROR: {p['name']} at 0x{p['offset']:06X}: "
                  f"expected {p['original'].hex()}, got {current.hex()}")
            sys.exit(1)
        data[p["offset"]:p["offset"] + 4] = p["patched"]
        print(f"  {p['name']}: {p['desc']}")
    return bytes(data)


def update_hash(b01_data, mdt_data, b12_hash):
    """Update hash[12] in b01 and mdt with the new b12 SHA-256."""
    b01 = bytearray(b01_data)
    mdt = bytearray(mdt_data)

    hash_offset = HASH_HEADER_SIZE + HASH_INDEX * HASH_SIZE
    old_hash = b01[hash_offset:hash_offset + HASH_SIZE]

    print(f"  hash[{HASH_INDEX}] old: {old_hash.hex()}")
    print(f"  hash[{HASH_INDEX}] new: {b12_hash.hex()}")

    if old_hash == b12_hash:
        print(f"  Hash already up to date")
        return bytes(b01), bytes(mdt)

    # Update in b01
    b01[hash_offset:hash_offset + HASH_SIZE] = b12_hash

    # Update in mdt (b01 is embedded at MDT_B01_OFFSET)
    mdt_hash_offset = MDT_B01_OFFSET + hash_offset
    mdt[mdt_hash_offset:mdt_hash_offset + HASH_SIZE] = b12_hash

    return bytes(b01), bytes(mdt)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    fw_dir = Path(sys.argv[1])
    check_only = "--check" in sys.argv

    b12_path = fw_dir / "modem.b12"
    b01_path = fw_dir / "modem.b01"
    mdt_path = fw_dir / "modem.mdt"

    for p in [b12_path, b01_path, mdt_path]:
        if not p.exists():
            print(f"ERROR: {p} not found")
            sys.exit(1)

    b12_data = b12_path.read_bytes()
    b01_data = b01_path.read_bytes()
    mdt_data = mdt_path.read_bytes()

    # Check current status
    results = check_patches(b12_data)
    print("Patch status:")
    for name, status, offset, desc in results:
        print(f"  [{status:8s}] {name} (b12 offset 0x{offset:06X})")

    if check_only:
        return

    # Apply patches
    print("\nApplying patches to modem.b12...")
    b12_patched = apply_patches(b12_data)

    # Compute new hash
    b12_hash = hashlib.sha256(b12_patched).digest()

    print("\nUpdating hash segment...")
    b01_patched, mdt_patched = update_hash(b01_data, mdt_data, b12_hash)

    # Verify mdt embeds b01 correctly
    assert mdt_patched[MDT_B01_OFFSET:MDT_B01_OFFSET + B01_TOTAL_SIZE] == b01_patched, \
        "mdt/b01 mismatch after update"

    # Write files
    b12_path.write_bytes(b12_patched)
    b01_path.write_bytes(b01_patched)
    mdt_path.write_bytes(mdt_patched)

    print(f"\nPatched files written:")
    print(f"  {b12_path}")
    print(f"  {b01_path}")
    print(f"  {mdt_path}")
    print(f"\nDeploy to device /lib/firmware/ and reboot.")


if __name__ == "__main__":
    main()
