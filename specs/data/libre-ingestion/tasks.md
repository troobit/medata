---
references:
    - specs/data/libre-ingestion/requirements.md
    - specs/data/libre-ingestion/design.md
    - specs/data/libre-ingestion/decision_log.md
---
# Tasks: Libre Ingestion

- [x] 1. Add GlucoseGraph + GlucoseGraphTests targets and port the corpus resources <!-- id:14pl0eb -->
  - Package.swift: add GlucoseGraph target (no internal deps) and GlucoseGraphTests test target with Resources
  - Copy 9 corpus PNGs + expected/*.csv + reading-procedure README.md from ~/repos/imgdatacollector/data into MedataCore/Tests/GlucoseGraphTests/Resources/corpus
  - Stream: 1
  - Requirements: [6.1](requirements.md#6.1)

- [x] 2. Port OCR wrapper and bitmap decode (TextRecogniser, Bitmap) <!-- id:14pl0ec -->
  - TextRecogniser.swift: TextBox + recognise(cgImage:) via VNRecognizeTextRequest accurate no-language-correction; bottom-left normalised to top-left pixel conversion at the boundary
  - Bitmap.swift: RGBA8 buffer decoded via CGContext in the image's own colour space (Decision 5)
  - Blocked-by: 14pl0eb (Add GlucoseGraph + GlucoseGraphTests targets and port the corpus resources)
  - Stream: 1
  - Requirements: [1.4](requirements.md#1.4)

- [x] 3. Port calibration layer (GraphCalibration): fits, view classification, plot rect <!-- id:14pl0ed -->
  - LinearFit + least-squares + 3%-of-pitch residual gate with drop-worst retry
  - Printed-date regex; hour-label row clustering; cumulative hours with midnight wrap; uniformity checks; y-label column filter
  - Axis-tick x-fit refinement (_find_axis_line/_detect_ticks/_refine_x_fit) and plot-rect derivation
  - Constants verbatim from graph.py with reference names in comments (Decision 1)
  - RejectImage error with reason strings
  - Blocked-by: 14pl0ec (Port OCR wrapper and bitmap decode (TextRecogniser, Bitmap)), wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper, wrapper
  - Stream: 1
  - Requirements: [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5)

- [x] 4. Port date/time layer: establishDate, hoursToUtcMs, dstWarnings, weekdayWarnings, markHours <!-- id:14pl0ee -->
  - establishDate: printed date for daily24h; asset creationDate (device time zone) for home8h; EXIF DateTimeOriginal fallback; reject when absent; asset-before-printed warning
  - hoursToUtcMs with crossing-window base-day shift
  - dstWarnings per covered day
  - weekdayWarnings with pipe-separator crossing rules
  - markHours: 288 half-open for 24h; observed trace extent for 8h
  - Blocked-by: 14pl0ed (Port calibration layer (GraphCalibration): fits, view classification, plot rect)
  - Stream: 1
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.6](requirements.md#2.6), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5)

- [x] 5. Port trace extraction and sampling (TraceExtractor, Sampler) and extract orchestrator <!-- id:14pl0ef -->
  - Colour classes isOrange/isRed/isBlack; in-plot text masking (confidence >= 0.8; straddling-boundary rule)
  - Current-dot detection: largest near-circular orange blob; core columns; dark-ring outward walk
  - remove_dashed_rows structural filter; column_runs with rejoin gap 12; choose_run_center extremum rule
  - sampleTrace: half-pitch search; <=10-min linear bridge; occluded marks omitted; 1-decimal rounding
  - extract(cgImage:assetDate:timeZone:) orchestrator returning Extraction with warnings
  - Blocked-by: 14pl0ee (Port date/time layer: establishDate, hoursToUtcMs, dstWarnings, weekdayWarnings, markHours)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3)

- [x] 6. Write accuracy gate + unit tests for GlucoseGraph against the corpus <!-- id:14pl0eg -->
  - AccuracyTests parameterised over 9 corpus images: >=95% within 0.3; max <=0.6; recall >=98%; zero readings at fixture-absent marks; prints per-image MAE + max
  - Fixture local times pinned to Europe/Dublin
  - Unit tests: view classification per image; blank image rejects; 3-21 and 3-27 ranges; below-3 extrapolation unclamped; date establishment paths; DST warning; midnight crossing incl. right-edge-00:00
  - Blocked-by: 14pl0ef (Port trace extraction and sampling (TraceExtractor, Sampler) and extract orchestrator), extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract
  - Stream: 1
  - Requirements: [2.4](requirements.md#2.4), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.4](requirements.md#6.4)

- [x] 7. Write PersistenceTests for EventType.bsl, ingestBsl keep-first, isImageProcessed, schema v4 <!-- id:14pl0eh -->
  - Temp-DB tests: keep-first merge; agreeing/discrepant classification incl. exactly-0.3 tolerance (1e-9)
  - Single transaction: rows + processed_images commit together; failure leaves neither
  - eventsDidChange: one tick per batch with stored>0; no tick when stored==0
  - Meal rows and side tables untouched by ingest; events(in:type: bsl) returns ingested rows
  - isImageProcessed false -> true across ingest; rejected images never marked
  - PRAGMA: processed_images present; schema_version 4
  - Stream: 2
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4)

- [x] 8. Implement persistence additions: EventType.bsl, processed_images, ingestBsl, isImageProcessed <!-- id:14pl0ei -->
  - PersistenceStore.swift: EventType.bsl; BslReading; BslIngestSummary (struct not tuple for discrepant entries); two protocol methods
  - GRDBPersistenceStore: createSchema adds processed_images; migrate stamps version 4; ingestBsl one queue.write; notify once when stored>0
  - Metadata JSON written verbatim as supplied by caller
  - Blocked-by: 14pl0eh (Write PersistenceTests for EventType.bsl, ingestBsl keep-first, isImageProcessed, schema v4)
  - Stream: 2
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4), [4.5](requirements.md#4.5), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3)

- [x] 9. Update stub PersistenceStore conformers for the two new methods <!-- id:14pl0ej -->
  - Add fatalError-unused stubs + any exercised implementations in PersistenceTests/RetentionSchedulerTests
  - PipelineTests/EstimationFailureTests
  - HarnessCLITests/PipelinePerformanceTests
  - MeData/Tests/MealHistoryModelTests
  - Blocked-by: 14pl0ei (Implement persistence additions: EventType.bsl, processed_images, ingestBsl, isImageProcessed)
  - Stream: 2
  - Requirements: [4.1](requirements.md#4.1)

- [ ] 10. Build import UI: GlucoseImportModel + GlucoseImportView + Settings entry <!-- id:14pl0ek -->
  - GlucoseImportModel (@Observable @MainActor): sequential pipeline load->sha256->isProcessed->decode->asset date->extract (detached)->ingestBsl->ImageResult; cancellation after in-flight image
  - GlucoseImportView sheet: PhotosPicker (.screenshots preferred; multiple)
  - progress
  - per-image outcome rows incl. rejection reasons + warnings + discrepancy counts
  - SettingsView: Glucose data section with import row; British English copy passing make spell
  - Blocked-by: 14pl0ef (Port trace extraction and sampling (TraceExtractor, Sampler) and extract orchestrator), extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, extract, 14pl0ei (Implement persistence additions: EventType.bsl, processed_images, ingestBsl, isImageProcessed)
  - Stream: 3
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [2.2](requirements.md#2.2), [5.4](requirements.md#5.4)

- [ ] 11. Verify: make test (both totals), make spell, device build; compare 2-3 live imports against the Python tool <!-- id:14pl0el -->
  - make test green reporting BOTH totals (XCTest + swift-testing)
  - make spell clean
  - make build + deploy-device visual pass: import 2-3 real screenshots; compare stored counts/values against imgdata process output for the same images
  - Confirm Trends-facing events(in:type: bsl) returns rows on device (log or debug)
  - Blocked-by: 14pl0eg (Write accuracy gate + unit tests for GlucoseGraph against the corpus), 14pl0ej (Update stub PersistenceStore conformers for the two new methods), 14pl0ek (Build import UI: GlucoseImportModel + GlucoseImportView + Settings entry)
  - Stream: 3
  - Requirements: [6.4](requirements.md#6.4)

- [ ] 12. Regenerate specs/OVERVIEW.md and update docs/agent-notes <!-- id:14pl0em -->
  - Run /specs-overview regeneration
  - docs/agent-notes: new note libre-ingestion.md (module layout
  - corpus provenance
  - port-fidelity rule
  - date-establishment gotchas)
  - Reconcile specs/DECISIONS.md if any decision is cross-cutting
  - Blocked-by: 14pl0el (Verify: make test (both totals), make spell, device build; compare 2-3 live imports against the Python tool), compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against, compare, imports, against
  - Stream: 3
