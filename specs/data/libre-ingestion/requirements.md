# Requirements: Libre Ingestion

## Introduction

FreeStyle LibreLink shows continuous glucose data only as graphs on a phone screen. This feature lets the user pick LibreLink screenshots from their photo library inside MeData and extracts the plotted readings on-device, recording each as a `"bsl"` event row (mmol/L) in the app's long-form event log (`specs/data/event-log-schema/`). It is the importer that `specs/ui/design-handoff-00` anticipates: the Trends chart reads `bsl` events; this feature is what puts them there.

The extraction process is a Swift port of the validated Python reference implementation in the `imgdatacollector` repository (`specs/mvp/` there): Vision OCR → view classification (8-hour home view / 24-hour daily report) → axis calibration → trace extraction → 5-minute sampling → keep-first merge with content-hash dedup. Its accuracy corpus (9 screenshots with hand-read ground-truth fixtures) ports with it and gates this implementation to the same bar.

## Non-Goals

- Medical review, trend analysis, alerting, or any interpretation of the readings. The Trends chart itself is `specs/ui/design-handoff-00` scope.
- CGM/HealthKit/third-party sync; LibreView CSV or API import.
- Any `event_type` other than `"bsl"`; resolution finer than 5-minute intervals.
- Graph sources other than the two LibreLink views in the corpus (8-hour home view, 24-hour daily report).
- Unit conversion (mg/dL) or localisation of any kind — glucose is mmol/L, full stop.
- Reading the screenshot's status-bar clock.
- Deleting recorded readings by source image — recovery from a misdated import is out of scope, as in the reference MVP.
- Recovering trace values occluded by the current-reading marker.
- Automatic/background import; import is always user-initiated from the picker.
- A user-facing date-entry fallback when a date cannot be established (reject instead; see 2.2).

## Requirements

### 1. Import Entry Point and Photo Selection

**User Story:** As a user, I want to pick LibreLink screenshots from my photo library inside MeData, so that my glucose history gets into the app without transcribing anything.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL provide an import entry point in Settings that presents the system photo picker allowing multiple image selection in one session.
2. <a name="1.2"></a>The system SHALL process each selected image independently: a rejected image SHALL NOT prevent the remaining images from processing.
3. <a name="1.3"></a>While an import session is processing, the system SHALL indicate progress, and WHEN the session completes, the system SHALL present a per-image summary naming each image's outcome (stored counts, skips, rejection reason, warnings).
4. <a name="1.4"></a>The system SHALL process images entirely on-device and SHALL NOT transmit image data off the device.

### 2. Graph Recognition and Date Establishment

**User Story:** As a user, I want the app to work out which LibreLink view a screenshot shows and which date it covers, so that readings land at the right instants without me typing dates.

**Acceptance Criteria:**

1. <a name="2.1"></a>WHEN given a 24-hour daily-report screenshot, the system SHALL establish the report date from the printed date in the image and SHALL map the time axis as that date's half-open window [00:00, 00:00 next day).
2. <a name="2.2"></a>WHEN given an 8-hour home-view screenshot, the system SHALL establish the date of the window's right edge from the photo asset's creation date; IF the asset's creation date is unavailable THEN the system SHALL reject the image with a message naming the missing date.
3. <a name="2.3"></a>The system SHALL place the 8-hour view's time axis from the printed hour labels rather than the window edges, and WHEN the window crosses midnight, readings before midnight SHALL be attributed to the preceding calendar day.
4. <a name="2.4"></a>The system SHALL produce correct glucose values for the labelled axis present in the image — including both observed label ranges (3–21 and 3–27) — without per-image configuration.
5. <a name="2.5"></a>IF the view type cannot be identified, the glucose axis cannot be calibrated, or the date cannot be established THEN the system SHALL reject the image with a message naming what failed and SHALL write nothing for that image.
6. <a name="2.6"></a>The system SHALL warn — without rejecting the image — WHEN a legible weekday label contradicts the established date's weekday, and, for a 24-hour view, WHEN the photo asset's creation date precedes the printed date (a screenshot cannot predate its report).

### 3. Trace Extraction and Sampling

**User Story:** As the data owner, I want readings at exact 5-minute marks with absolute timestamps, so that data extracted from many screenshots lines up into one continuous series.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL extract the full plotted trace — including segments rendered in a different colour (e.g. red below-threshold segments) and isolated plotted points detached from the main trace — SHALL exclude non-trace elements (threshold lines, target band, gridlines, surrounding UI), and SHALL omit readings at marks where the current-reading marker occludes the trace.
2. <a name="3.2"></a>The system SHALL record each reading at its plotted value in mmol/L to one decimal place — the plotted value at a mark being the vertical centre of the trace stroke at that mark's horizontal position, or WHERE that position holds multiple disjoint strokes (a turning point), the local extremum of the trace — including values plotted beyond the labelled gridline range, which SHALL NOT be clamped.
3. <a name="3.3"></a>WHERE the trace is absent for a span wider than 10 minutes of axis width (a gap), the system SHALL omit the readings at every 5-minute mark inside the gap and SHALL NOT interpolate across it; WHERE the trace is absent at a mark but the surrounding absence spans 10 minutes or less, the system SHALL record the value interpolated linearly between the adjacent trace ends.
4. <a name="3.4"></a>The system SHALL emit readings only at 5-minute wall-clock boundaries (:00, :05, :10, …) within the graph's time window; a 24-hour window SHALL yield at most 288 marks (right edge excluded).
5. <a name="3.5"></a>The system SHALL convert each wall-clock time to UTC milliseconds since epoch using the device's current time zone; WHEN any calendar day covered by the graph's window contains a DST transition, the system SHALL warn that readings on that day may be offset rather than attempt special handling.

### 4. Event-Log Storage

**User Story:** As a developer, I want each reading stored as one `bsl` event through the app's persistence store, so that glucose lives beside meals in the single source of truth and the UI updates as it does for meals.

**Acceptance Criteria:**

1. <a name="4.1"></a>The system SHALL store each reading through the app's persistence store as one event with a fresh UUID id, `timestamp` at the reading's UTC instant, `event_type` `"bsl"`, `value` in mmol/L, and JSON `metadata`.
2. <a name="4.2"></a>The system SHALL include in each reading's `metadata`: a content hash of the source image, the detected view type, the established date and how it was established, the time zone used for conversion, and the labelled axis range — such that any reading traces back to its image and inputs.
3. <a name="4.3"></a>The system SHALL NOT modify, reorder, or delete any existing event of any type while ingesting; meal rows and their side tables are untouched.
4. <a name="4.4"></a>WHEN an ingest writes at least one event row, the system SHALL emit the store's change notification exactly once for the batch, so that subscribed UI (the Trends chart) refreshes.
5. <a name="4.5"></a>All rows from one image, together with the image's processed marker (Req 5.1), SHALL commit in a single transaction: a failure mid-image SHALL leave no partial rows and no processed marker.

### 5. Duplicate and Overlap Handling

**User Story:** As a user, I want re-processed or overlapping screenshots handled safely, so that existing data is never silently destroyed.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN a submitted image's content is identical to an already-processed image, the system SHALL skip it and report the skip, WHERE already-processed means the earlier processing completed without rejection (a rejected image SHALL NOT count as processed); re-processing any image SHALL never alter stored readings.
2. <a name="5.2"></a>WHEN a new image yields readings for timestamps that already hold stored `bsl` readings, the system SHALL keep the stored readings unchanged and append only readings at timestamps not yet covered.
3. <a name="5.3"></a>WHEN a kept stored reading and the newly extracted value at the same timestamp differ by more than 0.3 mmol/L, the system SHALL report the discrepancy in the import summary without modifying the stored value.
4. <a name="5.4"></a>After processing each image, the system SHALL report how many readings were extracted, stored, and skipped as already present, and — of the overlapping readings — the count agreeing within ±0.3 mmol/L and the count differing by more than 0.3 mmol/L.

### 6. Extraction Accuracy

**User Story:** As the system owner, I want the Swift port held to the reference implementation's measured accuracy, so that porting cannot silently degrade the data.

**Acceptance Criteria:**

1. <a name="6.1"></a>The ground-truth fixtures from the reference corpus (9 images, hand-read per the documented reading procedure) SHALL be committed as test resources together with the reading-procedure document.
2. <a name="6.2"></a>Per corpus image: at least 95% of extracted readings SHALL be within ±0.3 mmol/L of the fixture value, no extracted reading SHALL deviate by more than ±0.6 mmol/L, at least 98% of marks where the fixture records a value SHALL yield an extracted reading, and the accuracy test SHALL report each image's mean absolute error and maximum error.
3. <a name="6.3"></a>The system SHALL NOT emit a reading at any 5-minute mark where the ground-truth fixture marks the trace absent.
4. <a name="6.4"></a>The accuracy gate SHALL run in the standard test suite (`make test`) on macOS.
