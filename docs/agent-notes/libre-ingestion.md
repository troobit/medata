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

## Device verification

2026-07-04: import flow run on the iPhone 16 Pro (build stamp `82504b8-…`) by the owner — picker, extraction, and per-image summaries confirmed on device. Same day, after design-handoff-00 round 2 landed (build `db015aa-…`): the real TrendsView rendered the imported series (2,596 bsl rows from 12 images, verified by pulling `Documents/meals.sqlite` off the device via `devicectl device copy from --domain-type appDataContainer`). Root-free log tailing that works: `uvx pymobiledevice3 syslog live` — but ONLY over USB (`usbmux list` must be non-empty; WiFi pairing needs root tunnels). `make logs-device` needs sudo in a real terminal. Note the primary dev device (iPhone 13 Pro Max) was offline; `make deploy-device` needed `DEVICE_UDID=6AD781BA-89FF-5A82-A2A1-B5EC9469F465` and `make logs-device DEVICE_NAME=you` (requires sudo) for that phone.
