#!/usr/bin/env python3
"""
Partial decompilation of modem firmware (Hexagon QDSP6 V5) using pyghidra.
Targets QMI UIM access check functions and LPA AID filter code.

Prerequisites:
  - pyghidra: pip install pyghidra
  - Ghidra 12.0.4 installed at ~/ghidra_12.0.4_PUBLIC
  - Hexagon sleigh plugin: CUB3D/ghidra-hexagon-sleigh (alpha-0.0.10)
    Install to: ~/ghidra_12.0.4_PUBLIC/Ghidra/Extensions/Hexagon/
  - ELF files in /tmp/ (created by wrap-modem-elf.py or similar):
    /tmp/modem.elf      — full monolithic ELF (all 26 segments, ~49MB)
    /tmp/modem_b12.elf  — code segment only (seg12, 17MB)
    /tmp/modem_b14.elf  — data segment only (seg14, 6.3MB)

Usage:
  GHIDRA_INSTALL_DIR=~/ghidra_12.0.4_PUBLIC python3 tools/decompile-modem.py [pass]

  pass 1: Core functions — restriction check, open_logical_channel, aid_check, LPA
  pass 2: AID filter chain — called functions from pass 1
  pass 3: Cross-segment functions — OS/utility functions in seg9
  pass 4: ISD-R AID reference search + async handler
  pass 5: MMGSDI dispatch chain — state machine, dispatch tables, AID routing

See docs/modem_patch_plan.md for firmware layout and VA addresses.
"""
import os
import sys
import struct

os.environ.setdefault(
    "GHIDRA_INSTALL_DIR",
    os.path.expanduser("~/ghidra_12.0.4_PUBLIC"),
)

import pyghidra


def decompile_targets(elf_path, targets, language="QDSP6:LE:32:default"):
    """Open an ELF, disassemble+decompile at each target VA."""
    with pyghidra.open_program(elf_path, language=language, analyze=False) as flat:
        program = flat.getCurrentProgram()
        from ghidra.app.cmd.disassemble import DisassembleCommand
        from ghidra.app.cmd.function import CreateFunctionCmd
        from ghidra.program.model.address import AddressSet
        from ghidra.app.decompiler import DecompInterface

        af = program.getAddressFactory()
        space = af.getDefaultAddressSpace()
        fm = program.getFunctionManager()

        # Disassemble around each target
        for name, va in targets.items():
            addr_set = AddressSet(
                space.getAddress(max(va - 0x100, 0)),
                space.getAddress(va + 0x2000),
            )
            cmd = DisassembleCommand(space.getAddress(va), addr_set, True)
            cmd.applyTo(program)

        decomp = DecompInterface()
        decomp.openProgram(program)

        for name, va in targets.items():
            addr = space.getAddress(va)
            func = fm.getFunctionContaining(addr)
            if func is None:
                cmd = CreateFunctionCmd(addr)
                cmd.applyTo(program)
                func = fm.getFunctionAt(addr)

            print(f"\n{'='*70}")
            if func is None:
                print(f"[{name}] FAILED at 0x{va:08X}")
                continue

            entry = func.getEntryPoint().getOffset()
            body = func.getBody().getNumAddresses()
            print(f"[{name}] {func.getName()} @ 0x{entry:08X} ({body} bytes)")
            print(f"{'='*70}")

            result = decomp.decompileFunction(func, 120, None)
            if result.decompileCompleted():
                df = result.getDecompiledFunction()
                if df:
                    c = df.getC()
                    if len(c) > 8000:
                        print(c[:8000])
                        print(f"\n  [... truncated, {len(c)} chars total ...]")
                    else:
                        print(c)

        decomp.dispose()


def search_immext(elf_path, immext_bytes, label):
    """Search a binary for an immext instruction pattern."""
    with open(elf_path, "rb") as f:
        data = f.read()

    f2 = open(elf_path, "rb")
    f2.seek(0x1C)
    phoff = struct.unpack("<I", f2.read(4))[0]
    f2.seek(phoff)
    ph = struct.unpack("<8I", f2.read(32))
    seg_off, seg_va = ph[1], ph[2]
    seg_end = seg_off + ph[4]
    f2.close()

    pos = seg_off
    results = []
    while True:
        idx = data.find(immext_bytes, pos)
        if idx == -1 or idx >= seg_end:
            break
        va = seg_va + (idx - seg_off)
        results.append(va)
        pos = idx + 1

    print(f"\n{label}: found {len(results)} references")
    for va in results:
        print(f"  VA 0x{va:08X}")
    return results


# ── Pass definitions ──────────────────────────────────────────────

PASS1_TARGETS = {
    # Already-patched restriction bitmask loader
    "restriction_check":        0xC0A16DA8,
    # Open logical channel handler (calls restriction_check twice)
    "open_logical_channel":     0xC0A15234,
    # AID-specific check called from open_logical_channel
    "aid_check":                0xC0985CC4,
    # LPA subsystem — ISD-R AID filter code
    "lpa_isdr_filter_1":        0xC0F115E8,
    "lpa_isdr_filter_2":        0xC0F116B4,
    "lpa_isdr_filter_3":        0xC0F11758,
    # NV init / path table dispatch
    "nv_init_dispatch":         0xC1611600,
}

PASS2_TARGETS = {
    # Pre-check (thunk to 0xC0717D4C in seg9)
    "session_or_aid_check":     0xC0985C7C,
    # Called from aid_check — QMI UIM command processor
    "aid_compare":              0xC09847F8,
    # ISD-R/LPA state checks
    "isdr_check_1":             0xC0999610,
    "isdr_check_2":             0xC0999630,
    # LPA thunks (to seg9 utility functions)
    "lpa_memcpy_thunk":         0xC0F1051C,
    "lpa_memset_thunk":         0xC0F11880,
    "lpa_search_thunk":         0xC0F119B8,
    "lpa_slot_lookup":          0xC0F12D14,
    # Aid match handler
    "aid_match_handler":        0xC098ACC0,
    # LPA AID lookup functions
    "lpa_aid_lookup_1":         0xC14B4540,
    "lpa_aid_lookup_2":         0xC14B408C,
}

PASS3_TARGETS = {
    # Functions in seg9 (0xC0700000-0xC0733934, OS/utility layer)
    # These are called from b12 via thunks
    "session_state_lookup":     0xC0717D4C,
    "lpa_state_read":           0xC0717134,
    "get_current_task":         0xC0714400,
    "session_state_byte":       0xC0717168,
    "signal_init":              0xC0715C10,
    "signal_wait":              0xC0716820,
    # QMI dispatch function (calls open_logical_channel)
    "qmi_dispatch":             0xC0A07700,
}

PASS4_TARGETS = {
    # Async handler that processes open_logical_channel after signal
    # Writes result to 0xC2149DB4 which is read by the handler
    "async_process":            0xC0A23140,
    # Session management functions called from async handler
    "session_mgr_1":            0xC093B13C,
    "session_mgr_2":            0xC092A1E4,
}

PASS5_B12_TARGETS = {
    # MMGSDI dispatch chain — resolved thunk targets in seg12
    # dispatch_table_store: just stores R1 at R0+0x14, tiny function
    "dispatch_table_store":     0xC1736674,
    # dispatch_table_lookup: searches APDU cmd tables at 0xC1F8B588/0xC1F8B648
    "dispatch_table_lookup":    0xC1736690,
    # state_machine: decides callback (returns -2) vs generic path
    "state_machine":            0xC1735ED4,
    # generic_handler: processes APDU through normal MMGSDI path
    "generic_handler":          0xC1735F70,
    # MMGSDI async callback: entry point for incoming APDU signals
    "mmgsdi_async_callback":    0xC09CAA78,
    # LPA main handler: copies ISD-R AID, checks LPA AID table at 0xC27EE260
    "lpa_main_handler":         0xC0F1173C,
}

PASS5_FULL_TARGETS = {
    # validate function in seg9: table index lookup that gates callback path
    "validate_table_lookup":    0xC071A6C4,
}


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    pass_num = sys.argv[1]

    if pass_num == "1":
        print("Pass 1: Core functions (using b12 ELF)")
        decompile_targets("/tmp/modem_b12.elf", PASS1_TARGETS)

    elif pass_num == "2":
        print("Pass 2: AID filter chain (using b12 ELF)")
        decompile_targets("/tmp/modem_b12.elf", PASS2_TARGETS)

    elif pass_num == "3":
        print("Pass 3: Cross-segment functions (using full modem.elf)")
        decompile_targets("/tmp/modem.elf", PASS3_TARGETS)

    elif pass_num == "4":
        print("Pass 4: Async handler + ISD-R AID search")
        decompile_targets("/tmp/modem.elf", PASS4_TARGETS)

        # Search for references to LPA AID table (0xC27EE290)
        # immext(#0xc27ee280) = 8a 7b 27 0c
        search_immext(
            "/tmp/modem_b12.elf",
            bytes([0x8A, 0x7B, 0x27, 0x0C]),
            "LPA AID table (immext 0xC27EE280)",
        )

        # Search for references to async result (0xC2149DB0)
        # immext(#0xc2149d80) = 76 52 21 0c
        search_immext(
            "/tmp/modem_b12.elf",
            bytes([0x76, 0x52, 0x21, 0x0C]),
            "Async result (immext 0xC2149D80)",
        )

    elif pass_num == "5":
        print("Pass 5: MMGSDI dispatch chain (b12 + full ELF)")
        decompile_targets("/tmp/modem_b12.elf", PASS5_B12_TARGETS)
        decompile_targets("/tmp/modem.elf", PASS5_FULL_TARGETS)

    elif pass_num == "search":
        print("Searching for ISD-R AID references in b12")
        # immext(#0xc1cd0640) = 19 74 1c 0c
        search_immext(
            "/tmp/modem_b12.elf",
            bytes([0x19, 0x74, 0x1C, 0x0C]),
            "ISD-R AID region (immext 0xC1CD0640)",
        )

    else:
        print(f"Unknown pass: {pass_num}")
        print("Valid passes: 1, 2, 3, 4, 5, search")
        sys.exit(1)

    print("\n\nDone.")


if __name__ == "__main__":
    main()
