# About — page-specific overrides

**Inherits:** `design-system/MASTER.md`. The §13 About / legal screen. Reached
via a `NavigationLink` from Settings.

**Brief:** Where the numbers come from and what the app is not, so a user can
trust its limits. Legal and safety copy here is exempt from the minimal-wording
rule (Req 13.1).

---

## Layout

```
┌─────────────────────────────────────┐
│  About                              │
│  DATA SOURCES                       │
│  CoFID — Crown Copyright, OGL v3    │
│  AFCD — FSANZ, CC BY 4.0            │
│  Nutrition5k — Google, CC BY 4.0    │
│                                      │
│  METHOD                             │
│  Medata estimates carbohydrate …    │  One-paragraph method summary
│                                      │
│  LEGAL                              │
│  Not a medical device               │
│  … informational only …             │
│  All processing is on-device.       │
│  Nothing leaves the phone.          │
└─────────────────────────────────────┘
```

---

## Specifics

- **Container:** system `List`, title `About`, inline.
- **Data sources (§13.1, ⚖):** the food-source attributions moved out of Settings.
  - `CoFID — McCance & Widdowson, Food Standards Agency. Crown Copyright, Open
    Government Licence v3.`
  - `AFCD — Australian Food Composition Database, Food Standards Australia New
    Zealand, CC BY 4.0.`
  - `Nutrition5k — Google Research, CC BY 4.0. Values adapted: portion-volume
    calibration factors are derived from the dataset.` (the CC BY "indicate
    changes" obligation from nutrition5k-calibration Req 1.5).
- **Method (§13.1, ⚖):** a one-paragraph summary — on-device computer vision
  recovers the meal's three-dimensional shape (LiDAR depth or two-view geometry),
  segments the foods, and multiplies portion volume by density and composition
  values from the bundled CoFID and AFCD databases; nothing is sent to a server.
- **Legal (§13.1, ⚖):** a `Not a medical device` heading with a one-line
  clarification (informational, not for dosing), and the on-device privacy line
  `All processing is on-device. Nothing leaves the phone.`

---

## Anti-patterns

- Do NOT minimise the licence attributions — they are licence-required, exempt
  from §14.1.
- Do NOT drop the Nutrition5k "values adapted" line — CC BY requires indicating
  changes.
- Do NOT soften `Not a medical device`.
