# Design: Meal Review

## Overview

One review surface replaces `SegmentationReviewView` + `ResultView(.justCaptured)`. It marks detected foods on the photo by outline, permits relabel and reject, keeps the shipped serving/gram controls, and retains one correction record per detected food — predicted values beside corrected ones — in a store that outlives the meal and is never pruned.

## Architecture

### Surface composition

`MealReviewView` replaces both screens on the capture stack. `CaptureRoute` loses `.review`; `runEstimation` pushes `.result` directly (`CaptureFlowModel.swift:841`), satisfying Req 1.2.

`ResultView` is **not** deleted — its `historyDetail` presentation remains the Records/Graph read path (Non-Goal: correcting from Records). Only `.justCaptured` is superseded, so `ResultView.mode` collapses to one case. `onRetake` cannot simply go with it: it is used twice, at `:974` (mode-gated, so that use goes) and at `:930` **inside `veryLowSurface`, which is not mode-gated** — `showsVeryLowSurface` (`:298`) checks only σ and `keepAsIsDismissed`. The retake button there is already inert in history (`onRetake` defaults to `{}`), so `veryLowSurface` is gated to the review path and removed from `historyDetail`, which makes an existing dead affordance explicit rather than changing behaviour. `ResultView.logPill` (`:694`) and its `adjustmentPending` arming (`:356`) are removed from the review path per Req 7.4; corrections apply live.

`MealReviewModel` (`@Observable @MainActor`) owns pending state. The view is composition only, per the `CaptureFlowModel` convention.

**Layout order** (Req 6.6 requires the scale control above the fold; Decision 2 and Decision 9 both note density pressure beyond ~4 foods):

```
photo + outlines          ~40% height, fixed
carb total + confidence pill + corrected marker    (Req 1.4, 8.6)
primary action
scale control             ← must be visible without scrolling (Req 6.6)
─────────── scroll boundary ───────────
accessory line            calibration / liquid / unknown, collapsed to one (Req 1.4, 1.5)
food rows                 name, predicted→corrected when relabelled, amount, ±
```

The accessory signals collapse to a single expandable line so a meal carrying all three does not push the scale control off-screen. The confidence pill sits inline with the total rather than on its own row, for the same reason.

**The very-low-confidence surface owns the fold when it fires.** `ResultView.veryLowSurface` (`:919-953`) is two lines of copy and two 44 pt buttons — roughly 120 pt — and it demands a decision before the estimate is worth correcting. When σ < 0.20 it replaces the scale control above the boundary; Req 6.6's guarantee is suspended in that state, because a retake decision precedes any adjustment. This is the one case `prerequisites.md` cannot treat as a pure layout check.

`placeholderChip` (`:862-870`, fires whenever `segmenterSource == "dev_stub"`) is **not** carried onto the review surface: under `DEV_STUB_SEGMENTER` it would be permanently present in every Debug build, and the segmenter source is already recorded per correction (Req 9.8).

### Correction store

One row per detected food per capture, holding the predicted values and the finally-corrected values side by side. Not an event stream (Req 9.1, 9.3).

```sql
CREATE TABLE IF NOT EXISTS correction_records (
    meal_id         TEXT NOT NULL,
    predicted_class TEXT NOT NULL,
    outcome_id      TEXT,                  -- estimation_outcomes row (Req 8.3)
    created_at      INTEGER NOT NULL,
    updated_at      INTEGER NOT NULL,
    class_corrected INTEGER NOT NULL,      -- independent facts, not one enum: corrections compose
    rejected        INTEGER NOT NULL,
    absent          INTEGER NOT NULL,
    amount_corrected INTEGER NOT NULL,
    record_json     BLOB NOT NULL,
    PRIMARY KEY (meal_id, predicted_class)
);
CREATE INDEX IF NOT EXISTS idx_correction_records_meal ON correction_records(meal_id);
```

The primary key is the natural one, so the millisecond-collision defect in `corrections`' `PRIMARY KEY (meal_id, created_at)` cannot arise here, and a held stepper updates one row rather than appending per repeat — no debouncing is needed for correctness, only the usual UI coalescing to avoid needless writes.

Creation and mutation use different statements. Creation is `INSERT … ON CONFLICT (meal_id, predicted_class) DO NOTHING`; mutation is `UPDATE` against the corrected columns only. Never `INSERT OR REPLACE`: the surface can re-appear for the same meal, and a blanket upsert would reset `created_at`, wipe `corrected`, and overwrite a `predicted` side that Req 9.2 says never changes.

The four boolean columns are denormalised copies of fields inside `record_json`, present so the corpus can be queried and browsed without decoding every blob.

**No eviction, ever (Req 9.9).** No count bound, no age sweep, no pruning. The corpus is the deliverable; a discarded record is a regression that can no longer be run and a training example that no longer exists. This is the one store in the app deliberately exempt from the bounding that `estimation_outcomes` (`GRDBPersistenceStore.swift:940-1010`) and the artefact sweep apply.

Growth is bounded in practice by capture rate. A JSON-encoded record is ~800 bytes (the `jsonString()` encoding `appendCorrection` already uses; proto binary would be roughly a third). At three meals a day averaging four detected foods, that is ~44 k rows and **~35 MB over a decade** — comfortable, but an order of magnitude more than the "single-digit megabytes" an earlier draft claimed. If that ever matters, the lever is encoding, not eviction.

**Cascade break (Req 9.10).** `deleteMeal` (`GRDBPersistenceStore.swift:177`) and `deleteRecords` (`:542`) each `DELETE FROM corrections WHERE meal_id = ?`. `correction_records` gains no such delete. `corrections` keeps its cascade: it is the meal's current display value and a deleted meal has no display value — its retention role is now fully served by `correction_records`, which carries the per-food amounts that `PbUserCorrection.note` previously had to stand in for. The supersession register entry demanding both cascades break predates this store and is withdrawn.

**The Debug reset (Req 9.9).** `deleteAllData()` (`GRDBPersistenceStore.swift:1209`, reached from `SettingsView.swift:243`) enumerates its tables by hand. `correction_records` is **exempt** and must not be added to that list — Req 9.9 admits no deletion path, and the corpus is not test data. The button clears meals, artefacts and the processed-image ledger as it does today.

**Artefact sweep (Req 8.4).** `sweepIfDue()` (`GRDBPersistenceStore.swift:733`) deletes `meals/<id>/` including `mask.png` after 30 days, and has **no production caller** today — only the protocol declaration (`PersistenceStore.swift:330`) and a test stub. The exemption belongs on `deleteArtefacts(olderThan:)` (`:660`), which is what actually removes the directories and is `public` on the protocol (`PersistenceStore.swift:328`), so it must skip meals holding a row with an *actual* correction — `class_corrected OR rejected OR absent OR amount_corrected` — regardless of caller. Not merely "holding a row": every meal holds one, which would make the function an unconditional no-op rather than a retention policy. It must also delete the `meal_artefacts` rows alongside the directory, which it does not do today.

The masks are the storage question, not the records. A `mask.png` is a 1920 × 1440 8-bit indexed PNG (`MaskArtefactWriter.swift:11-13, 31-34`); at three captures a day a decade of them is comfortably an order of magnitude more than the ~35 MB of records, which is why the sweep is a policy worth keeping rather than disabling. A record stays interpretable without its mask (Req 9.11), but the mask is the only pixel-level supervision, so deleting it downgrades a training example rather than destroying it.

### Meal total and corrected names — the reconciling write

Every display surface reads `corrections` for the meal's current value — `MealHistoryModel.swift:81`, `TrendsModel.swift:108`, `RecordsModel.swift:105-121`, `ResultView.swift:1019`, and `MealOverviewView.swift:226`, which composes its own display and is one of only two surfaces that names foods. Each takes the latest row.

**Both stores are written in one `queue.write` transaction on every mutation**, not at `record()`. An earlier draft deferred the `corrections` write to the primary action; a session killed mid-review would then leave the corpus holding a relabel while Records showed the uncorrected total *permanently* — the exact failure Decision 6 rejected its own first draft over, and its "bounded by the review session" claim would be false. `record()` therefore only dismisses.

That write cannot use `appendCorrection` as it stands. It is a plain `INSERT` (`GRDBPersistenceStore.swift:122-137`) into `PRIMARY KEY (meal_id, created_at)` at millisecond granularity, so two mutations in the same millisecond — a held stepper, or a scale tap that rewrites every row — raise a constraint violation. Because both stores share one transaction, that would roll back the `correction_records` write too, and the failure is swallowed (Req 8.5): the corpus would silently lose rows in the one store the spec exists to make lossless.

The review path therefore uses a new `upsertCorrection(mealId:)` writing **one row per meal**, `created_at` fixed at review-session start, `ON CONFLICT (meal_id, created_at) DO UPDATE`. Every reader already takes the latest row (`MealHistoryModel.swift:84`, `TrendsModel.swift:109`, `RecordsModel.swift:111`, `ResultView.swift:1026`, `MealOverviewView.swift:226`), so a single row satisfies them all. `appendCorrection` is untouched for existing callers.

Row *creation* writes `correction_records` only — never `corrections`. Otherwise `isCorrected = !corrections.isEmpty` becomes true for every meal and the Req 8.6 corrected-marker appears on all of them.

`PbUserCorrection` gains one field so a relabelled food is named correctly everywhere (Req 8.7):

```protobuf
map<string, string> corrected_class_ids = 5;   // predicted class id → corrected class id
```

Without it, `ResultView.swift:316-330` and every history row render `record.macros.perClass` keys, so a rice→couscous relabel displays "Rice" for the life of the record. This engages `estimation/pipeline` Req 14.4 (the correction schema is shared verbatim with the future clinical track) — a map with a default of empty is additive and leaves existing readers valid.

**Meal-total rule.** `ResultView.swift:363-367` deliberately totals as *stored total + per-class delta* so historic records do not jump when the database edition changes. The review surface uses the same rule; `Macros.compute` is called per corrected food and its `totalCarbsG` is used only as that food's contribution, never as the meal total.

### Relabel shortlist ordering (Req 3.1)

`perClassMeanProb` cannot serve. `PostProcessing.swift:172-178` increments `perClassCount[cId]` only where `cId` **won the argmax**, so the map contains an entry only for classes already detected on this plate — each of which already has its own row — and the value is the winner's mean confidence, not a candidate posterior. The food the user wants has no entry.

The signal that would serve is the mean probability of every candidate class over each detected class's pixels. That is affordable in principle — the candidate universe is 25 solid classes (`ClassPalette.v2Standard`; `cofid_db.sqlite` `foods` has 33 rows, one per palette class) — but computing it needs a new parallelised pass over the full-resolution tensor after `regulariseLabelMap`, a new message on `PbMealRecord`, a `PaletteMigrator` obligation, and a device measurement on the timed capture path.

**That work is deferred to an estimation-domain spec** (Decision 18), now filed as [`estimation/alternative-class-candidates`](../../estimation/alternative-class-candidates/requirements.md). This spec orders the shortlist by **recency** — foods the user has recently chosen for a food of that kind — and relies on the full eligible list for everything else. On a 25-item universe where the five-item shortlist already covers a fifth of the candidates, ordering is a convenience rather than a functional gate; the design was already conceding recency-only for liquids and for replayed fixtures, which made score ordering a partial answer at best.

`shortlist_source` on the correction record (Req 3.3) names the ordering that produced each shortlist, so corpus rows made under recency ordering stay distinguishable from rows made later under score ordering. Without it, `shortlist_rank` would silently mean two different things.

**The eligible list** (Req 3.4) is 25 solid classes, or 8 liquid ones — a scrollable list, not a search problem. At AX5 it will not fit one screen, so it carries a plain text filter over food names; no index, no ranking, no query beyond the in-memory palette. Note the consequence for Req 5: nearly every real food is outside a 25-class palette, so "not in the database" is the common case rather than the exception, and the absent action is prominent rather than tucked under a search.

### β divide-out (Decision 11, Req 3.5)

β is multiplied into volume during estimation on **both** paths — `HeightFieldEstimator.swift:192` and `VoxelCarveEstimator.swift:214, 230`, all `preCm3 * beta` — so the *persisted* volume is post-β.

The pre-β volume nonetheless already exists in the pipeline: `VolumeEstimate.perClassVolumesPreBetaCm3` (`VolumeTypes.swift:84`), produced by both estimators (`HeightFieldEstimator.swift:190, 197`) and already carried into `PipelineDiagnostics` (`:128`). It simply never reaches the meal record. `VolumeResult.proto` uses fields 1–4, so one additive line persists it:

```protobuf
map<string, float> per_class_volumes_pre_beta_cm3 = 5;
```

```
corrected = preBeta[classId] * beta(newClass)         // BetaCorrection.entries[newClass]
```

An earlier draft instead recovered the pre-β figure as `stored.volumeCm3 / stored.betaUsed`, and needed a refusal path for when `betaUsed` was zero or non-finite. Persisting the value removes the division, the float round-trip it introduced, and that refusal path entirely — and it is a smaller estimation-path change than the candidate matrix this design already makes.

`Macros.compute` is then called with `["<newClass>": corrected]` — the **post-β** volume, because `Macros.compute` never applies β itself; it stamps `betaUsed: entry.beta` and `betaStatus` from the DB row (`Macros.swift:132-133`). That is what carries Req 3.7's calibration indication onto the row for free. It is also passed `liquidClassIds:` and `liquidOverEstimate:` so a liquid's over-read flag is not silently dropped.

**Always derive from `predicted`**, never from a previous corrected value, or repeated relabels compound Float32 drift. `predicted` is immutable (Req 8.1), which makes this checkable.

**The scale control's base** (Req 6.4) is each row's *current derived* mass — post-relabel, pre-user-amount — not the row's first estimate. `ResultView.applyFraction` (`:739`) scales `row.originalGrams` today, which becomes wrong once relabelling exists: scaling the rice mass after the user said couscous discards the re-derivation. A row carrying a user-set mass is scaled from that mass, and its `mass_source` becomes `MEAL_SCALE`.

**Unless the user has already set the amount** (Req 3.6). A user-set mass is a direct assertion; a volume-derived one is an inference. So a relabel after an amount edit keeps the mass and re-derives only carbohydrate from the new food's coefficient, skipping the β and density steps entirely. Without this rule Req 3.6 and Req 6.9 give different masses for the same sequence, and the user's own number silently loses to the model's.

**Where the pre-β volume is absent** — records written before this field exists — the relabel falls back to `stored.volumeCm3 / stored.betaUsed`, and is refused where `betaUsed` is zero or non-finite rather than shipping one class's β on another's figure. Reject, absent-food and amount adjustment stay available in that case.

Note `PaletteMigrator.swift:83-86` already computes `volumeCm3 * rhoNew * betaNew / (rhoOld * betaOld)` — the same derivation. Decision 8's Impact clause requires the recomputation share `Pipeline`'s derivation rather than reimplement it; that obligation now covers three call sites, so the arithmetic belongs in one place in `MedataCore/Sources/Macros/`.

### Overlay: outline replaces fill

`MaskOverlayLoader` decodes the class-index PNG and composites a tinted raster at 0.55 alpha with `.allowsHitTesting(false)` (`:40`). Req 2.1 forbids obscuring the pixels; Req 2.4 requires hit-testing.

The mask is **full camera resolution** — `PostProcessing.swift:123-126` resizes logits back to `originalWidth × originalHeight`, 1920×1440 on device (the 513×513 in `PreProcessing.swift:51` is model input only). Contour extraction at that size is 2.76 M cells per class pass, and the existing decode is already MainActor-isolated with no cache, re-running on every appearance via `.task(id:)`.

So the contour path is specified with the numbers stated:

| Parameter | Value | Reason |
|---|---|---|
| Extraction raster | label map downsampled to ≤512 long edge, nearest-neighbour | ~0.19 M cells; class identity must not be interpolated |
| Minimum area | 0.25% of image | drops speckle the outlines would otherwise trace |
| Simplification | Douglas–Peucker, ε = 1.5 px at extraction scale | staircase polygons otherwise |
| Actor | `nonisolated` decode off the MainActor, result cached by `mealId` | current decode blocks the push transition |
| Emitted for | class ids present in `macros.perClass` | Req 2.8 — thresholded-out classes get no outline |

Each outline carries a small numbered badge at its largest contour's centroid, matching the number on its row. That is the non-colour identity channel Req 2.3 requires and the means by which adjacent foods stay distinguishable under Differentiate Without Colour (Req 2.2) — stroke colour alone cannot satisfy either. A relabelled food's badge row shows predicted→corrected, satisfying Req 3.10's "on the selected marking". A rejected food keeps its outline at reduced stroke weight with its badge struck through and its predicted name on the row (Req 4.2).

Selection dims outside the selected class via an even-odd `Path` (Req 2.5); `Path.contains(_:eoFill:)` gives hit-testing. Canvas is rejected on measurement, not principle: it would need the same `accessibilityChildren` shadow layer either way, so the decision rests on whether ≤25 stroked `Shape` views outperform one `Canvas` — resolved on device, with `Canvas` + shadow layer the fallback if they do not.

Accessibility (Req 2.6, 10.4): `accessibilityChildren` over a shadow `ZStack`, plus `ContentShapeKinds.accessibility` so the focus ring follows the contour rather than a bounding box. Where a class's largest contour is under 44 pt, its row is the hit target (Req 2.4 already makes rows selectable).

**Req 1.5's banner input must survive.** `MaskOverlayLoader.onDecode: (Set<Int>) -> Void` is the sole source of `presentClassIds`, which drives the unknown-region and unsupported-liquid banners (`SegmentationReviewView.swift:22, 30-31`). `unknown_food` and `unsupported_liquid` are never in `macros.perClass`, so the Req 2.8 emission rule would delete the banners' input. `presentClassIds` is retained as an output of the new decode, independent of contour emission.

#### Pattern extension audit — `MaskOverlayLoader` consumers

| Consumer | Needs contour variant? | Rationale |
|---|---|---|
| `MealReviewView` (new) | Yes | Req 2.1, 2.4 — only interactive consumer |
| `MealOverviewView.swift:79-80` | No | Read-only history; keeps the fill path |
| `SegmentationReviewView` | N/A | Deleted |
| `onDecode` / `presentClassIds` | Retained on both paths | Req 1.5 banners |

`MaskOverlayDecoder` gains `contours(from:)` beside the colourise path; neither is removed. Placement: `App/MaskOverlayLoader.swift`, no new file — avoids the four-place `project.pbxproj` registration (`docs/agent-notes/ui-capture-flow.md`).

### Artefact retention (Req 8.2–8.4)

Req 8.2 now scopes to macro re-derivation: per-class volumes, `beta_used`, palette version and database edition, all already in the meal record. Req 8.3 makes re-segmentation explicitly not a retention obligation, with `outcome_id` as the join to a capture bundle where one survives.

Req 8.4 is covered in the store section: the artefact sweep must exempt meals holding a `correction_records` row before it is ever wired up.

## Components and Interfaces

```swift
// App/MealReviewModel.swift
@Observable @MainActor final class MealReviewModel {
    private(set) var foods: [ReviewFood]        // order fixed at init (Req 6.10)
    private(set) var selected: String?
    private(set) var scale: PlateFraction       // Req 6.3 — reuses ResultView.swift:193-203
    var pendingTotalCarbsG: Double { get }

    func select(classId: String?)                          // does NOT open alternatives (Req 2.7)
    func openAlternatives(for classId: String)             // arms the abandonment signal
    func dismissAlternatives()                             // writes PICKER_ABANDONED if unchanged
    func alternatives(for classId: String) -> [FoodCandidate]
    func eligibleFoods(for classId: String) -> [FoodCandidate]   // Req 3.4 — full list

    func relabel(classId: String, to: FoodCandidate) async
    func reject(classId: String) async
    func markAbsent(classId: String, query: String?) async
    func setAmount(classId: String, grams: Double) async   // Req 6, debounced
    func setScale(_ scale: PlateFraction) async            // Req 6.3 — see scale base, below
    func reverse(classId: String) async

    func record() async                                    // dismisses only
    func discard(reason: DiscardReason) async              // retake | delete → CAPTURE_ABANDONED
}

struct ReviewFood {
    let classId: String                 // immutable identity; survives relabel, keeps the mask join
    let predicted: FoodDerivation       // never mutated (Req 8.1, 9.2)
    var corrected: FoodDerivation?      // nil until any dimension is corrected
    var flags: CorrectionFlags          // classCorrected / rejected / absent / amountCorrected /
                                        // pickerOpenedUnchanged / wasReverted — independent, composable
    var massSource: MassSource          // none | perFood | mealScale
}
```

**Visual conformance** (Req 10.1, 10.2): rows adopt `IntakeView`'s grouped-row metrics — `RoundedRectangle(cornerRadius: 12)` on an elevated surface, 12 pt vertical padding, `.headline` over `.caption.monospacedDigit()` — restated against the capture palette (`captureChromeBG`/`captureChromeText`) rather than the grouped one. Colour comes from `App/Colors.swift` tokens only; the `Color(uiColor: .systemOrange)` sites the review path inherits (`SegmentationReviewView.swift:104`) resolve to `confidenceModerate`, which is the same colour.

**Contracts.** Mutators are `async` because the store is (`PersistenceStore.swift:365`); each upserts its `CorrectionRecord` and the reconciling `PbUserCorrection` in one transaction before returning (Req 9.4). Each is idempotent per (classId, resulting state) — repeating a relabel to the same target is a no-op write. Persistence failure is logged and swallowed, never surfaced (Req 8.5), per the `MaskArtefactWriter` precedent.

`classId` stays the identity key after a relabel, which is why relabelling two foods to the same target does not merge their rows, and why `predicted.class_index` remains a valid mask join.

**Record lifecycle** (Req 9.1, 9.5). One row is created per detected food when the review surface appears, in state `UNCHANGED` — not deferred to `record()`, so a capture abandoned before the primary action still yields a full set.

Creation is `INSERT OR IGNORE`, never an upsert. The surface can appear more than once for the same meal — `CaptureFlowView.swift:83-87` resyncs `showingResult` when the stack is popped by back-gesture — and a second creation must not reset `created_at` or, worse, overwrite a `predicted` side that Req 9.2 says never changes. Only the mutators write, and they touch the `corrected` side and `state` only.

`dismissAlternatives()` sets `pickerOpenedUnchanged` where nothing changed; any subsequent change to that food clears it, or a food that was hesitated over and then corrected would be counted as both. Decision 5 rests specifically on that signal, so it has to mean only what it says.

`discard()` sets `captureAbandoned` across every row of the meal. It is a per-meal fact held per-row deliberately: a row must stay interpretable after its meal is deleted (Req 9.10), so there is no meal-scoped row left to carry it.

Reversal is **per correction dimension, not per row**. Reversing a relabel (Req 3.11) restores `corrected.class_id` to `predicted.class_id` and re-derives carbohydrate, leaving any user-set mass in place; reversing a rejection (Req 4.3) restores the contribution. Only when no dimension remains corrected does `corrected` go unset — and `was_reverted` is set, so a rejected-then-un-rejected food is distinguishable from a confirmed correct prediction rather than contaminating the per-class precision numerator Decision 5 exists to enable. A blanket "unset `corrected`" would discard a co-existing amount edit that no requirement says to discard — set 180 g, relabel, reverse the relabel, and the 180 g would vanish from both the screen and the corpus. Intermediate values within a dimension are still not retained (Req 9.3).

**Browse and export** (Req 9.13): `EstimationLogView` gains a corrections section reading `correction_records`, and a JSONL export beside its existing share-sheet path. `exportArchive()` shipping raw SQLite does not satisfy Req 9.11's "interpretable as a training example without the app".

## Data Models

```protobuf
message FoodDerivation {                // the same shape on both sides
    string class_id = 1;
    uint32 class_index = 2;             // locates the food in the stored mask (Req 9.12)
    double volume_cm3 = 3;              // post-β, as stored
    double volume_pre_beta_cm3 = 4;
    double beta_used = 5;
    BetaCalibrationStatus beta_status = 6;  // beta_used == 1.0 is ambiguous without this
    double density_g_per_cm3 = 7;       // carried, not looked up (Req 9.11)
    double carbs_per_100g = 8;          // per 100 g edible portion, as CoFID defines it
    string density_source = 9;          // provenance: measured or assumed
    string coefficient_source = 10;
    double mass_g = 11;
    double carbs_g = 12;
}

message CorrectionRecord {
    string schema_version = 1;
    string meal_id = 2;
    string outcome_id = 3;              // → estimation_outcomes → capture bundle where it survives
    int64  created_at_ms = 4;
    int64  updated_at_ms = 5;

    string palette_version = 6;         // Req 9.12 — absent from PbMealRecord
    string database_edition = 7;
    string segmenter_source = 8;        // Req 9.8 — excludes dev_stub from exports
    string build_stamp = 9;

    FoodDerivation predicted = 10;      // never mutated (Req 9.2)
    FoodDerivation corrected = 11;      // updated in place (Req 9.3); unset when unchanged

    // Independent facts, not a single state enum — a food can be both
    // relabelled and amount-corrected, and one enum cannot say so.
    bool   class_corrected = 12;
    bool   rejected = 13;
    bool   absent = 14;
    bool   amount_corrected = 15;

    bool   picker_opened_unchanged = 16; // Req 9.5 — the shortlist-failing signal
    bool   capture_abandoned = 17;      // Req 9.5 — retaken or deleted
    MassSource mass_source = 18;        // NONE | PER_FOOD | MEAL_SCALE — see below
    int32  shortlist_rank = 19;         // 1-based; 0 = no relabel (Req 9.7)
    string shortlist_source = 21;       // Req 3.3 — "recency" now, "score" after the
                                        // estimation-domain candidate matrix lands
    string absent_query_text = 20;      // Req 5.2
}
```

Four independent booleans replace a single `state` enum because corrections compose: a food can be relabelled *and* amount-corrected, and one enum cannot represent that. It also keeps "left unchanged" readable — Req 6.3's whole-meal scale writes a mass to every row, so a single scale tap would otherwise leave an entire meal in `UNCHANGED`, contaminating exactly the per-class confirmations Decision 5 depends on.

`mass_source` distinguishes those cases. "I ate three quarters of the plate" and "the segmenter over-traced this potato" are opposite signals; collapsing both into one ratio makes the boundary-error proxy meaningless. The ratio itself is not stored — it is `corrected.mass_g / predicted.mass_g`, both already in the record, and a stored copy could disagree with its own inputs.

`shortlist_rank` is 1-based with 0 meaning "no relabel", because proto3 scalars default to 0: a `-1` sentinel would make "no relabel" indistinguishable from "picked the first shortlist entry", which is the most common relabel and the most important signal for evaluating the shortlist.

**The corrected side by state:**

| State | `corrected` |
|---|---|
| Unchanged | unset |
| Relabelled | full derivation for the chosen food |
| Rejected | present, class unchanged, `mass_g` and `carbs_g` zero — so a rejection is a readable training example, not an absence |
| Absent | present, `class_id` empty, density and coefficient copied from `predicted`, mass as the user left it |

`PbPerClassMacros` carries `volumeCm3`, `massG`, `carbsG`, `betaUsed`, `betaStatus`, `densitySource` and `coefficientSource` but **no density and no carbs-per-100g**. Both are derived arithmetically from the stored figures — `ρ = mass_g / volume_cm3`, `κ = 100 · carbs_g / mass_g`, guarding zero — never re-looked-up from the database. A fresh lookup would reintroduce exactly the drift Decision 16 rejects, on the side Req 9.2 says never changes; the derivation records what was *applied*, not what the database says today.

`beta_status`, `density_source` and `coefficient_source` are carried because a row that discards how trustworthy its own coefficients are is not the self-contained training example Req 9.11 asks for — and `beta_used == 1.0` is otherwise indistinguishable from an uncalibrated class. Fields are `double` to match the app's own arithmetic (`Macros.compute`, `pendingTotalCarbsG`), so the corpus value equals the displayed one. `FoodDerivation` carries **density and carbohydrate coefficient, not just the resulting figures**. That is what makes a row a self-contained training example: it can be read without the app, without the food database pinned at the edition that produced it, and without the mask (Req 9.11). `class_index` is stored alongside `class_id` because the mask is an 8-bit index raster (`MaskArtefactWriter`) and resolving a name to an index otherwise needs the in-app palette table.

Both sides share one message so predicted and corrected are diffable field-by-field without special-casing, and so a future estimator change can be evaluated against either.

Denormalisation throughout is deliberate — a record must stay readable after its meal is gone (Req 9.10).

## Error Handling

| Condition | Behaviour |
|---|---|
| `betaUsed` ≤ 0 or not finite | Relabel refused; diagnostic event written. Reject, absent and amount stay available. |
| Chosen food lacks density or coefficient | Filtered from alternatives and the eligible list (Req 3.8), so unreachable at relabel time. |
| Detected food is a liquid | Alternatives limited to liquid classes, recency-ordered (Req 3.9). |
| Correction write fails | Logged, swallowed; meal recording unaffected (Req 8.5). |
| Mask artefact missing | No outlines, no banners; rows and total render; relabel and reject work from rows (Req 1.6). |
| Photo unavailable | Rows and total render without the photo (Req 1.6). |
| Every food rejected | Total 0 g, recordable (Req 4.4). |

## Testing Strategy

Per CLAUDE.md the app-target gate is build + device; no new app-target scaffolding. Three MedataCore tests, where the logic is pure:

1. **β re-derivation equality.** `relabel(rice → couscous)` on a stored `PerClassMacros` produces a `PerClassMacros` identical to `Macros.compute(["couscous": preBeta * beta_couscous], …)`. This is Decision 11's stated invariant and catches a factor inversion. A deterministic equality, not a property test — the earlier property-based round-trip tested IEEE-754 over a β range outside the real domain of (0, 1].
2. **Cascade.** `deleteMeal` removes the meal and its artefacts and leaves `correction_records` intact. This is the regression test for the defect the spec exists to fix.
3. **Row identity.** Repeated corrections to one food leave exactly one row, with `predicted` byte-identical to its first write and `corrected` reflecting only the latest change (Req 9.2, 9.3). Includes the re-presentation case: creating rows twice for the same meal must not reset `created_at` or clear a correction already made.

Alternatives ordering is deferred until the candidate matrix lands. Interaction-cost bounds (Req 7.5–7.8), contrast (Req 10.3), Dynamic Type to AX5 (Req 10.6), Reduce Transparency (Req 10.5) and the Req 6.6 above-the-fold constraint are device-verified in `prerequisites.md`.
