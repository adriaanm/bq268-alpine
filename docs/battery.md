# The BQ268 battery: what the device expects, and the replacement spec

Reference doc for the someday-project of replacing the battery pack
(owner ruling 2026-08-16: significant, deferred). The stock pack
predates the bootloader/kernel-upgrade era and has suffered; its pogo
contacts are part of a measured ~350 mΩ source impedance that turns
radio-PA bursts into rail sag (see the brownout entries in the
top-level `~/g/bq268/CLAUDE.md` learnings log, 2026-08-16). The owner's
plan: source a new pack and replace the pogo-pin path with a soldered
cable.

## What the device provides (read from the hardware, 2026-08-16)

- Charger: **PM8909 `qpnp_lbc` — a LINEAR charger.** Float voltage
  4.20 V (`/sys/class/power_supply/battery/voltage_max_design` =
  4200000). Input is USB, default **500 mA** ("Registered internal USB
  PSY, default 500mA"). So the pack is charged gently: ≤0.5 A CC into a
  4.20 V CV — no fast-charge negotiation of any kind exists.
- **Battery-presence detection is via the pack thermistor** (probe line
  `bpd=1`; `temp` reads real values, e.g. 231 = 23.1 °C). The pack
  exposes a third contact carrying an NTC. A battery whose therm line
  is absent or out of range reads as "no battery": charging is refused.
- Fuel gauge: **VM-BMS** (`qpnp_vm_bms`), voltage-based SoC from an OCV
  table tuned for the stock pack — and that table is itself flagged
  "estimated" (TASKS.md "Battery OCV table"). Expect SoC % drift on any
  new pack until recalibrated; `voltage_now` stays honest.
- `voltage_min_design` reads 4.308 V on this driver — nonsense; ignore
  the field.
- PMIC brownout behavior: power-off UVLO around ~3.0–3.2 V rail;
  `smpl_en` auto-restarts the device after a momentary loss.
  `dload_on_uvlo` MUST stay 0 (set, a brownout strands the device in
  EDL instead of rebooting).

## Load profile the pack must serve

- Cellular PA: the dominant transient. Modem prefers `umts, lte`
  (continuous-ish ~0.6–0.8 A TX); a 2G fallback would mean ~2 A pulsed
  bursts. Spec the pack for the 2G case.
- Speaker at full volume (`PlayVol` fixed): ~100 mV of sag observed on
  the current 350 mΩ path — a few hundred mA.
- CPU (quad A7 @ 1.09 GHz, all cores): ~200 mV on the current path.
- Worst measured stack (CPU max + UMTS TX flood + chirp): 385 mV sag.
  Budget the whole system for ~3 A bursts with margin.

## Replacement pack: the spec cheat sheet

Must-match (safety):

- **1S Li-ion/LiPo, 4.20 V charge voltage, 3.7 V nominal.** Not
  LiFePO4 (3.6 V float mismatch), not a 4.35 V "high-voltage" cell
  (chargeable but never fills), never 2S.
- **NTC line reproduced.** Measure the STOCK pack's third contact to
  B− at room temperature before ordering (expect ~10 kΩ NTC; could be
  47 k/100 k) and match the curve. A bare two-wire cell needs an NTC
  glued to the cell and wired to the therm contact. A fixed resistor
  satisfies presence detection but blinds thermal protection on a
  device that charges unattended in a kid's room — use a real NTC.
- **Protection PCM on the pack** (the PMIC covers only the charge
  side): over-discharge cutoff ~2.5–2.8 V, over-charge ~4.25–4.3 V,
  and an overcurrent trip comfortably ABOVE 4–5 A so PA bursts never
  trip it mid-call.

Performance:

- **DCIR ≤ 80 mΩ** fresh at 50% SoC (datasheet spec) — the entire
  point of the exercise; today's pack+pogo path measures ~350 mΩ.
- Burst capability ≥ 3 A (any ≥1500 mAh cell at 1–2C clears this).
- **Capacity ~2–3 Ah**: match or exceed stock; the linear charger
  takes ~2.5 h per 1000 mAh, so 3 Ah ≈ overnight. Bigger buys sag
  margin and runtime but silly charge times past ~3 Ah.

The cable (the actual fix):

- Total added resistance budget **< 50 mΩ round trip**: < 10 cm of
  20–22 AWG silicone wire on both conductors, soldered to the pack
  tabs (or the pack's own leads). Every 100 mΩ removed buys back
  ~200 mV of rail at 2 A burst.
- Connector rated ≥ 3 A with low contact resistance — **XT30** class.
  Skip 2 A-class micro connectors (JST-PH). The NTC wire carries no
  current and can be thin.
- Strain relief at both ends; the pack sits in a device that gets
  dropped.

## Experiment: determine the stock NTC's values

Goal: the two numbers a replacement NTC must match — **R25** (resistance
at 25 °C) and the **beta** (curve steepness) — plus proof that the
kernel's ADC table agrees with the pack's curve.

1. **Measure the pack, not the device.** Remove the pack (device off).
   Multimeter in Ω between the third contact and B−. Measuring the
   device-side pogo pads instead reads the PMIC's pull-up network and
   lies.
2. **Three temperature points.** Record (T, R) at:
   - room temperature (note an actual thermometer, not "about 20");
   - cold: ~30 min in the fridge (~5 °C), measure quickly on removal;
   - warm: held in hands / pocket until stable (~33–35 °C).
   An NTC moves a LOT: a 10 kΩ B≈3435 part reads ~25 kΩ at 5 °C and
   ~6.5 kΩ at 35 °C — so sloppy thermometry still separates the
   candidate families.
3. **Fit beta** from any two points, temperatures in Kelvin:
   `B = ln(R1/R2) / (1/T1 − 1/T2)`. Interpolate R25 (or measure at an
   actual 25 °C room). Match against the usual suspects:
   | family | R25 | B25/85 (approx) |
   |---|---|---|
   | 10 kΩ B3435 | 10 kΩ | 3435 |
   | 10 kΩ B3950 | 10 kΩ | 3950 |
   | 47 kΩ | 47 kΩ | ~4050 |
   | 100 kΩ B4250 | 100 kΩ | ~4250 |
4. **Cross-check the kernel's table.** Pack back in, boot, let it
   settle, then compare `cat /sys/class/power_supply/battery/temp`
   (deci-°C: 231 = 23.1 °C) against the thermometer — once at room
   temp, once warm. Agreement within ~2–3 °C means the VADC mapping in
   the DT matches the pack's curve, and the replacement NTC must match
   the SAME R25/beta or the reported temperature (and the charger's
   JEITA thresholds with it) shifts.
5. No multimeter handy: step 4 alone (fridge/warm vs sysfs) verifies
   curve consistency, but R25 needs the meter — without it, order the
   replacement only after finding the pack's model number or reading
   the DT's `qcom,battery-therm` table in bq268-caf-4.4.

## After the swap

- Recalibrate the VM-BMS OCV table against the new pack (the existing
  TASKS.md item) or accept lying percentages.
- Re-run the impedance check from the learnings log: 4-core burn at
  performance governor while sampling `voltage_now` — expect the
  ~200 mV CPU-burn sag to drop well under 100 mV if the cable did its
  job. The full stress recipe (CPU + `ping -I ppp0` TX flood + chirp)
  is in the 2026-08-16 learnings entry.
