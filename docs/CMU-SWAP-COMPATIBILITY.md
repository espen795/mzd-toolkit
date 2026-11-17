# CMU swap compatibility - Mazda Connect Gen-1 (CMU-150)

Guide for replacing the Connectivity Master Unit in a Gen-1 Mazda (Mazda 3
BM/BN, Mazda 6 GJ/GL, CX-5 KE/KF, CX-3, Mazda 2, MX-5 ND - roughly 2014-2021).
Compiled 2026-11-15/16 from community sources (miatafy, cx5-forum.de,
r/mazda3) and one verified unit label; items are marked **[verified on a real
unit]** or **[community-reported]** where the claim was not independently
confirmed.

## 1. Three axes that decide compatibility

### Axis 1 - HARD gate: generation and region

- **Generation:** only **Gen-1 (CMU-150)** donors fit. **Gen-2** (2019+
  Mazda 3 BP, CX-30, late CX-5 KF) is a different manufacturer, uses CAN-FD,
  a different display and is VIN-locked - it does not fit physically or
  electrically. Dead end.
- **Region:** buy an **EU** unit (for an EU car). Do not buy NA/JP. The region
  lives in the firmware/UI; flashing a non-EU unit to EU fights the SKU lock
  in NOR flash and is risky. Buying EU removes the problem entirely.
  (The hardware label itself carries EU + FCC + IC + COFETEL + CMIIT marks
  at once - the hardware appears region-independent. **[inferred from label,
  not externally confirmed]**)
- **Model does NOT matter:** Mazda 3/6/CX-5/CX-3/MX-5/Mazda 2 of the Gen-1
  era share the same CMU and the same 0920-201B connector. A CX-5 or Mazda 6
  unit fits a Mazda 3 just as well. **[community-reported]**

### Axis 2 - SOFT gate: vehicle configuration (Bose / nav / HUD / 360 cam)

- The CMU carries an **as-built configuration** from the donor car. A mismatch
  leads to **no audio (Bose vs non-Bose)**, missing HUD menus, nav/camera
  DTCs.
- **DAB note (important correction to older guides):** the tuner sits in the
  **TAU** (separate tuner/amplifier behind the dash), **not in the CMU**. DAB
  reception therefore comes from your own car; a CMU swap does not break DAB
  as long as the CMU runs **EU firmware** (otherwise only the DAB menu is
  missing from the UI).
- Fixing a mismatch:
  1. **Best: buy a matching config** -> factory reset after installation
     (`Settings -> System -> Restore All Factory Settings`) -> the CMU syncs
     with your CAN bus. Usually done.
  2. **FORScan (DIY):** can write the Mazda CMU as-built (Extended License +
     MS/HS-CAN adapter, e.g. vLinker FS / OBDLink EX). Load your factory
     `.abt` (from a backup, or via VIN from Mazda's as-built portal) ->
     Write All -> CMU reboot (`MUTE+NAV+BACK` 10 s) -> clear DTCs. Not trivial
     but doable. **[community-reported]**
  3. **MDARS (dealer):** fetches the factory profile via VIN and writes it.
     Paid route.

### Axis 3 - SOFT gate: hardware revision (reliability)

- Part number pattern: `[PREFIX]-66-9C0[SUFFIX]`, e.g. `BHP1-66-9C0K`.
  - **PREFIX** (BHP1, BJS7, BANF, KA0G, GMD7, BPN2, ...): encodes
    model/trim/**region/sound-system**. Matching the prefix automatically
    matches Bose/non-Bose.
  - **SUFFIX** (A...N): hardware revision.
- **Suffix A-F:** older eMMC and weaker EMI/thermal shielding -> prone to the
  known eMMC-degradation bootloop. Avoid.
- **Suffix J and higher:** newer board layout, better eMMC endurance. Prefer.
- **Supersession is backward-compatible within the same prefix:**
  `BHP1-66-9C0K` safely replaces any older `BHP1-66-9C0A...H`.
  **[community-reported]**

## 2. Best choice, in order

1. **Your own prefix, higher suffix.** Read the part number sticker on your
   (broken) CMU - the metal box's rear label - and buy the same prefix with
   suffix **J/K/L/M**. Identical region/trim/Bose config -> truly
   plug-and-play, just newer silicon. No as-built work.
2. **Same options tier, different Gen-1 model, EU, suffix J+.** E.g.
   non-Bose stays non-Bose. Factory reset after installation; sometimes
   FORScan as-built is needed.
3. **A late Gen-1 unit (2020+)** for the newest hardware - more expensive and
   the config can be fiddly. Wired CarPlay/Android Auto via firmware v70+ plus
   the `TK78-66-9U0C` USB hub is the proven retrofit route.
4. **Do NOT buy:** suffix A-F - NA/JP region - Gen-2 (2019+) - a Bose unit
   for a non-Bose car (or vice versa) without as-built correction.

### Example (verified unit)

A Mazda 3 BM (2015) EU with working stock firmware carries CMU part number
**`BPN2 66 9C0C`** (suffix C = older revision) and display **`BHP1 61 1J0D`**
**[verified on a real unit label]**. Note the prefix here is `BPN2`, not
`BHP1` - always match the prefix of your own unit. For a swap on this car:
look for **`BPN2-66-9C0` with suffix J or higher** (e.g. `BPN2-66-9C0K`).
The supersession chain in Mazda's parts catalog reportedly continues as
`BADE-66-9C0K` (replacing `BADE-66-9C0` A...J) **[community-reported, catalog
page not directly readable - have it confirmed against your VIN at the dealer/
parts counter before buying]**.

Purchase order for the example car: `BADE-66-9C0K` -> `BPN2-66-9C0K` ->
`BPN2-66-9C0J`. Not: suffix A-F.

## 3. Prefix cheat sheet (Gen-1, approximate)

| Model | Common CMU prefixes |
|---|---|
| Mazda 3 BM/BN | `BHP1`, `BJS7`, `BANF`, `B45C`, `BHN1`, `BPN2` |
| CX-5 KE/KF | `KA0G`, `KB9S`, `TK78` |
| Mazda 6 GJ/GL | `GHP9`, `GMD7`, `GMR3`, `GJR9` |
| CX-3 DK / Mazda 2 DJ | `DB49`, `DD2F`, `DA7H` |
| MX-5 ND | `N243`, `N3H1`, `NA1P` |

The prefix also encodes Bose/non-Bose, so matching on prefix covers that
automatically. The list is community-collected and not exhaustive.

## 4. Practical notes

- The **display is a separate part** (`BHP1 61 1J0D` style numbers) and stays
  in your car during a CMU swap.
- A swapped CMU has a **new Bluetooth/WiFi MAC** (unit-unique, printed on the
  label) - re-pair your phones. The WiFi MAC is the Bluetooth MAC + 1 in the
  last byte.
- Do not copy the **serial number, VIN or MAC addresses** from a label into
  documentation or listings - they are unit-unique identifiers.
- Within Gen-1 there is no substantially newer platform; the real upgrade is
  CarPlay/Android Auto (firmware v70+ and the `TK78-66-9U0C` USB hub + cable
  set). Claims about a "TC3N" unit with wireless CarPlay in Gen-1 are
  **unconfirmed** - do not rely on them.
