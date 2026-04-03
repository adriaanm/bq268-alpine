# Modem Firmware Patch — APDU Restriction Bypass

## Goal

Bypass the modem's QMI UIM APDU security restriction (NV 67312) to allow
logical channel operations for eSIM provisioning.

## Status: three patches (b12 code + b14 data)

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

### Patch 3: ISD-R AID corruption (b14 offset 0x2D0679) — TESTED, NOT SUFFICIENT

Corrupts the single copy of the ISD-R AID in the firmware's data segment.
LPA uses this byte string as its reference when registering for the ISD-R
AID at boot time.

```
Original: A0  →  first byte of ISD-R AID (A0000005591010FFFFFFFF8900000100)
Patched:  00  →  LPA registers for AID 00000005591010... (non-existent)
```

**Rationale**: Decompilation of the full MMGSDI dispatch chain revealed
that the AID routing is established at LPA registration time, not at
dispatch time. The MMGSDI state machine at 0xC1735ED4 doesn't compare
AID bytes — it follows pre-set callback pointers in the session structure.
The LPA's ISD-R AID reference (VA 0xC1CD0679, in b14) is the ONLY copy
in the entire firmware (searched all 25 segments). Corrupting it causes
LPA to register for a non-matching AID, so real ISD-R requests fall
through to the generic UICC path.

**Why Option C (registration NOP) didn't work**: The LPA registration
call at 0x619014 writes to one of multiple dispatch tables. The actual
AID-to-session routing uses a different mechanism (session table at
0xC2DA5218) populated through a path we couldn't fully trace via code
patches alone. Corrupting the AID data is more reliable because it
affects ALL registration paths regardless of which code path executes.

### Signing chain

QFPROM root hash fuses are not programmed — any cert chain is accepted.
MBA only checks SHA-256 hashes, not the RSA signature. Just update
hash[12] in modem.mdt — no re-signing needed.

### Applying the patches

```bash
python3 tools/patch-modem-b12.py firmware/modem     # patch b12 + update hash
just flash-modem                                     # deploy to device
```

Four files are modified in `firmware/modem/`:
- `modem.b12` — two 4-byte code patches
- `modem.b14` — one 1-byte data patch (ISD-R AID corruption)
- `modem.b01` — updated SHA-256 hashes for b12 (hash[12]) and b14 (hash[14])
- `modem.mdt` — embeds the updated b01 (at offset 884)

## Next steps

### 1. Test Patch 3 (ISD-R AID corruption)

Apply all three patches and test on device:
```bash
python3 tools/patch-modem-b12.py firmware/modem
just flash-modem
# After reboot, test:
qmicli -d /dev/wwan0qmi0 --uim-open-logical-channel=A0000005591010FFFFFFFF8900000100
```

Expected result: card responds instead of AccessDenied.

### Decompilation findings

Full MMGSDI dispatch chain decompiled (see `modem_decompiled_src/` and
`tools/decompile-modem.py` passes 1-5).

**Call chain for open_logical_channel**:
```
FUN_c0a15234 (QMI UIM handler)
  → FUN_c0a16da8 (restriction bitmask — PATCHED, returns 0)
  → signal(0x402) → wait → read result from 0xC2149DB0+4
                            ↓
FUN_c09caa78 (async callback, fires via signal)
  → FUN_c0a23140 (table lookup: session_table[slot])
  → FUN_c093b13c → 0xC1736674 (stores handler in request)
  → 0xC1736690 (searches APDU cmd dispatch tables at 0xC1F8B588/0xC1F8B648)
  → FUN_c092a1e4 → 0xC1735ED4 (state machine)
      → 0xC071A6C4 (validate: table index lookup)
      → if valid entry found: calls 0xC1735F70 (generic handler)
      → if NULL/out of bounds: loads callback from request+0x20
        → if callback exists: r16=0xFE, callr callback, return -2
        → if no callback: r16=0xFE, log, return -2
  → result written to 0xC2149DB4 → QMI handler reads → error 82
```

**Key insight**: the AID comparison is NOT in the dispatch chain.
MMGSDI's command dispatch tables (0xC1F8B588, 0xC1F8B648) match by
APDU command bytes (CLA/INS/P1P2), not AID bytes. The AID-to-session
mapping is established at LPA registration time, before any APDU
arrives. Corrupting the AID reference in b14 is the correct approach.

**Key structures**:
- Session table: `0xC2DA5218[slot*4]`
- Async result: `0xC2149DB0` (+4 = result value)
- LPA AID table: `0xC27EE260[idx*8]` (LPA's private table, not MMGSDI's)
- ISD-R AID: VA 0xC1CD0679 (b14 offset 0x2D0679) — ONLY copy in firmware
- APDU command dispatch: `0xC1F8B588` (22 entries), `0xC1F8B648` (dynamic)

**Previously considered code patches** (superseded by Patch 3):

a) Patch state machine at 0xC1735F18: `r16 = #0xfe` → `r16 = #0x0`.
   Risk: fakes success but LPA callback intercepted — no actual channel.

b) Patch async callback at 0xC09CAABC: NOP error jump.
   Risk: same as (a), LPA still intercepts, no real card communication.

c) Patch LPA init to skip registration. Tried at 0x619014, didn't work —
   multiple registration paths exist.

d) **Patch 3 (b14 AID corruption)**: attacks the root cause. LPA can't
   register for the correct AID → ISD-R falls through to generic path →
   card receives MANAGE CHANNEL + SELECT → real response.

See `tools/decompile-modem.py` (passes 1-5) for reproducible decompilation.

### 2. Alternative: DIAG MMGSDI raw APDU

DIAG subsystems now respond (kernel #55 fixes). MMGSDI (subsystem 0x19)
returns 0x13 (bad mode) for command 0x00, meaning it exists but needs
the right command code. Probe with `diag-apdu probe-ss 0x19` to
enumerate. Typical MMGSDI DIAG interface:
- Command 0x02: Send APDU
- Command 0x03: Get ATR

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
| DIAG EFS PUT | **Returns success, silently discards** | Confirmed twice (kernel #52 and #55). PUT returns error code 0 but file does not exist on read-back. Modem EFS security policy accepts the command but blocks creation on protected `/nv/item_files/modem/qmi/uim/` paths. SPC unlock does not help. |
| DIAG EFS OPEN+O_CREAT | fd=-1 errno=2 | OPEN with O_CREAT returns ENOENT — same security policy. |
| QMI PDC (MBN config) | NV items not applied | Config loads and activates, but SW configs only apply NV items when SIM PLMN matches the carrier profile. No SIM → no NV writes. Activating Reliance config + reboot **crashed the modem** (incompatible NVs for BQ268 hardware — caused bootloop, required EFS wipe). |
| QMI UIM | AccessDenied | This is the restriction we're trying to bypass. |
| AT+CSIM | "operation not supported" | Firmware advertises AT+CSIM but doesn't implement it. |
| rmt_storage overrides | No effect | Serving empty modemst1/modemst2 creates fresh EFS, but the NV file doesn't exist in factory state. FSG golden copy is ignored. |
| DIAG MMGSDI/UIM (0x19, 0x44, 0x48) | **Respond with 0x13** (bad mode) | Subsystems are alive but command 0x00 isn't valid in current mode. Need correct command codes. |
| DIAG PEEKD/POKED (0x36/0x39) | **No response** | Legacy memory peek/poke disabled in firmware. Commands reach modem (confirmed via write counter) but modem ignores them. |
| Legacy NV_WRITE (cmd 0x27) | N/A | Item ID 0x106F0 exceeds 16-bit NV ID range. |
| Factory EFS (EDL modemst dumps) | File not found | `apdu_security_restrictions` doesn't exist in factory EFS. |
| Factory MCFG MBNs | None contain item | Checked all 60+ carrier configs on modem partition. |

**Key finding on MCFG/PDC**: Factory MBNs DO support NV_FILE type items
(Reliance config has 60 NV_FILE items that load fine). The "PDC crashes on
custom NV_FILE items" from earlier docs was wrong — the crash came from
activating a full carrier config with NVs incompatible with BQ268 hardware.

**Key finding on DIAG**: The kernel DIAG driver required THREE fixes to work
on MSM8909 (see "DIAG kernel fixes" section below). With all fixes applied
(kernel #55), subsystem commands reach the modem and get responses. However:
- EFS PUT still silently discards writes to protected NV paths
- PEEKD/POKED (memory read/write) disabled in firmware — no response
- MMGSDI/UIM/GSTK subsystems respond with "bad mode" for cmd 0x00
  (need correct command codes to use them)

**Key finding on modemst partitions**: Previous experiments (MCFG PDC
activation with Reliance config) corrupted modemst1/modemst2 EFS. This
caused the modem to crash ~25s after boot, triggering system reboot via
RELATED subsystem restart. Fixed by restoring factory EFS from EDL dumps.
The rootfs `/lib/firmware/*.bin` override files (if present) take priority
over the eMMC partitions via rmt_storage — ensure no stale override files
exist.

## DIAG kernel fixes (MSM8909)

Three kernel fixes are required for DIAG to work on MSM8909. All are in
`~/bq268-caf-4.4`:

### Fix 1: SMD channel pre-registration (commit 034ada814c88, kernel #52)

The DIAG driver's transport negotiation (SMD vs glink vs socket) never
fires on MSM8909 because only SMD exists. This leaves DATA/CMD/DCI
channels unregistered and the CNTL `peripheral_info` unpopulated.

Fix: pre-register all channels during `diag_smd_init()` and copy
`early_init_info` to `peripheral_info` for CNTL.

### Fix 2: Direct feature mask send (kernel #55)

`diag_cntl_channel_open` queues `mask_update_work` via the `cntl_wq`
workqueue. The work is queued successfully (`queue_work` returns true)
but the worker thread never executes it — the kworker pool doesn't
pick it up (cause unknown, possibly related to singlethread WQ
scheduling on this kernel).

Fix: call `diag_send_updates_peripheral()` directly from
`diag_cntl_channel_open` instead of via workqueue. This sends the
AP's feature mask synchronously when the CNTL channel opens.

### Fix 3: Modem command fallback forwarding (kernel #55)

After feature mask exchange, the modem is expected to send
`DIAG_CTRL_MSG_REG` messages on the CNTL channel to register its
command handlers. This firmware (MPSS.JO.3.1) never sends these
registrations. Without them, `diag_cmd_search()` returns NULL and
`diag_process_apps_pkt()` drops all modem-bound commands.

Additionally, `process_incoming_feature_mask()` calls
`diag_cmd_remove_reg_by_proc()` which wipes any pre-registered
entries when the modem's feature mask arrives — so adding
registrations in `diag_cntl_channel_open` doesn't work either.

Fix: add fallback in `diag_process_apps_pkt()` after `diag_cmd_search`
returns NULL — if the modem's feature mask was received, forward the
command directly via `diagfwd_write(PERIPHERAL_MODEM, TYPE_CMD, ...)`.

### DIAG probe results (kernel #55)

```
SS 0x03 WCDMA     error (0x13)   # bad mode — subsystem exists
SS 0x04 GSM       no response    # not present on this firmware
SS 0x06 CM        error (0x13)
SS 0x08 GPS       ALIVE (10 bytes)
SS 0x0A NAS       error (0x14)   # bad parameter
SS 0x0C UIM       error (0x13)
SS 0x13 EFS2      error (0x15)   # bad length (cmd 0x00 needs more data)
SS 0x19 MMGSDI    error (0x13)
SS 0x2D QMI       ALIVE (5 bytes)
SS 0x48 QMI_UIM   error (0x13)
```

EFS2 commands work with correct formatting (MKDIR, OPEN, READ, WRITE,
PUT all functional after SPC unlock). PEEKD/POKED disabled.

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
