# Modem Firmware Patch — APDU Restriction Bypass

## Goal

Bypass the modem's QMI UIM APDU security restriction (NV 67312) to allow
logical channel operations for eSIM provisioning.

## Status: two patches, both in modem.b12

### Patch 1: APDU restriction bypass (offset 0x121DCC) — VERIFIED

Lifts the QMI UIM APDU security restriction bitmask. Without this,
open_logical_channel and send_apdu are blocked for all AIDs.

```
Original: C0 7D 81 91  →  r0 = memw(r1+#0x7B8)   // load restriction bitmask
Patched:  00 40 00 78  →  r0 = #0x0                // always "no restrictions"
```

### Patch 2: LPA ISD-R disable (offset 0x619014) — TESTED, NOT SUFFICIENT

Replaces the `call lpa_register` at VA 0xC0F0E014 with `r0 = #0x1`,
preventing the LPA from writing its callback into the table at
0xC27EDEB8. The LPA task still starts but skips ISD-R registration.

```
Original: B8 79 FF 5B  →  call 0xC0F0D384   // lpa_register(slot, callbacks, aid_type)
Patched:  20 40 00 78  →  r0 = #0x1          // pretend registration returned "already done"
```

**Result: still AccessDenied.** The MMGSDI routing to the LPA uses a
DIFFERENT mechanism than this table. The actual AID comparison and
routing happens inside the MMGSDI state machine (FUN_c093b13c /
FUN_c092a1e4), and the LPA's claim on the ISD-R AID is registered
through a path we haven't identified yet.

**Attempted patches that don't work:**
- 0x618F7C: force `lpa_support` check to "disabled" — too early,
  gets overwritten by later init code
- 0x61901C: force `r17 = #0x1` after registration call — registration
  already happened at 0xC0F0D384 before this point
- 0x619014: NOP the registration call — table at 0xC27EDEB8 is not
  what MMGSDI uses for AID routing

See `docs/modem_apdu_path.md` for the full APDU routing architecture.

### Signing chain

QFPROM root hash fuses are not programmed — any cert chain is accepted.
MBA only checks SHA-256 hashes, not the RSA signature. Just update
hash[12] in modem.mdt — no re-signing needed.

### Applying the patches

```bash
python3 tools/patch-modem-b12.py firmware/modem     # patch b12 + update hash
just flash-modem                                     # deploy to device
```

Three files are modified in `firmware/modem/`:
- `modem.b12` — two 4-byte code patches
- `modem.b01` — updated SHA-256 hash for b12 (hash[12])
- `modem.mdt` — embeds the updated b01 (at offset 884)

## Next steps

### 1. Bypass ISD-R AID filter (second firmware patch)

**Decompilation findings** (pyghidra + Ghidra Hexagon sleigh plugin):

The ISD-R AID is at VA 0xC1CD0678 in b14 as a length-prefixed blob:
`10 A0 00 00 05 59 10 10 FF FF FF FF 89 00 00 01` (16 bytes + length).

The AID filter is NOT in the QMI UIM handler (FUN_c0a15234). The handler
does a restriction bitmask check (our existing patch) and session state
lookup, but never examines AID bytes. The actual filter is in the MMGSDI
async processing layer:

**Call chain for open_logical_channel**:
```
FUN_c0a15234 (QMI UIM handler)
  → FUN_c0a16da8 (restriction bitmask — PATCHED, returns 0)
  → signal(0x402) → wait → read result from 0xC2149DB0+4
                            ↓
FUN_c09caa78 (async callback, fires via signal)
  → FUN_c0a23140 (table lookup: *(0xC2DA5648 + param*4))
  → FUN_c093b13c (session manager — resolves request via dispatch tables)
  → FUN_c092a1e4 (state machine processor — returns -2 on denial)
      → dispatches via callback at offset +0x20 of request structure
      → if callback returns or is NULL: returns 0xFFFFFFFE (-2)
      → -2 written to 0xC2149DB4 → handler reads it → AccessDenied
```

The state machine in FUN_c092a1e4 uses a callback-based dispatch. The
LPA registers itself in this dispatch table during initialization, causing
ISD-R AID requests to be routed to the LPA callback which returns -2.

**Key structures**:
- Session table: `0xC2DA5218[slot*4]` — per-slot session pointers
- Async result: `0xC2149DB0` — signal variable, +4 = result value
- LPA AID table: `0xC27EE290[idx*4]` — LPA's own registered AIDs
  (referenced ONLY from LPA code at 0xC0F0F000-0xC0F13A00)
- ISD-R data: VA 0xC1CD0600+ — LPA strings ("cancelSessionResponse",
  "pendingNotification", ISD-R AID, "/lpa/store_data_resp_from_card")
- Dispatch tables: `0xC1F8B588` (22 entries), `0xC1F8B648` (dynamic)

**Decompiled key functions**:
- `FUN_c0999610`: returns `func_0xc0717134(0xC21499B0) == 0` (LPA idle)
- `FUN_c0999630`: returns `func_0xc0717134(0xC21499B0) == 8` (LPA state 8)
- `FUN_c0717d4c`: session state lookup — `table[param1*4][param2*0x2C+2]`
- `FUN_c0717134`: reads `*(param+4)` (generic signal/state reader)

**Patch candidates** (in order of preference):

a) **Patch FUN_c092a1e4 to skip LPA callback**: NOP the callback dispatch
   at the point where it calls `*(request+0x20)` for ISD-R requests.
   The function is in seg23 (modem.b23, 0xC3F49000-0xC40DA000, RWX).
   Same hash-update workflow as b12 — just also update hash[23] in b01/mdt.

b) **Patch FUN_c09caa78 to ignore -2 result**: Change the comparison at
   0xC09CAABC from `cmpb.eq(r0, #0x0)` to always succeed. This would
   make ALL open_logical_channel succeed regardless of AID, which is safe
   since the card itself will reject invalid requests.

c) **Patch the LPA initialization** (FUN_c0f11758) to skip ISD-R AID
   registration. The call `func_0xc0f1051c(param_1, 0xc1cd0678)` copies
   the AID into the LPA structure. NOPing this prevents registration, but
   may break the LPA's own eSIM operations (which we don't need).

d) **Patch the async result check** in the handler at 0xC0A153DC: change
   `r0 = !cmp.eq(r0, #-0x2)` to `r0 = #0x1`. This skips the -2 check
   but the actual channel still won't be opened — the async handler
   would have already failed.

**Patch approach (b) detail** — at b12 offset **0x0D5ABC** (VA 0xC09CAABC):
```hexagon
; Current: check if FUN_c092a1e4 returned 0 (success)
c09caabc:  p0 = cmpb.eq(r0,#0x0)              ; 00 40 00 dd
c09caac0:  if (!p0.new) jump:nt 0xc09cab74     ; 5c 48 20 5c  ← error path

; Patched: NOP the conditional jump (keep parse bits = 01 for mid-packet)
c09caabc:  p0 = cmpb.eq(r0,#0x0)              ; 00 40 00 dd  (unchanged)
c09caac0:  nop                                  ; 00 40 00 7f  ← NOP, parse=01
```

This always falls through to the success path, bypassing the state
machine's access denied result. The state machine still runs (LPA
callback fires for ISD-R AID and returns -2), but we ignore the result.
The session status bytes at +0x194/+0x19c get cleared, and the async
handler returns success.

**Risk**: the state machine didn't actually open a channel to the card
(the LPA callback intercepts and never sends MANAGE CHANNEL to the SIM).
The QMI response would say "success" but the channel doesn't exist —
subsequent send_apdu commands would fail. Need to test on device.

**Patch approach (a) detail** — b12 offset **0xE40F18** (VA 0xC1735F18):

The state machine (FUN_c092a1e4 → thunk → 0xC1735ED4) always returns -2
after calling any registered callback (offset +0x20 in request structure):
```hexagon
c1735ef8:  r4 = memw(r0+#0x20)    ; load callback from request
c1735f18:  r16 = #0xfe            ; d0 5f 00 78 — pre-set return = -2
c1735f1c:  callr r4               ; call callback (LPA handler)
c1735f4c:  r0 = sxtb(r16)         ; return sxtb(0xfe) = -2
```
Patch `r16 = #0xfe` → `r16 = #0x0` (change bytes `d0 5f` → `10 40`).
Makes ALL callback-dispatched requests return success. Broader than (b)
but cleaner — the callback still runs, the LPA still fires, but the
state machine reports success to the caller. Same risk as (b): the LPA
callback might not actually open a channel to the card.

See `tools/decompile-modem.py` for reproducible decompilation passes.

### 2. Alternative: DIAG MMGSDI raw APDU

DIAG subsystems now respond (kernel #52 fix). MMGSDI (subsystem 0x19)
may support raw APDU passthrough commands that bypass QMI UIM entirely.
The MMGSDI DIAG interface is typically:
- Command 0x02: Send APDU
- Command 0x03: Get ATR

Need to probe subsystem 0x19 with specific command codes. The diag-apdu
tool's `probe-ss` command can enumerate available commands.

### 3. Alternative: modem's built-in LPA

The modem contains an LPA at VA 0xC1CD0600+ (strings like
"cancelSessionResponse", "/lpa/store_data_resp_from_card"). If the modem
exposes its LPA via a QMI service, we might use it directly instead of
lpac. Needs investigation of available QMI services.

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
| OS/utility seg | **modem.b09** — seg 9, VA 0xC0700000, 200KB, PF_R\|PF_W\|PF_X |
| Code segment | **modem.b12** — seg 12, VA 0xC08F5000, 17MB, PF_R\|PF_X |
| Data segment | **modem.b14** — seg 14, VA 0xC1A00000, 6.3MB, PF_R (no execute) |
| RW data seg | **modem.b15** — seg 15, VA 0xC2056000, 1.7MB, PF_R\|PF_W |
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

## Signing chain — SOLVED

### Key discoveries

1. **modem.mdt embeds modem.b01**: The MDT file is ELF headers (884 bytes)
   + the full hash segment (7272 bytes = 8156 total). The MBA/TrustZone
   reads the hash segment from modem.mdt, NOT from the standalone modem.b01.
   Modifying only b01 has no effect — you MUST also update mdt.

2. **QFPROM root hash fuses are NOT programmed**: The MBA accepts any
   certificate chain. Verified by booting with a completely new self-signed
   chain (via test-key b01 embedded in original mdt with original hashes —
   though see note below about what actually got tested).

3. **MBA does NOT verify the RSA signature over the hash data**: Updating
   ONLY hash[12] in the mdt-embedded hash segment (keeping the original
   now-invalid QPSA signature) passes MBA authentication. The MBA checks
   that each segment's SHA-256 matches the corresponding hash in the embedded
   b01, but does not verify the signature covers those specific hash values.

4. **Patch verified working**: With the hash-only update in mdt, the patched
   modem.b12 loads successfully. Logical channel opens return SimFileNotFound
   (card doesn't have that AID) instead of AccessDenied. The APDU security
   restriction is lifted.

### Certificate chain (informational)

| Cert | CN | O |
|------|----|---|
| Attestation | SecTools Test User | SecTools |
| CA | QPSA F4 TEST CA | QUALCOMM |
| Root | QPSA F4 TEST ROOT | QUALCOMM |

### Patch files (on buildbox /tmp/)

| File | Deploy to | Description |
|------|-----------|-------------|
| `modem_b12_patched.bin` | `/lib/firmware/modem.b12` | 4-byte code patch at offset 0x121DCC |
| `modem_b01_hashonly.bin` | `/lib/firmware/modem.b01` | Updated hash[12], original sig+certs |
| `modem_mdt_hashonly.bin` | `/lib/firmware/modem.mdt` | Embeds updated b01 at offset 884 |

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

- **modem.mdt embeds modem.b01**: Always update mdt when modifying the
  hash segment. The MBA reads from mdt, not the standalone b01 file.

- **MBA checks hashes but not signatures**: On this device, only the SHA-256
  hash table matters. The RSA signature in the hash segment is not verified
  against the hash data.
