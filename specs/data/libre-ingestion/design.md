# Design: Libre Ingestion

References: [requirements.md](requirements.md), [decision_log.md](decision_log.md).
Reference implementation: `~/repos/imgdatacollector` (`specs/mvp/design.md` there) — the validated Python pipeline this design ports. Where this document says "per reference", the Python source is normative for algorithm behaviour and constants.

## Overview

Three additive pieces:

1. **`GlucoseGraph`** — a new MedataCore target holding the extraction pipeline: Vision OCR → view classification → axis calibration → trace extraction → 5-minute sampling → wall-clock→UTC conversion. Pure functions over a decoded bitmap; no persistence, no UI, no internal package dependencies.
2. **Persistence additions** — `EventType.bsl`, a `processed_images` table, and a keep-first `ingestBsl` API on `PersistenceStore`/`GRDBPersistenceStore`.
3. **Import UI** — a Settings entry presenting the system photo picker, driving extraction per image off the main actor, and showing the per-image summary.

The estimation pipeline is untouched. Everything runs on-device (Req 1.4).

## Architecture

### GlucoseGraph module

`MedataCore/Sources/GlucoseGraph/`:

| File | Contents (ported from) |
|---|---|
| `TextRecogniser.swift` | `TextBox` (text, top-left pixel rect, confidence); `recognise(cgImage:)` wrapping `VNRecognizeTextRequest` (`.accurate`, no language correction). Converts Vision's bottom-left normalised boxes to top-left pixel coordinates at this boundary, as the reference `ocr.py` does. |
| `Bitmap.swift` | `Bitmap` — width/height plus an RGBA8 buffer with `rgb(x:y:)` accessor. Decoded from `CGImage` by drawing into a `CGContext` whose colour space is **the image's own** (identity transfer — no colour management), so channel values match what PIL's unmanaged decode fed the reference thresholds (Decision 5). |
| `GraphCalibration.swift` | `LinearFit`, `Calibration`, `RejectImage` error; printed-date regex; hour-label row clustering; cumulative hours with midnight wrap; uniformity checks; y-label column filter; least-squares fit with the 3%-of-pitch residual gate and drop-worst retry; axis-tick x-fit refinement (`_find_axis_line`, `_detect_ticks`, `_refine_x_fit`); plot-rect derivation. Ports `graph.py` lines 1–372. |
| `TraceExtractor.swift` | Colour classes (`isOrange`/`isRed`/`isBlack`), in-plot text masking, current-dot detection with ring walk, structural dashed-row removal, column runs with re-join gap, extremum rule. Ports `graph.py`'s trace layer. |
| `Sampler.swift` | `markHours`, `sampleTrace` (half-pitch search window, ≤10-min linear bridging, occlusion omission), rounding to 1 decimal. |
| `GlucoseExtraction.swift` | `Reading(tsUtcMs:value:)`, `Extraction` (view, readings, axisRange, date, dateSource, timezone, warnings); `establishDate`; `hoursToUtcMs`; `dstWarnings`; `weekdayWarnings`; the top-level `extract(cgImage:assetDate:timeZone:)` orchestrator. |

All numeric constants (`_RESIDUAL_GATE = 0.03`, `_X_PITCH_TOLERANCE = 0.2`, `_REJOIN_GAP = 12`, `_DASH_MAX_LEN = 45`, `_DASH_MIN_RUNS = 20`, `_DASH_MIN_COVERAGE = 0.45`, `_MIN_COLUMN_PIXELS = 3`, `_MIN_DOT_AREA = 500`, `_MAX_RING_REACH = 2.2`, `_RING_MIN_COVERAGE = 0.25`, colour-class thresholds, the 0.7 axis-line coverage, tick grouping ≤2 px, 0.4/0.15 px-per-hour tick gates) are copied verbatim with the reference names preserved in comments (Decision 1). Any behavioural deviation discovered during the port is a decision-log entry, not a silent fix.

**Date establishment (differs from reference by design, Decision 3).** The CLI's `--date` flag becomes the photo asset's creation date:

- `daily24h`: printed date (OCR) governs, exactly as the reference. The asset date is used only for the Req 2.6 sanity warning (asset date < printed date).
- `home8h`: the asset creation date's calendar day **in the device's current time zone** is the date of the window's right edge (the home view always ends at "now", which is when the screenshot was taken). Reference AC 2.3 semantics (right-edge date; midnight-crossing marks belong to the preceding day) apply unchanged.
- Asset date resolution order: `PHAsset.creationDate` (via the picker item's `assetIdentifier`) → EXIF/TIFF `DateTimeOriginal` from the image bytes → reject naming the missing date (Req 2.2).
- `date_source` metadata values: `"ocr"` (printed date) and `"asset"` (creation date) — replacing the reference's `"supplied"`.

**Time conversion.** `hoursToUtcMs` mirrors the reference: base = established date minus one day when the window crosses midnight; wall-clock minutes resolved against `TimeZone.current` via `Calendar(identifier: .gregorian)` with that zone. DST check per covered day: UTC offset at 00:00 vs 00:00 next day; difference → Req 3.5 warning string. The IANA zone identifier lands in metadata.

### Persistence additions

```swift
public enum EventType {
    public static let meal = "meal"
    public static let bsl = "bsl"     // blood glucose, value = mmol/L
}

public struct BslReading: Sendable, Equatable {
    public let timestampMs: Int64
    public let value: Double          // mmol/L, one decimal
}

public struct BslIngestSummary: Sendable, Equatable {
    public let extracted: Int
    public let stored: Int
    public let skippedExisting: Int
    public let agreeing: Int                                  // within ±0.3
    public let discrepant: [(timestampMs: Int64, kept: Double, new: Double)]
}

public protocol PersistenceStore {
    // …existing surface unchanged…
    func isImageProcessed(hash: String) async throws -> Bool
    func ingestBsl(readings: [BslReading], metadataJSON: String,
                   sourceHash: String, filename: String) async throws -> BslIngestSummary
}
```

`GRDBPersistenceStore.ingestBsl` is one `queue.write` transaction (GRDB's single-writer queue gives the reference's `BEGIN IMMEDIATE` guarantee for free):

1. `SELECT timestamp, value FROM events WHERE event_type='bsl' AND timestamp IN (…)` — the coverage snapshot.
2. Insert a row (`id` fresh UUID, shared `metadataJSON`) for each reading at an uncovered timestamp; covered timestamps are classified agreeing (≤ 0.3 + 1e-9 tolerance, per reference `_FLOAT_TOLERANCE` so a one-decimal difference of exactly 0.3 stays "agreeing") or discrepant — never written (Reqs 5.2, 5.3).
3. Insert the `processed_images` row in the same transaction (Req 4.5).
4. After commit, `changeBroadcaster.notify()` once, and only when `stored > 0` (Req 4.4).

`isImageProcessed` reads `processed_images` by hash. A rejection happens before `ingestBsl` is ever called, so nothing marks the image processed (Req 5.1).

Schema — `createSchema` gains (and `migrate()` re-stamps version `"4"`; the table DDL matches the reference byte-for-byte):

```sql
CREATE TABLE IF NOT EXISTS processed_images (
    hash         TEXT    PRIMARY KEY,   -- "sha256:<hex>" is stored WITHOUT the prefix here; prefix lives in metadata
    filename     TEXT    NOT NULL,
    processed_at INTEGER NOT NULL
);
```

`metadata` JSON per bsl row (Req 4.2), same keys as the reference:

```json
{"source_hash": "sha256:…", "source_file": "IMG_0570.PNG", "view": "home8h",
 "date": "2026-07-02", "date_source": "asset", "timezone": "Europe/Dublin",
 "axis_range": [3, 21]}
```

`exportArchive` copies the whole SQLite file — bsl rows and `processed_images` ride along with no change, as design-handoff-00 already assumes.

### Pattern extension audit

| Call site | Change |
|---|---|
| `GRDBPersistenceStore.createSchema` / `migrate` | Add `processed_images`; version `"3"` → `"4"`. No DDL on existing tables. |
| `PersistenceStore` protocol | Two additive methods. `eventsDidChange` contract extended to fire on bsl ingest (write path — consistent with "emits after every successful event-row write"). |
| Stub conformers — `PersistenceTests/RetentionSchedulerTests`, `PipelineTests/EstimationFailureTests`, `HarnessCLITests/PipelinePerformanceTests`, `MeData/Tests/MealHistoryModelTests` | Add the two methods as `fatalError("unused")` stubs. |
| `deleteMeal`, `allMeals`, `meal(id:)`, `deleteArtefacts` | No change — already filter on `event_type = meal`, so bsl rows are invisible to them (Req 4.3). |
| `events(in:type:)` | No change — `type: EventType.bsl` already works; its fail-fast metadata JSON check accepts the bsl metadata shape (valid JSON object). |
| `specs/ui/design-handoff-00` (parallel branch) | Consumes `EventType.bsl` + `events(in:type:)`; both exist after this feature. Its DEBUG `seedDemoBslEvents` becomes optional once real import works. Merge coordination only — no shared files beyond `PersistenceStore.swift`/`GRDBPersistenceStore.swift` additions. |

### Import UI

`App/GlucoseImportView.swift` + `App/GlucoseImportModel.swift`:

- Settings gains a "Glucose data" section with an "Import LibreLink screenshots" row opening a sheet hosting the flow (keeps `SettingsView` churn minimal for the parallel redesign).
- `PhotosPicker` (PhotosUI, `photoLibrary: .shared()`) with `matching: .screenshots` preferred filter (falls back to `.images` behaviour on selection — filter is a convenience, not a gate), multiple selection.
- `GlucoseImportModel` (`@Observable @MainActor`) processes items **sequentially** (bounded memory; Vision is itself parallel internally): load `Data` → SHA-256 (CryptoKit) → `store.isImageProcessed` → decode `CGImage` → resolve asset date (`PHAsset.fetchAssets(withLocalIdentifiers:)` → EXIF fallback via `CGImageSourceCopyPropertiesAtIndex`) → `GlucoseGraph.extract` on a background task → `store.ingestBsl` → append an `ImageResult` (filename, outcome, counts, warnings) to the published list.
- Extraction runs via `Task.detached` (CPU-bound; keeps the main actor free); results hop back for UI updates. Cancellation: leaving the sheet cancels the session after the in-flight image completes (per-image transactions make this safe).
- Rejections (`RejectImage.reason`) and store errors render as that image's outcome row; processing continues (Req 1.2).
- Copy: British English; strings pass `make spell`.

## Error Handling

`RejectImage(reason)` is the only expected failure and is per-image (Req 2.5): unknown view, < 2 usable y-labels or bad fit, unestablishable date. Corrupt/undecodable image data → the same per-image failure path with a generic "cannot read image" outcome. Store/transaction errors surface on the image's row and halt nothing else. Warnings (weekday contradiction, asset-before-printed date, DST) attach to the image's summary row and never reject (Req 2.6, 3.5).

## Testing Strategy

New test target `GlucoseGraphTests` with `Resources/corpus/` holding the 9 reference PNGs, their `expected/*.csv` fixtures, and the reading-procedure `README.md` (Req 6.1, Decision 6). The fixture CSV format (`local_time,value`) and reading rules are unchanged from the reference.

| Behaviour | Test |
|---|---|
| Accuracy gate per corpus image (Reqs 6.2, 6.3): ≥95% within ±0.3, max ≤0.6, recall ≥98%, zero readings at fixture-absent marks; prints MAE + max per image | `AccuracyTests`, parameterised over all 9 images — the acceptance test, running in `make test` on macOS (Req 6.4). Fixture local times resolve in Europe/Dublin (the corpus's zone), pinned explicitly so the test passes on any machine. |
| View classification per corpus image; blank/cropped image rejects with reason | unit on `extract` |
| Y-calibration handles 3–21 and 3–27; extrapolates below 3 unclamped (Req 2.4, 3.2) | accuracy test + targeted assertion |
| Date establishment: printed date for 24h; asset date for 8h; EXIF fallback; reject when absent; asset-before-printed warning (Reqs 2.1, 2.2, 2.6) | unit with synthetic inputs |
| Midnight-crossing attribution incl. right-edge-at-00:00 (Req 2.3); 24h half-open 288 marks (Req 3.4) | unit on the time fit with synthetic label boxes |
| DST warning fires for a Europe/Dublin transition day, absent otherwise (Req 3.5) | unit, no image needed |
| `ingestBsl`: keep-first, agreeing/discrepant classification incl. the exactly-0.3 tolerance, single transaction with `processed_images`, notify-once-per-batch, meal rows untouched (Reqs 4.3–4.5, 5.2–5.4) | `PersistenceTests` extension on a temp DB |
| `isImageProcessed`: unprocessed → false; after ingest → true; rejected images never marked (Req 5.1) | `PersistenceTests` |
| Schema: `processed_images` present, version "4" | PRAGMA assertion in existing schema test |

No new app-target test scaffolding (test-gate policy): the import UI is verified by build + on-device pass — pick 2–3 real screenshots, confirm summary counts match the Python tool's output for the same images, confirm Trends-facing `events(in:type:)` returns the rows.
