# Copy Inventory — design-handoff-00

The verbatim contract for every user-facing string (Req 14.2). Implementation matches the **Final** column exactly. Sources: handoff scaffold strings, existing app strings. Rules: Req 14.1 (minimal wording). Legal/safety copy exemptions marked ⚖.

## Capture chrome (§2)

| Context | Handoff / current | Final |
|---|---|---|
| Mode capsule, single | `1-VIEW · LiDAR` | `1-VIEW · LiDAR` |
| Mode capsule, two-view nadir | `2-VIEW · NADIR` | `2-VIEW · NADIR` |
| Mode capsule, two-view oblique | — | `2-VIEW · OBLIQUE` |
| Telemetry labels | `tilt` / `dist` / `LiDAR` | `tilt` / `dist` / `LiDAR` |
| Telemetry, no depth | — | `dist 30–40 cm` (static band) |
| Bottom mode control | `1-VIEW` / `2-VIEW` | `1-VIEW` / `2-VIEW` (distinct from the top capsule) |
| Guide capsule (distance hint) | `Move closer · ID-1 card optional` | `Move closer` |
| Plate alignment guide | `ALIGN PLATE\nWITHIN OUTLINE` | `ALIGN PLATE` |
| Accessibility: Graph button (on Graph root + capture entry) | — | `Graph` |
| Accessibility: Data button | — | `Data` |
| Accessibility: Settings button | — | `Settings` |

## Capture errors (§4) — chip ≤ 3 words, hint one clause

| Failure | Handoff headline + detail | Final chip | Final hint |
|---|---|---|---|
| Tilt (oblique cap) | `Tilt 14°` / `Top-down view needs to be within ±5° of vertical.` | `too tilted` | `Target 25°` |
| Distance | `Move closer` / `Hold the phone 30–40 cm from the food.` | `too far` | `30–40 cm` |
| Tracking lost | `Tracking lost` / `We lost our place between views. Retake the second photo.` | `tracking lost` | `Retake second photo` |
| No LiDAR, no card | `Add a card` / `Without LiDAR depth we need a reference card…` | `card needed` | `Any bank card sets scale` |
| Low light *(dormant — no low-light failure case exists yet)* | `More light` / `It's too dark to read the plate edge reliably.` | `more light` | `Too dark for plate edge` |
| Unsupported device | `Unsupported` / `Medata requires an iPhone with a rear LiDAR scanner.` | `no LiDAR` | `2-view still works` |
| Actions | `Skip to 2-view` / `Cancel` | `Retry` / `2-view` / `Cancel` | — |

## Fork sheet (§3)

| Context | Handoff | Final |
|---|---|---|
| LiDAR banner | `LiDAR available` + `Single photo is enough — distance and shape come from depth.` | `LiDAR available` |
| Path 1 title | `Quick (1 photo)` | `Quick (1 photo)` |
| Path 1 sub | `~1 s · uses LiDAR depth` | `~1 s · LiDAR` |
| Path 1 badge | `Recommended` | `Recommended` |
| Path 2 title | `Two-view (canonical)` | `Two-view` |
| Path 2 sub | `~1.8 s · top-down + 25° angle. Use when LiDAR can't see the whole plate.` | `~2 s · top-down + 25°` |
| Card section | `Add a reference card?` + `Any ID-1 card (driving licence, bank card)… improves scale confidence.` | `Reference card` + `Improves scale confidence` |
| Card toggle | `Include card this time` | `Include card` |
| Actions | `Take 1 photo` / `Take 2 photos` | `1 photo` / `2 photos` |

## Segmentation review (§5)

| Context | Handoff | Final |
|---|---|---|
| Title | `Review foods` | `Foods` |
| Instruction line | `Tap a region to confirm or relabel` | *(dropped — no relabel interaction in this spec)* |
| Class count header | `Detected (N)` | `Detected (N)` |
| Unknown banner | `Unrecognised region.` + `A small area didn't match any known food and will be flagged as 'unknown carbs'.` | `Unknown region · counted as unknown carbs` |
| Liquid banner | — | `Liquid · not estimated` |
| Primary action | `Estimate carbs` | `Carbs` (estimation already done — Decision 7) |

## Result (§6)

| Context | Handoff / current | Final |
|---|---|---|
| Hero suffix | `g carbs` | `g carbs` |
| Summary: count | `N foods recognised` | `N foods` |
| Summary: mass | `Total mass` | `N g total` |
| Breakdown header | `Per-class breakdown` | `Per food` |
| Macro placeholders | `Protein — soon` / `Fat — soon` | `Protein — soon` / `Fat — soon` |
| Actions (fresh capture) | `Adjust manually` / `Save to history` | `Adjust` / `Done` (Decision 17) |
| ⋯ menu (fresh) | `Retake` / `Delete` | `Retake` / `Delete` |
| Actions (from overview) | — | `Adjust` / `Done`; ⋯ menu `Delete` |
| Summary: DB edition | `CoFID 2024` | `CoFID + AFCD` |
| Very-low surface (existing) ⚖ | `This may be wrong by orders of magnitude` | unchanged (safety copy) |
| Placeholder chip (existing) | current copy | unchanged (research Req 23.3 contract) |

## Correction (§7)

| Context | Handoff | Final |
|---|---|---|
| Title | `Adjust` | `Adjust` |
| Stepper label | `TOTAL CARBS` | `TOTAL CARBS` |
| Prior value | `was N g · auto-estimated` | `was N g` |
| Note field | `Note (optional)` | `Note` |
| Preservation notice | *(removed — Decision 21 / §14.5)* | — |
| Per-food edit row | — | `{class name}` + value in `g` (stepper) |
| Action | `Save` | `Save` |

## Full-screen surfaces (Decision 19)

| Context | Final |
|---|---|
| Close control on Capture / Data / Settings (presented from Graph root) | xmark icon; accessibility label `Close` |

## Data (§8) + Meal overview (§9)

| Context | Handoff | Final |
|---|---|---|
| Sheet title | `Data` | `Data` |
| Day headers | `Today` / `Yesterday` / date | `Today` / `Yesterday` / date |
| Empty state | — | `No meals yet` |
| Overview title | `Meal` | `Meal` |
| Corrected marker | `User-corrected — original estimate preserved` | `corrected` |
| Class header | `Foods (N)` | `Foods (N)` |
| Actions | `Adjust` / `Full result` / `Delete` | `Adjust` / `Full result` / `Delete` |
| Delete confirm | — | `Delete meal?` + `Delete` / `Cancel` |

## Graph (§10) — renamed from Trends (Decision 21)

| Context | Handoff | Final |
|---|---|---|
| Title | `Trends` | `Graph` |
| Range control | `Day` / `Week` / `Month` | `Day` / `Week` / `Month` |
| Metric chips | `Carbs` / `Blood glucose` / `Protein · Fat` | `Carbs` / `Glucose` / `Protein · Fat` |
| Chip captions (options sheet) | `bars · from meal captures` / `line · from CGM / meter import` | `bars · meals` / `line · glucose import` |
| Band row | `Target range band` + `3.9 – 10.0 mmol/L` | `Target band` + `3.9–10.0 mmol/L` |
| Placeholder caption | `coming later` | `soon` |
| Scale section | `Scale`, `Glucose y-axis`, `Auto`, `Fixed`, `Fixed max` | `Scale`, `Auto`, `Fixed`, `Max` |
| Options title | `Graph options` | `Options` |
| Stat cards | `Total carbs` / `Avg carbs/day` / `Time in range` / `Avg glucose` | `Total carbs` / `Avg carbs/day` / `In range` / `Avg glucose` |
| No-glucose state | — | `no glucose data` |
| Empty TIR | — | `—` |
| Day meal list header | `Meals this day` | `Meals` |
| Footer | *(removed — Decision 21 / §14.5)* | — |

## Settings (§12) + About (§13)

| Context | Handoff / current | Final |
|---|---|---|
| Title | `Settings` | `Settings` |
| Account row | `Account` | `Account` (disabled) |
| DB section | `Food database` · `CoFID 2024` · `IFCDB 2023 overlay` | `Food database` · `CoFID` + `AFCD` (editions from bundled DB metadata) |
| Capture section | `Capture` · `Default path` · `Single-view (LiDAR)` / `Two-view` · `Always include reference card` | `Capture` · `Default path` · `1-view` / `2-view` · `Always include card` |
| Export | `Export all data` | `Export` |
| Debug seed (DEBUG only) | — | `Seed demo glucose` |
| About title | `About Medata` | `About` |
| Sections | `Data sources` / `Method` / `Legal` | `Data sources` / `Method` / `Legal` |
| CoFID attribution ⚖ | Crown Copyright / OGL v3 text | unchanged in substance (licence-required wording) |
| AFCD attribution ⚖ | — (handoff had IFCDB) | AFCD attribution per its licence |
| Not-medical ⚖ | `Not a medical device` | `Not a medical device` |
| Privacy line ⚖ | `…runs entirely on your device — no photo or measurement leaves the phone.` | `All processing is on-device. Nothing leaves the phone.` |

## Estimating state (§1.3)

| Context | Final |
|---|---|
| Accessibility label on loader | `Estimating` |

## Capture transient surfaces (§2.1 clause) and permission state

| Context | Current | Final |
|---|---|---|
| Initialising hint | `Initialising…` | `Initialising` |
| Tracking-lost hint | `Tracking lost — hold steady` | `hold steady` |
| Capturing hint | `Capturing…` | `Capturing` |
| Oblique guidance (above shutter) | dynamic tilt message | `Target 25°` (same string as the §4 tilt hint) |
| Nadir thumbnail label | `Nadir` | `Nadir` |
| Blocked-shutter chip (transient) | — (badge reveal) | failing gate's §4 chip (`too far` / `hold steady` / `wait`) |
| Permission denied line (camera) | current refusal copy | `Camera access denied` |
| Permission denied line (motion) | current refusal copy | `Motion access denied` |
| Permission denied action | `Open Settings` | `Open Settings` (system term, unchanged) |

## Existing contract strings (listed per Req 14.2; unchanged)

| Context | Status |
|---|---|
| `ConfidencePill` tier labels (`High` / `Moderate` / `Low` / `Very Low`) | unchanged (Decision 5, iphone-experience Decision 17) |
| Calibration banner copy (full / softened) ⚖ | unchanged — safety copy, research-spec contract |
| Liquid over-estimate flag ⚖ | unchanged — safety copy |
| Very-low retake surface ⚖ | unchanged — safety copy |
| Placeholder (dev-stub) chip | unchanged — research Req 23.3 contract |

## Additional states

| Context | Final |
|---|---|
| Fork sheet, no LiDAR | `LiDAR unavailable` (quick path disabled) |
| Meal overview metadata line | `{1-view · LiDAR / 2-view} · {time}` |
| Trends day meal list, empty | `no meals` |
| About method paragraph ⚖ | one-paragraph method summary (§13.1 exemption; drafted in `about.md` page) |

Strings not listed here (log lines, accessibility identifiers like `medata.loadingSymbol`) are not user-facing copy and are unconstrained by §14.
