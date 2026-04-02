# Modem Firmware Decompilation Plan — APDU Restriction Bypass

## Goal

Patch the modem's QMI UIM service to skip the APDU security restriction
check (NV 67312), allowing logical channel operations for eSIM provisioning.

## Why firmware patching

Every AP-side approach to create the NV file has been blocked:

| Approach | Result |
|----------|--------|
| DIAG EFS PUT | Returns success but silently discards (security filter) |
| DIAG EFS OPEN+O_CREAT | Rejected as bad command |
| QMI PDC (MBN config) | Modem parser crashes on custom NV_FILE items |
| QMI UIM | AccessDenied (the restriction we're trying to bypass) |
| AT+CSIM | "operation not supported" on this firmware |
| rmt_storage overrides | Fresh EFS lacks file; FSG golden copy ignored |

The restriction is enforced inside the Hexagon modem firmware. The NV file
doesn't exist in factory EFS and can't be created from the AP.

## Firmware details

| Property | Value |
|----------|-------|
| Architecture | Hexagon QDSP6 V5 (e_machine=0xA4) |
| Build date | Sep 27 2024 |
| Entry point | 0x88000000 |
| Segments | 26 program headers, ~47MB total |
| Signing | RSA-2048 signature + 6KB cert chain |
| Secure boot | Likely NOT enforced ("Debug policy not present - msadp. Continue.") |
| Partition | FAT16 filesystem on eMMC `modem` partition |
| Files | `modem.mdt` + `modem.b00`–`modem.b24` (split ELF format) |
| EDL dump | `~/bq268-edl/dump/modem.bin` (69MB, full partition) |

## Ghidra setup

1. **Install Hexagon plugin**: need a Ghidra Hexagon processor module.
   Options: [ghidra-hexagon](https://github.com/gsmk/ghidra-hexagon)
   or [quarklab hexagon plugin](https://github.com/quarkslab/ghidra-hexagon).

2. **Reassemble split ELF**: Ghidra can't load split mdt+bXX directly.
   Use `pil-splitter` in reverse, or concatenate segments manually:
   ```
   # Quick approach: extract from FAT partition
   # The Hexagon ELF starts at offset 0xAC600 in modem.bin
   # Or use the mdt+bXX files to reconstruct a monolithic ELF
   ```

3. **Load in Ghidra**: Import as ELF, select Hexagon QDSP6 processor.
   Base address: 0xC0000000 (from PH3 vaddr).

## Target segment

**PH14** — the LOAD segment containing QMI UIM code and data:

```
PH14: off=0x01999000  vaddr=0xC1A00000  size=6.3MB  (modem.b14)
```

This segment contains:
- `/nv/item_files/modem/qmi/uim/apdu_security_restrictions` at **va 0xC1E72F50**
- `/nv/item_files/modem/qmi/uim/auth_security_restrictions` at **va 0xC1E72F18**
- `/nv/item_files/modem/qmi/uim/sap_security_restrictions` at **va 0xC1E72EE1**
- `/nv/item_files/modem/qmi/uim/apdu_security_aid_list` at **va 0xC1E72FD6**
- Source file name `qmi_uim.c` at **va 0xC1C21DBE**
- Source file name `qmi_uim_parsing.c` at **va 0xC1C21DD7**

The QMI UIM debug strings (qmi_uim_util.c messages) are also in this segment,
at va 0xC1E72000+ region.

## Decompilation strategy

### Step 1: Find the NV read

Search for cross-references (XREFs) to the string at **va 0xC1E72F50**
(`apdu_security_restrictions`). This will lead to the function that:
1. Constructs the full EFS path `/nv/item_files/modem/qmi/uim/apdu_security_restrictions`
2. Calls an EFS/NV read function (likely `mcfg_fs_read()` or `efs_get()`)
3. Stores the result in a global variable or struct field

### Step 2: Find the access check

The NV read result feeds into a check function. Look for the pattern:
```
load restriction_value
compare with 0
branch if nonzero → allow APDU
(default path) → deny with QMI error 82 (AccessDenied)
```

The function is likely called from QMI UIM's `open_logical_channel` and
`send_apdu` message handlers. Search for XREF chains:
- String "apdu_security_restrictions" → NV read function → check function
- QMI message handler (msg 0x0042) → check function → error path

### Step 3: Identify the patch point

Two options:

**Option A — Patch the check function return value:**
Make the security check function always return "unrestricted" (0).
Typically a single instruction change: force the return register to 0.

**Option B — Patch the NV read default:**
Where the code handles "NV file not found" (EFS error 2 = ENOENT),
change the default from "restricted" to "unrestricted".
This is usually a `mov R0, #1` → `mov R0, #0` change.

Option B is preferred — it's a smaller semantic change and leaves the
restriction mechanism intact for cases where the file exists.

### Step 4: Patch and rebuild

1. Modify the bytes in the relevant segment file (`modem.b14`)
2. Recompute the SHA256 hash for the modified segment
3. Update the hash in the hash segment (`modem.b01`)
4. If secure boot is enforced: resign with the development key, or find
   a way to disable signature checking

### Step 5: Test

1. Flash modified `modem.b01` + `modem.b14` to the modem partition
2. Reboot — check `dmesg` for PIL loading errors
3. Test: `qmicli -d msmipc://0 --uim-open-logical-channel=1,<ISD-R AID>`
4. If access granted: proceed with eSIM provisioning

## Signature / secure boot — TESTED

The hash segment (modem.b01) header shows:
- `signature_size = 0x100` (256 bytes, RSA-2048)
- `cert_chain_size = 0x1800` (6144 bytes)

The firmware IS signed, and **MBA DOES enforce hash verification.**

**Test result (2026-04-02)**: Modified 4 bytes in modem.b12 (code patch at
VA 0xC0A16DCC). Tried both with and without updating b01 hashes. Both failed:
```
MBA returned error -19 for image
RMB_MBA_STATUS: ffffffed
RMB_MBA_DEBUG_INFORMATION: 00000012
pil-q6v5-mss: modem: Failed to bring out of reset(rc:-22)
```

Error code 0x12 = hash/integrity check failure. The MBA verifies:
1. Each segment's SHA-256 against the hash in modem.b01
2. The hash segment (b01) itself against a signature

The message `Debug policy not present - msadp. Continue.` refers to debug
policy specifically — the signature/hash chain is still enforced.

**Next steps for firmware patching:**
- Extract the certificate chain from modem.b01 and check if it uses
  Qualcomm development keys (publicly known)
- Check if the Secure Boot fuses (QFPROM) are blown or open
- If fuses are open, we can resign with a development key
- Alternative: patch the MBA (mba.mbn) to skip hash verification, though
  the MBA itself may also be signature-checked by PBL/SBL

## Decompilation results — COMPLETED

### Actual string locations (corrected from initial plan)

| String | VA | File offset in b14 |
|--------|-----|-------------------|
| `apdu_security_restrictions` | 0xC1E5FF6D | 0x45FF6D |
| Full path `/nv/item_files/modem/qmi/uim/apdu_security_restrictions` | **0xC1E5FF50** | 0x45FF50 |
| `auth_security_restrictions` | 0xC1E5FF35 | 0x45FF35 |
| `sap_security_restrictions` | 0xC1E5FEFE | 0x45FEFE |
| `qmi_uim.c` | 0xC1C0EDBE | 0x20EDBE |

### NV path pointer table

33-entry table of NV item path pointers at VA 0xC1E60540–0xC1E605C4 (in b14 data).
Entry at index 23 (VA 0xC1E6059C) points to the APDU restriction path.

### Code flow — restriction check

**Restriction bitmask accessor** at VA 0xC0A16DA8 (in modem.b12, segment 12):
```hexagon
allocframe(#0x0)
r0 = ##0xC3454D80                          // session lookup key
r1 = memw(r0<<#2 + ##0xC2DA5620)          // lookup session in table
if (r1 == 0) jump error
r1 = memw(r1+#0x4)                         // follow pointer chain
if (r1 == 0) jump error
r0 = memw(r1+#0x7B8)                       // ← restriction bitmask
dealloc_return
```

Returns a bitmask at struct offset **0x7B8**. Bit meanings:
- **Bit 2**: APDU security restriction (logical channel + send APDU)
- **Bit 8**: Additional restriction (checked in open_logical_channel)

**Open logical channel handler** at VA 0xC0A15234 (in modem.b12):
```hexagon
call 0xC0A16DA8                            // get restriction bitmask
p0 = !tstbit(r0, #0x2)                     // test APDU restriction bit
if (p0.new) jump allowed_path              // bit clear → APDU allowed
// bit set → fall through to denied:
r20 = #0x1                                 // error flag
jump error_handling
```

### Identified patch point

**modem.b12 offset 0x121DCC** (VA 0xC0A16DCC):
```
Original: C0 7D 81 91  →  r0 = memw(r1+#0x7B8)   // load restriction bitmask
Patched:  00 40 00 78  →  r0 = #0x0                // always return "no restrictions"
```

This patch disables ALL QMI UIM security restrictions (APDU, SAP, auth).
The patch is valid Hexagon V5 — same parse bits (PP=01), same packet structure.
**Blocked by MBA hash verification** — see above.

### NV init function

NV items are read at init by a dispatch function at ~VA 0xC1611600 (in b12).
It iterates over the NV path table, calls:
1. `strlen()` at 0xC1825F60
2. `mcfg_fs_read()` at 0xC0F16784 (args: buf, 0x100, path, path_len)
Results stored in a structure, accessed later via offset 0x7B8 bitmask.

## Non-patch approaches — ALL EXHAUSTED

| Approach | Result |
|----------|--------|
| DIAG EFS PUT/CREATE | No response (kernel DIAG MUX bug: encode_rsp_and_send err -19) |
| DIAG EFS OPEN+O_CREAT | No response |
| MCFG/PDC SW config | Config activates but NV items not applied (needs matching SIM) |
| MCFG/PDC + reboot | Reliance config NV items crash modem (incompatible NVs) |
| MCFG HW config | No HW config infrastructure on modem partition |
| rmt_storage empty EFS | Modem creates fresh EFS — no NV file → still restricted |
| AT+CSIM | "operation not supported" |
| QMI UIM | AccessDenied (the restriction itself) |
| DIAG MMGSDI/UIM (0x19, 0x44, 0x48) | Subsystems don't respond |
| Legacy NV_WRITE (cmd 0x27) | Item 0x106F0 exceeds 16-bit ID range |
| Factory EFS (EDL modemst dumps) | No `apdu_security_restrictions` file found |
| Factory MCFG MBNs (60+ configs on modem partition) | None contain the NV item |

**Key finding**: Factory MCFG MBNs DO support NV_FILE type items (Reliance
config has 60 NV_FILE items). The PDC crash in earlier testing was caused
by using a full carrier config whose NV items are incompatible with the BQ268
hardware — not by the NV_FILE format itself.

## Related NV items (same access control family)

All three share the same code pattern — patching one reveals the pattern for all:

| NV path | Controls | Restriction bit |
|---------|----------|-----------------|
| `apdu_security_restrictions` | Logical channel + APDU send | Bit 2 |
| `sap_security_restrictions` | SAP (SIM Access Profile) | TBD |
| `auth_security_restrictions` | Authentication commands | TBD |

## Source file map (from debug strings)

| Source file | Role |
|------------|------|
| `qmi_uim.c` | Main QMI UIM service (message handlers) |
| `qmi_uim_util.c` | Utility functions (slot validation, etc.) |
| `qmi_uim_parsing.c` | QMI TLV parsing |
| `qmi_uim_encryption.c` | Encrypted APDU handling |
| `qmi_uim_cat_common.c` | CAT/STK shared code |
| `qmi_uim_simlock.c` | SIM lock / personalization |
| `qmi_uim_simlock_parsing.c` | SIM lock TLV parsing |

## Tools and files on buildbox

```
# Disassembly (working)
llvm-objdump-14 -D --triple=hexagon --print-imm-hex /tmp/modem_b12.elf

# Reconstructed ELF files (for disassembly)
/tmp/modem_b12.elf          # b12 code segment wrapped in ELF with .text section
/tmp/modem_b14.elf          # b14 data segment wrapped in ELF
/tmp/modem.elf              # Full monolithic ELF (all segments)

# Modem partition (mounted read-only)
/tmp/modem-fat/             # FAT16 mount of ~/bq268-edl/dump/modem.bin

# Patched files (hash verification blocks flashing)
/tmp/modem_b12_patched.bin  # modem.b12 with 4-byte patch at offset 0x121DCC
/tmp/modem_b01_patched.bin  # modem.b01 with updated SHA-256 for b12
```

## Next steps

1. **Check QFPROM secure boot fuses** — `cat /sys/bus/nvmem/devices/qfprom*/nvmem`
   or read via DIAG. If fuses are open, resign with development keys.
2. **Extract and analyze cert chain from b01** — identify if keys are
   Qualcomm development (publicly known) or OEM-specific.
3. **Consider patching MBA (mba.mbn)** — if MBA hash check can be disabled,
   unsigned segments can be loaded. MBA is loaded by PBL/SBL and may have
   its own signature chain.
4. **Fix kernel DIAG driver** — the MUX response path (encode_rsp_and_send
   err -19) blocks all DIAG EFS operations. If fixed, DIAG EFS might work
   for creating the NV file directly (some firmwares allow creation after
   SPC unlock).
