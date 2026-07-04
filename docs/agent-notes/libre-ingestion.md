# Libre ingestion (GlucoseGraph + bsl events)

Spec: `specs/data/libre-ingestion/`. Reference implementation: `~/repos/imgdatacollector` (Python) — **normative** for algorithm behaviour and constants. Any Swift-side behavioural change must land in a decision-log entry and, ideally, in the Python repo too, or the two corpora drift.

## Layout

- `MedataCore/Sources/GlucoseGraph/` — extraction pipeline, zero internal package dependencies. Public entry point: `GlucoseGraphExtractor.extract(cgImage:assetDate:timeZone:)` → `Extraction`; throws `RejectImage(reason:)`.
- `MedataCore/Tests/GlucoseGraphTests/` — accuracy gate + unit tests. `Resources/corpus/` holds the 9 personal LibreLink screenshots and `expected/*.csv` ground-truth fixtures **copied from imgdatacollector; never edit them to fit output**.
- Persistence: `EventType.bsl`, `BslReading`, `BslIngestSummary`, `isImageProcessed(hash:)`, `ingestBsl(...)` (one transaction: rows + `processed_images` marker; keep-first; notifies `eventsDidChange` once per batch only when `stored > 0`). Schema version is now "4" (adds `processed_images`).
- App: `App/GlucoseImportModel.swift` / `App/GlucoseImportView.swift`, entry row in `SettingsView` ("Glucose data" section). Registered explicitly in `project.pbxproj` (the App/ dir is NOT a synchronized group). `GlucoseGraph` is a **second package product** linked by the app — it is not reachable through the `MedataCore` product (Pipeline does not depend on it, deliberately).

## Gotchas

- **Colour space**: `Bitmap` draws the CGImage into a context using the image's OWN colour space (Decision 5). iPhone screenshots are Display P3; a colour-managed sRGB decode shifts channel values and breaks the tuned orange/red/black thresholds. Never "fix" this to sRGB.
- **Python parity details that matter**: banker's rounding (`pythonRound`/`pythonRound1` mirror Python `round()`), `[y0, y1)` vs inclusive ranges, cluster-by-first-element in `hourLabelRow`. The Swift port reproduces the Python per-image MAE/max **exactly** (verified 2026-07-04: identical to 3 decimals on all 9 images) — treat any parity drift as a port bug.
- **Date establishment** (differs from the CLI by design, Decision 3): 8h home view gets its date from the photo asset's creation date (PHAsset, then EXIF `DateTimeOriginal`, else reject); 24h report uses the printed date only — the asset date cannot substitute (screenshots of day reports happen days later) and only feeds a "screenshot predates report" warning.
- **British spelling lint** applies to identifiers: `centre`, not `center` (`tools/check_spelling.sh` runs over all Swift).
- The accuracy fixtures' local times are pinned to Europe/Dublin inside the test, so `make test` is machine-independent.
- Duplicate-hash `ingestBsl` throws (processed_images PK) and rolls back the whole batch — callers must check `isImageProcessed` first; the test suite relies on this as the atomicity probe.

## Merge coordination (2026-07-04)

`specs/ui/design-handoff-00` (parallel branch) also adds `EventType.bsl` and a DEBUG `seedDemoBslEvents()`; when both are in, keep one `bsl` constant and consider the seeder redundant once real import works. Trends reads `store.events(in:type: EventType.bsl)` — already served by this feature's rows.

## Outstanding

- On-device visual pass of the import flow (device was locked/unavailable at merge time): Settings → Import LibreLink screenshots → pick 2–3 real screenshots → per-image counts should match `imgdata process` output for the same files.
