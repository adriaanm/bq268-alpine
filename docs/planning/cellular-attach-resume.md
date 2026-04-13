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
