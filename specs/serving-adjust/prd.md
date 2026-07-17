# PRD: Serving-based portion adjustment on the result screen

## Product summary

The snaqui portion control shipped as a global "Ate 1 of 1" stepper pair in its own card above the per-food list. On device it reads as an opaque "edit 1 of 1" widget: it is disconnected from the ingredients it scales, and its unit — plates — is not how anyone thinks about a partially eaten meal. The per-food breakdown below it is read-only, so the list the user actually looks at cannot be adjusted, and the separate Adjust screen edits in raw carb-grams, a unit no human estimates by eye. User direction (2026-07-17): the less/more controls belong on the ingredient rows themselves, and they should count in servings — "spoons of peas", "number of potatoes" — with grams as the powerful-but-secondary path. Serving-first is an experiment (no surveyed competitor leads with household units; SNAQ itself is gram-centric), so the serving definitions must be data, not code, and easy to tune.

A research pass (2026-07-17, session record) grounds the redesign: portion-cognition literature shows people cannot estimate grams but handle household measures and do best with reference portions (Oxford Nutrition Reviews 2020; PMC4976119); logging-friction studies show default-accept flows with edit-by-exception retain users while >30-second logging churns them; and the leftovers case ("ate half of it") is the single most common correction, arguing for a one-tap plate-fraction control alongside per-row steppers. The British Dietetic Association "Portion sizes" Food Fact Sheet (https://www.bda.uk.com/resource/food-facts-portion-sizes.html) provides citable household-unit gram weights; Crawley, *Food Portion Sizes* (FSA, 3rd ed., ISBN 9780112429616) is the authoritative underlying reference for foods the free sheet omits.

Target repository: `medata` (this repository). Two contexts: the food-database generator gains a solid-food servings table (mirroring the existing `liquid_servings` precedent), and the SwiftUI result surface in `App/` is reshaped around per-ingredient serving steppers. The estimation pipeline, segmenter, and volume/mass maths are untouched; persistence continues through the existing append-only `PbUserCorrection` mechanism.

## Goals

- The per-food list on the result screen is the adjustment surface: each ingredient row carries its own less/more control, stepping in that food's household serving unit, with the hero carb total updating live.
- Serving units and gram weights are bundled data with per-row source citations, tuneable without code changes.
- The happy path stays zero-additional-taps: an untouched result records exactly what it records today; adjustments are edit-by-exception.
- The leftovers case is one tap: a plate-fraction control scales every row at once.
- Grams remain available per ingredient as the secondary, precise path — never the default unit.
- The original estimate is never overwritten; every adjustment is an appended correction, reversible and re-adjustable, and downstream surfaces (Graph, Records, Meal overview) keep showing the corrected "eaten" number.

## Non-goals

- No changes to the estimation pipeline, Core ML model, volume/mass/β maths, or the per-100 g composition data — serving scaling is post-estimation arithmetic on the recorded estimate.
- No new correction mechanism, event types, or schema changes on the Swift side: portion adjustments persist via `store.appendCorrection` exactly as the snaqui portion control does today.
- No photo-reference portion images this cycle (the research says they help; they need art direction and a licensing pass — record as a possible successor, do not build).
- No changes to benchmark truth entry (`BenchmarkView` keeps weighed grams — benchmark ground truth is deliberately gram-precise) or to the manual Intake surface.
- No localisation of units (metric-only invariant stands; UK/Irish household measures only).
- No new test scaffolding beyond the MVP gate: MedataCore/generator tests where the maths naturally lives, app surfaces verified by build + on-device look. No app-target test files.

## Food database servings

Covers `tools/food_db/generate.py`, its tests in `tools/food_db/tests/`, the committed `cofid_db.sqlite`/`afcd_db.sqlite` under `MedataCore/Sources/Foods/Resources/`, and the Swift access layer in `MedataCore/Sources/Foods/`.

1. The generator MUST emit a `solid_servings` table alongside the existing `liquid_servings` precedent, and the committed databases MUST be regenerated with it.
   - Acceptance: schema `solid_servings(class_id TEXT PRIMARY KEY, unit_singular TEXT, unit_plural TEXT, grams_per_unit REAL, step REAL, source TEXT)`; `step` is the stepper increment in serving units (e.g. 0.5 or 1.0) so granularity is data, not code.
   - Acceptance: every non-liquid palette class in the `foods` table either has a `solid_servings` row or is deliberately absent (absence = the app falls back to grams); the generator fails if a class id in `solid_servings` does not exist in `foods`.
   - Acceptance: each row's `source` names a citable reference. Seed values (BDA Food Fact Sheet unless noted): bread_white/bread_wholemeal 1 slice = 36 g; potato_boiled 1 egg-sized potato = 58 g; potato_mashed 1 scoop = 60 g (Crawley — verify); white_rice/brown_rice 1 serving spoon = 50 g cooked; pasta 1 serving spoon = 50 g cooked; peas / mixed_vegetables / broccoli / carrot 1 heaped tablespoon = 27 g; beans_baked 1 tablespoon = 37 g; lentils 1 tablespoon = 37 g (Crawley — verify); chips_fries 1 handful = 55 g (Crawley — verify); apple 1 apple = 80 g; banana 1 banana = 80 g; tomato 1 tomato = 80 g; cheese 1 matchbox piece = 30 g; egg 1 egg = 50 g; beef/chicken/pork/fish_white 1 palm-sized piece = 90 g; salad_leaves 1 handful = 20 g (Crawley — verify). Rows flagged "verify" carry `source` = "Crawley Food Portion Sizes (unverified figure)" so the provenance is honest.
   - Acceptance: generator tests cover the new table (schema, coverage rule, orphan-class failure) following the existing test layout in `tools/food_db/tests/`.
2. The Swift food-database layer MUST expose the serving definition per class.
   - Acceptance: the `FoodDatabase` surface (see `MedataCore/Sources/Foods/`) gains a lookup returning `(unitSingular, unitPlural, gramsPerUnit, step)` or nil for a class id, read from `solid_servings`; covered by a test in the existing executed Foods/MedataCore suite (e.g. potato_boiled resolves, water does not).
   - Acceptance: `make test` green (report both totals) and `make spell` clean.

## iOS app

Covers the SwiftUI result surfaces in `App/`: `ResultView.swift` (both `justCaptured` and `historyDetail` presentations), `ManualCorrectionView.swift`, and their route wiring in `CaptureFlowView`/`MealRouting`. Read `docs/agent-notes/ui-capture-flow.md` before touching `App/`.

1. The per-food breakdown MUST become the adjustment surface, replacing the separate portion card.
   - Acceptance: the "PORTION / Ate N of M" card and `PortionStepper` pair are gone from `ResultView`; the "Per food" rows each show the food name, the estimated amount expressed serving-first (e.g. "≈ 2 potatoes", "≈ 3 spoons", using `unit_singular`/`unit_plural` and the nearest displayable half-unit), the gram mass as secondary text, and that row's carb contribution.
   - Acceptance: each row carries inline − / + controls stepping by the class's `step` in serving units, floored at 0; the hero carb total updates live with the same `.numericText()` transition the hero uses today, and the "estimated N g" line keeps showing the untouched full estimate whenever the pending state diverges.
   - Acceptance: a class with no `solid_servings` row (and any liquid class) falls back to a gram stepper on the same row — never a dead row.
2. A plate-fraction quick control MUST cover the leftovers case in one tap.
   - Acceptance: a compact control on the result screen (e.g. segmented "All · ¾ · ½ · ¼") scales every row's pending amount from the original estimate in one tap; selecting it then nudging an individual row keeps the other rows at the fraction (fraction first, per-row refinement second).
   - Acceptance: the control's default state is All and writes nothing.
3. Grams MUST remain the secondary precise path per ingredient.
   - Acceptance: tapping a row's amount (not the − / + controls) reveals an editable gram value for that row, two-way bound with the serving display (editing grams updates the serving readout and vice versa); the gram field uses the digits-only clamp convention from the existing carb-entry surfaces.
4. Confirming adjustments MUST persist through the existing correction mechanism, edit-by-exception.
   - Acceptance: with nothing touched, no correction is written and Done behaves exactly as today (zero additional taps photo → recorded meal).
   - Acceptance: once any row or the fraction control diverges from the recorded state, a single confirm action appears (the existing "Log N g" pill pattern) that appends one `PbUserCorrection` carrying the scaled total, per-class carbs scaled per row, and a machine-readable note recording the per-class serving counts (extend the `PortionFormat` note convention; keep parsing the legacy `portion N/M` notes so existing history still seeds).
   - Acceptance: scaling always derives from the ORIGINAL estimate so repeated adjustments never compound; reopening from history seeds rows from the latest correction and re-adjusting (including back to the full estimate) appends a further correction.
   - Acceptance: Graph carb bars, Records rows, and Meal overview show the corrected total via the existing wiring (`displayTotalCarbsG` / corrections fold-in) — verified by the existing MedataCore tests staying green and by build.
5. The separate Adjust screen MUST be retired in favour of the inline surface.
   - Acceptance: `ManualCorrectionView.swift` is deleted, the Adjust button leaves the result action row (Done remains), and no route references it; the free-text correction note entry is dropped (notes are now the machine-written serving/portion stamps).
   - Acceptance: any pbxproj references are removed per the four-section checklist in `docs/agent-notes/ui-capture-flow.md`.
6. The redesigned surface MUST follow the existing design system and copy rules.
   - Acceptance: capture palette (`Colors.swift`), sizing/`contentShape` inside Button labels (the dead-pill trap), no reassurance/disclaimer copy, Irish/British spelling (`make spell` clean), monospaced digits for numbers.
   - Acceptance: no ellipsis truncation in portrait on the primary device at default Dynamic Type; row layout survives the longest unit strings ("heaped tablespoons").
   - Acceptance: load the `frontend-design` skill before reshaping the screen — this is a design uplift, not a mechanical swap.

## Execution notes

- Quality gates (repo-root Makefile): `make build`, `make test` (report BOTH totals — XCTest and swift-testing), `make spell`. App target compile check: `xcodebuild -project MeData/MeData.xcodeproj -scheme MeData -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -configuration Debug -derivedDataPath /tmp/medata-debug CODE_SIGNING_ALLOWED=NO build` (codesigning stays disabled — pre-existing raw-mlpackage bundle issue on simulator codesign). Generator tests: run the pytest suite under `tools/food_db/tests/` the way its existing tests run.
- Ordering: the "Food database servings" context lands first — the iOS context consumes its Swift lookup. Implement sequentially on one branch; the two contexts touch disjoint files but the UI cannot be verified without the data.
- Regenerating the databases runs `tools/food_db/generate.py`; the committed sqlite files under `MedataCore/Sources/Foods/Resources/` are the build artefacts and MUST be committed with the generator change (bake-lock conventions in `specs/estimation/nutrition5k-calibration` notes apply — do not touch β values or composition columns).
- The `solid_servings` seed weights marked "verify" could not be confirmed against a free authoritative source (research session 2026-07-17); they ship with honest provenance strings and are data-only to change. Do not block on them.
- The app project only resolves in a checkout literally named `medata` — if a worktree is used for the app context, the app-target build must happen post-merge (precedent: snaq-parity phases).
- Do NOT add app-target tests (`MeData/Tests/` is a documentation contract, not an executable suite). Serving⇄gram conversion arithmetic belongs in MedataCore (Foods or a small pure helper) where the executed suite covers it.
- STOP — on-device looks-right pass on the iPhone 16 Pro (serving steppers ergonomics, fraction control, gram reveal, no truncation) is the user's call after the build lands; the executor verifies to the simulator-build level.
