# Modem Firmware Patch — APDU Restriction Bypass

## Goal

Bypass the modem's QMI UIM APDU security restriction (NV 67312) to allow
logical channel operations for eSIM provisioning.

## Status: patch identified, blocked by MBA signature verification

The restriction check function has been found and a 4-byte patch identified.
Flashing is blocked because the MBA (Modem Boot Authenticator) verifies
SHA-256 hashes AND RSA-2048 signatures on every segment. The firmware is
signed with Qualcomm test keys (QPSA F4 TEST) — if we obtain the private
keys or find a way to bypass the signature check, the patch is ready to go.

## AP-side approaches — all exhausted

Every approach to create or write the NV file from the application processor
has been tried and failed:

| Approach | Result | Notes |
|----------|--------|-------|
| DIAG EFS PUT | **Returns success, silently discards** | Confirmed with fixed DIAG driver (kernel #52). PUT returns error code 0 but file does not exist on read-back. Modem EFS security policy accepts the command but blocks creation on protected `/nv/item_files/modem/qmi/uim/` paths. SPC unlock does not help. |
| DIAG EFS OPEN+O_CREAT | fd=-1 errno=2 | OPEN with O_CREAT returns ENOENT — same security policy. |
| QMI PDC (MBN config) | NV items not applied | Config loads and activates, but SW configs only apply NV items when SIM PLMN matches the carrier profile. No SIM → no NV writes. Activating Reliance config + reboot **crashed the modem** (incompatible NVs for BQ268 hardware — caused bootloop, required EFS wipe). |
| QMI UIM | AccessDenied | This is the restriction we're trying to bypass. |
| AT+CSIM | "operation not supported" | Firmware advertises AT+CSIM but doesn't implement it. |
| rmt_storage overrides | No effect | Serving empty modemst1/modemst2 creates fresh EFS, but the NV file doesn't exist in factory state. FSG golden copy is ignored. |
| DIAG MMGSDI/UIM (0x19, 0x44, 0x48) | No response | Subsystems don't register DIAG commands on this firmware. |
| Legacy NV_WRITE (cmd 0x27) | N/A | Item ID 0x106F0 exceeds 16-bit NV ID range. |
| Factory EFS (EDL modemst dumps) | File not found | `apdu_security_restrictions` doesn't exist in factory EFS. |
| Factory MCFG MBNs | None contain item | Checked all 60+ carrier configs on modem partition. |

**Key finding on MCFG/PDC**: Factory MBNs DO support NV_FILE type items
(Reliance config has 60 NV_FILE items that load fine). The "PDC crashes on
custom NV_FILE items" from earlier docs was wrong — the crash came from
activating a full carrier config with NVs incompatible with BQ268 hardware.

**Key finding on DIAG**: The kernel DIAG driver fix (commit 034ada814c88,
kernel #52) restored bidirectional DIAG communication. With working responses,
we confirmed that EFS PUT **returns success but silently discards** — the
modem's EFS security policy blocks file creation on protected NV paths even
after SPC unlock. This eliminates DIAG EFS as a viable path.

## Firmware details

| Property | Value |
|----------|-------|
| Architecture | Hexagon QDSP6 V5 (e_machine=0xA4) |
| Build date | Sep 27 2024 |
| Entry point | 0x88000000 |
| Segments | 26 program headers, ~47MB total |
| Code segment | **modem.b12** — seg 12, VA 0xC08F5000, 17MB, PF_R\|PF_X |
| Data segment | **modem.b14** — seg 14, VA 0xC1A00000, 6.3MB, PF_R (no execute) |
| Hash segment | **modem.b01** — 7272 bytes (40-byte header + 26×32 hashes + 256 sig + 6144 certs) |
| Signing | SHA256 + RSA-2048 PKCS#1 v1.5 (custom padding — raw hash, no DigestInfo) |
| Cert chain | **QPSA F4 TEST** (Qualcomm development keys) — 3 certs |
| Partition | FAT16 on eMMC `modem` partition |
| Files | `modem.mdt` + `modem.b00`–`modem.b24` (split ELF format) |
| EDL dump | `~/bq268-edl/dump/modem.bin` (69MB, full partition) |

## Decompilation results

Disassembled with `llvm-objdump-14 --triple=hexagon` (LLVM 14 has Hexagon target).

### String locations (in modem.b14, data segment)

| String | VA | b14 offset |
|--------|-----|-----------|
| Full path `/nv/item_files/modem/qmi/uim/apdu_security_restrictions` | **0xC1E5FF50** | 0x45FF50 |
| `auth_security_restrictions` | 0xC1E5FF35 | 0x45FF35 |
| `sap_security_restrictions` | 0xC1E5FEFE | 0x45FEFE |
| `apdu_security_aid_list` | 0xC1E5FFD6 | 0x45FFD6 |
| `qmi_uim.c` | 0xC1C0EDBE | 0x20EDBE |
| `qmi_uim_util.c` | 0xC1C0EDC8 | 0x20EDC8 |

### NV path pointer table

33-entry table at VA 0xC1E60540–0xC1E605C4 (null-terminated) in b14.
Entry at **index 23** (VA 0xC1E6059C) points to the APDU restriction path.

The table is accessed by a dispatch function at ~VA 0xC1611600 (in b12) via:
```hexagon
r17 = memw(r0<<#0x2 + ##0xC1E60540)    // load path pointer from table[r0]
```

### Restriction check function (VA 0xC0A16DA8, in modem.b12)

```hexagon
allocframe(#0x0)
r0 = ##0xC3454D80                          // session lookup key
r1 = memw(r0<<#2 + ##0xC2DA5620)          // lookup session in table
if (r1 == 0) jump error
r1 = memw(r1+#0x4)                         // follow pointer chain
if (r1 == 0) jump error
r0 = memw(r1+#0x7B8)                       // ← load restriction bitmask
dealloc_return                              // return bitmask in r0
```

Returns a bitmask from struct offset **0x7B8**:
- **Bit 2**: APDU security restriction (logical channel + send APDU)
- **Bit 8**: Additional restriction (also checked in open_logical_channel)

### Open logical channel handler (VA 0xC0A15234, in modem.b12)

```hexagon
call 0xC0A16DA8                            // get restriction bitmask
p0 = !tstbit(r0, #0x2)                     // test APDU restriction bit
if (p0.new) jump allowed_path              // bit clear → APDU allowed
// bit set → fall through to denied:
r20 = #0x1                                 // error flag
jump error_handling
```

The function calls the restriction check twice (at VA 0xC0A15298 and
0xC0A152C8), testing bit 2 and bit 8 respectively.

### NV init function (~VA 0xC1611600, in modem.b12)

Reads all NV items at modem boot via dispatch over the path table:
1. `strlen()` at VA 0xC1825F60
2. `mcfg_fs_read()` at VA 0xC0F16784 (args: r0=buf, r1=0x100, r2=path, r3=pathlen)

Results stored in a session structure, accessible via the restriction check
function's bitmask at offset 0x7B8.

## The patch

**modem.b12 offset 0x121DCC** (VA 0xC0A16DCC):
```
Original: C0 7D 81 91  →  r0 = memw(r1+#0x7B8)   // load restriction bitmask
Patched:  00 40 00 78  →  r0 = #0x0                // always "no restrictions"
```

Valid Hexagon V5 — same parse bits (PP=01), same packet structure
`{ r0 = ...; dealloc_return }`. Disables ALL QMI UIM security restrictions
(APDU, SAP, auth) since the function always returns 0.

## Signature verification — TESTED, ENFORCED

**MBA enforces both hash AND signature verification.**

Test (2026-04-02): Applied the 4-byte patch to modem.b12 on device.
Tried two approaches — both failed identically:

1. Updated b01 hash for b12, kept original signature → MBA error -19
2. Original b01 (hash mismatch for b12) → MBA error -19

```
MBA returned error -19 for image
RMB_MBA_STATUS: ffffffed
RMB_MBA_DEBUG_INFORMATION: 00000012
pil-q6v5-mss: modem: Failed to bring out of reset(rc:-22)
```

Debug code 0x12 = hash/integrity failure. The modem won't boot with ANY
modification to ANY segment unless the hash segment signature is valid.

**Consequence**: The earlier log message `Debug policy not present - msadp.
Continue.` does NOT mean secure boot is disabled — it refers specifically to
debug policy. The hash/signature chain is fully enforced.

**Consequence**: Leaving patched firmware in `/lib/firmware/` causes a
bootloop — the modem fails to load on every boot, and repeated subsystem
restart failures eventually crash the system. This required reflashing the
rootfs to recover.

### Certificate chain analysis

Extracted from modem.b01 (offset 0x468, 6144 bytes):

| Cert | CN | O | Size |
|------|----|---|------|
| Attestation | SecTools Test User | SecTools | 1199 bytes |
| CA | QPSA F4 TEST CA | QUALCOMM | 1034 bytes |
| Root | QPSA F4 TEST ROOT | QUALCOMM | 1059 bytes |

Attestation cert OUs (define what it can sign):
- `SW_ID = 0000000000000002` (modem image type)
- `HW_ID = 0000000000000000` (no hardware restriction)
- `OEM_ID = 0000`
- `SHA256 = 0001` (algorithm selector)

**These are Qualcomm development/test keys** from the SecTools package.
The private keys are NOT on this buildbox but are widely available in
Qualcomm SDK distributions.

Signing uses SHA-256 + RSA-2048 with a **custom PKCS#1 v1.5 variant**:
the signed data is `00 01 FF..FF 00 <raw-32-byte-SHA256>` (no ASN.1
DigestInfo wrapper). The exact data range that's hashed is TBD — standard
candidates (header+hashes, hashes-only) didn't match the decrypted signature.

### Prepared patch files (on buildbox /tmp/)

| File | Description |
|------|-------------|
| `modem_b12_patched.bin` | modem.b12 with 4-byte patch at offset 0x121DCC |
| `modem_b01_patched.bin` | modem.b01 with updated SHA-256 hash for b12 (invalid sig) |
| `modem_b01_nosig.bin` | modem.b01 with updated hash, sig_size=0, cert_size=0, truncated |
| `modem_b01_nosig_wcert.bin` | modem.b01 with updated hash, sig_size=0, certs kept |
| `modem_b01_badsig.bin` | modem.b01 with updated hash, original (invalid) sig+certs |

## Next steps (priority order)

### 1. Check QFPROM secure boot fuses

Read QFPROM to determine if a root certificate hash is programmed:
```bash
cat /sys/bus/nvmem/devices/qfprom*/nvmem | xxd | head -20
# Or via DIAG if the sysfs path doesn't exist
```

If the root hash fuse is all-zeros, the MBA accepts ANY certificate chain.
We can generate our own RSA-2048 key pair, create a self-signed cert chain,
and sign the modified hash segment ourselves.

### 2. Try unsigned hash segment (long shot)

Test if MBA accepts a hash segment with `sig_size=0, cert_size=0`.
File ready: `/tmp/modem_b01_nosig.bin`. If the MBA falls through on
missing signatures, this bypasses the entire signing requirement.

## Disassembly tools

```bash
# Hexagon disassembly (working, LLVM 14 has Hexagon target)
llvm-objdump-14 -D --triple=hexagon --print-imm-hex /tmp/modem_b12.elf

# Reconstructed ELF files for disassembly
/tmp/modem_b12.elf          # b12 code segment (17MB) wrapped in ELF with .text section
/tmp/modem_b14.elf          # b14 data segment (6.3MB) wrapped in ELF
/tmp/modem.elf              # Full monolithic ELF (all segments, 47MB)

# Modem partition (mounted read-only from EDL dump)
/tmp/modem-fat/             # FAT16 mount of ~/bq268-edl/dump/modem.bin
# Contains modem.mdt, modem.b00-b24, and 60+ MCFG carrier configs

# Extracted certificates
/tmp/modem_cert_attest.der  # Attestation cert (SecTools Test User)
/tmp/modem_cert_ca.der      # CA cert (QPSA F4 TEST CA)
/tmp/modem_cert_root.der    # Root cert (QPSA F4 TEST ROOT)
```

## Lessons learned

- **MCFG carrier configs are dangerous**: activating an incompatible carrier
  config (Reliance for India on a Chinese BQ268) crashes the modem in a loop.
  The config persists in modem EFS and survives reboots. Recovery requires
  wiping modemst1/modemst2 partitions (`dd if=/dev/zero of=/dev/mmcblk0p26`).

- **Patched firmware in /lib/firmware/ causes bootloops**: if the MBA rejects
  the modified segment, the modem fails to load on every boot. After enough
  failed subsystem restarts, the system crashes. Always keep original firmware
  backed up and restore before rebooting with untested changes.

- **"Debug policy not present" ≠ "secure boot disabled"**: this log message
  refers specifically to Qualcomm debug policy, not to the hash/signature
  verification chain. The MBA enforces hash+signature verification regardless.
