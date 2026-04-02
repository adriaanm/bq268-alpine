#!/usr/bin/env python3
"""
Patch modem firmware for eSIM provisioning and update hashes in b01/mdt.

Patches applied:
  1. APDU restriction bypass (b12 offset 0x121DCC)
     r0 = memw(r1+#0x7B8) → r0 = #0x0
     Disables the QMI UIM APDU security restriction bitmask.

  2. LPA ISD-R disable (b12 offset 0x619014)
     call lpa_register → r0 = #0x1
     Prevents the modem's built-in LPA from registering as the handler
     for the ISD-R AID (A0000005591010...).

  3. ISD-R AID corruption (b14 offset 0x2D0679)
     A0 → 00 (first byte of ISD-R AID in data segment)
     LPA's hardcoded ISD-R AID reference becomes 00000005591010...,
     so it registers for a non-existent AID. Real ISD-R requests
     (A0000005591010...) flow through the generic UICC path to the card.

After patching, updates the corresponding SHA-256 hashes in modem.b01
and modem.mdt. MBA only checks hashes, not the RSA signature, so no
re-signing is needed. See docs/modem_patch_plan.md for full analysis.

Usage:
    python3 tools/patch-modem-b12.py firmware/modem
    # Patches modem.b12, modem.b14, modem.b01, modem.mdt in-place

    python3 tools/patch-modem-b12.py firmware/modem --check
    # Just report patch status without modifying anything
"""
import hashlib
import shutil
import struct
import sys
from pathlib import Path

PATCHES_B12 = [
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

PATCHES_B14 = [
    {
        "name": "ISD-R AID corruption",
        "offset": 0x2D0679,
        "original": bytes.fromhex("a0"),
        "patched": bytes.fromhex("00"),
        "desc": "AID first byte A0 → 00 (LPA registers for non-existent AID)",
    },
]

# Collect all patches grouped by segment file
SEGMENT_PATCHES = {
    "modem.b12": {"patches": PATCHES_B12, "hash_index": 12},
    "modem.b14": {"patches": PATCHES_B14, "hash_index": 14},
}

HASH_HEADER_SIZE = 40   # hash segment header
HASH_SIZE = 32           # SHA-256
MDT_B01_OFFSET = 884     # where b01 is embedded in mdt
B01_TOTAL_SIZE = 7272    # 40 + 26*32 + 256 + 6144


def check_patches(data, patches, seg_name):
    """Report patch status for each patch in a segment."""
    results = []
    for p in patches:
        size = len(p["original"])
        current = data[p["offset"]:p["offset"] + size]
        if current == p["patched"]:
            status = "PATCHED"
        elif current == p["original"]:
            status = "ORIGINAL"
        else:
            status = f"UNKNOWN ({current.hex()})"
        results.append((p["name"], status, p["offset"], seg_name))
    return results


def apply_patches(data, patches, seg_name):
    """Apply patches to segment data. Returns modified data."""
    buf = bytearray(data)
    for p in patches:
        size = len(p["original"])
        current = buf[p["offset"]:p["offset"] + size]
        if current == p["patched"]:
            print(f"  {p['name']}: already patched, skipping")
            continue
        if current != p["original"]:
            print(f"  ERROR: {p['name']} at {seg_name} 0x{p['offset']:06X}: "
                  f"expected {p['original'].hex()}, got {current.hex()}")
            sys.exit(1)
        buf[p["offset"]:p["offset"] + size] = p["patched"]
        print(f"  {p['name']}: {p['desc']}")
    return bytes(buf)


def update_hash(b01_data, mdt_data, seg_hash, hash_index):
    """Update hash[index] in b01 and mdt with a new SHA-256."""
    b01 = bytearray(b01_data)
    mdt = bytearray(mdt_data)

    hash_offset = HASH_HEADER_SIZE + hash_index * HASH_SIZE
    old_hash = b01[hash_offset:hash_offset + HASH_SIZE]

    print(f"  hash[{hash_index}] old: {old_hash.hex()}")
    print(f"  hash[{hash_index}] new: {seg_hash.hex()}")

    if old_hash == seg_hash:
        print(f"  Hash already up to date")
        return bytes(b01), bytes(mdt)

    # Update in b01
    b01[hash_offset:hash_offset + HASH_SIZE] = seg_hash

    # Update in mdt (b01 is embedded at MDT_B01_OFFSET)
    mdt_hash_offset = MDT_B01_OFFSET + hash_offset
    mdt[mdt_hash_offset:mdt_hash_offset + HASH_SIZE] = seg_hash

    return bytes(b01), bytes(mdt)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    fw_dir = Path(sys.argv[1])
    check_only = "--check" in sys.argv

    b01_path = fw_dir / "modem.b01"
    mdt_path = fw_dir / "modem.mdt"

    for p in [b01_path, mdt_path]:
        if not p.exists():
            print(f"ERROR: {p} not found")
            sys.exit(1)

    # Load segment files and check all patches
    seg_data = {}
    all_results = []
    for seg_name, info in SEGMENT_PATCHES.items():
        seg_path = fw_dir / seg_name
        if not seg_path.exists():
            print(f"ERROR: {seg_path} not found")
            sys.exit(1)
        seg_data[seg_name] = seg_path.read_bytes()
        all_results.extend(
            check_patches(seg_data[seg_name], info["patches"], seg_name))

    b01_data = b01_path.read_bytes()
    mdt_data = mdt_path.read_bytes()

    print("Patch status:")
    for name, status, offset, seg_name in all_results:
        print(f"  [{status:8s}] {name} ({seg_name} offset 0x{offset:06X})")

    if check_only:
        return

    # Apply patches to each segment and update hashes
    patched_files = []
    for seg_name, info in SEGMENT_PATCHES.items():
        seg_path = fw_dir / seg_name
        print(f"\nApplying patches to {seg_name}...")
        patched = apply_patches(seg_data[seg_name], info["patches"], seg_name)

        seg_hash = hashlib.sha256(patched).digest()
        print(f"\nUpdating hash[{info['hash_index']}]...")
        b01_data, mdt_data = update_hash(
            b01_data, mdt_data, seg_hash, info["hash_index"])

        seg_path.write_bytes(patched)
        patched_files.append(seg_path)

    # Verify mdt embeds b01 correctly
    assert mdt_data[MDT_B01_OFFSET:MDT_B01_OFFSET + B01_TOTAL_SIZE] == b01_data, \
        "mdt/b01 mismatch after update"

    b01_path.write_bytes(b01_data)
    mdt_path.write_bytes(mdt_data)

    print(f"\nPatched files written:")
    for p in patched_files:
        print(f"  {p}")
    print(f"  {b01_path}")
    print(f"  {mdt_path}")
    print(f"\nDeploy to device /lib/firmware/ and reboot.")


if __name__ == "__main__":
    main()
