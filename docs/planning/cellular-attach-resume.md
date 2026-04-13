# Cellular attach — resume prompt

Scratch doc to restart the cellular-data bringup investigation without
re-reading the whole session history. Pick up from commits `bd05c19`,
`efef99c`, `0d2c089` on `main`.

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
