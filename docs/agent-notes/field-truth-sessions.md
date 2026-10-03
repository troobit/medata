# Field-truth capture sessions (weighed ground truth)

Scale-weighed plates captured on device, with the app's estimates — the
evidence base for β_c calibration and class-coverage decisions. Pull the
outcome rows and bundles per the devicectl recipe in
`device-build-and-test.md`.

## Recording a weighed figure (since 2026-10-03)

Enter it on the phone, not in a field note. On the review screen of a field
build (`FIELD_LOOP`: Debug or Release), "…" → **Weighed mass** opens one gram
field per food still on the plate; Save once every food has one. The mass line
then reads "≈ N g on plate · M g weighed". Name or reject unnamed and
"not in the database" rows first — truth carbohydrate is grams × the item
class's own coefficient, and those rows have none. Re-entering replaces the
earlier figure.

The data path, end to end:

1. `PersistenceStore.attachWeighedTruth` writes a `fidelity=weighed` row to the
   device's `benchmark_meals` (items = `[{class_id, grams}]` under each row's
   current class, truth derived at save from the bundled coefficient at the
   record's edition) and sets `estimation_outcomes.benchmark_meal_id` on the
   capture's attempt — one transaction, in `Documents/meals.sqlite`. Log line:
   `event=weighed.attach outcomeId=… benchmarkMealId=… items=class:grams`.
2. `make field-pull` (or `make field-notes` when the bundle is already ashore)
   copies `meals.sqlite`; `ingest._ingest_device_rows` copies the benchmark row
   into `index.sqlite` and the outcome with its link (`upsert_outcome`: the
   device wins when it has a link).
3. `make field-derive CALIBRATION_OUT=<dir>` joins outcome → benchmark →
   capture by timestamp and hardlinks the fixture into `<dir>`;
   `field_close`'s weighed veto reads the same rows.

After a sitting: `make field-pull`, then `make field-derive
CALIBRATION_OUT=<dir>` and read `ingested=`. A capture whose bundle is still on
the phone reports as skipped until a full pull lands it.

Gotchas:

- The entry needs the attempt's outcome id, which the review resolves after a
  possible 500 ms retry; the menu item stays disabled until then, and for good
  on a history meal whose outcome row has been evicted.
- A re-entry deletes the superseded meal on the device only when that meal was
  written after the attempt; a meal authored on Settings › Benchmark before the
  capture is kept. Ingest never deletes, so a superseded meal that was already
  pulled stays in the index joined to nothing — inert.
- Re-tagging moves the attempt out of the 500-row non-benchmark eviction
  population into a one-row benchmark group, so it needs no protection row.
- The derived directory is not yet a one-command `calibrate` input. It mixes
  segmenter checkpoints, and the loader refuses any bundle whose checkpoint is
  not `--checkpoint-sha256`, so split it per checkpoint first. The weighed
  figure is not in the bundles either (it lives in `benchmark_meals`), so
  `accuracy` scores nothing and `calibrate` fits nothing until the truth is
  written into the fixture. The 2026-10-03 entry has the scratch recipe. Run
  `calibrate` with `--ingest-summary <dir>/run_summary.json`; it needs no
  `--depth-test-split` since 2026-10-03.

## 2026-10-03 — an 80 g roll three times on the R16 segmenter, and four truths back-filled (builds `a179e0b-20261003-110500`, `0ff10cc-20261003-110738`, segmenter `coreml_88d34e27e8bf`)

Pull `20261003-1`. The roll weighed 80 g on the plate and was captured three
times: single-view on `a179e0b`, then single-view and two-view on `0ff10cc`.
Field notes: "Exact 80g on plate 1 view got pretty close", "VERY good estimate
1 view", "STILL very good for 2 view, 80g truth on plate". Both builds carry
the two-view plane refit (two-view-trust Decision 10) and predate both the
Weighed mass sheet and the 200 cm² seed-area gate (`7f52815`), so they have the
same estimation code. The same pull brought the 2026-09-30 note "True weight -
83 grams (from scale)" on capture `1790748465041` (build `2d39910`, segmenter
`coreml_ab812dc3aa9d`). The screenshot shows two slices of topped toast, not a
roll.

**Truth, back-filled by hand into `index.sqlite`** the way the 104 g row was
(`fidelity=weighed`, bread_wholemeal at 38.0 g/100 g):

| Benchmark row | Outcome | Capture | Grams | Truth carbs |
|---|---|---|---|---|
| `backfill-1790748516454-toast` | `BF8BECC2` | `1790748465041` | 83 | 31.54 |
| `backfill-1790989704658-roll` | `34E24CCE` | `1790989654696` | 80 | 30.40 |
| `backfill-1790989773659-roll` | `FA1C12F5` | `1790989735795` | 80 | 30.40 |
| `backfill-1790989820366-roll` | `BB6B5835` | `1790989787903` | 80 | 30.40 |

Each id is named after its note's stamp. The `1790989773659` note gives no
weight; the roll's other two notes do. The class comes from the developer's
corrections. The toast relabelled `unknown_food` to bread_wholemeal. The roll
was relabelled bread_white → bread_wholemeal once (`FA1C12F5`); the other two
captures kept bread_white and were not relabelled. If the roll is white bread,
truth is 38.4 g of carbohydrate and the bread_white readings below fall within
−4 % to +12 %.

<details><summary>SQL as run (backup first: <code>cp index.sqlite …bak</code>)</summary>

```sql
BEGIN;
INSERT INTO benchmark_meals (id, pull_id, name, created_at, items, truth_carbs_g, db_edition, fidelity) VALUES
('backfill-1790748516454-roll', '20261003-1', 'bread roll, 83 g weighed (back-filled from field note)', 1790748516454,
 '[{"class_id": "bread_wholemeal", "grams": 83.0, "carbs_per_100g": 38.0, "carbs_g": 31.54, "mass_source": "kitchen_scale", "provenance": "weighed and stated in field note 1790748516454 (''True weight - 83 grams (from scale)''); class is the developer''s correction on outcome BF8BECC2 (unknown_food relabelled bread_wholemeal beside a bread_wholemeal region); carbs from the bundled CoFID coefficient, not assayed"}]',
 31.54, 'CoFID 2024 + AFCD 2024', 'weighed'),
('backfill-1790989704658-roll', '20261003-1', 'bread roll, 80 g weighed (back-filled from field note)', 1790989704658,
 '[{"class_id": "bread_wholemeal", "grams": 80.0, "carbs_per_100g": 38.0, "carbs_g": 30.4, "mass_source": "kitchen_scale", "provenance": "weighed and stated in field note 1790989704658 (''Exact 80g on plate''); class from the developer''s correction of the same roll on outcome FA1C12F5 (bread_white relabelled bread_wholemeal) - this outcome kept bread_white uncorrected and rejected a white_rice region; carbs from the bundled CoFID coefficient, not assayed"}]',
 30.4, 'CoFID 2024 + AFCD 2024', 'weighed'),
('backfill-1790989773659-roll', '20261003-1', 'bread roll, 80 g weighed (back-filled from field note)', 1790989773659,
 '[{"class_id": "bread_wholemeal", "grams": 80.0, "carbs_per_100g": 38.0, "carbs_g": 30.4, "mass_source": "kitchen_scale", "provenance": "the roll weighed 80 g in the same sitting (field notes 1790989704658 and 1790989820366); this note (1790989773659) is on this capture but states no weight; class is the developer''s correction on this outcome (bread_white relabelled bread_wholemeal); carbs from the bundled CoFID coefficient, not assayed"}]',
 30.4, 'CoFID 2024 + AFCD 2024', 'weighed'),
('backfill-1790989820366-roll', '20261003-1', 'bread roll, 80 g weighed (back-filled from field note)', 1790989820366,
 '[{"class_id": "bread_wholemeal", "grams": 80.0, "carbs_per_100g": 38.0, "carbs_g": 30.4, "mass_source": "kitchen_scale", "provenance": "weighed and stated in field note 1790989820366 (''80g truth on plate''); class from the developer''s correction of the same roll on outcome FA1C12F5 (bread_white relabelled bread_wholemeal) - this outcome kept bread_white uncorrected; carbs from the bundled CoFID coefficient, not assayed"}]',
 30.4, 'CoFID 2024 + AFCD 2024', 'weighed');
UPDATE outcomes SET benchmark_meal_id = 'backfill-1790748516454-roll' WHERE id = 'BF8BECC2-BA92-4006-A60D-98827CFB4460';
UPDATE outcomes SET benchmark_meal_id = 'backfill-1790989704658-roll' WHERE id = '34E24CCE-1327-4186-A124-CACEDF4EA8D1';
UPDATE outcomes SET benchmark_meal_id = 'backfill-1790989773659-roll' WHERE id = 'FA1C12F5-B7B5-4C00-9B95-A533267919E3';
UPDATE outcomes SET benchmark_meal_id = 'backfill-1790989820366-roll' WHERE id = 'BB6B5835-1FCE-41F1-97CA-FE3EF3DA6D3C';
COMMIT;
-- after the screenshot showed toast, not a roll:
UPDATE benchmark_meals SET name = 'two slices of topped toast, 83 g weighed (back-filled from field note)' WHERE id = 'backfill-1790748516454-roll';
BEGIN;
UPDATE benchmark_meals SET id = 'backfill-1790748516454-toast' WHERE id = 'backfill-1790748516454-roll';
UPDATE outcomes SET benchmark_meal_id = 'backfill-1790748516454-toast' WHERE id = 'BF8BECC2-BA92-4006-A60D-98827CFB4460';
COMMIT;
```

The items carry `grams`, the key the device's `BenchmarkMealItem` decodes. The
104 g row from 2026-09-29 carries `mass_g` instead.
</details>

**Replay.** `make field-derive CALIBRATION_OUT=<dir>` printed `ingested=4
skipped=1`. The skipped capture is the 104 g roll, whose bundle survives only
under `reports/calibration-20260929-roll/`. The figures below are the harness
at `bac388c`: the installed builds plus the seed-area gate, which gates
single-view growth only. Each bundle replays its own recorded segmenter output.
The replay matches every device row to 0.1 cm³ except capture `…654696`, the
one the gate changes: its seed is 259.8 cm² because the segmenter took table
speckle for food (the note says so).

| Capture | Path | Replayed class(es), cm³ | Mass at true class | Carbs as labelled | Truth | Mass error | Carbs error as labelled |
|---|---|---|---|---|---|---|---|
| `1790655022746` 104 g roll (09-29) | single-view, card+lidar | unknown_food 226.3 (+ coffee 59.5, rejected) | 90.5 g | 0.2 g | 104 g / 39.52 g | −13.0 % | −99.5 % |
| `1790748465041` toast (09-30) | single-view, lidar | bread_wholemeal 300.9 + unknown_food 125.0 (relabelled) | 170.4 g | 45.7 g | 83 g / 31.54 g | +105.3 % | +45.0 % |
| `1790989654696` roll, `a179e0b` | single-view, lidar | bread_white 201.6 (+ white_rice 16.3, rejected); device 223.4 + 47.7 | 80.6 g (device 89.4) | 40.6 g (device 51.9) | 80 g / 30.4 g | +0.8 % (device +11.7 %) | +33.5 % (device +70.7 %) |
| `1790989735795` roll, `0ff10cc` | single-view, lidar | bread_white 236.8 (relabelled wholemeal) | 94.7 g | 43.2 g | 80 g / 30.4 g | +18.4 % | +42.1 % |
| `1790989787903` roll, `0ff10cc` | two-view carve, card+lidar | bread_white 224.2 | 89.7 g | 40.9 g | 80 g / 30.4 g | +12.1 % | +34.5 % |

"Mass at true class" is the volume of the food regions the review kept, at
bread_wholemeal's 0.4 g/cm³. Its error is also the carbohydrate error once the
review names the food correctly. "Carbs as labelled" is the harness `accuracy`
figure: the segmenter's own class at β = 1, with an `unknown_food` region
priced at 0.

| Over the weighed set (n = 5) | MAPE | MAE (carbs) |
|---|---|---|
| `accuracy`, as labelled (HEAD) | 50.9 % | 17.4 g |
| Same, installed builds (`--growth-gate-cm2 0`) | 58.4 % | 19.7 g |
| True class (HEAD) | 29.9 % | 9.6 g |
| True class, the four roll captures | 11.1 % | 3.7 g |

- **Volume is inside the MAPE < 20 % bar on the rolls; labelling is not.**
  All four roll captures are within ±18.4 % of the scale at the true class,
  and the two-view carve reads +12.1 %, its first weighed figure. End to end,
  bread_white (48 g/100 g against 38) adds about +26 % on a wholemeal roll,
  and `unknown_food` prices the 104 g roll at zero.
- **The gate helps the one plate it touches.** On `…654696` it holds bread_white
  at 201.6 cm³ against the device's 223.4, and the white_rice phantom at
  16.3 cm³ against 47.7. The seed is large because the table speckle is in it,
  so the gate is firing for the wrong reason.
- **The toast over-read is not growth.** Corrected the same day; see
  "Growth guard replay" below. The seed is 43,039 px (27.8 cm², well under the
  gate), and growth takes it to 317,062 px (205.2 cm²) on an `edgeBand`
  plane. Ungrown it reads 61.4 cm³ (−70 %); grown, 426.0 cm³ (+105 %). The
  grown region is the two slices, not the plate. The excess is the plate
  under them and the density.
- **`calibrate` runs and bakes nothing.** With no truth in the bundles, the
  field plates take the legacy single-dominant path with zero truth. With
  truth written in (scratch copies), every plate is purity-dropped: the truth
  class is bread_wholemeal and the volume is bread_white or `unknown_food`
  (the toast's 300.9 of 426.0 cm³ is 0.71 against τ 0.90). A field β needs the
  review's relabel applied to the volume before the purity gate.

Scratch recipe for scoring field bundles, used above: hardlink the bundles
into one directory per checkpoint. Copy each one and append protobuf fields 17
(`ground_truth_class_mass_g`, `{class: grams}`) and 18
(`ground_truth_total_carbs_g`); a protobuf message followed by more fields
parses as their merge. Then run `accuracy`, `volumes` and `calibrate
--ingest-summary <derived>/run_summary.json` on the copies. Never append to
the corpus files: the derived directory holds hardlinks to them.

Tooling fixed the same day (`derive_dataset.py`, `CalibrateRun.loadIngestSummary`,
HarnessCLI `calibrate`). The field `run_summary.json` now loads: `skipped`
is `{reason: [stems]}`, `render_config` carries `intrinsics_model`
(`arkit_per_capture`), `estimator_paths` says `single_dominant`, and the
reader no longer requires `plane_depth_mm`, which a real capture does not have.
`calibrate` identifies Nutrition5k by the `source_dataset` stamp, so device
bundles no longer need `--depth-test-split`. A `medata_field` summary now
records its own lineage and licence, where the run used to fall back to
N5k's CC BY 4.0.

### Growth guard replay (harness at `2a6f2b8`, depth-grown-food-region Decision 6)

The toast's +105 % looked like runaway growth, so a second guard was swept: a
grown/seed ratio cap and a grown-footprint cap, each as a fall-back to the
ungrown map or as a clamp on the fill. Mass at the true class (the kept
regions at 0.4 g/cm³) against the scale:

| Capture | Ratio / grown footprint | Growth off | Current | Fall back, ratio > 4–6× | Clamp 3× | Clamp 100 cm² |
|---|---|---|---|---|---|---|
| `1790655022746` 104 g roll | 3.92× / 98.8 cm² | −80.8 % | −13.0 % | −13.0 % | −27.1 % | −13.0 % |
| `1790748465041` 83 g toast | 7.37× / 205.2 cm² | −70.4 % | +105.3 % | −70.4 % | +12.4 % | +32.4 % |
| `1790989654696` roll, `a179e0b` | gated (259.8 cm² seed) | +0.8 % | +0.8 % | +0.8 % | +0.8 % | +0.8 % |
| `1790989735795` roll, `0ff10cc` | 1.06× / 80.1 cm² | +14.2 % | +18.4 % | +18.4 % | +18.4 % | +18.4 % |
| `1790989787903` roll, two-view | plane-only | +12.1 % | +12.1 % | +12.1 % | +12.1 % | +12.1 % |
| MAE / MAPE (5) | | 32.8 g / 35.7 % | 25.2 g / 29.9 % | 19.4 g / 22.9 % | 12.7 g / 14.2 % | 13.1 g / 15.3 % |
| Nutrition5k carb MAE (216) | | 9.334 g | 9.215 g | 9.215 g | 9.222 g | 9.239 g |

Nothing shipped. The full grid is in Decision 6.

- **The toast is measured whole, and correctly.** The bundle's LiDAR depth
  shows two slabs 18–25 mm above the board, where the slices are. The plate
  between them sits 1–4 mm above the board, and the segmenter labelled only
  the crust ends. The cells at least 12 mm up cover 207 cm² and hold 415 cm³;
  growth's region is 205.2 cm² and 426.0 cm³. The excess over the scale has
  two parts. One is the plate under the toast, 20–80 cm³: the plane is the
  board, and the `edgeBand` refit was not adopted. The other is density: 83 g
  over 345–405 cm³ is 0.20–0.24 g/cm³ for thick toasted open-crumb bread,
  against bread_wholemeal's 0.4 measured on a roll.
- **Every guard that helps the toast cuts a correct footprint.** The ratio
  fall-back returns the crust-only 13.6 % of the toast (−70 %). The clamps
  keep a part of it chosen by distance from the crusts. Their MAE gains are a
  density error offset by chance. A ratio cap low enough to catch the toast
  would also have removed the 2026-09-24 roll capture that grew 15.2×
  (25.6 against 230.7 cm³, roll 260 cm³).
- **Next for this plate:** a toasted-bread density, and the plane under food on
  an `edgeBand` fit (`support-plane-reference`). A ring median would not do:
  it reads the rim (11.4 mm), not the 1–4 mm under the toast.

## 2026-09-25 — the roll with an ID-1 card in frame: the card path picked nothing, build `1a6c35c-20260925-132501` (Release)

Two-view capture `1790306988367` (outcome 681F8E4C), gold portrait card flat on the table beside the plate, roll on the plate. Field note: "Unknown food registered here - that is the reference card". Row: `scaleSource=lidar`, no `card` block, bread_white 534.5 cm³ + unknown_food 1103.8 cm³; nadir argmax is unknown_food over the whole roll and over the card's printed panel, oblique is bread_white with unknown patches (two-view label mismatch, Req 2, unchanged).

Readings:

- **Vision found the card but the solver rejected it.** Harness `cards` on the bundle: candidate 2 of 3 is the card (186 × 299 px, portrait). It solved at 86 px residual because `CardPoseSolver` mapped the first listed edge onto the 85.60 mm side; with the corner order rotated it solves at 14 px, 2.2 % off LiDAR. The bread on the same frame solves at 15 px, 57 % off LiDAR. Residual alone does not separate card from food; LiDAR scale does. Fixed the same afternoon (Decision 3 revised): the pick runs after the plane fit and the LiDAR scale arbitrates.
- **Afternoon re-shoot on build `c5235bd-20260925-140627`, same setup.** Two-view `1790310086654` (outcome 78768152): card picked, residual 1.7 px, 0.6 % off LiDAR, 38,463 nadir pixels cleared, `scaleSource=card+lidar`, no card row. The roll came out as two rows, bread_white 314.8 cm³ + bread_wholemeal 401.7 cm³: the nadir says wholemeal, the oblique says white, and the carve keeps both as single-view-only classes (Req 2, open). Single-view `1790310107431` (outcome A807BA80): growth 112,439 → 200,165 px, refit edgeBand, 518.7 cm³ against yesterday's 280 cm³ for the same roll; the owner sees speckles on the plate around the roll in the outline. Growth is leaking onto the plate. Replay with the first plane from the pre-shutter mask reproduces the row exactly; the added cells are a 3–5 mm plate blob to the rim (about 11 cm³, full depth confidence) and the rest of the excess is the refit landing on the table (`edgeBand`) and being adopted as the integration plane with no offset: same mask, first plane kept, 247 cm³. Fixed the same day (depth-grown-food-region Decision 3: a table refit is never adopted, floor 5 mm): replays at 224 cm³ today and 302 cm³ yesterday with the outline on the roll.
- **Third sitting, build `0880ebb-20260925-150855` (growth Decision 3).** Single-view `1790313330330` (outcome 3F186BDA): the roll labelled `unknown_food` this time, 284.4 cm³, growth 185,281 → 231,796 px with a `foodSupport` refit; owner: "looked ok but still extra around the roll (acceptable error bound though as volume looked OK)". Two-view `1790313381100` (outcome 6C9B26B7): card picked (2 candidates, residual 8.3 px, 8 % off LiDAR, 41,631 px cleared); nadir `unknown_food` only, oblique `bread_wholemeal` + unknown patches, so two rows again: unknown_food 1007.8 cm³ + bread_wholemeal 289.2 cm³. Owner: "1 seems correct, but is perhaps 100 % obscured by 2 unknown food. Card if used should ideally be pointed out as reference (shaded or some such)" and "when taking photo, it flips 90 degrees in the UI … confusing for user, so unless 100 % necessary remove this". Reconciliation (Decision 5) shipped the same evening: both bundles replay to one bread_wholemeal row from the carve (no single-view fallback), but at 1055 and 935 cm³, 3–4× the roll: the nadir silhouette is wider than the roll and a 26° oblique bounds height only at its far edge (backlog 29). The flip is fixed for the frozen frames and thumbnail; the review photo still shows the landscape buffer. Card shading is a two-view-trust task.
- **Fourth sitting, build `77887ac-20260925-153545` (reconciliation Decision 5, flip fix).** Two-view at 27° (`1790315734391`): oblique labelled the roll bread_white + bread_wholemeal + unknown, so the Decision 5 class-count gate refused (`applied=false`) and three rows came out, unknown_food 801 cm³ on top; owner: "Accurate, but the UI shows number 3 unknown food, and doesn't show number one or two" (the outline is the nadir's, which only had unknown). Two-view at 40° (`1790315814452`): same split, bread_wholemeal 736 + unknown 193 + white 41; "estimate seems okay". Single-view with card (`1790315865030`): wholemeal 184 + unknown 245, growth 122k → 236k px, "by far the worst yet". Single-view without card (`1790315900185`): wholemeal 289 + unknown 121, growth 89k → 242k px, first plane foodSupport with ring median −0.36 mm and residual 2.6 mm, "the highlighted regions show the plate as food items". Two follow-ups the same evening: Decision 6 (one connected object is one class, both paths; commit 0a27217) and a second growth investigation on the two single-view bundles. Decision 6 replays the single-view roll as one bread_wholemeal row (410 cm³, growth leak included); on the two-view bundles the gate still refuses because the oblique holds a second object, the card, which only the nadir clears — task 8 (project the nadir quad through the verified transform) is the blocker.
- **Evening fixes for the fourth sitting, build `27ce487-20260925-163749`.** Growth: the first plane is 4–5° off the plate (edgeBand threading the plate top beside the food on `1790315900185`, a non-planar table depth field on `1790315865030`), so the plate's far half reads 6–16 mm above "support" and no floor bounds it; added cells now must reach the seed cells' median height minus 10 mm (depth-grown Decision 4): 410 → 299 and 434 → 317 cm³, the other five bundles within 20 cm³ of before. Two-view: the card is cleared in the oblique through the verified transform (task 8, commit 494686e), so with Decision 6 all three card bundles replay to one carved bread row: 920, 930 and 851 cm³, still about 3× the roll (backlog 29). The harness now picks and clears the card and fits the first plane from the pre-shutter mask on both paths.
- **Fifth sitting, build `27ce487-20260925-163749`.** Single-view with card ×2 (`1790318604792`, `1790318616477`): one row each, bread_white 272.0 and bread_wholemeal 266.9 cm³, growth 124k → 144k and 127k → 143k px, foodSupport both, card cleared (5.0k and 22.4k px); owner: "only 1 row". Two-view at 26.7° (`1790318627741`): card picked (3.0 px, 1.9 % off LiDAR, 30,960 nadir px cleared) but `obliqueClearedPixels=0`; reconciliation applied (nadir [4,34], oblique [34] → wholemeal); one row, 926.9 cm³, 3.4× the roll (backlog 29); owner: "2 view wasn't great". Investigation answered both the same evening. The zero oblique clear is correct: the projected quad lands on the card (Vision's own oblique rectangle sits 15–27 px outside it, the side-and-shadow bias of Decision 4), and inside that quad the oblique argmax is 51,345 px of pure background — the oblique segmenter did not call this card food, so there was nothing to clear. The 3× is not a carve defect: a synthetic control carves 800 cm³ at 26°, 712 at 40°, 552 at 60° against a voxelised truth of 337, and the grid's 120 mm cap accounts for ~92 % of the excess (backlog 29).
- **Evening desk work, 2026-09-25.** The carve's grid now stops at the measured food height (P98 of the height field over the nadir food mask, +5 mm, clamped 30–120 mm) and its silhouette is the regularised label map rather than the raw tensor at 50 % non-background. The three two-view bundles replay at 397, 510 and 351 cm³ against 927, 929 and 850 — still 1.3–1.9x the single-view 267–302 band, so footprint and perspective-cone widening are what remain. The growth sweep re-run on the corrected path passes the area gate (median +0.5 %, no cap trips, 13 of 19 refits landing `foodSupport`) but costs carbohydrate accuracy on the three weighed plates, 33.2 g MAE to 40.4 g (backlog 30).
- **Req 1.3 passed offline on `1790310086654`.** The nadir card's P4P corners, mapped through the row's `transform1To2Mm`, land on the oblique card face at 2.9 / 9.2 / 9.3 / 2.0 px (mean 5.8) once both quads follow the gold face; Vision's oblique rectangle sits 15–20 px outside the face (card side and shadow at 26°), which is a detection bias, not a transform error (Decision 4).
- **The 5-minute log collection carried no estimate lines**, only `event=launch` and the field-note save on the Shutter channel; the outcome row carried everything needed instead (`twoViewPoses` present, transform rotation ≈ 24° about y, translation (−91, −4, −36) mm).

## 2026-09-24 — the same sesame roll, no truth taken: the depth-grown food region measures it whole, model `coreml_ab812dc3aa9d`, builds `365aff0-20260924-130129` (morning) and `4feedd1-20260924-164906` (afternoon), both Release

**Morning (build 365aff0, unknown-food-nameable tasks 1–7 on the phone).** Three captures, no refusals now that the shutter needs food-like pixels. The model labelled two specks of the roll as bread on a roll that fills 7 % of the frame (bundle `1790223818017-success`: bread_white 0.16 % + bread_wholemeal 0.33 % of the frame, no `unknown_food` at all), the plane fell back to `edgeBand` (ring median 19.7 mm), and the record read 4.2 g of carbohydrate (9.6 + 16.0 cm³). Outcome `72B75CD0`. The two-view capture (`1790223844719-success`, outcome `FE37458C`) read bread_white 286 cm³ plus an `unknown_food` row of 1148 cm³ from a nadir mask with no unknown pixels — BACKLOG 24. The LiDAR depth showed the whole roll as one raised slab (`bundle_view.py` overlay in the session scratchpad). That gap is what `specs/estimation/depth-grown-food-region` closes.

**Afternoon (build 4feedd1, depth-grown-food-region tasks 1–5 on the phone).** Single-view capture `1790232681422-success`, outcome timestamp 1790232681422: the model now labels 5.3 % of the frame bread_wholemeal (the lighting or angle gave it the crust this time), growth adds 30,250 pixels (146,278 → 176,528, +21 %), the refit lands `foodSupport` (residual 0.95 mm, 7 supporting sectors, ring median −3.6 mm), and the record reads bread_wholemeal 280 cm³ → 112 g → 42.6 g carbohydrate. Developer's field notes on the review screen: "Estimate very good though", "Estimate speckles around edge of roll" (the grown region maps depth cells back as 7.5 × 7.5 px blocks, so the outline's edge is blocky — cosmetic, noted for the outline renderer), and "2 unknown food: not shown in UI. Why?" on the two-view capture `1790232615202-success`, whose record carries bread_wholemeal 383 cm³ + a phantom `unknown_food` 317 cm³ (BACKLOG 24 again; the review's handling of that row is unverified). No weight was taken at the time; 112 g is heavy for a crusty roll and the bread_wholemeal density (0.4 g/cm³) was the named suspect, not the geometry. **That was wrong — see 2026-09-29 below: the roll weighs 104 g, so this reading was +7.7 %, and both the density and the single-view geometry are vindicated.**

**Re-annotated the same night.** Every two-view figure above (383 cm³, 317 cm³, and the morning's 286 + 1148 cm³) is the §6.6 single-view extrusion at a 30 mm prior height, not a carved volume: the two-view geometry had never intersected two silhouettes on a real capture (`docs/agent-notes/two-view-geometry-audit.md`; four defects fixed 2026-09-25, device verification pending). The same applies to every earlier two-view row in this file, including the 2026-08-16 9.5–10.2× under-read.

**What the sitting settled.** `region.grow` is on the Release log channel; the outcome row's `regionGrowth` block carries applied / capTripped / before / after / refitReference. The corpus sweep behind the constants is in the spec's Decision 1.

## 2026-09-23 — sesame bread roll on a white plate: six `noFoodPixels` refusals, model `coreml_ab812dc3aa9d`, build `36b570e-dirty-20260923-145702` (Release; the dirty file is the deploy-script fix committed as 76ac807)

One food, no truth taken. A dark, sesame-crusted bread roll on a white plate,
first on a white stone benchtop, then on a wooden table, single-view LiDAR at
34–40 cm. Six shutter presses, six refusals, all "no food detected"
(`estimate.end failure=noFoodPixels`); three further presses lost to
`worldTrackingDegraded`. Bundles `1790139770341/774406/777960/780725/783509/788143-refused`
pulled to the session scratchpad; five of the six nadir frames are well framed
with the plate centred (the third is a stray taken mid-move).

**What actually happened.** Every refusal came from the support-plane fitter's
empty-mask gate (`supportplane.end failure=emptyFoodMask`), which runs on the
pre-shutter mask *before* the full-resolution segmenter. Four bundles carry a
1920×1440 pre-shutter mask with zero 1-bits; two carry none. The bundled Core
ML model replayed on the Mac against the six nadir PNGs labels 1.2–4.1 % of
each frame `unknown_food` and nothing as a named food (one stray frame gets
3.4 % `bread_wholemeal`). `unknown_food` is not a food class, so the
pre-shutter `BinaryMask` is all zero, the fitter refuses, and the pipeline
maps that to `noFoodPixels`. The `enforceRecognisedFoodDominance` gate that
would have said `unrecognisedFood` (bugfix
unrecognised-food-estimated-as-residual-sliver) never runs — it sits after
segmentation, and segmentation never ran.

**Two defects, neither in the model's control:**

1. The refusal copy is wrong. An unknown-dominant scene refuses as "no food"
   from the pre-shutter path, and as "unrecognised food" from the
   post-segmentation path. The sliver fix ordered only the latter.
2. Arm-then-refuse. `canShutter` (`CaptureFlowModel.hasUsablePreShutterMask`)
   checks that a mask exists and is fresh, not that it has any 1-bits, so the
   shutter arms on an all-zero mask and every press is a guaranteed refusal.
   The first-shot-nofoodpixels-race fix gated only on presence.

**Model finding.** A crusty sesame roll is out of distribution for
`bread_white`/`bread_wholemeal` (the corpus bread is sliced). Worth a
`myfoodrepo-bridge` note when the next data round is planned; not fixable at
the desk today.

Refused bundles carry no probs, so `make harness-accuracy` skips them
(`probsSizeMismatch … got: 0`); replay the nadir PNG through `export.py`'s
`build_reference_chw` + `run_coreml` instead, which is how the numbers above
were measured.

## 2026-08-16 — toast and a cereal bowl, model `coreml_ab812dc3aa9d`, build `a33cb5d-20260815-231735` (Release, clean tree)

The `myfoodrepo-bridge` task 7 capture pass. No scale truth taken — the developer
judged by eye, so the numbers below are against nominal portions, not weighed
ground truth. Every attempt wrote a bundle to `Documents/captures/`.

**This session is what closed task 6.** All nine outcome rows carry
`modelVersion=coreml_ab812dc3aa9d` on a build installed the night before, which
is the live-lineage evidence the launch log cannot give (see
`device-build-and-test.md`, "`segmenterSource` has two forms").

### Scene 1 — one slice of toast, 11:42–11:44

| Time | Path | Outcome | Estimate / failure |
|---|---|---|---|
| 11:42:56 | single-view LiDAR | success | `bread_wholemeal` 188.9 cm³ → 75.6 g / **28.7 g carbs** |
| 11:43:21 | two-view SfS | refused | `noFoodVolumeRecovered`, oblique 28.2° |
| 11:44:09 | two-view SfS | refused | `noFoodPixels`, no oblique mask at all |
| 11:44:33 | two-view SfS | refused | `noFoodVolumeRecovered`, oblique 29.3° |

Nominal for one medium wholemeal slice is ~36 g / ~15 g carbs, so the LiDAR
reading is about **2x over** — the familiar direction. `planeReference=edgeBand`,
`planeRingBandMediansMm=[3.75, 5.49, 6.90]`, median **5.15 mm**: the same
plane-below-the-table mechanism as the 26.1 mm reproductions below, an order of
magnitude smaller this time. Solving the excess over a nominal ~110 cm³ against a
5.15 mm offset implies a ~150 cm² footprint, about one slice — self-consistent,
but inferred, not weighed. **Take a scale truth on the next flat-food capture**;
this session cannot settle whether the offset shrank or the slice was thick.

### Scene 2 — a bowl of milk, yogurt and submerged Weetbix, 11:55

| Time | Path | Outcome | Estimate / failure |
|---|---|---|---|
| 11:55:31 | two-view SfS | refused | `noFoodPixels`; `supportplane.end failure=emptyFoodMask candidates=0`, oblique 18.2° |
| 11:55:33 | two-view SfS | refused | same, same frame |
| 11:55:34 | two-view SfS | refused | `worldTrackingDegraded` at oblique capture |
| 11:55:43 | two-view SfS | success | `bread_wholemeal` 63.8 cm³ + `tomato` 246.6 cm³ = **14.5 g carbs**; oblique 25.3° |
| 11:55:56 | single-view LiDAR | success | `cheese` 66.9 cm³ → 73.6 g / **0.07 g carbs** |

Every mask read `topClass=33 topClassPercent=94–98` — class 33 is `background`
(`ClassPalette.swift:69`) — leaving 0–2 % food coverage, against 8–10 % on the
toast.

**This is not a cereal misclassification, and reading it as one would send the
next retrain in the wrong direction.** The developer's account of the scene:
the visible surface was milk and yogurt, with the Weetbix submerged beneath it.
So `cereal` (24) was not visible to be predicted, `milk` (28) exists as a liquid
class but was not chosen, and **yogurt has no class in the palette at all**. No
correct answer was available to the segmenter. The gap is that the pipeline
estimates what it can see and has no concept of food occluded beneath a liquid
or another food — a bowl whose contents are mostly hidden is outside what the
visual hull plus a surface segmentation can express, however the model is
trained. Adding cereal training images does not address it.

**Third reproduction of the dangerous-direction failure.** `cheese` at 0.07 g
carbs for a breakfast bowl repeats the pattern of `carrot` at 1.50 g for bread
(2026-08-05, below): a confident success whose wrong class hides a large carb
load. For a dosing tool an under-read is the direction that harms; the toast's
2x over-read at least errs safe.

**The bowl defeats the edge-band plane reference.** The LiDAR capture fitted
`planeReference=edgeBand` with a ring median of **23.3 mm** — the ring is sitting
on the bowl rim, not the table — while the two-view capture of the same scene
fitted `foodSupport` and got **1.57 mm**. That is the sharpest edgeBand-vs-
foodSupport contrast recorded so far and it is direct evidence for
`estimation/support-plane-reference`: whatever else it settles, the reference
must not be the rim of the vessel.

### On the two-view carve

Mixed, and it partly rehabilitates `specs/bugfixes/two-view-carve-no-volume`,
whose Resolution blames a mis-aimed oblique and left the on-device verification
open. Today the carve **recovered volume at an oblique of 25.3°** — dead on the
target ring — and recovered nothing at 28.2° and 29.3°, both inside the 10–40°
arming band. Aim matters more than "inside the band" captures. What that report
still does not explain: the 28.2°/29.3° attempts had food pixels in *both* views
(10/8 % and 5/4 %) with `degenerateRaySkipCount=0`,
`degenerateVoxelSkipCount=0` and nothing threshold-discarded, and still carved
nothing. Do not close that report on this session — it needs a trail where the
oblique is aimed and the tilt is off the ring.

## 2026-08-13 — speckle/stability gate closed (no weighed truth)

Developer verdict on device: speckle is gone and readings are stable.
`tasks-segmenter-training-pipeline` task 7 (the on-device STOP acceptance
gate) is now **closed** on this evidence — accepted on the promoted
`coreml_ab812dc3aa9d` model plus the shipped `PostProcessing.swift`
connected-component cleanup, explicitly overriding the 2026-08-04 hold that
reserved the gate for the retrained model. Task 6 (the new-recipe training
run) remains open but is no longer what acceptance waits on.

## 2026-08-11 — weighed bread slice, model `coreml_ab812dc3aa9d`, build `9509b27-20260811-185011` (Release)

Scene: **1 slice of bread, 58 g total** (scale truth), white plate. Yellow bank
card as the ID-1 reference for two-view captures. iPhone 16 Pro. 15 attempts
19:05–19:08 local; bundles for every attempt (successes and refusals) in
`Documents/captures/`, single-view bundle pulled to
`tmp/device_captures/1786439141215-success.fixture`.

| Time | Stem | Path | Outcome | Estimate |
|---|---|---|---|---|
| 19:05:41 | `1786439141215` | single-view LiDAR | success | bread_wholemeal 48.6 cm³ → **19.4 g / 7.4 g carbs** |
| 19:07:14 | `1786439234576` | two-view SfS | success | bread_wholemeal 382.9 cm³ → 153.2 g + **cheese 43.7 g (the bank card)** = 196.9 g / 58.2 g carbs |
| 19:08:20 | `1786439300420` | two-view SfS | success | bread_wholemeal 301.3 cm³ → **120.5 g / 45.8 g carbs** |

Interleaved refusals, all in two-view mode: `noFoodPixels` ×7,
`worldTrackingDegraded` ×5 — the same framing-refusal pattern as the 2026-08-05
session, roughly half the shutter presses again.

Paired re-shoot at 22:08, same plate, same 58 g, build `6675525-20260811-192504`
— taken from **inside** the ~365 mm smear envelope after the range finding below
(median food depth 272.9 mm vs the first capture's 399.9 mm, measured off the
committed slices):

| Time | Stem | Path | Outcome | Estimate |
|---|---|---|---|---|
| 22:08:50 | `1786450130307` | single-view LiDAR | success (`foodSupport`, 8/8 sectors) | bread_wholemeal 77.1 cm³ → **30.8 g / 11.7 g carbs** |
| 22:09:22 | `1786450162911` | two-view SfS | refused `unrecognisedFood` | — |

The inside-envelope capture still under-reads **1.9×** with a stronger plane
verdict than the contaminated one — range explains 3.0× → 1.9× and no more.
Slice committed as `1786450130307.depthslice`; the residual under-read is the
lead question for the support-plane task 26 pass.

Readings:

- **First field firing of the promoted support plane.** The single-view capture
  selected `planeReference=foodSupport` (6/8 supporting sectors, ring median
  −0.97 mm, residual 1.81 mm) — the first real capture where the restricted fit
  was admissible under the shipped placeholder constants. But the estimate is
  **3.0× UNDER** by mass (19.4 vs 58 g; ~215 cm³ expected vs 48.6 measured),
  where the pre-feature defect was a 2–3.6× over-read. Plausible mechanism: the
  admitted plane sits at or near the bread's top surface rather than the plate,
  truncating the height field. The pulled bundle is the evidence for
  support-plane task 26; slice with `tools/fixture_slice.py` and add to
  `SupportPlaneCorpusMeasurementTests`.
- **Two-view still over-reads over the table plane.** Both two-view successes
  kept `planeReference=edgeBand`; capture 3's ring median is **+12.9 mm** (the
  table), and the over-reads (2.1×, 2.6× on the bread rows) match the known
  constant-height mechanism on flat food.
- **The reference card is segmented as food.** The yellow bank card was
  classified `cheese` (39.7 cm³ → 43.7 g phantom mass, EST_SOLID density) in
  capture 2 — out-of-palette-object-as-food, same family as the brussels-sprouts
  and pumpkin sessions, but now corrupting the two-view decomposition while the
  card simultaneously serves scale (`scaleSource=card+lidar`). A card mask
  exclusion zone may be worth a spec: the card's pose is already solved, so its
  image-plane extent is known to the pipeline.
- Weighed carb truth for the plate is ~24 g (58 g wholemeal at ~42 g/100 g), so
  the carb errors are −69 % (single), +143 % (capture 2, incl. phantom cheese),
  +91 % (capture 3).

## 2026-07-26 — staged plate, model `coreml_ab812dc3aa9d` (36-channel palette)

Build: PRE-gate binary for all four attempts (the unrecognised-food gate and
palette fixes deployed 18:39, after this session). Scale truth from the user;
estimates from `estimation_outcomes` (localtime timestamps).

| Time | Plate (scale truth) | Outcome | Estimate |
|---|---|---|---|
| 18:35:50 | 208 g white rice | success | white_rice 603 cm³ → **440 g / 141 g carbs** |
| 18:36:47 | + fried brussels sprouts = 309 g | refused `noFoodVolumeRecovered` (white_rice 0 cm³) | — |
| 18:36:49 | same plate | refused `noFoodPixels` | — |
| 18:37:40 | + squash & pumpkin = 551 g | success | carrot 45 g + mixed_vegetables 350 g = **395 g / 17.7 g carbs** |

Readings:

- **Rice-only over-read is 2.1× by mass** (440 vs 208 g; 603 cm³ carved vs
  ~285 cm³ at FAO cooked-rice density). This is the expected uncalibrated
  β = 1.0 upward bias (model-production "uncalibrated honesty") plus
  height-field over-carve on a mounded pile. Prime β_c calibration datum.
- **Brussels sprouts are effectively out-of-palette** (fried, dark): the
  segmenter returned a rice sliver then nothing — same failure family as the
  pumpkin session (unrecognised-food-estimated-as-residual-sliver). On the
  post-gate binary these refusals surface as `unrecognisedFood`.
- **Layered plates break the nadir path**: with vegetables on top, the rice
  disappeared entirely from the 551 g capture (subsumed into
  mixed_vegetables), so the true carb load (~58 g from 208 g cooked rice)
  read as 17.7 g. Squash/pumpkin chunks read as `carrot` (orange). Occlusion
  is structural for single-nadir capture — no segmenter fixes a food that is
  not visible; flag for the estimation roadmap (multi-view / user-assisted
  layering).
- Earlier same day, 17:27: pumpkin-only plate — 3 refusals + one "cheese
  18 cm³" estimate from a 0.21 % sliver; full analysis in
  `specs/bugfixes/unrecognised-food-estimated-as-residual-sliver/report.md`.
- **The 208 g rice bundle does not replay, and the capture itself is bad.**
  `1785054950406-success.fixture` is still on the device and pulls fine
  (194.9 MB, stamp `ab812dc3aa9d`), but `FixtureLoader` loads **zero meals**
  from it — `make harness-accuracy` over a directory containing it reports one
  fewer meal than files present, with no error. The two bread-session bundles
  from the same era (`1785135663727`, `1785901032716`) load normally, so it is
  not an era-wide format problem.

  **Diagnosed 2026-08-05 at the depth level** (support-plane-reference
  Decision 31). `tools/fixture_slice.py` cuts it cleanly — the loader failure is
  not a slice-level one — but **41 %** of the frame and **43.2 %** of the food
  mask carry ARKit's low confidence, against 22.7 %/0.0 % and 0.1 %/0.0 % on the
  two bread captures. The discarded samples are the near ones (median 247.9 mm
  against the surviving 277.8 mm): τ_conf removes the rice mound and leaves the
  flat remnant around it, so the best support-plane candidate reports the food
  as 9.0 mm *below* its own plane. The bundle still returned a "success" and
  603 cm³ at capture time, which is the lesson worth carrying — **an estimate
  is no evidence the depth frame was any good**. The slice is committed as a
  rejected fixture in `SupportPlaneCorpusMeasurementTests` so the exclusion is
  reproducible. Don't re-pull it expecting it to work, and don't re-slice it
  expecting it to serve as a non-flat anchor.

Follow-ups seeded by this session:

- Mass readout in the UI (specs/ui/mass-readout) so scale validation is
  real-time.
- These weighed plates are benchmark-meal material (BenchmarkView →
  weighed fidelity); logging them there scores every future model/β change
  against today's truth.

## 2026-08-04 — device session, speckle verdict (no weighed truth)

Qualitative pass during the roadmap §2 device session; no scale truth taken, so
nothing here is a calibration datum.

- **Overlay speckle is gone.** Developer verdict on device: "speckles
  DEFINITELY gone". Attributable to the shipped deterministic
  connected-component cleanup in `Segmentation/PostProcessing.swift`
  (`estimation-quality` → `tasks-mask-post-processing-cleanup`, all ticked)
  running against the promoted `coreml_ab812dc3aa9d` model — **not** to the new
  training recipe, which has not been run
  (`tasks-segmenter-training-pipeline` task 6 is still open). So
  `tasks-segmenter-training-pipeline` task 7 stays open: it is the acceptance
  gate for the *retrained* model, and ticking it on this evidence would credit a
  run that never happened. *(Superseded: the developer closed task 7 on
  2026-08-13 — see that session's entry.)*
- **Estimation quality improved substantially but is not yet at target.**
  Developer verdict: "improved HUGELY since this bugfix, albeit is not yet as
  accurate as hoped". No numbers — this session took no weighed truth, so the
  gap is an impression, not a measurement.
- **Follow-up:** the only way to move that verdict from impression to number is
  the accuracy loop in `docs/roadmap.md` §4 — a truth manifest joined at
  evaluation time plus the append-only per-fixture error log keyed on
  `(fixture_id, segmenter_sha)`. Until that lands, "not as accurate as hoped"
  cannot be attributed between the segmenter, β = 1.0, the carve, or the
  support-plane offset. Weigh the next session's plates.

## 2026-08-05 — raw sweet potato, two-view + card: refused (correct), no truth taken

Build `6db23e7-20260805-115608` (Release + `coreml_ab812dc3aa9d`), mode=double, five shutter
attempts 12:53:01–12:53:20. Log at `/tmp/medata-device.log`; bundles
`1785898381149`, `1785898392365`, `1785898394289`, `1785898400083`.

**Outcome: every attempt refused. That is the correct behaviour, not a defect.** A raw sweet
potato has no target class anywhere in the system:

- The v2 segmenter palette's 25 solid classes are cooked staples. The only potato channels are
  `potato_boiled` and `potato_mashed`; there is no raw-potato and no sweet-potato class.
- The bundled food database agrees — all 33 `class_id` rows, and the only raw entries are
  `apple`, `banana`, `tomato`. Even `carrot` is "Carrot (boiled)".
- Both training corpora (FoodSeg103, FoodRec2022) are prepared-meal datasets. A whole raw root
  vegetable is out of distribution, not merely unseen.

The segmenter said so plainly: `foodCoveragePercent=0 topClass=33 topClassPercent=94
distinctClasses=3` — class 33 is `background`, so 94 % of the frame read as "not food".

**Two different refusal reasons for one scene, and the mechanism matters.** Attempt 1 refused
`unrecognisedFood`; attempts 2–5 refused `noFoodPixels`. The split is not random:
`Pipeline.estimate` fits the support plane from `captureResult.preShutterFoodMask` at Stage D,
**before** it ever runs its own segmenter.

- No fresh pre-shutter mask → the plane fit proceeds, the pipeline reaches segmentation, logs
  `event=segmenter.mask`, and the recognised-food gate returns `unrecognisedFood`. Bundle
  **205 MB** (full probability tensor).
- Fresh but empty pre-shutter mask → `supportplane.end failure=emptyFoodMask` short-circuits to
  `noFoodPixels` before segmentation. No `segmenter.mask` line, no probs, no argmax. Bundle
  **3.6 MB**.

So the refusal the user sees depends on whether the live preview happened to have published a
mask at the shutter instant. Worth unifying: same scene, same cause, two messages.

**The diagnostic gap this creates.** An `emptyFoodMask` refusal is decided by the *pre-shutter
preview* segmenter, and that mask is recorded nowhere — the bundle carries no probs, no argmax
and no mask. The refusal therefore cannot be replayed or second-guessed offline, which is the
opposite of what the recorder exists for. Recording the pre-shutter mask on this refusal path
would cost a few KB. Filed against `capture-bundle-recorder`.

Also seen once: `capture.end stage=oblique success=false error=worldTrackingDegraded` at
12:53:15 — one oblique frame lost to ARKit tracking, recovered on the next tap. Not investigated.

**Not a truth datum:** nothing was weighed and every attempt refused, so this session contributes
no calibration evidence — only the coverage finding above.

## 2026-08-05 — 2 slices multigrain bread, weighed: independent confirmation of the 26.1 mm plane error

Build `6db23e7-20260805-115608`. **Truth from the developer: ~80 g, ~34 g carbs**, unbuttered.
Two captures ~30 s apart on the same physical scene.

### Capture A — single-view LiDAR (`1785901032716`), class CORRECT, volume 3.6x over

| | Value | Truth |
|---|---|---|
| Class | `bread_wholemeal` ✓ | multigrain bread |
| Volume | 714.84 cm³ | ~200 cm³ (80 g ÷ 0.400 g/cm³) |
| Mass | 285.94 g | 80 g — **3.57x** |
| Carbs | 108.66 g | 34 g — **3.20x** |

Density (0.400, MEASURED) and β (1.0) are both correct, and the class is right, so the entire
error is volume. Solving `(h + 26.1) / h = 3.57` for the plane offset already measured in
`specs/estimation/support-plane-reference/requirements-notes.md` gives an implied true slice
thickness of **10.1 mm**, against the ~10.9 mm that analysis derived from a *different* capture
(`1785135663727`). Implied footprint 197 cm², i.e. ~14 x 14 cm for two slices side by side —
physically right.

**So this is a second, independent, weighed-truth reproduction of the 26.1 mm support-plane
error, agreeing to within about a millimetre.** The defect is no longer inferred from one
capture. `planeResidualMm` was 1.97 with 1,286,181 of 1,478,354 candidates as inliers — the fit
is *confident and wrong*, which is the signature: RANSAC maximises inlier count and the worktop
wins on area.

Flat food is the worst case, and bread is a carb staple. A constant height offset is
proportionally largest on the thinnest food, so the dish type most likely to be photographed is
the one most over-read.

### Capture B — two-view SfS (`1785901065701`), class WRONG, volume 4x under

| | Value | Truth |
|---|---|---|
| Class | `carrot` ✗ | multigrain bread |
| Volume | 46.70 cm³ | ~200 cm³ |
| Mass | 34.09 g | 80 g |
| Carbs | **1.50 g** | 34 g — **23x under** |

`scaleSource=card+lidar`, `cardFallback=false`, so the ID-1 card was detected and used. Two
distinct failures compounding: the SfS carve recovered a quarter of the volume, and the class was
wrong in the direction that hides it — `carrot` at 3.2 g carbs/100 g reads a bread-sized object as
nearly carb-free. A 23x UNDER-read is the dangerous direction for a dosing tool; the single-view
3.2x over-read at least errs safe.

### The finding neither capture shows alone: classification is unstable run-to-run

Captures A and B are the same bread, same worktop, ~30 s apart, and the nadir frames classified
**differently** — `bread_wholemeal` then `carrot`. Nadir food coverage was 17 % then 13 %.
Multigrain crust is brown-orange and `carrot` is the orange class; the same confusion produced
"squash/pumpkin read as carrot" in the 2026-07-26 session. This is not a two-view-path defect —
it is the segmenter giving a different answer to the same question, and it belongs with
`estimation/estimation-quality`'s run-to-run variance work rather than with the carve.

## 2026-08-05 09:09–09:20 UTC — four weighed truths, all on the wrong path

Build carrying `coreml_ab812dc3aa9d`. 49 attempts, 3 successes. **Every weighed truth landed on
`two_view_sfs`; all 22 `single_view_lidar` attempts refused.** Raw notes for integration.

### The four events

| Attempt | Truth | Estimate | Error | Class | Path |
|---|---|---|---|---|---|
| bowl of prawns (09:09–09:12) | — | refused | `noFoodPixels` ×many, one `unrecognisedFood` | — | mixed |
| `1785921329668` bread | 196 g | 20.7 g | **9.5× under** | `bread_white` ✓ | two-view |
| `1785921526968` heaped rice, **lipped plate** | 245 g | 841 g | **3.43× over** | `carrot` + `mixed_vegetables` ✗ | two-view |
| `1785921628874` white rice | 320 g | 31.4 g | **10.2× under** | `white_rice` ✓ | two-view |

Full decompositions:

- `1785921329668` — `bread_white` 54.6 cm³ / 20.7 g / 10.0 g carbs, MEASURED density.
  plane residual 2.47 mm, inliers 599,779 / 1,081,362, nadir tilt 1.9°,
  foodRegionCoverage 99.6 %, segNadir foodCoverage 9 %.
- `1785921526968` — `carrot` 260.0 cm³ / 189.8 g / 8.4 g carbs (FAO_DENS) **plus**
  `mixed_vegetables` 1002.1 cm³ / 651.4 g / 29.3 g carbs (MEASURED). Total 1262 cm³ / 841 g /
  37.7 g carbs. plane residual 2.32 mm, inliers 23,791 / **30,576**, nadir tilt 2.4°,
  **foodRegionCoverage 0 %**, segNadir foodCoverage **0 %**.
- `1785921628874` — `white_rice` 43.0 cm³ / 31.4 g / 10.0 g carbs, FAO_DENS.
  plane residual 2.75 mm, inliers 158,972 / 575,060, nadir tilt 3.5 °,
  foodRegionCoverage 88.9 %, segNadir foodCoverage 6 %.

All three: `scaleSource = card+lidar`, `cardFallback = false`, `sigmaView = 0.75`.

Bundles on device: `1785921329668-success.fixture` (390.5 MB), `1785921526968-success.fixture`
(390.3 MB), `1785921628874-success.fixture` (389.8 MB), plus `1785921175528-refused.fixture`
(198.9 MB, the prawn bowl's `unrecognisedFood`).

### What the numbers say

**The two-view carve under-reads by an order of magnitude, not a margin.** 9.5× and 10.2×, both
with the class *correct*, so this is the carve and not segmentation. The previously recorded figure
was ~4× (2026-08-05 bread session). Belongs to `bugfixes/two-view-carve-no-volume`, not to
`support-plane-reference`.

**Carbs, which is the number that matters:** white rice 320 g → 10.0 g carbs reported against
~90 g expected for cooked rice. The lipped plate reported 37.7 g against ~69 g expected, so mass
was 3.4× *over* while carbs were ~45 % *under* — the wrong classes carry much lower carb density,
and the two errors partly cancel in a way that hides both.

**`1785921526968` is anomalous beyond the misclassification.** `foodRegionCoveragePercent: 0` and
segmenter `foodCoveragePercent: 0`, with `planeCandidateCount` 30,576 against ~1 M on the
neighbouring captures — yet it returned a success carrying 1,262 cm³. A success recorded on a frame
with no confident depth over the food. Worth its own look; not diagnosed here.

**The bowl attempts prove nothing about bowls.** Prawns are not among the 25 solid palette classes,
so segmentation refused before plane selection was ever reached. Same family as the raw sweet potato
(2026-08-05 earlier entry). A bowl capture can only exercise the support-plane fallback if the food
is in palette — rice, pasta or cereal.

**`worldTrackingDegraded` refused 13 of 49 attempts.** Roughly a quarter of shutter presses lost to
ARKit tracking. Not investigated; it sets the realistic yield of a weighed sitting at about half the
presses.

### Consequence for `support-plane-reference`

Four weighed truths, zero usable evidence — the feature corrects the *depth-derived* plane, and no
capture reached that path. `1785921526968` is nonetheless the only lipped-plate capture in
existence, and Decision 14's radial-band and support-visibility mitigations have no field evidence
of any kind. Recorded as Reqs 7.10 (a weighed single-view lipped-plate case) and 7.11 (a weighed
capture counts as evidence only where it completed single-view), with the session written up in
that spec's `prerequisites.md`.

## 2026-09-29 — the roll is weighed: 104 g (build `2d39910`, segmenter `coreml_ab812dc3aa9d`)

**The first weighed object in the corpus, and the first denominator any volume
figure has ever had.** Field note `1790655037216` on `meal.review`: "Exactly 104g
on plate", linked to meal `45FE1DF5` / outcome `006D7CFA`. Back-filled into the
index as `benchmark_meals` row `backfill-1790655037216-roll` — 104 g, 39.52 g
carbohydrate at the bundled CoFID coefficient (38.0 g/100 g), `fidelity=weighed`.
At the measured bread_wholemeal density of 0.4 g/cm³ that puts **truth volume at
260 cm³**. The review screen writes the same row on the phone since 2026-10-03
(see "Recording a weighed figure" above). The four captures back-filled that
morning predate the sheet, so they were the last hand back-fills.

What it settles:

| Reading | Volume | Against 260 cm³ |
|---|---|---|
| single-view band, historical | 267–302 cm³ | +3 % to +16 % |
| 2026-09-24 single-view | 280 cm³ → 112 g | **+7.7 %** |
| 2026-09-29 single-view | 226.3 cm³ → 90.5 g | **−13.0 %** |
| two-view rows, historical | 851 / 920 / 930 cm³ | **3.3–3.6×** |
| two-view success, 2026-09-29 | 42.2 cm³ | **−84 %** |
| Decision 10 refit, audit bundles | 268.0 / 390.1 cm³ | +3 % / 1.5× |

- **The density is not the residual error.** 0.4 g/cm³ is right; the measured
  volumes imply 0.34–0.39. The 2026-09-24 reading was inside the MAPE < 20 % bar
  (MD-25) all along, and the correction above retracts that note's conclusion.
- **Single-view precision is ±11 %.** The same roll read 90.5 g and 112 g in two
  sessions. That spread, not either figure, is the honest number.
- **The two-view path produced nothing.** Six of seven captures `refused`. Four
  logged estimates each ran
  `supportplane.end success=false failure=noLowerSilhouetteEdges` →
  `estimate.end success=false failure=noSupportPlaneWithoutDepth`, with
  `estimate.degraded reason=unbounded_carve_height` alongside. Both photos were
  fine every time (`capture.end success=true`, 1920×1440); one separate oblique
  failed `worldTrackingDegraded`.

  **Corrected 2026-09-29, same day.** The transcript above originally carried
  `candidates=0 inliers=0` and bbox −1, and this note read them as a detector
  that had searched and found nothing. They were never measurements: the
  card-only branch returns a default-constructed `SupportPlaneFitStats`, so
  nothing had run. Nor is this a three-step cascade —
  `unbounded_carve_height` is stamped from `twoViewSfS && depth == nil` before
  any stage can refuse (`Pipeline.swift`), a property of the capture rather than
  a consequence. The refusal now logs `stats=unfitted` and no numbers, so the
  misreading is not available to the next reader. **What survives: the no-depth
  branch refuses before any candidate collection, so the height-bound work in
  two-view-trust Decisions 8/11 is downstream of a plane that is never
  attempted.**
- **One plate, two regions, one phantom.** A second region came back `coffee`
  at 59.5 cm³ / density 1.0 and had to be rejected by hand — the same
  BACKLOG 24 shape as 2026-09-24's phantom `unknown_food`.

The bundle survives the corpus discard at
`medata-corpus/reports/calibration-20260929-roll/` (fixture + `run_summary.json`
+ README); `captures/` was cleared the same day, so that copy is the last one.

### Re-run 2026-10-03 against the preserved bundle (harness at `abd9750` + the seed-area gate)

- **`volumes`.** Replays the device row exactly: seed 32,436 px (25.1 cm² on
  the first plane, an `edgeBand` fit), grown to 127,121 px with a
  `foodSupport` refit, `unknown_food` 226.3 cm³ (−13.0 % against 260) plus the
  phantom `coffee` 59.5 cm³. The seed is far under the 200 cm² gate, so
  depth-grown-food-region Decision 5 leaves it growing. Without growth:
  `unknown_food` 49.8 cm³ (−81 %) on the table plane.
- **`carve-audit`.** Single-view, so it prints the `profile` line only: first
  plane `edgeBand` at −383.4 mm, residual 2.62 mm, ungrown footprint
  26.2 cm², height field 74.5 cm³ over both regions, height above that (table)
  plane p50 37.1 / p90 42.0 / max 44.3 mm.
- **`calibrate`.** Produces nothing to bake: both classes stay β = 1
  (`uncalibrated_unity`, effective sample 0). The bundle carries no truth (it
  lives in `benchmark_meals`), and its class is `unknown_food`. Two tooling
  defects on the way: the derived `run_summary.json` does not load
  (`tools/field_loop/derive_dataset.py` writes `"skipped": []`, a list, where
  `CalibrateRun.loadIngestSummary` expects `{reason: [ids]}` —
  `DecodingError.typeMismatch` at `skipped`), and `calibrate` treats the field
  bundle as Nutrition5k and refuses without `--depth-test-split` (a
  placeholder split file gets past it). Both fixed 2026-10-03 (see that
  entry).

**Backlog 30, answered.** On this weighed roll growth moves the carbohydrate
reading from −31.9 g to −5.1 g. With it in the set, growth no longer costs
accuracy across the weighed single-view plates (four-plate MAE 31.6 g with
growth, 32.9 g without), and Decision 5's gate removes the one plate it made
worse (25.8 g).

**Backlog 29, as far as one object goes.** No two-view figure for item 29 can
come from this roll. Its one two-view success of the day (outcome `055BB705`,
`1790655148006`, bundle discarded) read 42.2 cm³ (−84 %) because the nadir
silhouette was 18,305 px, a 16.6 cm² footprint of a roll whose grown
single-view footprint is about 103 cm² (127,121 px at the card's
0.285 mm/px), and the measured food height was 3.6 mm — read from the row,
not replayed, but that is a `foodSupport` plane on the roll's own top, the
case where plane-only growth adds nothing (it did not: `applied=false`). That is a silhouette
under-read, not the hull over-read item 29 is about. What the roll does give
item 29 is a scale for its reference. The like-for-like reference of
`two-view-geometry-audit.md` §7 is the LiDAR height field at the adopted
plane; on this weighed roll that reference reads −13 %, and on the 2026-09-24
capture of the same roll +7.7 %. The 0–24 % "unexplained" carve excess is
measured against a reference that spreads −13 % to +16 % across captures of
this one object, so one object cannot separate the two, and a two-view β still
has no weighed two-view capture behind it. The grown footprint (~103 cm²) sits
inside the 102.7–127.5 cm² §7 measured on the two-view roll silhouettes,
consistent with its finding (a) that the footprint is not wide.
