# Decision Log: Libre Ingestion

## Decision 1: Faithful Port of the imgdatacollector Pipeline

**Date**: 2026-07-04
**Status**: accepted

### Context

The extraction problem (LibreLink screenshots → 5-minute glucose readings) is already solved and validated in the `imgdatacollector` Python repository: a nine-image corpus with hand-read ground-truth fixtures, an accuracy gate (±0.3 mmol/L / ±0.6 max / 98% recall), and thirteen logged decisions covering view classification, calibration, trace extraction, and merge semantics. MeData needs the same capability on-device in Swift.

### Decision

Port the Python pipeline to Swift verbatim: same stage structure, same numeric constants (with reference names preserved in comments), same reject/warning semantics, gated by the same corpus at the same accuracy bar. The Python source is normative; any behavioural deviation found necessary during the port is logged here, never silently applied.

### Rationale

The reference implementation's constants were tuned against the corpus and its decisions record why each threshold sits where it does. Re-deriving them in Swift would repeat that work with new failure modes; porting faithfully and re-running the identical corpus gate is the cheapest way to prove the Swift extractor is the same extractor. Both use Apple Vision for OCR, so recognition behaviour carries across.

### Alternatives Considered

- **Re-implement from the spec only**: Cleaner-room port - Rejected: the load-bearing knowledge is in tuned constants and corpus-driven edge cases (dot ring walk, dashed-row removal), not the prose.
- **Run the Python tool off-device and sync its SQLite**: No Swift port at all - Rejected: violates the in-app, on-device import requirement; a manual desktop step defeats the feature.
- **LLM/vision-model extraction**: Rejected outright: the repo bans LLMs and network calls in data paths, and deterministic extraction is already proven.

### Consequences

**Positive:**
- Accuracy is inherited, not re-earned; the corpus gate catches port regressions mechanically.
- The reference decision log answers "why is this constant 0.45" without re-litigating.

**Negative:**
- Swift code mirrors Python structure in places where a from-scratch Swift design might differ (set-based pixel work becomes buffer loops).
- Two implementations now exist; a future algorithm fix must land in both or the corpora drift.

---

## Decision 2: New `GlucoseGraph` Target with No Internal Dependencies

**Date**: 2026-07-04
**Status**: accepted

### Context

The extraction pipeline needs a home in MedataCore. It uses only Foundation, Vision, CoreGraphics, and ImageIO; it does not touch persistence, contracts, or the estimation pipeline.

### Decision

Create a new SwiftPM target `GlucoseGraph` under `MedataCore/Sources/GlucoseGraph` with no dependencies on other package targets, plus a `GlucoseGraphTests` test target holding the corpus.

### Rationale

Zero internal dependencies keeps the module portable (the Android port re-specifies only the platform binding — here that is Vision/CoreGraphics) and keeps `Persistence` free of image code. It mirrors how the reference tool separates `graph.py`/`ocr.py` from `store.py`.

### Alternatives Considered

- **Fold into `Persistence`**: One fewer target - Rejected: drags Vision/CoreGraphics into the persistence module and tangles two concerns the reference kept apart.
- **Fold into `Segmentation` or `CaptureKit`**: Also image code - Rejected: those serve the estimation path; glucose ingestion is a separate data stream (PROCESS.md §9) with its own cadence.

### Consequences

**Positive:**
- The module is testable in isolation; the accuracy corpus lives beside the code it gates.
- App target consumes it through one `extract` entry point.

**Negative:**
- One more target in an already long `Package.swift`.

---

## Decision 3: Photo Asset Creation Date Replaces the `--date` Flag

**Date**: 2026-07-04
**Status**: accepted

### Context

The reference CLI requires `--date` for 8-hour home views because that view prints no date (its Decision 3). In-app there is no flag, and the non-goals rule out a date-entry UI for the MVP. The 8-hour home view always ends at "now" — and a screenshot's creation instant *is* that "now".

### Decision

For 8-hour views, establish the right-edge date from the photo asset's creation date (`PHAsset.creationDate`, falling back to EXIF `DateTimeOriginal` from the image bytes), interpreted in the device's current time zone. For 24-hour reports the printed date still governs; the asset date only feeds a sanity warning when it precedes the printed date. Reject when no date source is available.

### Rationale

The screenshot creation instant coincides with the graph's right edge by construction, so it carries exactly the information `--date` supplied, with less user friction and less room for typo error. The reference's own Decision 3 anticipated metadata-derived dates as a follow-on once out of CLI constraints.

### Alternatives Considered

- **Date-entry UI per rejected image**: Maximum control - Rejected for MVP: adds a whole interaction surface for a case (stripped metadata) that barely occurs with native screenshots; revisit if rejections show up in practice.
- **Reject all 8-hour views (24h-only import)**: Simplest - Rejected: the home view is the corpus majority and the view users actually screenshot ad hoc.
- **Trust EXIF only (skip PHAsset)**: Fewer Photos API calls - Rejected: the picker's `assetIdentifier` route is the reliable primary source; EXIF is the fallback for items without library identity.

### Consequences

**Positive:**
- Zero-input import for both view types in the normal case.
- `date_source: "asset"` in metadata keeps the provenance auditable.

**Negative:**
- A screenshot whose asset date was edited (or an image shared without metadata) can be rejected or — if edited to a wrong-but-valid date — misdated. Same manual-SQL recovery stance as the reference MVP (non-goal).
- An 8-hour view screenshotted from LibreLink's history scroll (if such exists) would be misdated; the corpus contains no such view.

---

## Decision 4: Keep-First Ingest as a `PersistenceStore` Method, Schema Version 4

**Date**: 2026-07-04
**Status**: accepted

### Context

The reference `store.py` owns dedup (`processed_images`), the keep-first merge, and the per-image transaction against its own SQLite file. In MeData the events table belongs to `GRDBPersistenceStore`, and requirement 4.3 demands ingest never disturbs meal rows.

### Decision

Add `isImageProcessed(hash:)` and `ingestBsl(readings:metadataJSON:sourceHash:filename:)` to the `PersistenceStore` protocol, implemented in `GRDBPersistenceStore` as one write transaction (rows + `processed_images` marker), keep-first with the reference's agreeing/discrepant classification. Add the `processed_images` table to `createSchema` and bump `schema_version` to "4".

### Rationale

The store already owns transactionality, the change broadcaster, and the events DDL; a second database or a parallel writer would fracture the single source of truth the event-log spec just established. GRDB's serialised writer queue provides the reference's `BEGIN IMMEDIATE` concurrency guarantee structurally.

### Alternatives Considered

- **Separate glucose SQLite file**: Mirrors the reference tool exactly - Rejected: defeats the point of the shared event log; Trends would need two readers and export two files.
- **Generic `saveEvents([Event])` API**: More future-proof surface - Rejected: keep-first merge and dedup are bsl-specific semantics; a generic write API would push that logic into the UI layer. A future stream adds its own method with its own semantics, per PROCESS.md §9.
- **No schema version bump**: `CREATE TABLE IF NOT EXISTS` is self-healing - Rejected: the version string exists to label shape changes; a silent shape change is what it guards against.

### Consequences

**Positive:**
- One transaction, one notification, one exported archive; meal paths untouched (they filter on `event_type`).
- Stub conformers advertise the new surface, so test doubles fail loudly if exercised unexpectedly.

**Negative:**
- The protocol grows two methods every conformer must stub.
- Parallel branch (`design-handoff-00`) touches the same two files additively; merge needs care but no redesign.

---

## Decision 5: Decode Pixels in the Image's Native Colour Space

**Date**: 2026-07-04
**Status**: accepted

### Context

The trace-extraction colour thresholds (orange/red/black classes) were tuned in the reference against PIL's decode, which returns the PNG's raw channel values without colour management. iPhone screenshots carry a Display P3 profile; a colour-managed decode into sRGB shifts channel values and would silently move every threshold.

### Decision

Decode the `CGImage` by drawing into a `CGContext` whose colour space is the image's own, yielding the file's raw channel values — the same numbers the reference thresholds saw.

### Rationale

Identity colour space means no conversion, matching PIL byte-for-byte on the corpus. The design-handoff-00 mask loader records the same class of hazard (colour-managed `UIImage` decode remapping label indices); this is the palette-side twin of that lesson.

### Alternatives Considered

- **Colour-managed sRGB decode + re-tuned thresholds**: "Correct" colour science - Rejected: re-tuning forfeits the inherited validation for zero user-visible benefit.
- **Raw `CGDataProvider` bytes**: No draw pass at all - Rejected: pixel format/stride handling per source image is fiddlier than one identity-space draw and saves nothing measurable.

### Consequences

**Positive:**
- Corpus accuracy carries over without threshold work.

**Negative:**
- If LibreLink ever ships screenshots in a wildly different profile, thresholds inherit that risk exactly as the reference does — acceptable, the corpus gate would catch it.

---

## Decision 6: Personal Corpus Committed as Test Resources

**Date**: 2026-07-04
**Status**: accepted

### Context

The accuracy gate needs the nine reference screenshots and their hand-read fixtures. They are the repository owner's personal glucose graphs. Options were committing them, gitignoring them locally, or testing pure maths only. The owner chose committing (session decision, 2026-07-04).

### Decision

Commit the corpus (9 PNGs, 9 fixture CSVs, reading-procedure README) under `MedataCore/Tests/GlucoseGraphTests/Resources/`, and run the full accuracy gate in `make test`.

### Rationale

The gate is only as strong as its availability: a gitignored corpus makes the acceptance test vanish on every other checkout, and pure-maths tests cannot catch OCR- or pixel-level port regressions. The owner explicitly accepted committing personal data to this private repository.

### Alternatives Considered

- **Gitignored corpus, skip-when-absent test**: Keeps personal data out of git - Rejected by owner: CI-invisible coverage.
- **Pure-maths tests only**: No personal data, no images - Rejected by owner: weakest proof of port fidelity.

### Consequences

**Positive:**
- `make test` proves port fidelity on any checkout, forever.

**Negative:**
- ~10 MB of images in the repository; personal medical data in git history (owner-accepted; repo is private).

---

## Decision 7: Sequential Per-Image Processing Behind a Settings Sheet

**Date**: 2026-07-04
**Status**: accepted

### Context

The import UI must fit the current TabView shell while the parallel `design-handoff-00` branch replaces that shell. Extraction is CPU-heavy (per-pixel scans plus Vision OCR) and users may select many screenshots at once.

### Decision

A "Glucose data" section in Settings opens a sheet hosting the picker and results list. Images process strictly sequentially on a detached background task; each image commits independently; the sheet shows per-image outcomes as they land. Closing the sheet cancels after the in-flight image.

### Rationale

Settings is the surface `design-handoff-00` keeps (its Settings sheet lists capture defaults, export, DEBUG seed row), so a self-contained sheet survives the reskin with a one-line entry-point move. Sequential processing bounds memory (one decoded bitmap at a time) and makes cancellation and the per-image transaction story trivial; Vision already parallelises internally, so image-level concurrency buys little.

### Alternatives Considered

- **Concurrent per-image tasks**: Faster wall-clock on many images - Rejected: unbounded decoded-bitmap memory, interleaved summary updates, and racy first-covered-wins merge ordering for overlapping screenshots — for a flow that runs occasionally.
- **Import from the Meals/Data tab**: Nearer the data - Rejected: that tab is being replaced wholesale by the redesign; Settings is the stable seam.

### Consequences

**Positive:**
- Deterministic merge order (selection order); trivially safe cancellation; minimal conflict surface with the parallel branch.

**Negative:**
- Large batches take linearly long; acceptable for a manual, occasional flow with visible per-image progress.
