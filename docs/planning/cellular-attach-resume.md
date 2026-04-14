# Cellular attach — resume prompt

Scratch doc to restart the cellular-data bringup investigation without
re-reading the whole session history. Pick up from commits `bd05c19`,
`efef99c`, `0d2c089` on `main`.

## Overriding ground truth (2026-04-14)

**The same Eskimo eSIM, moved into an Android phone at the same
physical location, attaches to Sunrise on 4G/5G and passes real data.**

This is not a hypothesis. It rules out, as a class:

- The Eskimo account being unfunded or expired.
- Eskimo's plan not including data roaming in CH.
- Sunrise refusing PS for this IMSI.
- The iPhone reference from earlier sessions being a different SIM —
  we now have a direct same-SIM-swap comparison.
- Reception / coverage / cell-tower issues at the test location.
- The HSS path (Sunrise → Singtel → Eskimo) being broken.

Whatever is keeping the BQ268 off Sunrise-LTE-with-data is
**BQ268-specific** — kernel, modem firmware, MCFG, NV, or RF
hardware on this board. Every remaining hypothesis has to be
compatible with "Android, same SIM, same location, works." That
cuts a lot of wishful thinking.

## Session 2026-04-14 (session 8) — 🏆 ROOT CAUSE: eSIM-provisioning firmware patches silently break LTE attach

**First ever successful LTE attach + real data over LTE on the BQ268.**
Attached to Sunrise (228/02) on LTE, RSRP -111 dBm, SNR 9 dB, PPP up
with public IPv4 `100.100.105.20`, ping 8.8.8.8 at 0% loss. Fully end
to end.

### The trigger

After session 7 ruled out (via SIB1 decode of the captured BCCH
payloads) the idea that cells were barred or operator-reserved — all
six visible Swiss LTE cells broadcast `cellBarred: notBarred` and
`intraFreqReselection: allowed`, including the Sunrise B20 cell
Android attaches to (PCI 76, EARFCN 6200) — the user flagged an
under-explored hypothesis: **"We patched the modem firmware for
eSIM provisioning. The patches were accepted, but maybe there's a
silent kill-switch for patched firmware that's keeping the modem
from progressing?"**

This was dismissed in earlier sessions because (a) UMTS PS attach
*does* work on patched firmware, so there's no *blanket* kill-switch
and (b) the patch script only touches an APDU bitmask and the LPA
ISD-R registration path, none of which obviously touch LTE
bringup. But none of our existing evidence had ever tested
**BQ268 with unpatched firmware on LTE**, so the hypothesis had
never actually been falsified — we just didn't have the datapoint.

### The experiment

1. `tools/patch-modem-b12.py` grew a `--revert` flag that swaps the
   `original`/`patched` byte sequences in `PATCHES_B12`/`PATCHES_B14`
   before invoking the existing `apply_patches` + hash-update logic.
2. Staged a rolled-back copy of the firmware into
   `/tmp/modem-unpatched/` and verified with `--check` that all
   three patches report `ORIGINAL`.
3. Backed up the patched runtime files on device to
   `/root/modem-patched.bak/`, scp'd the unpatched
   `modem.b12/b14/b01/mdt` into `/lib/firmware/`, and rebooted so
   MBA reloads the segments from disk.
4. After the device came back, pre-flighted the modem to `online`
   via `dms-set-operating-mode=online` (the `shutting-down`-on-boot
   known-issue still bites on the first wake attempt), then ran
   `just diag-capture-lte 90`.

### The result — the single-run RRC_SUMMARY tells the whole story

**Patched firmware** (session 7, unchanged):

```
total=241 parse_fail=0
  bcch_bch=0  bcch_dl_sch=241
  pcch=0  dl_ccch=0  dl_dcch=0
  ul_ccch=0  ul_dcch=0
```

**Unpatched firmware** (this session):

```
total=213 parse_fail=0
  bcch_bch=0  bcch_dl_sch=81
  pcch=67  dl_ccch=1  dl_dcch=14
  ul_ccch=1  ul_dcch=49
```

**`ul_ccch` went from 0 → 1** (one RRC Connection Request sent — the
very thing that was never happening across three entire sessions
of debugging). `dl_ccch` 0 → 1 (one RRC Connection Setup received).
`ul_dcch` 0 → 49 and `dl_dcch` 0 → 14 (SRB1/SRB2 signalling
traffic — NAS ATTACH REQUEST, SECURITY MODE, ATTACH ACCEPT,
PDN CONNECTIVITY REQUEST/ACCEPT). And `pcch` 0 → 67 (the network
pages the UE only after registration is complete, so 67 paging
messages means the device is a first-class participant in the
cell again).

Immediately after the capture, QMI reported:

```
Registration state: registered
CS: attached
PS: attached
Radio interfaces: lte
Current PLMN: MCC 228 MNC 2 (Sunrise)
LTE: RSSI -77 dBm  RSRQ -10 dB  RSRP -111 dBm  SNR 9.0 dB
```

and `cell-data up` brought PPP up cleanly:

```
cell-data: serving plmn=228/2 rat=lte roaming=true (home=525/1)
cell-data: data path up on ppp0 (100.100.105.20)
```

followed by a clean `ping -I ppp0 8.8.8.8` at 0% loss and ~180 ms
RTT. **This is the first real LTE data the BQ268 has ever carried
in this investigation.**

### What's actually happening

The `tools/patch-modem-b12.py` patches — applied to enable raw
QMI UIM APDU access for eSIM provisioning via lpac — do more than
their docstring comment implies. At least one of them (most
likely Patch 2, the LPA ISD-R disable at `modem.b12 0x619014`
that rewrites a `call lpa_register` instruction to
`r0 = #0x1`) has a side-effect that silently blocks LTE NAS from
progressing past PLMN search. UMTS NAS is unaffected, which is
why session 3 and onward never noticed — we were camped on
UMTS Orange F throughout the investigation because that was
the only thing that worked.

Concretely: on patched firmware, NAS sits in PLMN-search limbo
(we only saw 10 × 0xB0EE NAS PLMN-op events and zero
0xB0E0 LTE_NAS_EMM_STATE transitions during the session 7
capture). NAS never decides to proceed with an attach on any
LTE PLMN, so it never asks LTE RRC to establish a connection,
and the 241 BCCH_DL_SCH frames we see are just idle-mode cell
measurement activity. On unpatched firmware that same idle-mode
measurement completes normally and NAS transitions through
its full attach sequence in <10 s, producing the 213-event
capture above.

We don't yet know which of the three patches is the
load-bearing one, or what exact mechanism in Qualcomm's modem
firmware takes "the LPA didn't register for ISD-R correctly"
and translates that into "never kick LTE RRC". The experiment
to narrow it down is to revert the patches one at a time and
rerun the capture — backlog item in TASKS.md.

### Patch bisection (later in session 8)

Added `tools/patch-modem-b12.py --patches=N[,M,...]` which
selects a subset of patches to apply (1-based across the global
order `[APDU restriction bypass, LPA ISD-R disable, AID
corruption]`) and reverts the rest — so the same invocation
can flip between any subset cleanly. Ran a bisection of all
three patches against LTE attach (via `just diag-capture-lte`
RRC_SUMMARY) and lpac eUICC reachability (via
`LPAC_APDU=stdio lpac profile list < <(lpac-qmi-wrapper)`,
which fails at `euicc_init` code `-1` when the LPA intercepts
the ISD-R channel).

| Patches     | LTE attach | lpac euicc_init | Notes                               |
|-------------|:----------:|:---------------:|-------------------------------------|
| *none*      |     ✓      |        ✗        | Session 8 main result               |
| 1           |     ✗      |        ✗        | Kill-switch trigger                 |
| 2           |     ✓      |        ✗        |                                     |
| 3           |     ✓      |        ✗        |                                     |
| 1+3         |     ✗      |        ✗        |                                     |
| 2+3         |     ✓      |        ✗        | Our best-hoped-for-minimal, no dice |
| 1+2+3       |     ✗      |     ✓ (hist)    | Historical; provisioning works      |

The table collapses to one fact: **Patch 1 (APDU restriction
bypass, `modem.b12` offset `0x121DCC`, 4-byte Hexagon instruction
`r0 = memw(r1+#0x7B8) → r0 = #0x0`) is simultaneously the LTE
kill-switch AND required for lpac to reach the eUICC ISD-R
channel**. There is no subset of the three patches that enables
provisioning without breaking LTE. The two capabilities are
genuinely mutually exclusive on this firmware.

Patches 2 and 3 are individually benign for LTE, and their
combination is also benign. But neither enables provisioning,
either alone or together — so there is no point shipping them
in the LTE default. Only one untested combo remains, `1+2`, and
it's uninteresting: we already know `1` alone breaks LTE, so
`1+2` can only break LTE too; the one remaining question is
whether `1+2` is enough for provisioning (avoiding patch 3's
AID corruption). That question is cosmetic — the `provision-
esim-mode` recipe already ships the full `1+2+3` set which is
known to work for provisioning, and provisioning is rare enough
that a minor patch-count reduction isn't worth another test
cycle. Left as a backlog nice-to-have.

Best guess at *why* patch 1 kills LTE: the `r0 = memw(r1+#0x7B8)`
instruction reads a struct field at offset 0x7B8, and whatever
lives there looks like a per-access-technology capability /
eligibility bitmap that NAS consults during PLMN selection.
Zeroing it out ("always allow" for the APDU restriction path)
also zeroes out the LTE-allowed bit for NAS, causing NAS to
silently treat LTE as unavailable and never progress past
idle-mode SIB measurement. UMTS still works because its
eligibility is in a different field. This is a guess — confirming
would need Hexagon disassembly of the code at `b12 0x121DCC`
to see what function the instruction is in, and whether the
same field is read by NAS code paths. Not worth the dig right
now unless a future session needs it.

### Workflow in the justfile

- `build-rootfs` now depends on `unpatch-modem`, not `patch-modem`.
  Every rootfs build produces an LTE-working device by default.
- `patch-modem` still exists but is no longer called from the
  build. It's only invoked by `provision-esim-mode`.
- `provision-esim-mode`: stages patched firmware, backs up the
  current on-device unpatched segments to
  `/root/modem-unpatched.bak/`, pushes patched segments, reboots,
  prompts for the interactive lpac session, then restores
  unpatched and reboots again and verifies LTE attach with a
  short `diag-capture-lte`. Intended for a once-every-few-months
  eSIM profile change.
- `diag-capture-lte` grew a pre-flight loop that waits for the
  modem to leave `shutting-down` (up to 8 × 15 s) and forces
  `dms-set-operating-mode=online` before starting the capture.
  Both of session 7/8's bounce-cycles on this trap are now
  handled by the recipe rather than requiring manual
  intervention.

### Final runtime state

Live device is running **unpatched firmware**, verified end to
end:

```
serving: 228/02 Sunrise LTE, roaming
cell-data up → ppp0 10.192.231.199
ping -I ppp0 8.8.8.8: 3/3, avg 232 ms
cell-data down → clean
```

Still-open cellular tasks are now about productising this path
(hardening, metrics, the `wata-metricsd` on-device cellular
validation that couldn't complete during session 3 because
attach wasn't working) rather than investigating why it
doesn't work.

### Implications for the rootfs build

- **The currently-shipping `firmware/modem/*.mbn` tree in this
  repo is patched** (confirmed via
  `patch-modem-b12.py firmware/modem --check`). Any `just
  build-rootfs` → flash produces a device that cannot use LTE.
  That's been the state since we first baked the patched
  firmware in for eSIM provisioning.
- **The eSIM is already provisioned and active on the eUICC.**
  The patches are needed at the LPA APDU path only during
  profile *management* (add/delete/switch) via lpac. Once a
  profile is enabled, the modem uses it for authentication
  without touching ISD-R on the provisioning channel, so the
  running modem does not need the patches for day-to-day
  cellular operation.
- **Proposed path forward**: ship unpatched firmware as the
  rootfs default, keep patched segments alongside in tree for
  on-demand use, and add a `just provision-esim` recipe that
  (a) swaps in patched `b12/b14/b01/mdt`, (b) reboots, (c)
  runs the lpac provisioning flow, (d) swaps back to unpatched,
  (e) reboots, (f) verifies LTE attach still works. Tracked as
  a new task.
- **Narrower option**: figure out which of the three patches
  is load-bearing (Patch 1 APDU bitmask is almost certainly
  orthogonal; the LPA ISD-R disable is the prime suspect) and
  try a minimal patch set that keeps eSIM provisioning working
  without killing LTE. If Patch 1 alone is enough for lpac to
  talk to ISD-R, we ship firmware with only Patch 1.

### Tools landed this session

- `tools/cell-diag.c` RRC OTA decoder now dumps the full payload
  hex under `"raw"` alongside the parsed `{ver, pci, earfcn,
  ch, ch_name}`. We previously used a best-guess `pdu_off=15 +
  u16 len` pair that was off-by-two — the raw-payload-and-slice
  approach below is more robust.
- `tools/decode-bcch.py` offline decoder reads
  `cell-diag-lte.log`, slices `raw[19:]` out of each
  `BCCH_DL_SCH` event, runs it through
  `pycrate_asn1dir.RRCLTE.EUTRA_RRC_Definitions.BCCH_DL_SCH_Message`,
  and emits a per-cell summary of PLMN list, TAC, Cell ID,
  `cellBarred`, `intraFreqReselection`, `csg-Indication`,
  `q-RxLevMin`, and `freqBandIndicator`. Needs `pycrate` via
  `pip3 install --break-system-packages pycrate`. The empirical
  pdu-offset (19 bytes into the 0xB0C0 payload for ver=13) was
  reverse-engineered by lining up known fields in the raw hex
  against the SIB1 ASN.1 schema; it's documented in
  `decode-bcch.py`'s module docstring.
- `tools/cell-diag.c` LTE log subscription widened from
  `0xC0..0xFF` to `0x00..0xFF` within equipment id 0x0B. The
  wider mask doesn't change the key UL_CCCH finding but does
  expose 0xB0EE (NAS PLMN op), 0xB0C3/0xB0C4 (serving cell /
  PLMN search), 0xB063 (ML1 DL bursts), and on unpatched
  firmware also 0xB0CB (LTE_ML1 serving cell state) — more
  context for future debugging.
- `tools/patch-modem-b12.py --revert` flag rolls the patches
  back in place. Used to stage `/tmp/modem-unpatched/` for the
  kill-switch experiment.

### SIB1 decode results (session 7 data, analyzed this session)

For the record, here's the per-cell SIB1 summary from
`decode-bcch.py cell-diag-lte.log` on the session 7 capture —
all six visible Swiss LTE cells are permissive, which is
consistent with everything-works-on-Android:

```
PCI   39 EARFCN  3750 (B8)   PLMN 228/01 Swisscom  notBarred allowed
PCI   76 EARFCN  6200 (B20)  PLMN 228/02 Sunrise   notBarred allowed  ← Android camps here
PCI  154 EARFCN    50 (B1)   PLMN 228/02 Sunrise   notBarred allowed
PCI  210 EARFCN  1850 (B3)   PLMN 228/02 Sunrise   notBarred allowed
PCI  228 EARFCN  6300 (B20)  PLMN 228/01 Swisscom  notBarred allowed
PCI  337 EARFCN  9435 (B28)  PLMN 228/01 Swisscom  notBarred allowed
```

No cellBarred, no cellReservedForOperatorUse, no CSG indication,
q-RxLevMin uniformly -64 dBm (trivially satisfiable). Nothing
at the SIB level to explain why the modem refuses to RRC-connect.

This decoder and the captured log are kept for any future
inspection — if we want to dig further into why patched firmware
abandons NAS PLMN selection, the raw frames are in
`cell-diag-lte.log` at the repo root.

### Known traps rediscovered this session

- **`cell-data wake` silently "succeeds" when the modem is
  already PS-attached** from a previous run. The session 7
  LTE-only capture's restore step re-attached the modem to
  UMTS Orange F, so running `just diag-capture-lte` again
  without a reboot makes the wake a no-op ("serving
  plmn=208/1 rat=umts"). For the unpatched firmware test we
  had to reboot for the firmware reload anyway, so the issue
  didn't bite — but in general, the LTE-only capture recipe
  should force `dms-set-operating-mode=offline`+`online` or
  clear PS attach before kicking the wake. Backlog.
- **The modem peripheral's `state` sysfs says `ONLINE` while
  `dms-get-operating-mode` says `shutting-down`** for up to
  ~2 minutes after a fresh boot. The subsys is up, but the
  QMI DMS state machine hasn't yet processed its own boot
  transition. Manually issuing `dms-set-operating-mode=online`
  unsticks it. Session 7 and session 8 both hit this; the
  session 7 first attempt actually crashed the device mid-wake
  because `cell-data wake`'s 20 s `WAKE_BUDGET` ran out and
  escalated to `dms reset` while the modem was mid-boot. The
  `diag-capture-lte` recipe should pre-flight this.

## Session 2026-04-14 (session 7) — LTE UL RRC never fires, on any band

Extended `tools/cell-diag.c` to parse the 0xB0C0 LTE_RRC_OTA header
(version-dispatch: u16 earfcn for ver≤9, u32 earfcn for ver≥13) and
emit `{ver, pci, earfcn, ch, ch_name}` per event plus an
`RRC_SUMMARY` histogram on exit. Added `just diag-capture-lte` which
runs `cell-diag` while forcing `cell-data wake` into LTE-only mode
via the new `CELL_DATA_RAT` env override in `tools/cell-data.sh`
(respected by `ensure_rat_prefs`), then restores `lte|umts` on exit.

**Result of the first 90-second LTE-only capture (RRC_SUMMARY):**

```
total=241 parse_fail=0
  bcch_bch=0  bcch_dl_sch=241
  pcch=0  dl_ccch=0  dl_dcch=0
  ul_ccch=0  ul_dcch=0
```

**241 BCCH_DL_SCH frames, zero UL_CCCH, zero anything else.** The
modem scanned and decoded SIBs on at least six distinct LTE cells
during the wake, across three different bands:

| PCI | EARFCN | Band |
|-----|--------|------|
| 39  | 3750   | B7 (2600 MHz) |
| 348 | 1300   | B3 (1800 MHz) |
| 195 | 1601   | B3 (1800 MHz) |
| 197 | 1601   | B3 (1800 MHz) |
| 426 | 202    | B1 (2100 MHz) |
| …   | …      | … |

On all of them the modem completed DL SIB decode successfully
(all 241 events parse cleanly, ver=13) and then **never transmitted
a single RRC Connection Request**. Not on B20, not on B3, not on B7,
not on B1. No random-access Msg3 ever makes it to the RRC layer.

### What this rules out

- **B20-specific UL hardware issue** — dead hypothesis. The April-13
  session 5 suggestion that the B20 PA/filter population on the
  BQ268 PCB might be the gate is inconsistent with B1/B3/B7 also
  failing to emit UL_CCCH. If it were RF-hardware-path the failure
  pattern would be band-asymmetric.
- **Cell-reselection camping on the wrong cell** — also dead. The
  modem is clearly measuring and ranking multiple LTE cells. It
  just never picks one to attach to.
- **Android-reference ground truth contradiction** — fully
  intact: Android on the same SIM at the same location reaches
  RRC Connection Request on Sunrise B20 within seconds, so the
  failure is BQ268-specific and software-rooted, not hardware.

### What this points at

The failure is **upstream of RRC connection establishment**. The
candidates, in rough order of likelihood:

1. **NAS layer refuses to trigger RRC_CONNECTION_REQUEST.** NAS only
   asks RRC to set up a connection once it has (a) chosen a PLMN and
   (b) decided to start an ATTACH/SERVICE REQUEST procedure. If
   NAS's PLMN-selection logic decides none of the visible LTE cells
   are acceptable — because of SOR/steering rules, forbidden-TAI
   lists, SIB1 `cellBarred`/`intraFreqReselection`/`csg-Indication`
   flags, operator-policy blocks in the active MCFG, or a
   `T3346` / attach-attempt-counter backoff from a previous reject
   — NAS never kicks RRC. RRC stays in IDLE, keeps decoding SIBs on
   multiple cells (which is exactly what we see), and never
   transitions.
2. **Cell selection criterion S fails on every visible cell.** The
   modem's cell-selection loop computes `Srxlev = Qrxlevmeas −
   (Qrxlevmin + Qrxlevminoffset) − Pcompensation`. If `Qrxlevmin`
   from SIB1 is very high and our measured RSRP is too low for the
   criterion, the modem treats the cell as "not suitable" and
   never camps on it. But this normally produces `cell reselection
   to *** failed`-style events which we would see via 0xB0E0
   (LTE_NAS_EMM_STATE) — we don't. Also this would be band-sensitive
   and we're not seeing band asymmetry.
3. **MCFG-SW policy block**. The currently-active Singtel
   Commercial MCFG encodes Singtel's preferred-roaming-partner
   table and SOR rules. If that table marks all visible CH/FR LTE
   PLMNs as forbidden for PS attach, NAS will drop them out of
   the candidate set and never kick RRC. Session 4 already
   established that this MCFG has ~22 NV-by-number items we
   haven't decoded.
4. **Attach-attempt-counter / T3346 timer from an earlier failed
   attempt is still running**. If the modem has retried enough
   times that NAS has entered "attach attempt counter >= 5" state
   it will stop trying PLMN selection until a timer expires, a
   SIM is re-read, or the power is cycled. Would explain why
   BCCH is decoded (that's just measurement) but no RRC is ever
   triggered.

### Immediate follow-ups

- **Extend `cell-diag` log subscription to equip_id 0x0B items
  0xE0..0xEF and 0xE8..0xEB** — covers 0xB0E0 LTE_NAS_EMM_STATE and
  0xB0E1 FORBIDDEN_TAI. The current mask is 0xC0..0xFF so these
  *should* already be enabled, but nothing's showing up. Either
  (a) NAS never transitions state while we're in this stuck
  condition (plausible if it's camping in "searching, nothing
  acceptable"), or (b) the bit positions for EMM events don't
  match the 0xC0..0xFF range on this firmware version. Worth a
  single separate capture with the mask widened to 0x00..0xFF to
  see if other NAS events show up.
- **Add equip_id 0x04 (1X/GSM/WCDMA NAS) and 0x07 (LTE ML1
  serving/neighbour)** to the subscription. 0xB139/0xB17F ML1
  serving-cell measurements and LTE NAS GMM/MM events may reveal
  *why* cells are being rejected.
- **Dump SIB1 `cellBarred` / `intraFreqReselection` / PLMN-list
  for each cell** the modem measured. Can be decoded from the
  241 BCCH_DL_SCH payloads we already captured — each is an
  ASN.1-encoded RRC PDU, the first SIB is SIB1. Don't need new
  tooling, just a decoder pass over `cell-diag-lte.log`.
- **Re-check the attach-attempt counter**. On QMI: try a full
  `dms-set-operating-mode=offline` → `online` cycle *without*
  our script's `ensure_rat_prefs` churn, then capture. If the
  first wake after a clean cycle emits UL_CCCH and subsequent
  wakes don't, we're fighting NAS state that the script is
  leaving behind.
- **Dump active MCFG and diff against what Android uses**. Still
  the highest-leverage configuration lever that's plausibly
  different from the Android reference. Session 3 established we
  know how to decode the NV items; we just haven't done it for
  the bitmap/SOR entries.

### Known traps rediscovered this session

- **Starting `cell-data wake` on a freshly-booted device with
  modem in `shutting-down` can crash the device** — a full
  reboot happened mid-capture (uptime went back to 1 minute
  between the two runs). Likely the same `[pppd] in D state`
  SMD teardown hazard, or the `dms-set-operating-mode=reset`
  kworker leak exceeding a safe ceiling. **Workflow
  implication**: before running `just diag-capture-lte`, check
  `qmicli --dms-get-operating-mode` and wait for `online`
  manually, or `qmicli --dms-set-operating-mode=online` first.
  A first-boot-safe wake path is a separate task.
- **Parser decision was correct**: ver=13 uses the u32 earfcn
  layout, and the `pdu_num` offset (13) with `phy_cell_id` at
  offset 4 all produced sensible values on first run. The v≤9
  fallback path is still untested but unused on this firmware.

## Session 2026-04-14 (session 6) — attach fixes landed, PDP-activation cause identified as Orange F #33

This session moved the story forward in two big ways: the attach-side
code bugs are fixed and the modem now reliably reaches `PS: attached`
on *something*, and a direct AT test finally yielded the explicit
reject cause code that tells us which `something` we need.

### Attach-side: three cell-data bugs, one DIAG tool, one commit cluster

Commits `d06bede` → `0591b6d` → `ff447b8` → `7df1869` → `fcbc82e` →
`4078320` → `a13246a`.

- **`tools/cell-diag.c`** (new). Opens `/dev/diag`, switches to
  `MEMORY_DEVICE_MODE`/MPSS, subscribes to the LTE equipment class
  (`LOG_CONFIG SET_MASK` for `equip_id=0x0B`, items `0xC0..0xFF`),
  parses inbound `cmd=0x10` log packets, and appends one JSONL line
  per event to `/var/log/cellular-diag.log`. Also recognises the
  Qualcomm multi-frame concatenation (several `7e 01 LL LL ... 7e`
  wireline frames per USER_SPACE_DATA sub-packet) so it doesn't
  drop events. Wired as `just diag-capture [duration]` which
  cross-compiles, scps, runs `cell-data wake` on-device against a
  backgrounded capture, and pulls the log back. First capture during
  a failing `lte,automatic` wake showed **153 × 0xB0C0 LTE_RRC_OTA
  events, zero 0xB0E2/0xB0E3 EMM_OTA_IN/OUT** — the modem reads SIBs
  from LTE cells but never transmits an ATTACH REQUEST, which
  rewrote the whole investigation (the problem is upstream of NAS).
- **`cell-data.sh`, three bugs in sequence, all attach-breaking**
  (commit `7df1869`):
  1. **`ensure_rat_prefs` was enforcing `lte,automatic` (LTE-only)**
     because an earlier session feared cross-border UMTS latching.
     DIAG above showed `lte,automatic` is in fact the *reason* we
     never reach NAS — the BQ268 can read LTE SIBs but never sends
     a Connection Request UL, so the modem oscillates searching
     forever. Switching to `lte|umts,automatic` lets the modem fall
     back to UMTS, which at the test bench reliably attaches to
     Orange F within ~40 s. Kept as a temporary workaround with a
     comment flagging the LTE-attach block as the real bug.
  2. **`ensure_rat_prefs` grep matched a literal `'lte, umts'`** but
     the modem reports the mode preference as `'umts, lte'` after a
     set. With that never matching, `ensure_rat_prefs` re-applied
     preferences on every `wake`, and each re-apply caused a
     transient NAS detach, silently dropping whatever session was
     up. Fix is an `-E` grep accepting both orderings.
  3. **`ensure_mcfg` used `grep -A1 Singtel_Commercial` + `grep
     Active`**, but `Status: Active` is ~3 lines below
     `Description:` in `qmicli --pdc-list-configs` output, so the
     check *never* matched and the Singtel MCFG was re-activated on
     every wake. That triggers an internal modem reset and tears
     down registration mid-flow — a cost we'd been silently eating
     forever. Fix is `grep -A4` with an anchored `Status: *Active`.
  With those three fixes applied, `cell-data wake` reaches
  `PS: attached` on Orange F reliably and stays there across
  consecutive wakes without dropping the attach.
- **`rootfs/files/etc/ppp/cellular-chat`** (commit `4078320`)
  restored to the 2026-04-03 form documented in `docs/modem_data.md`:
  explicit `AT+CGDCONT=1,"IP","globaldata"` then `ATD*99***1#`. My
  earlier experiment with `ATD*99***2#` / hicard was a dead end (see
  AT-level test below — the reject is the same regardless of APN),
  so the chat now matches the form that is known to work once the
  modem is camped on a partner that allows data.

### The AT-level test that finally gave us a reject code

All earlier sessions stopped at "PPP IPCP loops with dummy values
(`ms-dns1 10.11.12.13`, peer `10.64.64.64`)" and had no way to tell
*why*. The dummy values are a Qualcomm internal fallback when PDP
context activation fails below IPCP, so the failing layer is inside
the modem, not on the PPP wire.

Bypassing pppd entirely and driving `/dev/smd7` with raw AT through a
backgrounded `printf ... > /dev/smd7 &` + `dd if=/dev/smd7` surfaced
the thing we needed:

```
AT                                 → OK
AT+COPS?                           → "Orange F Eskimo",2   (UMTS)
AT+CGDCONT=1,"IP","globaldata"     → OK
AT+CGACT=1,1                       → +CME ERROR: requested service
                                      option not subscribed
AT+CGPADDR=1                       → +CGPADDR: 1,0.0.0.0
AT+CEER                            → Requested service option not
                                      subscribed
```

That is **3GPP 24.008 cause #33 "requested service option not
subscribed"** from the Orange F SGSN/GGSN. Tried `globaldata`,
`hicard`, `internet`, and empty APN — identical reject on all four.
The specific APN does not matter while we are camped on 208/01
*today*, but see the next paragraph for why that is not evidence of
a contractual block.

**Important clarification — Orange F is a working data partner on
this device.** Orange France (208/01) is in the `eskimo_roaming.md`
approved partner list and is present in the generated
`/etc/cellular/roaming-partners`. We have **successfully run data
over Orange F on this exact BQ268 in previous experiments**; the
"PPP over SMD works" verification in `docs/modem_data.md` (2026-04-03)
was against Orange F. The test bench has weak-but-usable Orange F
coverage — line of sight across the border into France, with the
nearest tower roughly 10 km away — so the signal is marginal by
design, not absent.

So the `#33` we got today is **not** evidence of a signalling-only
MVNO agreement. The more likely readings are, in rough order:

1. **Marginal RF → intermittent PDP activation**. `#33` is the cause
   code you get when the network processes the request but refuses
   it; the most innocent reason at a 10 km cross-border cell is that
   the bearer setup timed out at the RNC/SGSN and the reject was
   returned as "not subscribed" rather than a more specific timing
   failure. The modem was only at `PS: attached` for a few seconds
   before we ran the CGACT. Next time, repeat the direct AT test
   several times over a few minutes and see if the result is stable
   or flickers between `OK` and `#33`, and record RSSI/RSRP at the
   same time via `qmicli --nas-get-signal-info`.
2. **Cell-specific block**. Orange F has many cells at the bench;
   the specific one we camp on today may be a femto, an emergency-
   only cell, or a cell whose `accessAllowed` bitmap excludes our
   IMSI, while the cell we used successfully in April was a
   different one. Include PCI and ARFCN in the AT-test capture
   (`AT+QENG` or the equivalent on this firmware, or cross-ref the
   DIAG `0xB0C0` RRC OTA events for the same window).
3. **The modem's session / NV state got dirty**. We ran a lot of
   `dms-reset`, MCFG-activate, and profile-modify calls during the
   session; any of these can leave the ESM/SM state machine in a
   half-provisioned state where the first CGACT after the reset is
   #33 and the second one is `OK`. Try a `dms-reset` + a single
   clean CGACT before drawing conclusions.

None of those invalidate what the session moved forward — the
cell-data attach fixes are still correct, `cell-diag` is still the
right visibility tool, the "never sends EMM_OTA on LTE" DIAG
finding still stands — but the high-confidence conclusion
"Orange F Eskimo is signalling-only" is **wrong**. The actual
status of Orange F as a data partner is **works when the RF is
good enough**, and today's `#33` is a failure mode we do not
understand yet rather than a contractual wall.

Combined with the overriding ground truth at the top of this doc
(Android on the same SIM attaches Sunrise-LTE and carries real
data at the same location), the remaining hypothesis space is now:

- **A: Sunrise LTE is the path of least resistance**, regardless
  of what Orange F is doing. Android picks it because LTE
  reselection prefers stronger LTE cells over UMTS, and the BQ268
  today cannot complete LTE attach on Sunrise (see the April 13
  session 5 and the DIAG data in this session). The fix is up in
  the RRC/NAS stack, not in data-plane routing.
- **B: Orange F weak-signal PDP failures are a separate
  intermittent problem**. Worth not attributing to the Sunrise
  investigation. Repeat the AT test on a day/hour when Orange F
  signal is slightly better and see if `#33` disappears; if it
  does, file it as "marginal-coverage data fragility on Orange F"
  and move on.
- **C: Some state carried across our reset churn is degrading
  both paths**. Can be disambiguated by a clean cold-boot test
  with no intermediate MCFG/profile manipulation — just boot,
  wake, direct AT CGACT, record result.

### Why we can't just steer to Sunrise today

Tried at runtime:

- `qmicli --nas-set-preferred-networks=22802,all` + reset → modem
  still comes up on Orange F. The user-controlled preferred PLMN
  list is a *soft* preference; automatic reselection still picks
  the strongest matching cell, and Orange F UMTS wins on signal.
- `--nas-set-preferred-networks=22802,eutran` + `lte|umts,automatic`
  → same outcome; modem searches LTE briefly, drops to UMTS, Orange.
- `--nas-set-system-selection-preference="lte|umts,manual=22802"` →
  `Registration state: not-registered` for ≥120 s while `PS:
  attached` stays set (a weird split-brain). Modem never completes
  registration on Sunrise. Matches the April 13 session 5 notes.
- `--nas-set-system-selection-preference="lte,automatic"` → same
  April-13 symptom: reads SIBs (DIAG shows `0xB0C0`), no NAS OTA,
  never attaches, eventually drops to `not-registered-searching`.

Preferred-networks, manual-selection and LTE-only all fail to move
us off Orange F → Sunrise. The primary follow-up is therefore:

- **Fix the LTE-attach-never-completes block on Sunrise.** April 13
  session 5 hypothesises a **B20 UL TX path issue** on the BQ268
  PCB (DL RX works — scans see cells — but UL may not). Before
  spending a session on RF hardware, extend `cell-diag` to parse
  the `0xB0C0 LTE_RRC_OTA` `pdu_num` field: if `UL_CCCH` (RRC
  Connection Request) frames never appear during a `lte,automatic`
  wake, UL is broken; if they do appear, UL is fine and the
  problem is higher up (SIB reject, TAI block, MCFG policy, etc).
  That's a ~1 hour parser change that either confirms a hardware
  bug or kills the hypothesis cheaply.

Secondary follow-ups, to do *only* if the primary stalls:

- Re-run the direct AT CGACT test against Orange F across several
  attempts with signal-info logging to see whether today's `#33`
  is a stable contractual wall or an intermittent marginal-RF /
  dirty-state thing.
- If Orange F is stable-working in a clean cold-boot test but
  reliably `#33` mid-session, something in cell-data's reset /
  MCFG / profile-modify churn is wedging SM state and we need to
  stop doing whichever operation is poisoning it.
- As a *last* resort, if LTE attach on Sunrise turns out to be
  genuinely unreachable, hard-blocking `208/01` via `EF_FPLMN`
  (`AT+CRSM` or `uim-write-transparent`) would force the modem
  onto Salt/Swisscom/Sunrise — but this is a workaround on top of
  a workaround and only makes sense once we know Orange F is
  broken *and* Sunrise is unreachable, which this session does
  not yet establish.

All follow-ups are live in `TASKS.md`.

### Ugly details worth remembering

- **`[pppd] in D state`**: killing `pppd` mid-IPCP on `/dev/smd7`
  wedges the kernel's SMD line-discipline teardown (`do_exit` stuck
  in `smd_close`), leaving a zombie `[pppd]` that only a reboot
  clears. Happens reliably. This is a CAF 4.4 SMD bug — file under
  the known SMD cleanup hazards. Worth a `cell-data down` that
  avoids `SIGKILL` and sends `SIGTERM` only, and a health-check in
  `wake` that refuses to start if a zombie `[pppd]` is present.
- **After a `dms reset`, the modem can take 90–120 s to leave
  `shutting-down` on its own**. `cell-data wake`'s `WAKE_BUDGET=20s`
  is too short for a post-reboot first-wake; it hits the reset
  escalation and fails with "modem stuck in shutting-down" even
  though the modem would have come up a minute later. Bump to 150 s
  for the post-boot-first-wake path, or detect reboot and take the
  long budget for the first run only.
- **Every `dms-set-operating-mode=reset` we issue via `qmicli -p`
  leaks a `kworker/u8:N` in D-state** and grows `drop_count` on the
  DIAG ring. Known issue; tracked under the qmi-proxy orphan task.
- **The `Mode preference` string ordering** (`'umts, lte'` vs
  `'lte, umts'`) is not stable — see bug 2 above. Any grep on
  `qmicli --nas-get-system-selection-preference` output that
  anchors on a specific RAT order is broken waiting to happen.

## What's done

- **`tools/cell-data.sh`** is the single entry point. `cell-data wake`
  is a bounded 2-minute state machine:
  1. `ensure_rat_prefs` — idempotently applies `lte|umts,automatic`.
     Stored in modem NV, survives resets and reboots, so this is
     usually a no-op.
  2. `set_online` — handles online / low-power / offline /
     shutting-down / resetting with a single reset-escalation on
     `WAKE_BUDGET=20s` timeout.
  3. `wait_ps_attached` — `ATTACH_BUDGET=45s` automatic-attach phase.
  4. **Partner fallback**: `nas-network-scan=lte` → filter visible
     networks against `/etc/cellular/roaming-partners` → try each
     approved partner with `manual=MCCMNC` for `PARTNER_BUDGET=30s`.
  - Exit codes: `1` = couldn't reach online (firmware deadlock),
    `2` = PS didn't attach (coverage/roaming). Callers and
    `just smoke-cellular` can distinguish the two.
- **`do_up`** chains wake → `pppd call cellular` → wait for `ppp0`
  to get an IPv4 (`PPP_BUDGET=30s`). **`do_down`** kills pppd. The
  old rmnet/WDS path was dead code — removed.
- **`log_serving`** records `plmn/rat/roaming/home` to
  `/var/log/cellular.log` on every successful attach, so data-byte
  correlation with roaming periods becomes possible.
- **`just smoke-cellular`** runs wake → up → `ping -I ppp0 8.8.8.8`
  → down against the live device.
- **`/etc/cellular/roaming-partners` is auto-generated** by
  `just gen-roaming-partners` (runs `tools/gen-roaming-partners.py`),
  joining `eskimo_roaming.md` (authoritative Eskimo partner list,
  extracted from https://www.eskimo.travel/en/network-coverage on
  2026-04-13) against `tools/data/mcc-mnc-list.json` (vendored
  `pbakondy/mcc-mnc-list`). Fuzzy brand match with accent folding and
  parent-brand aliases. Current coverage: 154 MCC/MNC rows for
  118/139 Eskimo countries; 21 unresolved long-tail entries printed
  to stderr — extend `BRAND_PARENTS`/`COUNTRY_ALIASES` and re-run.
- **Home SIM**: Eskimo eSIM, **MVNO on Singtel IMSI 525-01**.

## Key findings from cross-device testing

- **Eskimo eSIM works fine on Android** at the same physical
  location: attaches, 4G, picks Sunrise as roaming partner, data
  flows. Rules out Eskimo account state, Singtel HSS path, Sunrise
  roaming agreement, and reception. The blocker is specific to our
  MSM8909 modem / kernel / userspace config.
- **APN on Android: `hicard`**. We were attempting an empty APN
  (`AT+CGDCONT=1,"IP",""`) in `rootfs/files/etc/ppp/cellular-chat`
  and earlier notes mentioned `globaldata` from the initial bringup
  on Orange France. The chat-script fix (hardcoding `hicard` in
  CGDCONT) is committed, **but that only applies at CGACT / PPP
  time — after attach**. We're failing at attach. So the real
  question is: **what APN does the modem use during the attach-time
  PDN-CONNECTIVITY-REQUEST?** On Qualcomm firmware that comes from
  the default WDS 3GPP profile (profile 1), not from the chat
  script. Earlier enumeration showed profiles `empty-APN / ims /
  sos`. If attach is being rejected for "missing or unknown APN"
  (3GPP 24.301 #27) or "requested service option not subscribed"
  (#33), the fix is to set profile 1's APN to `hicard` via
  `qmicli --wds-modify-profile` before attach, not just in the
  chat script.

  **Next action**: set WDS profile 1 APN to `hicard` and retry
  `cell-data wake`. If attach then succeeds, wire this into
  `ensure_rat_prefs` (or a new `ensure_wds_profile`) as another
  idempotent bringup step. The chat-script change stays as a
  matching belt-and-braces for CGACT.

## What's broken

At the test bench on 2026-04-13 (Switzerland, same physical location),
the modem **sees LTE cells but cannot PS-attach** on any carrier.

- `nas-network-scan=lte` consistently returns all 5 visible networks
  (Swisscom 228/01, Sunrise 228/02, Salt 228/03, Orange FR 208/01,
  Free 208/15) as `available, roaming, not-forbidden`.
- `lte,automatic`: registration oscillates
  `not-registered-searching` → `not-registered` → `power-save`,
  radio stays at `none` or briefly goes to `umts`, never attaches.
- `lte|umts,automatic`: same behaviour, radio parks on `umts`
  searching without attaching.
- `lte,manual=22802` (Sunrise, the **correct Eskimo partner** per
  the authoritative list): accepted by qmicli,
  `Network selection preference: manual`, still no attach.
- Same result after device reboot, `rc-service modem restart`,
  `dms reset`, and clean NV prefs.

The script's 2-minute budget bounds the failure cleanly (exits 2),
so the state machine is correct. The actual attach failure is
downstream of the script — environmental, agreement-layer, or a
firmware/kernel problem.

## Session 2026-04-13 (session 5) — Android ground truth + RF reality check

Put the SIM in the user's Android phone (MediaTek Dimensity — so the
phone itself is useless for MCFG extraction, but great as behavioural
ground truth) and captured what an attached state actually looks like
on this SIM at this location:

- PLMN: **Sunrise 228/02**, RAT LTE, ROAMING/INTERNATIONAL
- Primary serving cell: **EARFCN 6200 = B20 (800 MHz DD)**, PCI 76,
  TAC 42100, BW 10 MHz, RSRP **-100 dBm**
- Other Sunrise cells seen: EARFCN 1850 (B3 1800) RSRP -116/-124,
  EARFCN 2850 (B7 2600) RSRP -124
- APN **hicard** (bearer 1, IPv6-only, `2400:1c00:…`) +
  separate IMS bearer on IPv4 (irrelevant for BQ268)
- Also confirmed: attach works fine with APN=`E-IDEAS` too, so the
  Singtel-default IA APN is not the gate.
- `apn.settings_default_roaming_protocol_string` empty → Android uses
  the APN's configured protocol (IPv4v6) but Sunrise grants v6 only.

### Module-level verification on BQ268

Confirmed our MSM8909 variant supports the right bands:

```
LTE bands capability: 1, 2, 3, 5, 7, 8, 20, 28, 38, 39, 40, 41
LTE band preference : 1, 3, 5, 7, 8, 20, 28, 39, 40
```

So B20/B3/B7 — all three bands Android saw Sunrise on — are available
on our RF. **Band capability is not the gate.**

### The actual gate: ??? — not pure RF, not MCFG, not usage-pref

Symptom: the modem parks on a strong Salt UMTS neighbour in
`Status: limited` (CS-only; Salt won't grant PS to this IMSI):

```
PLMN: 22803 (Salt), UARFCN 2938, PSC 80, RSCP -74…-92 dBm, ECIO -3dB
```

Sunrise LTE cells ARE visible to `--nas-network-scan=lte` (228/02
appears "available, roaming, not-forbidden" alongside Salt and
Swisscom) but the modem never completes attach on any of them, and
with `mode=lte` only it searches ~25s and then gives up into
power-save. With all RATs enabled, it falls through to the strong
Salt UMTS cell instead.

**Important correction from user**: the BQ268 has an **external
antenna**, so the earlier hypothesis that the walkie-talkie internal
antenna was eating 10-20 dB vs the Android phone is wrong. Sunrise LTE
RSRP on BQ268 should be comparable to what Android saw here (-100 dBm
on B20). This puts the problem back in software/firmware/MCFG
territory or a specific RF-path asymmetry (DL RX works — scans see
the cells — but UL TX on B20 may not; worth checking whether the B20
PA/filter is actually populated on this board).

`manual=22802` did not override — modem still ended up on Salt UMTS
limited.

### Things ruled out this session

- **Usage preference** (voice-centric vs data-centric): we *did* find
  the modem was voice-centric, which on paper is wrong for a data-only
  device. Fixed by extending qmicli to accept
  `usage=data-centric` (libqmi commit d8995d3) and wiring it into
  `ensure_rat_prefs`. Useful in general, but **did not change the
  observed behaviour** — cell reselection still hijacks to Salt UMTS.
- **MCFG policy**: swapped `Singtel_Commercial` for `ROW_Commercial`,
  same behaviour. Singtel MCFG is not the gate either.
- **FPLMN block**: EF_FPLMN contains only APAC Singtel-family entries
  (525/03, 525/05, 502/18, 502/19). No Swiss PLMN is forbidden.
- **`--nas-reset` + mode cycle**: NAS state refresh doesn't help.
- **IA APN mismatch**: ruled out by the E-IDEAS-on-Android test.

### Tools & repo state after this session

- `~/libqmi` commit d8995d3 extends `--nas-set-system-selection-preference`
  parser to accept `usage=data-centric|voice-centric` tokens.
- `tools/cell-data.sh` `ensure_rat_prefs` now enforces
  `lte,automatic,usage=data-centric`.
- Task #8 added: `send_filled_buffers_to_user: Send Failed -3` backlog
  from unserviced QMI indications. Not fatal yet, but growing.
- Task #7 (patch Singtel MCFG to allow Sunrise LTE attach) is
  effectively moot — rat_acq_order isn't the gate, and Singtel vs ROW
  MCFG make no visible difference for our actual problem (RF/location).

### Next session should

1. **Get ground-truth LTE signal on BQ268 at the stuck location.**
   `qmicli --nas-get-signal-info` + `--nas-get-cell-location-info`
   in `mode=lte` only, ideally while the scan is running. If RSRP on
   B20/B3 is comparable to Android (~-100) then RF is fine and it's
   a firmware/attach problem. If it's much worse, the RF path is
   asymmetric and we need hardware inspection (antenna routing, B20
   PA/filter population).
2. **Restrict LTE band preference** to force trying B3 only, then B7
   only, then B20 only. If only some bands can attach, the broken
   ones point at specific RF-path components. libqmi has
   `qmi_message_nas_set_system_selection_preference_input_set_lte_band_preference`
   but qmicli doesn't expose it — another small parser extension
   needed, similar to the `usage=` one.
3. **DIAG NAS logs** (task #4). Without them we're guessing at reject
   causes; with them we'd see exactly why attach fails (EMM cause
   code, ESM cause code, RACH outcome).
4. Task #8 (indication backlog) is worth handling either way; it's
   independent of the attach problem.

## Session 2026-04-13 (session 4) — MCFG NV dissection + rat_acq_order patch

Decoded the Singtel_Commercial MCFG's NV items (84 total: 22 NV by
number, 61 NV files, 1 trailer). The key finding: the Orange-FR UMTS
steering from session 3 is entirely explained by one 10-byte NV file,
`/sd/rat_acq_order`:

```
Singtel:    07 03 e7 00 05 09 05 03 02 04   ← UMTS (05) first, LTE (09) second
EU DT:      07 00 00 00 06 09 05 03 04 02 0b ← LTE (09) first
CMCC China: 07 03 e7 00 04 09 0b 05 03       ← LTE first (with 5G)
Singtel^:   07 03 e7 00 09 05 05 03 02 04   ← our patched: LTE first
```

Wrote `tools/patch-singtel-rat-first.py` — reads the rootfs Singtel
MBN, byte-swaps the first two RAT values (0x05↔0x09), recomputes the
hash segment (hash-only MBN per `gen-mcfg-mbn.py`, no signature).
Modem accepts the patched MBN via `--pdc-load-config` and the
config ID changes, proving hash integrity is what's validated.

**Behavioural delta**: the UMTS-Orange-FR bias is gone. Unpatched MCFG
camped on 208/01 UMTS within seconds; patched MCFG never camps on
any UMTS cell. But it also never camps on any LTE cell — modem stays
in `not-registered-searching` for the full 45s of polling, then
enters `power-save`.

So `rat_acq_order` **is** the steering mechanism we thought, but
there's a **second** gate blocking non-home LTE roaming. The Singtel
MCFG's 22 NV-by-number items are the likely location — numbers
include 917575 (Singtel_SG name string), 197463, 262992, 262993,
131981, 132088, 132089, 199614, 134604, 134605, ... Without the
Qualcomm NV catalog, we can't tell which one gates LTE roaming. The
ones with attrib 0x39 are different (rest are 0x19) — those are
worth looking at first.

**Committed**:
- `tools/patch-singtel-rat-first.py` — one-shot MBN patcher
- `rootfs/files/usr/share/cellular-mcfg/singtel_sg.mbn` — now the
  LTE-first variant (overwrites the original from session 3)

**Next session**:
1. Decode the 22 NV-by-number items. Attrib 0x39 items first. Try
   patching each one to 0/1/0xFF and testing attach behaviour —
   bisection will find the roaming gate if one exists.
2. Cross-reference against a known-good MCFG that DOES allow LTE
   roaming for APAC IMSIs. `generic/apac/reliance/commerci/mcfg_sw.mbn`
   has a different NV signature — worth diffing.
3. Alternatively, dump `modem.bin` from a current Android phone
   running an Eskimo eSIM. A newer Singtel MCFG variant may
   already have the Eskimo-specific roaming gate set.

## Session 2026-04-13 (session 3) — MCFG-SW carrier profiles

**The biggest finding of the whole investigation**: our modem was
running with **zero MCFG-SW carrier profiles loaded**
(`qmicli --pdc-list-configs=software` → `Total configurations: 0`).
MCFG-SW is Qualcomm's per-carrier policy bundle: roaming agreements,
default attach APN, SOR rules, PDN-type enforcement, band
restrictions, subscription overrides. Without one, the modem's NAS
layer runs a bare-bones fallback that never completes a default-EPS-
bearer activation for our Eskimo IMSI. That alone explains 95% of
the "attach never sticks" symptoms from sessions 1 and 2.

### What we did

1. **Mounted `~/bq268-edl/dump/modem.bin`** as FAT16 — it's the
   `/firmware` partition from the original vendor Android image.
   Contains 118 MCFG-SW files under
   `image/modem_pr/mcfg/configs/mcfg_sw/`, including
   `generic/sea/singtel/commerci/singapor/mcfg_sw.mbn` and
   `generic/common/row/commerci/mcfg_sw.mbn`.
2. **Copied Singtel + ROW MCFGs into the rootfs** at
   `/usr/share/cellular-mcfg/{singtel_sg.mbn,row_generic.mbn}`
   and deployed them to the device.
3. **Loaded and activated via QMI PDC**:
   `qmicli --pdc-load-config=<path>` uploads in 1024-byte chunks,
   then `--pdc-activate-config=software,<ID>`. Activation triggers
   an internal modem reset (NAS restart) as a side effect. Both
   configs persist in modemst1/2 NV across device reboots.
4. **Added `ensure_mcfg` as a new bringup step** in
   `tools/cell-data.sh`: idempotent, loads + activates Singtel
   MCFG if not already Active. Runs first in `do_wake` so the NAS
   layer has the right carrier policy before any other ensure_*
   step touches state.
5. **Stopped overriding WDS profile 1**. Profile 1 is the
   LTE-attach PDN, and the Singtel MCFG sets its APN to `E-IDEAS`
   (Singtel's default initial-attach APN). Eskimo's `hicard` is an
   overlay APN for the data session, not the initial attach, so we
   now leave profile 1 alone and rewrite **profile 2** to
   `hicard / IPV4V6` for use at CGACT time.

### Qualitative change to attach behaviour

Before this session: 0-2 second EMM-REGISTERED flashes, never
reproducible, no durable attach.

After Singtel MCFG activation + `lte,automatic` + PDC reactivate kick:
**15.5 seconds of stable `Registration: registered, Status:
available`**, fully reproducible from any clean modem state. This is
a qualitative jump.

### The catch

Looking at the serving-system during the 15s stable window:

```
Registration state: 'registered'
CS: 'attached'
PS: 'detached'
Radio interfaces: '1'
    [0]: 'umts'
Roaming status: 'on'
Current PLMN:
    MCC: '208'
    MNC: '1'
    Description: 'Orange F'
```

We're **camped on Orange France UMTS in CS-only mode**. CS-only
attach means voice works, data does not — and since Eskimo is
data-only, we still can't ping anything. The Singtel MCFG is
**steering us to Orange FR** because that's Singtel's configured
European roaming partner for their own direct subscribers. It
overrides our `lte,automatic` preference through its internal
SOR/preferred-roaming rules.

Eskimo (as an MVNO on Singtel infrastructure) has a **different**
roaming partner list — Sunrise in Switzerland — that isn't encoded
in the Singtel MCFG. Android on the same SIM in the same room
attaches to Sunrise LTE, so Android either (a) uses an MCFG we
don't have, or (b) bypasses the Singtel MCFG's steering via
RIL-level overrides we can't trivially replicate from Linux
userspace.

We tried two workarounds, both failed:

- **Singtel MCFG + `lte,manual=22802` (force Sunrise)**: modem
  searches for 25s and gives up — Singtel MCFG's rules block
  manual attach to Sunrise LTE.
- **ROW_Commercial MCFG + `lte,automatic`**: modem doesn't attach
  to anything. ROW has no IMSI routing knowledge for 525/01, so
  NAS falls back to the same bare fallback as "no MCFG".

### What's committed from this session

- `tools/cell-data.sh` — adds `ensure_mcfg` step that loads +
  activates Singtel_Commercial MCFG from
  `/usr/share/cellular-mcfg/singtel_sg.mbn`. New `PRIMARY/FALLBACK`
  file variables at top. Also revises `ensure_wds_profile` to
  write `hicard/IPV4V6` to **profile 2** (data session), leaving
  profile 1 to whatever the MCFG set (currently `E-IDEAS/IPV4V6`
  as the initial-attach APN).
- `rootfs/files/usr/share/cellular-mcfg/singtel_sg.mbn`,
  `row_generic.mbn` — extracted from modem.bin, shipped in the
  rootfs so a fresh flash picks them up automatically.

### Open next steps (ordered)

1. **Patch Singtel_Commercial MCFG to remove Orange-FR steering**.
   `tools/patch-mcfg-mbn.py` already exists in the tree. Approach:
   decode the MCFG's NV items, find the roaming preferred-PLMN /
   SOR rule that pins Orange-FR, either drop it or add Sunrise
   228/02 as a higher-priority entry. Re-sign (hash-only, no
   signature needed per `gen-mcfg-mbn.py` comments). Load via
   PDC. This is the single highest-leverage thing we can do now —
   all the infrastructure is already in the tree.
2. **Dump an Android /firmware partition from a Singtel device
   that's actually running an Eskimo eSIM**. If Android works
   with different MCFG, that MCFG is the answer. Needs physical
   access to such a device.
3. **Wire up DIAG NAS log subscription** to capture what the modem
   is actually sending in ATTACH_REQUEST and what the network
   responds with when we try manual=22802. Still the most
   informative fallback, but also the largest piece of work.
4. **Try oFono** as an alternative to our `cell-data.sh`. oFono
   on AF_MSM_IPC may have different bearer-activation semantics
   than bare qmicli.

## Session 2026-04-13 (session 2) — preferred-PLMN list + cell-data.sh hardening

Follow-on session after a device reboot. Focus: mimic what Android is
doing by populating the modem's preferred-PLMN list, then hardening
`cell-data.sh` so the winning config is applied automatically.

### What we did

1. **Dumped SIM PLMN-selector EFs via `qmicli --uim-read-transparent`:**
   - `EF_OPLMNwAcT` (6F61, operator-controlled roaming list):
     **only one entry — `525/01 Singtel` with UTRAN+EUTRAN+NG-RAN+GSM.
     Zero roaming partners.** Every other slot is `00 00 FF FF FF`.
   - `EF_PLMNwAcT` (6F60, user-controlled): also only `525/01`.
   - `EF_HPLMNwAcT` (6F62): correct HPLMN `525/01`.
   - `EF_FPLMN` (6F7B): `525/03, 525/05, 502/18, 502/19` — old SE-Asia
     forbidden entries, nothing Swiss-blocking.
   - Conclusion: Android must be succeeding by either (a) SOR from
     SingTel HSS after a first registration, or (b) scanning and
     attaching to any non-forbidden PLMN because OPLMN has no steering.
     We can fake (a) by writing the modem's *user-controlled*
     preferred list via QMI (no ADM PIN needed, persists in modem NV).

2. **Patched `tools/cell-data.sh`** (3 new idempotent bringup steps):
   - `ensure_rat_prefs` now applies `lte,automatic` (was
     `lte|umts,automatic`). UMTS is dropped because the modem
     otherwise latches onto weak cross-border **UMTS Orange-FR
     (208/01)** inside CH and never attempts Sunrise LTE.
   - `ensure_wds_profile` rewrites WDS profile 1 to
     `APN=hicard, PDP=IPV4V6` (was `'', ipv4`). Profile 1 is the
     LTE-attach PDN per `wds-get-lte-attach-pdn-list=[1]`, so this is
     what gets sent in the initial PDN-CONNECTIVITY-REQUEST.
   - `ensure_preferred_networks` writes a priority-ordered preferred
     PLMN list via `qmicli --nas-set-preferred-networks`. Cap is 20
     entries (see below). `PRIORITY_MCCS="228 208 262 222 232 214 268
     272 206 234"` — CH first, then immediate neighbours and common
     EU. Remainder filled from `/etc/cellular/roaming-partners` in
     file order (skipping priority MCCs). Persists in modem NV.

3. **Discovered the modem's preferred-PLMN list cap**: QMI accepts
   `--nas-set-preferred-networks` with up to ~80 entries, but the
   modem silently stores only the first **~23** — likely the SIM's
   EF_PLMNwAcT allocation (≈100 bytes / 5 bytes per entry). Writing
   all 154 partners unordered pushes `228/02 Sunrise` (position 27 in
   the alphabetically-sorted file) out of the window entirely. Fix
   is in `PRIORITY_MCCS` ordering + 20-entry cap in
   `ensure_preferred_networks`. Verified post-write that the dynamic
   list contains `[0] 228/2 eutran` as the top entry.

### What we observed

- **One real PS attach**, for ~3 seconds, captured live in a
  1.5-second serving-system poll:
  ```
  t=01 Registration: registered | PS: attached  | Selected: 3gpp
  t=02 Registration: registered | PS: attached  | Selected: 3gpp
  t=03 Registration: registered | PS: detached  | Selected: 3gpp
  t=04 Registration: registered | PS: detached
  t=05 Registration: registered | PS: detached
  t=06 Registration: not-registered-searching | Status: none
  ...
  t=18 Status: power-save
  ```
  This is the **only** successful PS attach in the entire
  investigation so far, and it came after all three fixes above were
  applied manually. Signature: EPS attach → default bearer allocated
  → bearer deactivated by network after ~3s → EMM stays registered
  briefly → full detach. Textbook "bearer teardown by core" (ESM
  cause #36 / #29 / #30 / #30-family, SGW/PGW policy / auth fail).
  This is **not** reproducible at will — subsequent runs with
  identical config go straight to `not-registered-searching →
  power-save` with no EMM flash, suggesting NAS backoff (T3402 or
  similar) and/or marginal signal at this bench.

- **iPhone data point still relevant**: iPhone on a Sunrise MVNO at
  the same bench reports 2/4 bars on LTE. Our modem may simply have
  a weaker RF frontend / SIB1 handling, or the accumulated-reject
  backoff is stickier on Qualcomm NAS.

### What's committed / ready to flash

- `tools/cell-data.sh` updated with the three new `ensure_*` steps
  (on-device at `/usr/sbin/cell-data`, also in repo).
- Profile 1 is `APN=hicard, PDP=ipv4-or-ipv6` in NV.
- Preferred-networks NV has 20 entries, `228/2 Sunrise eutran` at
  index [0].
- All new state is NV-backed so survives modem + device reboots.

### Open blockers / next-session priorities

1. **Get DIAG NAS logging actually working**. Without a NAS cause
   code, we can't distinguish "network rejecting our attach"
   (#33/#36/#8/#11/#27/#50/#51 all have different fixes) from "NAS
   backoff after earlier rejects". This is the single highest-value
   piece of tooling the project lacks. Starting points:
   - `modem_decompiled_src/pass7_diag*.c` — already have the DIAG
     CNTL analysis.
   - `memory/project_diag_state.md` — known state: feature mask
     sends OK but modem port blocks cmd registration. That blocker
     is the thing to crack.
   - Target: subscribe to LTE NAS log packets (LTE NAS EMM OTA
     Incoming/Outgoing 0xB0EC/0xB0ED, EMM state 0xB0E2), decode,
     print cause code.

2. **Alternate-SIM test**: a local Swiss prepaid (Sunrise/Swisscom/
   Salt physical SIM) in the same device. If it attaches
   immediately, the remaining failure is Eskimo-SIM-specific even
   with our config fix in place. If it fails, there's a real
   kernel/modem-firmware bug to chase. Cheap and decisive.

3. **Move to a location with stronger Sunrise LTE** and re-run
   `cell-data wake` with the current config. One attach-hold there
   would retroactively validate every fix in this session. If it
   still fails in strong coverage, we need DIAG.

4. **Consider the NAS backoff clearance path**. If reboots don't
   clear T3402 etc., the modem may have NV-persistent backoff state
   we can zero via NV writes (dangerous) or a factory reset via DMS.
   Only worth chasing if (3) also fails.

## Session 2026-04-13 (session 1) — live probing results

Android-with-same-SIM-same-location is confirmed working, so we spent a
session poking the modem via QMI to narrow down *where* on our side the
attach is failing. Summary of what we learned, in rough order of
importance:

1. **The LTE initial-attach profile chain is configured correctly.**
   - `wds-get-default-profile-number=3gpp` → 1
   - `wds-get-lte-attach-pdn-list` → `[1]`
   - Profile 1 APN was `''` and PDP type was `ipv4`.
   - **Set profile 1 APN=`hicard`, PDP type=`ipv4-or-ipv6`** this session
     — persists across `rc-service modem restart`, so it survives in
     modem NV. These should be added to `ensure_rat_prefs` (or a new
     `ensure_wds_profile`) as idempotent bringup steps.

2. **We finally triggered a real attach attempt and it reached
   EMM-REGISTERED briefly.** With `lte,manual=22802` (LTE-only, manual
   Sunrise) freshly applied, a 1.5-second serving-system poll captured:
   ```
   t=01 Registration: registered | PS: detached | Selected: 3gpp | Status: available
   t=02 Registration: registered | PS: detached | Selected: 3gpp | Status: available
   t=03 Registration: not-registered | Status: none
   ...
   t=18 Registration: not-registered | Status: power-save
   ```
   This is the signature of **attach reaching the core and being torn
   down within ~2s** — not an RF/roaming denial (which would stay
   `not-registered-searching` and never flash `registered`). Most likely
   culprits at this stage: ESM cause #33 (requested service option not
   subscribed), #50/#51 (PDN type IPv4-only / IPv6-only allowed), or
   #27 (missing or unknown APN) from HSS/P-GW. The IPv4→IPv4v6 fix in
   (1) is our best guess for addressing #50/#51; needs a re-run from a
   clean modem state to confirm.

3. **Under `lte|umts,automatic`, the modem biases hard to UMTS Orange F
   (208/01) instead of Sunrise LTE.** `nas-network-scan` shows
   `228/02 Sunrise lte` *and* `208/01 Orange F umts`, and the current-
   serving marker during scans lands on Orange F UMTS — weak
   cross-border signal from Switzerland. UMTS acquisition apparently
   wins the race against LTE in the modem's search priority. This is
   why automatic-mode wake never produced a `registered` flash at all:
   it was chasing UMTS France, not Sunrise LTE.
   - **Fix**: `ensure_rat_prefs` should use `lte,automatic` (not
     `lte|umts,automatic`) so UMTS is disabled and the modem is forced
     to attempt LTE attach somewhere. `umts` was a historical
     safety-net for 3G-only areas; at our bench this is actively
     harmful. Worth making it location-aware later (fall back to
     `lte|umts` if LTE fails for N minutes), but the default should
     be LTE-only.

4. **SIM preferred-PLMN list is essentially empty for roaming.**
   `nas-get-preferred-networks` returns exactly one entry: HPLMN
   `525/01 Singtel`. No operator-controlled PLMN list with Eskimo
   partners. Automatic selection is therefore pure "scan and pick
   strongest non-forbidden PLMN", which is why UMTS Orange F wins.
   Not fixable from our side without EFS writes — but (3) renders it
   moot.

5. **DMS / NAS state can desync into an unrecoverable deadlock.**
   Toward the end of the session, `dms-get-operating-mode` returned
   `shutting-down` permanently while `nas-get-serving-system` returned
   `not-registered-searching` (i.e. NAS thinks modem is online, DMS
   thinks it's shutting down). `dms-set-operating-mode=reset` and
   `rc-service modem restart` neither fix this. Only a full device
   reboot will. `cell-data wake` correctly exits 1 in this state. This
   is likely the same class of bug as the "stuck modem states" noted
   in `docs/modem_data.md`.

### Next session

1. Reboot the device to clear the DMS/NAS deadlock.
2. On the next `cell-data wake`, confirm that profile 1 still has
   `APN=hicard, PDP=ipv4-or-ipv6` (NV-persisted). If so:
3. Run `cell-data wake` once with the current `lte|umts,automatic`
   default — expect it to still fail, confirming the UMTS-bias
   hypothesis (3).
4. Edit `tools/cell-data.sh` `ensure_rat_prefs` to set
   `lte,automatic` instead of `lte|umts,automatic`. Re-run
   `cell-data wake`. If we see a durable `registered + PS: attached`,
   the session's fixes worked. If we see another ~2s EMM-REGISTERED
   flash and collapse, the IPv4v6 change was not enough and the next
   step is DIAG NAS logging (project, not a one-liner — see
   `modem_decompiled_src/pass7_diag*.c` as a starting point) to get
   the real ESM cause code.
5. Once attach sticks, add `ensure_wds_profile` as a new idempotent
   step in `cell-data.sh`: checks profile 1's APN and PDP type and
   rewrites only when wrong (same ethos as `ensure_rat_prefs`).

## Key data point (2026-04-13)

**An iPhone on a local Swiss MVNO that uses Sunrise's network
attaches successfully from the same physical location, reports 2/4
bars on 4G.** This narrows the failure mode significantly:

- **Reception is fine.** Sunrise LTE is reachable and usable from
  this spot — it's not an RF dead zone. Weak signal (2/4 bars) but
  good enough for home-network attach.
- **Sunrise's LTE cell is accepting registrations** — just not
  *roamer* registrations for our IMSI.
- **The problem is the roaming path**, not reception, not the
  modem's RF front-end, and (unless stock Android also fails here)
  not something broken in our kernel/firmware.

Most likely causes, in order of probability:

1. **Eskimo roaming not enabled on this eSIM for Switzerland.**
   Eskimo's advertised partner list ≠ per-account activation. The
   account may need a plan/pack with Switzerland enabled, or the
   HPLMN/VPLMN agreement may be live at the Singtel-wholesale layer
   but not provisioned on this specific eSIM profile. Check the
   Eskimo dashboard and profile state before assuming a technical
   bug.
2. **Singtel's roaming gateway is rejecting our IMSI.** With
   category = "MVNO on Singtel", the roaming path is Sunrise →
   Singtel HSS → Eskimo auth. If any link in that chain doesn't
   know about this IMSI (expired plan, unprovisioned, wrong APN for
   the roaming context), attach fails before the cell even reports
   a cause code.
3. **Modem NV missing Sunrise in the PLMN list / wrong SIB1
   handling.** Less likely given we can see 228/02 in the scan and
   manual register accepts it — but not impossible if the firmware
   has a stale roaming list baked in.

## Suggested next steps (ordered)

1. **Check Eskimo account state** — log into the Eskimo dashboard,
   confirm the eSIM profile is active, has a data plan that
   includes Switzerland, and is not throttled / soft-suspended /
   in a grace period. Cheapest test first: if the plan lapsed,
   everything else below is wasted effort.
2. **Enable modem DIAG logging on the NAS layer** and retry manual
   attach to 22802. Capture the actual reject cause — 3GPP TS
   24.008 §10.5.5.14:
    - `#7` (GPRS services not allowed),
    - `#8` (GPRS + non-GPRS not allowed),
    - `#11` (PLMN not allowed — roaming explicitly blocked),
    - `#12` (location area not allowed),
    - `#13` (roaming not allowed in this tracking area),
    - `#14` (GPRS not allowed in this PLMN),
    - `#15` (no suitable cells in location area).
   The cause code narrows down the layer (#11/#13 → roaming
   agreement; #14 → plan-level; #15 → SIB / tracking-area
   mismatch). DIAG is functional — see
   `modem_decompiled_src/pass7_diag*.c` and `tools/diag-*` for the
   existing toolchain.
3. **Cross-check with a different SIM** in the same device:
    - A local Swiss prepaid (Sunrise/Swisscom/Salt) should attach
      immediately — proves the modem/kernel path is fine.
    - Another roaming SIM (different MVNO / different home network)
      would isolate the issue to the Eskimo profile specifically.
4. **Test at a different location** with Eskimo as a secondary
   data point. If Eskimo works in Paris/Berlin/etc, the issue is
   Switzerland-specific (agreement not covering CH from this
   Eskimo plan variant). If it fails everywhere, the eSIM itself
   is the problem.
5. **Compare to stock Android** if an EDL dump path is still viable.
   Does stock boot PS-attach here with the same eSIM? Final
   discriminator between hardware/firmware and
   kernel/userspace/agreement.

## Files to read first

- `tools/cell-data.sh` — the current state machine. Start here.
- `docs/modem_data.md` — "Bringup chain (2026-04-13)" section with
  the recovery table and known stuck modem states.
- `TASKS.md` — "Cellular data hardening / optimization" section;
  the **"Live LTE attach still failing"** subtask is this exact
  problem, updated with the iPhone data point.
- `eskimo_roaming.md` + `tools/gen-roaming-partners.py` — if you
  need to extend the partner list for a new country.
- Last session's git log: `git log --oneline bd05c19..0d2c089`.

## Don't re-do

- Don't re-investigate QMI preferences persistence. Confirmed
  non-volatile: `lte|umts,automatic` survives both `dms reset` and
  full device reboots, written to modem NV by the NAS service.
- Don't re-chase the "LTE is last in acquisition order" bug. Fixed
  by `ensure_rat_prefs` putting `lte` first in the mode-pref arg,
  which flips the acquisition order to `lte, umts, gsm, ...`.
- Don't assume `cell-data.sh` has a state-machine bug. Every
  transition was live-tested through online / low-power / offline /
  shutting-down / resetting. The failure is downstream of the
  script — reaching `PS: attached` is what's blocked.
- Don't rebuild the roaming-partner list by hand. It's generated
  from `eskimo_roaming.md` + `tools/data/mcc-mnc-list.json`; edit
  the markdown (or the aliases in the Python script) and re-run
  `just gen-roaming-partners`.
