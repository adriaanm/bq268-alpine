#!/usr/bin/env python3
"""
Decompile modem firmware (Hexagon QDSP6 V5) using pyghidra with analysis.

Uses a persistent Ghidra project so analysis results accumulate across runs.
On first run, imports the full modem ELF, applies known function names and
thunk annotations, and runs Ghidra's analysis engine. Subsequent runs reuse
the analyzed project.

Prerequisites:
  - pyghidra: pip install pyghidra
  - Ghidra 12.0.4 installed at ~/ghidra_12.0.4_PUBLIC
  - Hexagon sleigh plugin: CUB3D/ghidra-hexagon-sleigh (alpha-0.0.10)
    Install to: ~/ghidra_12.0.4_PUBLIC/Ghidra/Extensions/Hexagon/
  - ELF files in /tmp/:
    /tmp/modem.elf      — full monolithic ELF (all 26 segments, ~49MB)
    /tmp/modem_b12.elf  — code segment only (seg12, 17MB)

Usage:
  GHIDRA_INSTALL_DIR=~/ghidra_12.0.4_PUBLIC python3 tools/decompile-modem.py <command>

Commands:
  init          — Create/update project: import ELF, apply labels, analyze
  decompile VA  — Decompile function at hex VA (e.g. 0xC0A15234)
  batch PASS    — Decompile a predefined batch (pass1..pass6)
  list          — List all predefined function targets
  search LABEL  — Search for immext references to known data addresses
"""
import os
import sys
import struct
import time

os.environ.setdefault(
    "GHIDRA_INSTALL_DIR",
    os.path.expanduser("~/ghidra_12.0.4_PUBLIC"),
)

import pyghidra

# ── Project paths ─────────────────────────────────────────────────

PROJECT_DIR = "/tmp/ghidra_modem_project"
PROJECT_NAME = "modem"
FULL_ELF = "/tmp/modem.elf"
B12_ELF = "/tmp/modem_b12.elf"
LANGUAGE = "QDSP6:LE:32:default"

# ── Known function names ──────────────────────────────────────────
# Applied as labels in the Ghidra project for better decompilation.

KNOWN_FUNCTIONS = {
    # QMI UIM layer
    0xC0A15234: "qmi_uim_open_logical_channel",
    0xC0A16DA8: "qmi_uim_restriction_check",
    0xC0A07700: "qmi_uim_dispatch",
    0xC0A07820: "qmi_uim_main_handler",
    0xC0A153D0: "qmi_uim_check_result_not_denied",
    0xC0A153E4: "qmi_uim_process_result",
    0xC0985CC4: "qmi_uim_aid_check",
    0xC09847F8: "qmi_uim_aid_compare",
    0xC098ACC0: "qmi_uim_aid_match_handler",
    0xC0985C7C: "qmi_uim_session_check_thunk",
    0xC0A17A2C: "qmi_uim_get_request_info",
    0xC09C3930: "qmi_uim_pre_dispatch",
    0xC0A05440: "qmi_uim_setup_1",
    0xC0A05640: "qmi_uim_setup_2",
    0xC09C2194: "qmi_uim_init_handler",
    0xC09DBA10: "qmi_uim_reset_result",

    # MMGSDI dispatch chain
    0xC09CAA78: "mmgsdi_async_callback",
    0xC09CAB80: "mmgsdi_async_alt_thunk",
    0xC0A23140: "mmgsdi_session_lookup",
    0xC093B13C: "mmgsdi_dispatch_thunk",
    0xC092A1E4: "mmgsdi_state_machine_thunk",
    0xC1736674: "mmgsdi_dispatch_store_handler",
    0xC1736690: "mmgsdi_dispatch_lookup",
    0xC1735ED4: "mmgsdi_state_machine",
    0xC1735F70: "mmgsdi_generic_handler",
    0xC1736118: "mmgsdi_handler_init",
    0xC1736120: "mmgsdi_handler_cleanup",
    0xC1736130: "mmgsdi_handler_continue",
    0xC17361A0: "mmgsdi_handler_notify",
    0xC1736210: "mmgsdi_handler_complete",
    0xC1736300: "mmgsdi_alt_dispatch",

    # LPA subsystem
    0xC0F1173C: "lpa_main_handler",
    0xC0F115E8: "lpa_isdr_filter_1",
    0xC0F116B4: "lpa_isdr_filter_2",
    0xC0F11758: "lpa_isdr_filter_3",
    0xC0F108B4: "lpa_entry_1",
    0xC0F10514: "lpa_entry_2",
    0xC0F12D14: "lpa_slot_lookup",
    0xC0F12D5C: "lpa_register_handler",
    0xC0F11B4C: "lpa_cleanup",
    0xC0F0D384: "lpa_register",
    0xC0999610: "lpa_is_idle",
    0xC0999630: "lpa_is_state8",

    # LPA thunks to seg9
    0xC0F1051C: "lpa_memcpy_thunk",
    0xC0F11880: "lpa_memset_thunk",
    0xC0F11890: "lpa_search_entry",
    0xC0F119B8: "lpa_search_thunk",

    # seg9 OS/utility (0xC0700000-0xC0733934)
    0xC0717D4C: "mmgsdi_session_state_lookup",
    0xC0717134: "signal_state_read",
    0xC0717168: "session_state_byte",
    0xC0714400: "get_current_task",
    0xC0715C10: "signal_init",
    0xC0716820: "signal_wait",
    0xC071A6C4: "table_validate_index",
    0xC0714250: "memcpy_wrapper",
    0xC071BB78: "session_type_check",
    0xC071BB88: "session_release",
    0xC071BDE0: "session_dispatch",
    0xC071C710: "session_log",
    0xC070DF10: "memcpy",
    0xC070E4E0: "memset",
    0xC070DD00: "memchr",
    0xC070DD58: "strlen",
    0xC0712140: "panic",

    # NV init
    0xC1611600: "nv_init_dispatch",
    0xC1611ED8: "nv_read_file",
    0xC0917B30: "efs_open",
    0xC0F16784: "mcfg_fs_read",

    # Logging
    0xC10DB594: "msg_send_3",
    0xC10DB57C: "msg_send_2",
    0xC0BDE25C: "log_1arg",
    0xC0BDE2C8: "log_2arg",
    0xC0BDE33C: "log_3arg",
    0xC0BDE3C0: "log_4arg",
    0xC0BDE450: "log_narg",
    0xC13E4C88: "err_fatal",

    # LPA AID lookup (in seg21)
    0xC14B4540: "lpa_aid_lookup_1",
    0xC14B408C: "lpa_aid_lookup_2",
    0xC14B4004: "lpa_aid_free",
    0xC14B40BC: "lpa_aid_parse",
    0xC14B46AC: "lpa_aid_iter_next",
    0xC14B51DC: "lpa_asn1_init",
    0xC14B5208: "lpa_asn1_free",
    0xC14B5864: "lpa_asn1_decode",
    0xC14B58E0: "lpa_asn1_decode_2",
    0xC14B5F88: "lpa_asn1_validate",
    0xC14B5F8C: "lpa_asn1_validate_2",
    0xC14B4448: "lpa_aid_result_free",
}

# ── Thunk mappings ────────────────────────────────────────────────
# These 8-byte stubs (immext + jump) fail to decompile due to V5
# duplex encoding issues. We tell Ghidra they're thunks to the real
# target so it inlines the target's decompilation.

THUNKS = {
    0xC093B13C: 0xC1736674,  # mmgsdi_dispatch → dispatch_store_handler
    0xC092A1E4: 0xC1735ED4,  # mmgsdi_state_machine → actual state machine
    0xC0985C7C: 0xC0717D4C,  # session_check → session_state_lookup
    0xC0F1051C: 0xC070DF10,  # lpa memcpy thunk
    0xC0F11880: 0xC070E4E0,  # lpa memset thunk
    0xC0F119B8: 0xC070DD00,  # lpa memchr thunk
    0xC09CAB80: 0xC1736300,  # mmgsdi alt dispatch thunk
}

# ── Batch definitions ─────────────────────────────────────────────

BATCHES = {
    "pass1": {
        "desc": "QMI UIM layer — restriction check, open_logical_channel",
        "targets": [
            0xC0A16DA8, 0xC0A15234, 0xC0985CC4,
            0xC0A153D0, 0xC0A153E4,
        ],
    },
    "pass2": {
        "desc": "AID filter chain — comparison, match, LPA state",
        "targets": [
            0xC09847F8, 0xC0999610, 0xC0999630,
            0xC0F12D14, 0xC098ACC0,
            0xC14B4540, 0xC14B408C,
        ],
    },
    "pass3": {
        "desc": "seg9 OS/utility — session, signal, memcpy",
        "targets": [
            0xC0717D4C, 0xC0717134, 0xC0714400,
            0xC0717168, 0xC0715C10, 0xC0716820,
            0xC071A6C4,
        ],
    },
    "pass4": {
        "desc": "MMGSDI dispatch chain — async callback, state machine",
        "targets": [
            0xC09CAA78, 0xC0A23140,
            0xC1736674, 0xC1736690,
            0xC1735ED4, 0xC1735F70,
        ],
    },
    "pass5": {
        "desc": "QMI UIM main handler — dispatch, setup, result processing",
        "targets": [
            0xC0A07700, 0xC0A07820,
            0xC09C2194, 0xC09C3930,
            0xC09DBA10, 0xC071BDE0,
        ],
    },
    "pass6": {
        "desc": "LPA subsystem — init, handlers, AID matching",
        "targets": [
            0xC0F1173C, 0xC0F115E8, 0xC0F116B4,
            0xC0F11758, 0xC0F108B4, 0xC0F10514,
            0xC0F0D384, 0xC0F11890,
            0xC0F12D5C, 0xC0F11B4C,
        ],
    },
}

# ── Ghidra helpers ────────────────────────────────────────────────

def get_or_create_project(elf_path):
    """Open existing project or create new one from ELF."""
    from java.io import File as JFile
    from ghidra.base.project import GhidraProject

    proj_dir = JFile(PROJECT_DIR)
    proj_file = JFile(os.path.join(PROJECT_DIR, PROJECT_NAME + ".gpr"))

    if proj_file.exists():
        print(f"Opening existing project: {PROJECT_DIR}/{PROJECT_NAME}")
        project = GhidraProject.openProject(PROJECT_DIR, PROJECT_NAME)
        program = project.openProgram("/", PROJECT_NAME, False)
        return project, program

    print(f"Creating new project from {elf_path}")
    os.makedirs(PROJECT_DIR, exist_ok=True)
    project = GhidraProject.createProject(PROJECT_DIR, PROJECT_NAME, False)

    from ghidra.program.model.lang import LanguageID, CompilerSpecID
    from ghidra.program.util import DefaultLanguageService

    lang_svc = DefaultLanguageService.getLanguageService()
    lang = lang_svc.getLanguage(LanguageID(LANGUAGE))
    cspec = lang.getDefaultCompilerSpec()

    program = project.importProgram(JFile(elf_path), lang, cspec)
    project.saveAs(program, "/", PROJECT_NAME, True)
    return project, program


def apply_labels(program):
    """Apply known function names as labels."""
    from ghidra.program.model.symbol import SourceType
    af = program.getAddressFactory()
    space = af.getDefaultAddressSpace()
    st = program.getSymbolTable()
    tid = program.startTransaction("Apply labels")
    count = 0
    try:
        for va, name in KNOWN_FUNCTIONS.items():
            addr = space.getAddress(va)
            existing = st.getPrimarySymbol(addr)
            if existing and existing.getName() == name:
                continue
            st.createLabel(addr, name, SourceType.USER_DEFINED)
            count += 1
    finally:
        program.endTransaction(tid, True)
    if count:
        print(f"  Applied {count} function labels")


def apply_thunks(program):
    """Mark known thunk functions so decompiler resolves them."""
    from ghidra.app.cmd.disassemble import DisassembleCommand
    from ghidra.app.cmd.function import CreateFunctionCmd, CreateThunkFunctionCmd
    from ghidra.program.model.address import AddressSet

    af = program.getAddressFactory()
    space = af.getDefaultAddressSpace()
    fm = program.getFunctionManager()

    tid = program.startTransaction("Apply thunks")
    count = 0
    try:
        for thunk_va, target_va in THUNKS.items():
            thunk_addr = space.getAddress(thunk_va)
            target_addr = space.getAddress(target_va)

            # Ensure both addresses are disassembled
            for va in [thunk_va, target_va]:
                addr = space.getAddress(va)
                addr_set = AddressSet(addr, space.getAddress(va + 0x100))
                cmd = DisassembleCommand(addr, addr_set, True)
                cmd.applyTo(program)

            # Create target function if needed
            target_func = fm.getFunctionAt(target_addr)
            if target_func is None:
                cmd = CreateFunctionCmd(target_addr)
                cmd.applyTo(program)
                target_func = fm.getFunctionAt(target_addr)

            # Create thunk
            thunk_func = fm.getFunctionAt(thunk_addr)
            if thunk_func is not None:
                if thunk_func.isThunk():
                    continue
                # Remove existing non-thunk function
                fm.removeFunction(thunk_addr)

            if target_func is not None:
                cmd = CreateThunkFunctionCmd(thunk_addr, AddressSet(thunk_addr, space.getAddress(thunk_va + 7)), target_addr)
                cmd.applyTo(program)
                count += 1
    finally:
        program.endTransaction(tid, True)
    if count:
        print(f"  Applied {count} thunk annotations")


def run_analysis(program):
    """Disassemble and create functions at all known addresses."""
    from ghidra.app.cmd.disassemble import DisassembleCommand
    from ghidra.app.cmd.function import CreateFunctionCmd
    from ghidra.program.model.address import AddressSet
    from ghidra.program.util import GhidraProgramUtilities

    print("  Disassembling known function regions...")
    t0 = time.time()
    af = program.getAddressFactory()
    space = af.getDefaultAddressSpace()
    fm = program.getFunctionManager()

    tid = program.startTransaction("Targeted disassembly and function creation")
    try:
        # Disassemble generous regions around each known function
        for va in KNOWN_FUNCTIONS:
            addr = space.getAddress(va)
            # Disassemble 16KB around each target (covers most functions + callees)
            start = max(va - 0x400, 0)
            end = min(va + 0x4000, 0xFFFFFFFF)
            addr_set = AddressSet(space.getAddress(start), space.getAddress(end))
            cmd = DisassembleCommand(addr, addr_set, True)
            cmd.applyTo(program)

        # Create functions at each known address
        created = 0
        for va in KNOWN_FUNCTIONS:
            addr = space.getAddress(va)
            if fm.getFunctionAt(addr) is None:
                cmd = CreateFunctionCmd(addr)
                cmd.applyTo(program)
                if fm.getFunctionAt(addr) is not None:
                    created += 1

        elapsed = time.time() - t0
        print(f"  Disassembled {len(KNOWN_FUNCTIONS)} regions, "
              f"created {created} functions ({elapsed:.0f}s)")
    finally:
        program.endTransaction(tid, True)

    # Mark as analyzed so we skip re-analysis on future opens
    tid2 = program.startTransaction("Mark analyzed")
    try:
        from ghidra.program.model.listing import Program
        opts = program.getOptions(Program.PROGRAM_INFO)
        opts.setBoolean("Analyzed", True)
    finally:
        program.endTransaction(tid2, True)


def decompile_function(program, va, timeout=180):
    """Decompile a single function and return C string."""
    from ghidra.app.cmd.disassemble import DisassembleCommand
    from ghidra.app.cmd.function import CreateFunctionCmd
    from ghidra.program.model.address import AddressSet
    from ghidra.app.decompiler import DecompInterface

    af = program.getAddressFactory()
    space = af.getDefaultAddressSpace()
    fm = program.getFunctionManager()

    addr = space.getAddress(va)

    # Ensure disassembled
    addr_set = AddressSet(
        space.getAddress(max(va - 0x200, 0)),
        space.getAddress(min(va + 0x4000, 0xFFFFFFFF)),
    )
    tid = program.startTransaction("Disassemble")
    try:
        cmd = DisassembleCommand(addr, addr_set, True)
        cmd.applyTo(program)
    finally:
        program.endTransaction(tid, True)

    func = fm.getFunctionContaining(addr)
    if func is None:
        tid = program.startTransaction("Create function")
        try:
            cmd = CreateFunctionCmd(addr)
            cmd.applyTo(program)
        finally:
            program.endTransaction(tid, True)
        func = fm.getFunctionAt(addr)

    if func is None:
        return None, f"FAILED to create function at 0x{va:08X}"

    name = func.getName()
    entry = func.getEntryPoint().getOffset()
    body = func.getBody().getNumAddresses()

    decomp = DecompInterface()
    decomp.openProgram(program)
    # Increase decompiler limits for complex functions
    decomp.setSimplificationStyle("decompile")
    result = decomp.decompileFunction(func, timeout, None)
    decomp.dispose()

    if not result.decompileCompleted():
        return None, f"Decompilation timed out for {name} @ 0x{entry:08X}"

    df = result.getDecompiledFunction()
    if not df:
        return None, f"No decompiled output for {name} @ 0x{entry:08X}"

    header = f"[{name}] @ 0x{entry:08X} ({body} bytes)"
    return df.getC(), header


# ── Commands ──────────────────────────────────────────────────────

def cmd_init(elf_path):
    """Create/update Ghidra project with labels and analysis."""
    pyghidra.start()
    project, program = get_or_create_project(elf_path)
    try:
        apply_labels(program)
        apply_thunks(program)
        run_analysis(program)
        project.save(program)
        print(f"\nProject saved to {PROJECT_DIR}/{PROJECT_NAME}")
    finally:
        project.close()


def cmd_decompile(va_str):
    """Decompile a single function by VA."""
    va = int(va_str, 16) if va_str.startswith("0x") or va_str.startswith("0X") else int(va_str, 16)
    pyghidra.start()
    project, program = get_or_create_project(FULL_ELF)
    try:
        c, header = decompile_function(program, va)
        print(f"\n{'='*70}")
        print(header)
        print(f"{'='*70}")
        if c:
            print(c)
        else:
            print(header)  # error message
    finally:
        project.close()


def cmd_batch(pass_name):
    """Decompile a predefined batch of functions."""
    if pass_name not in BATCHES:
        print(f"Unknown batch: {pass_name}")
        print(f"Available: {', '.join(sorted(BATCHES))}")
        sys.exit(1)

    batch = BATCHES[pass_name]
    print(f"{pass_name}: {batch['desc']}\n")

    pyghidra.start()
    project, program = get_or_create_project(FULL_ELF)
    try:
        for va in batch["targets"]:
            name = KNOWN_FUNCTIONS.get(va, f"FUN_{va:08x}")
            c, header = decompile_function(program, va)
            print(f"\n{'='*70}")
            print(header)
            print(f"{'='*70}")
            if c:
                print(c)
            else:
                print(f"  {header}")
            sys.stdout.flush()
    finally:
        project.close()

    print("\n\nDone.")


def cmd_list():
    """List all known functions and batches."""
    print("Known functions:")
    for va in sorted(KNOWN_FUNCTIONS):
        print(f"  0x{va:08X}  {KNOWN_FUNCTIONS[va]}")

    print(f"\nThunks ({len(THUNKS)}):")
    for thunk, target in sorted(THUNKS.items()):
        tn = KNOWN_FUNCTIONS.get(thunk, f"0x{thunk:08X}")
        tt = KNOWN_FUNCTIONS.get(target, f"0x{target:08X}")
        print(f"  {tn} → {tt}")

    print(f"\nBatches:")
    for name, batch in sorted(BATCHES.items()):
        funcs = [KNOWN_FUNCTIONS.get(va, f"0x{va:08X}") for va in batch["targets"]]
        print(f"  {name}: {batch['desc']}")
        for f in funcs:
            print(f"    - {f}")


def cmd_search(label):
    """Search for immext references to known addresses."""
    targets = {
        "isdr_aid":     (0xC1CD0640, "ISD-R AID region"),
        "lpa_aid_table": (0xC27EE280, "LPA AID table"),
        "async_result":  (0xC2149D80, "Async result (0xC2149DB0)"),
        "session_table": (0xC2DA5600, "Session table (0xC2DA5618)"),
        "dispatch_static": (0xC1F8B580, "MMGSDI static dispatch table"),
        "dispatch_dynamic": (0xC1F8B640, "MMGSDI dynamic dispatch table"),
        "lpa_state":     (0xC2149980, "LPA state (0xC21499B0)"),
    }

    if label not in targets:
        print(f"Unknown search target: {label}")
        print(f"Available: {', '.join(sorted(targets))}")
        sys.exit(1)

    upper, desc = targets[label]
    hi12 = (upper >> 20) & 0xFFF
    lo14 = (upper >> 6) & 0x3FFF

    with open(B12_ELF, "rb") as f:
        data = f.read()

    # Get segment info
    with open(B12_ELF, "rb") as f:
        f.seek(0x1C)
        phoff = struct.unpack("<I", f.read(4))[0]
        f.seek(phoff)
        ph = struct.unpack("<8I", f.read(32))
    seg_off, seg_va, seg_filesz = ph[1], ph[2], ph[4]
    seg_end = seg_off + seg_filesz

    print(f"Searching b12 for {desc} (immext upper=0x{upper:08X}):")
    total = 0
    for pp in range(4):
        word = (hi12 << 16) | (pp << 14) | lo14
        enc = struct.pack("<I", word)
        pos = seg_off
        while True:
            idx = data.find(enc, pos, seg_end)
            if idx == -1:
                break
            va = seg_va + (idx - seg_off)
            name = KNOWN_FUNCTIONS.get(va, "")
            name_str = f"  ({name})" if name else ""
            print(f"  VA 0x{va:08X}{name_str}")
            total += 1
            pos = idx + 4

    print(f"  Total: {total} references")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "init":
        elf = sys.argv[2] if len(sys.argv) > 2 else FULL_ELF
        cmd_init(elf)
    elif cmd == "decompile" and len(sys.argv) > 2:
        cmd_decompile(sys.argv[2])
    elif cmd == "batch" and len(sys.argv) > 2:
        cmd_batch(sys.argv[2])
    elif cmd == "list":
        cmd_list()
    elif cmd == "search" and len(sys.argv) > 2:
        cmd_search(sys.argv[2])
    else:
        print(__doc__)
        sys.exit(1)


if __name__ == "__main__":
    main()
