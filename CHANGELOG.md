# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added (Smolspec — shutter-blocked-feedback, tasks 1–4)

- `App/LiveIndicatorModel.swift` — `visible: Bool` and `reveal()` / `scheduleHide()` methods. Visibility and the 5 s auto-hide `Task` lift off the badge view onto the model so other code paths (a blocked-shutter tap) can re-reveal the badge without `Binding` ceremony (Decision 3).
- `App/ShutterButton.swift` — optional `onBlockedTap: (() -> Void)?` parameter and a `@State` `blockedTapCount` counter wired through `.sensoryFeedback(.warning, trigger:)`. Static `dispatchTap(state:action:onBlockedTap:)` routes `.ready` taps to `action()`, `.disabled` taps to `onBlockedTap?()`, and drops `.capturing` taps so an in-flight capture is not buzzed/spammed (Decisions 1, 2).
- `App/CaptureFlowModel.swift` — `@MainActor func shutterBlockedTapped()` reveals the indicator and emits one `event=blocked` `Logger.info` line with the full gating snapshot (state name, tilt degrees, target tilt, tilt-in-range, distance cm, LiDAR coverage, supportsLiDAR, canShutter, flowTaskActive, startTaskActive). No state mutation.
- `App/CaptureFlowModel.swift` — symmetric success-path logging on the same `Logger(subsystem: "ie.medata.app", category: "Shutter")`: `event=fired` (in `shutter()` with mode + stage), `event=capture.start` / `event=capture.end` (in `performFlow` with stage + frame dimensions or error type), and `event=estimate.start` / `event=estimate.end` (in `runEstimation` with capture path + meal id or `EstimationFailure` case name) — single Console.app predicate captures the full shutter→result trail (Decision 4).
- `MeData/Tests/LiveIndicatorModelTests.swift` — two Swift Testing cases: `reveal()` after `scheduleHide()` keeps `visible == true` and re-arms the hide task; chained `reveal()` calls cancel the prior hide.
- `MeData/Tests/ShutterButtonTests.swift` — three `dispatchTap` cases asserting `.ready` invokes `action` only, `.disabled` invokes `onBlockedTap` only, and `.capturing` invokes neither.
- `MeData/Tests/CaptureFlowModelTests.swift` — three cases asserting `shutterBlockedTapped()` leaves `state` unchanged across `.initialising`, `.trackingLost`, and `.ready(out-of-range)` and flips `indicators.visible` to `true` when previously `false`.
- `specs/shutter-blocked-feedback/decision_log.md` — Decision 5 documents dropping the `.isNotEnabled` accessibility trait (no such public SwiftUI API exists); `accessibilityValue("Disabled")` already carries the VoiceOver announcement.

### Changed (Smolspec — shutter-blocked-feedback, tasks 1–4)

- `App/LiveIndicatorBadge.swift` — renders `model.visible` directly and routes the existing `onChange` / `onTapGesture` / `onAppear` hooks through `model.reveal()` / `model.scheduleHide()`. The view's `@State visible` and `@State autoHideTask` are removed alongside the now-redundant `.onDisappear { autoHideTask?.cancel() }`.
- `App/ShutterButton.swift` — `.disabled(!state.isInteractive)` removed so blocked taps reach the action closure. Press-gesture guard tightened from `guard state.isInteractive` to `guard state != .capturing`, so the press animation also plays on `.disabled` taps and only `.capturing` keeps the gesture inert (Decision 1, Decision 2).
- `App/CaptureFlowView.swift` — shutter call site now passes `onBlockedTap: { model.shutterBlockedTapped() }`.

### Pending (Smolspec — shutter-blocked-feedback, task 5)

- On-device verification of the success-path trail (`event=fired` → `capture.*` → `estimate.*` → `ResultView`) for both `CaptureMode.single` and `CaptureMode.double`. Test plan and expected log trail captured in `specs/shutter-blocked-feedback/tasks.md` task 5; results to be appended to the decision log under a one-off "Verification Notes" section after the device run.
- `specs/shutter-blocked-feedback/decision_log.md` — "Verification Notes" section opened with the code-side audit (device build green; the five prescribed log sites confirmed in `App/CaptureFlowModel.swift` at the lines required by task 5) and an operator runbook for the Console.app predicate, expected single-/double-mode trails, and failure-mode follow-up rules. On-device observation block left empty pending the device run.

### Added (Research spec — Phase 1 dev-stub segmenter, tasks 76–83)

- `MedataCore/Sources/Segmentation/StubInferenceEngine.swift` — `public struct StubInferenceEngine: SegmenterInferenceEngine` per Req §23.2 / Decision 42. Bypasses image pre-processing and writes per-pixel FP32 logits (`+10` on `dominantClass`, `-10` elsewhere) so the post-processor's softmax places ≥ 0.99 mass on the dominant class. Phase 1 device-MVP runs the full Pipeline against this stub without bundling a `.mlpackage`.
- `MedataCore/Sources/Pipeline/PipelineFactory.swift` — `Pipeline.makeForDevice(store:palette:) throws -> Pipeline` factory selects the inference engine via `#if DEV_STUB_SEGMENTER` (StubInferenceEngine in Debug; CoreMLInferenceEngine in Release, throwing `PipelineFactoryError.segmenterModelMissing` until Phase 3 bundles `food_segmenter.mlpackage`). Constructs `GRDBFoodDatabase.bundled()` and stamps `segmenterSource` accordingly. Includes a `NullCardDetector` placeholder until the Vision-backed detector lands.
- `MedataCore/Tests/SegmentationTests/StubInferenceEngineTests.swift` — seven tests covering deterministic output across runs, input-byte independence, argmax = `dominantClass` for both default (0) and explicit (5) settings, ≥ 0.99 mass + ≤ 0.01 residual per pixel, FP16 HWC row-major byte-layout contract, and the < 50 ms per-view budget from Req §23.2.
- `MedataCore/Tests/PipelineTests/PipelineFactoryTests.swift` — factory smoke test, dev-stub stamping assertion (read via `@testable` internal access to `Pipeline.segmenterSource`), and explicit-init propagation test.
- `MedataCore/Tests/PersistenceTests/PersistenceTests.swift` — three new tests: `segmenterSource` round-trip via the JSON BLOB and the denormalised column for both `dev_stub` and `coreml_v0.1`, idempotent migration adding `segmenter_source` to a legacy pre-task-82 schema with empty-string default, and protobuf-JSON round-trip of the new field.
- `MeData/Tests/ResultViewTests.swift` — three new tests: banner shown for `segmenterSource == "dev_stub"`, absent for `"coreml_v0.1"`, absent for `""`.

### Changed (Research spec — Phase 1 dev-stub segmenter, tasks 76–83)

- `MedataCore/Sources/Pipeline/PipelineEstimator.swift` — protocol gains `mode: CaptureMode` parameter on `estimate(captureResult:mode:)`, fixing the Xcode-only build error where the protocol declared no `mode:` while `CaptureFlowModel` / the App stand-ins passed one. `swift build` did not catch this because it does not link the app target.
- `MedataCore/Sources/Pipeline/Pipeline.swift` — `estimate(captureResult:mode:)` dispatches volume estimation on `mode.capturePath` (authoritative input from §2.3 / Decision 35) and copies it to `MealRecord.capturePath`. Carries a new internal `segmenterSource` stored property stamped onto every produced `MealRecord`. `init` gains a `segmenterSource: String = ""` parameter, back-compatible with existing call sites.
- `MedataCore/Sources/Segmentation/CoreMLSegmenter.swift` — `CoreMLInferenceEngine` exposes a `public static let modelVersion: String = "v0.1"` used by the factory to compose the Phase 3 `coreml_<modelVersion>` stamp.
- `MedataCore/Sources/PortableContracts/Schemas/MealRecord.proto` — added `string segmenter_source = 15` carrying the Phase 1 / Phase 3 segmenter provenance identifier per Req §23.6.
- `MedataCore/Sources/PortableContracts/Generated/*.pb.swift` — regenerated from the updated `.proto` schema via `Schemas/generate.sh` (only `MealRecord.pb.swift` gains the new field; the others are touched by the generator's deterministic emit and are byte-for-byte stable bar trailing whitespace).
- `MedataCore/Sources/Persistence/MealRecord.swift` — added `segmenterSource: String` field plus pb round-trip wiring; `withPhotoAssetID(_:)` preserves the new field.
- `MedataCore/Sources/Persistence/GRDBPersistenceStore.swift` — `meals` schema gains `segmenter_source TEXT NOT NULL DEFAULT ''`; idempotent `migrate(_:)` adds the column to pre-existing DBs alongside the existing `photo_asset_id` migration. `save(_:)` writes the column in addition to the JSON BLOB.
- `Package.swift` — added `.define("DEV_STUB_SEGMENTER", .when(configuration: .debug))` to the `Pipeline` target's `swiftSettings` so Debug builds select the stub and Release builds bind the real Core ML engine. Top-of-file comment now documents both `HARNESS_ENABLED` and `DEV_STUB_SEGMENTER` flags.
- `App/App.swift` — `PendingPipeline` stand-in deleted from the non-UI-test path; production `MedataApp.init` now constructs `try! Pipeline.makeForDevice(store: store)`. The XCUITest seam keeps `StallingPipeline` and renames the immediate-refuse double from `PendingPipeline` to `RefusingPipeline` (scoped to `#if DEBUG`).
- `App/ResultView.swift` — added a top-of-screen, persistent, system-yellow / black-text placeholder banner reading "Placeholder estimate. The food recogniser is a development stub — the carbohydrate value is not a real measurement." (Req §23.3). Visibility is gated on the persisted `record.segmenterSource == "dev_stub"` value, NOT on `#if DEV_STUB_SEGMENTER`, so Phase 1 records still surface the banner when later viewed under a Phase 3 build. New `ResultFormat.showsPlaceholderBanner(segmenterSource:)` and `ResultFormat.placeholderBannerCopy` helpers used by the view and the tests.
- `MedataCore/Tests/PipelineTests/EstimationFailureTests.swift` — `pipeline.estimate(captureResult:)` calls updated to pass `mode:` for the new signature.
- `MedataCore/Tests/HarnessCLITests/PipelinePerformanceTests.swift` — same signature update on both `single` and `double` paths.
- `MeData/Tests/{CaptureFlowModelTests,LiveSampleObserverTests}.swift` — `ProgrammablePipeline`, `StallingPipeline`, and `NoopPipeline` test doubles updated to the new `mode:` signature.
- `MedataCore/Tests/SegmentationTests/CoreMLSegmenterTests.swift` — the existing test-local `StubInferenceEngine` test double renamed to `CannedInferenceEngine` to avoid name shadowing the new public `Segmentation.StubInferenceEngine`.

### Added (Research spec — v1 Adjustments phase, tasks 73–75)

- `App/PhotoLibrarySaver.swift` — new `PhotoLibrarySaver` protocol and iOS `PhotoKitSaver` implementation. Wraps `PHPhotoLibrary.shared().performChanges` and `PHAuthorizationStatus(for: .addOnly)`. Returns the resulting `PHAsset.localIdentifier` or `""` when the user denies the prompt (Decision 37, Req §17.3).
- `MedataCore/Sources/Foods/Resources/cofid_db.sqlite`, `afcd_db.sqlite` — both bundled and read-only per Decision 39. Replace the previous `food_db.sqlite` + `ifcdb_overlay.sqlite` pair.
- `MedataCore/Tests/PersistenceTests/PersistenceTests.swift` — three new tests for `photoAssetID` round-trip via the JSON BLOB and the denormalised column, empty-string handling when add-only authorisation is denied, and `updatePhotoAssetID` stamping an existing meal.
- `MedataCore/Tests/FoodsTests/FoodDatabaseTests.swift` — rewritten to exercise the CoFID-wins COALESCE join, AFCD-only fallthrough, missing-class behaviour, `databaseEdition` composite string, and `entry(for:edition:)` fallback for unknown edition strings.
- `MedataCore/Tests/HarnessCLITests/PipelinePerformanceTests.swift` — single end-to-end soft latency check per Decision 40 / Req §16.1: asserts < 30 s for both `single` and `double` modes on the v1 hardware floor. Skips on macOS — runs only on a tethered iPhone 13 Pro Max under `-D HARNESS_ENABLED`.

### Changed (Research spec — v1 Adjustments phase, tasks 73–75)

- `MedataCore/Sources/PortableContracts/Schemas/MealRecord.proto` — added `string photo_asset_id = 14` carrying `PHAsset.localIdentifier` (Decision 37).
- `MedataCore/Sources/PortableContracts/Schemas/RawFrameMetadata.proto` — `image_filename = 2` marked `reserved`; the original photo lives in the user's Photos library, not the app private container.
- `MedataCore/Sources/PortableContracts/Generated/*.pb.swift` — regenerated from the updated `.proto` schemas via `Schemas/generate.sh`.
- `MedataCore/Sources/Persistence/MealRecord.swift` — added `photoAssetID: String` field plus a `withPhotoAssetID(_:)` helper used by the capture flow to stamp the asset ID returned from PhotoKit on the persisted record.
- `MedataCore/Sources/Persistence/PersistenceStore.swift` — new protocol method `updatePhotoAssetID(mealId:photoAssetID:) async throws`.
- `MedataCore/Sources/Persistence/GRDBPersistenceStore.swift` — schema gains `photo_asset_id TEXT NOT NULL DEFAULT ''`; idempotent `migrate(_:)` adds the column to pre-existing DBs (schema_version bumped to `'2'`). `save(_:)` writes the column and the JSON BLOB; `updatePhotoAssetID` updates both. Existing test stubs (`NoOpPersistenceStore`, `StubPersistenceStore`, harness `NoOpStore`) updated to conform.
- `MedataCore/Sources/Foods/GRDBFoodDatabase.swift` — rewritten to open `cofid_db.sqlite` and ATTACH `afcd_db.sqlite`, with a CoFID-wins `UNION ALL` lookup that falls through to AFCD only for AFCD-exclusive classes. `bundled()` no longer takes an overlay flag. `version` reports the composite `"CoFID 2024 + AFCD 2024"` string used as `MealRecord.databaseEdition`.
- `MedataCore/Sources/Pipeline/EstimationFailure.swift` — `.noLidarDevice` message rewritten to point at the new hardware floor: "MeData requires an iPhone 13 Pro Max running iOS 26.5 or later." (Decision 40).
- `Package.swift` — `Foods` resources updated to copy `cofid_db.sqlite` + `afcd_db.sqlite`.
- `App/App.swift` — `CaptureFlowModel` now constructed with `store` and `PhotoKitSaver` injected; default `databaseEdition` bumped to `"CoFID 2024 + AFCD 2024"`.
- `App/CaptureFlowModel.swift` — accepts `store` and `photoSaver`; after `pipeline.estimate` returns successfully, `saveNadirPhoto(record:frame:)` saves the nadir frame to Photos (denial degrades to `""`), stamps the asset ID on the persisted record via `store.updatePhotoAssetID`, and routes the stamped record into `lastMeal` / `showingResult` / `navigationPath`.
- `App/SettingsKeys.swift` — removed `retentionDays` and `ifcdbOverlayEnabled`; only `captureMode` remains.
- `App/SettingsView.swift` — rewritten: retention picker and IFCDB toggle gone, replaced by static "About macronutrient sources" and "Photos" sections that surface the CoFID + AFCD attributions and explain Photos lifecycle. Archive export retained.
- `HarnessCLI/main.swift` — three call sites updated to use `GRDBFoodDatabase.bundled()` after the overlay flag was removed.
- `MeData/MeData.xcodeproj/project.pbxproj` — added `PhotoLibrarySaver.swift` to the iOS app target's sources and `NSPhotoLibraryAddUsageDescription` to the app's Info.plist build settings.
- `tools/food_db/generate.py` — rewritten to emit `cofid_db.sqlite` and `afcd_db.sqlite` (instead of the old CoFID + IFCDB overlay pair). Includes illustrative AFCD rows that exercise both the CoFID-wins case and the AFCD-only fallthrough.

### Removed (Research spec — v1 Adjustments phase, tasks 73–75)

- `MedataCore/Sources/Foods/Resources/food_db.sqlite`, `ifcdb_overlay.sqlite` — superseded by the bundled CoFID + AFCD pair.
- The per-stage `XCTClockMetric` performance assertions (former tasks 65/66 single-view ≤ 1000 ms and two-view ≤ 1800 ms P95 caps) — replaced by a single end-to-end < 30 s soft check per Decision 40.
- IFCDB overlay toggle and 30 / 90 / 365-day retention picker from the Settings screen.

### Added (Research spec — Harness and Calibration phase, tasks 55–65)

- `HarnessCore/AccuracyHarness.swift`, `BetaCalibrator.swift`, `FixtureLoader.swift`, `FixtureRunner.swift`, `SegBench.swift` — restored as `HarnessCore` SPM library target with every file wrapped in `#if HARNESS_ENABLED ... #endif`. Implements the §6.9 β_c log-residual calibration, §7.3 fixture-driven pipeline runner, §7.3 accuracy harness (MAPE, MAE, per-class breakdown, per-stage latency), and §7.5 segmenter mIoU bench per Decision 41.

### Changed (Research spec — Harness and Calibration phase, tasks 55–65)

- `Package.swift` — added `HarnessCore` library, `HarnessCLI` executable, and `HarnessCLITests` test target. All three define `HARNESS_ENABLED` only in their own `swiftSettings` so the iOS app product (`MedataCore` / `Pipeline`) links zero harness code (Decision 41). `HarnessCLITests` deps expanded to include `Pipeline`, `CardDetection`, `CaptureKit`, `Persistence` to satisfy the landed `PipelinePerformanceTests` imports.
- `HarnessCLI/main.swift` — entire file wrapped in `#if HARNESS_ENABLED ... #endif`.
- `MedataCore/Tests/HarnessCLITests/*.swift` (6 files) — wrapped in `#if HARNESS_ENABLED ... #endif` per Req 21.9.
### Added (UI spec v1.1 — Visual design, tasks 42–53)

- `App/Colors.swift` — full design-system token set per `design-system/MASTER.md` §"Colour tokens" (UI Req §20.1, Decision 16): `captureBackground`, `captureChromeText`, `captureChromeBG`, `captureScrim` (OLED capture/result chrome), `surfacePrimary`, `surfaceElevated`, `textPrimary`, `textSecondary`, `separatorSubtle` (Meals/Settings surfaces), `confidenceHigh`/`Moderate`/`Low` (pill bands), and `placeholderBG`/`placeholderFG` (dev-stub provenance chip). `medataAccent` is now the single source for `#63FF00` and aliased by `confidenceHigh`.
- `App/LiveIndicatorBadge.swift` — single consolidated indicator chip with tilt/distance/coverage sub-elements separated by 8pt hairlines, auto-hide after 5 s of in-range `.ready` state, and re-show on tap or any out-of-range write (Req §20.4). Pure `LiveIndicatorBadgeState` namespace carries the composition + in-range gates so the behaviour is testable without a SwiftUI host. Reduced-motion replaces the fade with snap-to-zero.
- `App/CaptureTopBar.swift` — minimal top chrome (Req §20.3): 40pt `captureChromeBG` capsules for close (`xmark`) and flash/torch (`bolt.fill`/`bolt.slash.fill`). Torch toggle is hidden when the active capture device has no torch, drives `AVCaptureDevice.torchMode` via an injected closure surface that keeps it testable without a real device.
- `App/CaptureModeToggle.swift` — capsule pill with an animated inner `medataAccent` pill (Req §20.5). `@AppStorage("captureMode")` bound to a new `enum CaptureMode { case single, double }` (default `.double`). Disabled `Single` segment on non-LiDAR devices emits the Irish-English no-LiDAR refusal copy. Reduced-motion replaces the `.bouncy` slide with a crossfade.
- `App/ShutterButton.swift` — 76pt outer ring + 60pt inner fill extracted from `CaptureFlowView` (Req §20.6). Press feedback: 100ms inner shrink + ring widen, 150ms `.snappy` release; outer footprint is fixed so the surrounding chrome never shifts during animation. `ShutterButtonState { case ready, capturing, disabled }` drives interactivity and the `accessibilityValue`. `ShutterButtonMetrics` exposes the sizing constants so `CaptureFlowView` can preserve the ≥24pt clearance above the tab bar.
- `App/RefusalSheet.swift` — bottom-sheet refusal surface superseding `RefusalBanner` (Req §20.7). Per-case SF Symbol + short title + verbatim `localisedMessage` + single "Try again" primary CTA. Presented via `.sheet(item: $model.refusal)` with `.presentationDetents([.fraction(0.35)])` and `.presentationDragIndicator(.visible)`.
- `App/ActiveRefusal.swift` — Identifiable wrapper around an `EstimationFailure` + `retryStage` so the refusal sheet can bind via `.sheet(item:)`. `id` derives from the failure case so consecutive renders of the same refusal don't re-present the sheet.
- `MeData/Tests/ColorTokenTests.swift`, `ColourTokenUsageTests.swift`, `ConfidencePillTests.swift`, `LiveIndicatorBadgeTests.swift`, `CaptureTopBarTests.swift`, `CaptureModeToggleTests.swift`, `ShutterButtonTests.swift`, `RefusalSheetTests.swift`, `ResultViewLayoutTests.swift`, `MealRowLayoutTests.swift` — Swift Testing suites covering the new components. `ColourTokenUsageTests` is the CI assertion: a source scan of the v1.1 view files denylists inline `Color(red:)` / `Color(.sRGB)` / `Color(hue:)` patterns and surfaces a per-file token coverage report (Req §20.1).
- `MeData/UITests/CaptureChromeUITests.swift` — XCUITest assertions for the new chrome (Req §20): close button presence, capture-mode pill visibility, shutter armed state when the harness drives `.ready`, and refusal-sheet present/dismiss.

### Changed (UI spec v1.1 — Visual design, tasks 42–53)

- `App/ConfidencePill.swift` — three-tier rendering now uses `Label` with `checkmark.seal.fill` / `exclamationmark.triangle.fill` / `xmark.octagon.fill` SF Symbols alongside the label so the band is distinguishable without colour (`color-not-only` rule). Background reads the token (`confidenceHigh` / `confidenceModerate` / `confidenceLow`).
- `App/ResultView.swift` — restyled per `design-system/pages/photo-tab.md` §"ResultView" (Req §20.2, §20.8, §20.11, §20.12): full-bleed photo via `PHImageManager` dimmed by a `captureScrim` top/bottom gradient; centred carb total at 72pt heavy monospaced (`ResultViewLayout.displayPoints` clamps at 88pt for AX5); confidence pill below; placeholder chip (`placeholderBG`/`placeholderFG`) when `record.segmenterSource == "dev_stub"`; `Retake` outline + `Done` solid action row hidden in `historyDetail` mode. `.contentTransition(.numericText())` falls back to snap-in under reduced motion. Replaces the previous `.justCaptured`-only "New Capture" button.
- `App/MealRow.swift` — feed-style layout per `design-system/pages/meals-tab.md` §"MealRow" (Req §20.9): full-width 4:3 photo with 14pt rounded corners above a caption row (24pt heavy monospaced carb total + `ConfidencePill` + optional placeholder chip), then the timestamp. Thumbnail target is `MealRowLayout.thumbnailTargetSize(rowWidth:)` = 2× row width, not `PHImageManagerMaximumSize`.
- `App/MealsTabView.swift` — `MealListView` hides row separators and uses `surfacePrimary` row backgrounds so the photo + 24pt gap carry the visual separation (Req §20.9).
- `App/CaptureFlowView.swift` — composed against the new chrome (Req §20, Decision 16): `captureBackground` full-bleed, `ARPreviewView` extending edge-to-edge, `CaptureTopBar` via safe area, `LiveIndicatorBadge` between the top chrome and the bottom chrome, `CaptureModeToggle` + `ShutterButton` stacked above the tab bar with the `ShutterButtonMetrics.bottomClearanceFromTabBar` reserved. `.sheet(item: refusalBinding)` presents `RefusalSheet` and routes "Try again" through `model.retry()`. Navigation bar hidden so the chrome is the only top-edge content.
- `App/CaptureFlowModel.swift` — exposes `supportsLiDAR` (relaxed from `private`) and adds `var refusal: ActiveRefusal?` derived from `state` for the bottom-sheet binding, plus a `retry()` alias for the new CTA's call site.
- `MeData/UITests/RefusalFlowUITests.swift` — renamed `testRefusalBannerShowsLocalisedMessageAndTryAgainReturnsToCapturing` → `testRefusalSheetShowsLocalisedMessageAndTryAgainReturnsToCapturing`; comments updated to reference the bottom sheet rather than the superseded top banner (Decision 16). Verbatim `localisedMessage` and "Try again" assertions are unchanged — they still anchor on the shared `refusal.message` / `refusal.tryAgain` accessibility identifiers.
- `MeData/MeData.xcodeproj/project.pbxproj` — wired the seven new `App/*.swift` files (`LiveIndicatorBadge`, `CaptureTopBar`, `CaptureModeToggle`, `ShutterButton`, `RefusalSheet`, `ActiveRefusal`) into the `MeData` target; removed the dead `LiveIndicatorView.swift` and `RefusalBanner.swift` build entries.
- `specs/ui/tasks.md` — marked tasks 42–53 complete via `rune complete`.

### Removed (UI spec v1.1 — Visual design, tasks 42–53)

- `App/LiveIndicatorView.swift` — superseded by `LiveIndicatorBadge.swift` (Req §20.4, Decision 16). The v1.0 three-corner indicator layout is gone.
- `App/RefusalBanner.swift` — superseded by `RefusalSheet.swift` (Req §20.7, Decision 16). The v1.0 top-banner overlay is gone.

### Added (UI spec v1.1 — Tab navigation + Meals tab, tasks 29–41)

- `App/AppRoot.swift` — three-tab `TabView` shell (Photo / Meals / Settings) per UI Decision 15. Owns the shared `CaptureFlowModel` and a `MealHistoryModel`. Tab selection persists across cold launches via `@AppStorage("selectedTab")`; the system Liquid Glass tab-bar material is used as-is (no custom appearance, Req §18.4).
- `App/AppTab.swift` — `enum AppTab: String, Hashable, Sendable { case photo, meals, settings }` used by the shell and `CaptureFlowModel.tabSelectionChanged(to:)`.
- `App/MealHistoryModel.swift` — `@Observable @MainActor` data source for the Meals tab. `start()` loads via `store.allMeals()` and subscribes to `mealsDidChange`; `delete(_:)` routes through `store.deleteMeal(id:)`; `cancel()` ends the subscription deterministically.
- `App/MealsTabView.swift` — Meals tab root with its own `NavigationStack`, the Irish-English empty state (`fork.knife` SF Symbol per Req §19.5), and `MealListView`'s plain `List` with a single trailing swipe-to-delete (Req §19.7, no `.searchable` / `EditButton` / selection per Req §19.8). `.navigationDestination(for: MealRecord.self)` pushes `ResultView(record:, mode: .historyDetail)`.
- `App/MealRow.swift` — `MealRow` view + pure `MealRowFormat` formatter. Renders the timestamp (`dd MMM yyyy, HH:mm` in `en_IE`), rounded carb total, shared `ConfidencePill`, and a yellow "Placeholder" chip when `record.segmenterSource == "dev_stub"` (Req §19.3). Thumbnail comes from `PHImageManager.requestImage(...)` keyed on `record.photoAssetID`; falls back to the `photo.fill` SF Symbol when nil or denied.
- `App/ConfidencePill.swift` — shared three-tier pill rendering extracted from `ResultView` so the Meals row and the just-captured result surface stay visually identical.
- `App/ResultView.swift` — new `ResultPresentation { case justCaptured, historyDetail }` mode parameter. `.historyDetail` hides the "New Capture" action so the Meals → detail push reads as terminal; `.justCaptured` keeps the Photo-tab affordance.
- `App/CaptureFlowModel.swift` — `tabSelectionChanged(to:)` mirrors `scenePhaseChanged(.background)` for non-Photo tabs with one carve-out (Req §1.7, §18.7, Decision 15): when state is `.estimating`, the in-flight `Pipeline.estimate(_:)` is NOT cancelled — it runs to completion and the result lands on next Photo re-entry. `.permissionDenied` and `.refused` are preserved across the switch so the user finds the same surface when they come back.
- `App/CaptureFlowView.swift` — removed the in-capture Settings `NavigationLink` (now reached only via the Settings tab per Req §11.1) and threaded the new `ResultPresentation.justCaptured` mode through `.navigationDestination`.
- `App/App.swift` — `MedataApp.body` now mounts `AppRoot(captureModel:, engine:, store:)` instead of presenting `CaptureFlowView` directly. New `-uitestResetSelectedTab` launch-arg support (DEBUG only, applied before `@AppStorage` is read) so the v1.1 XCUITests start on the Photo tab regardless of prior state.
- `MeData/UITests/TabNavigationUITests.swift` — XCUITest for tab persistence across cold launch (Req §18.6), Meals re-tap pop-to-root (Req §18.5), and the empty-state copy/icon on a fresh container (Req §19.5).
- `MeData/Tests/{MealHistoryModelTests,MealRowTests,CaptureFlowModelTabSelectionTests}.swift` — Swift Testing suites for the new model + row + tab-switch surfaces (tasks 31, 33, 38).
- `MeData/Tests/ResultViewTests.swift` — added `ResultPresentation` mode tests (task 35).
- `MedataCore/Tests/PersistenceTests/MealHistoryStoreTests.swift` — XCTest suite covering `allMeals` ordering and `segmenter_source` round-trip, `deleteMeal` row + artefact directory cleanup with best-effort behaviour, and per-subscriber `mealsDidChange` ticks after `save` and `deleteMeal` (task 29).

### Changed (UI spec v1.1 — Tab navigation + Meals tab, tasks 29–41)

- `MedataCore/Sources/Persistence/PersistenceStore.swift` — additive surface for the Meals tab: `func allMeals() async throws -> [MealRecord]` (sorted by `createdAt` desc), `func deleteMeal(id: UUID) async throws` (drops the SQLite row and the per-meal artefact directory; does NOT touch the user's `PHAsset`), and `var mealsDidChange: AsyncStream<Void> { get }` (per-subscriber, `BufferingPolicy.bufferingNewest(1)`, emitted on every successful write).
- `MedataCore/Sources/Persistence/MealRecord.swift` — added optional SQL-only fields `segmenterSource: String?` and `photoAssetID: String?` with `nil` defaults. Round-tripped via the GRDB store; the protobuf representation is unchanged. Default-nil keeps existing call sites and PB-derived records source-compatible while the Meals tab can carry the dev-stub provenance and Photos-asset id forward.
- `MedataCore/Sources/Persistence/GRDBPersistenceStore.swift` — schema gains `segmenter_source TEXT` and `photo_asset_id TEXT` columns plus `ALTER TABLE` upgrades for existing v1.0 databases. `save` writes the new columns and notifies subscribers; `meal(id:)` and the new `allMeals` read them back. Private `ChangeBroadcaster` fans out `mealsDidChange` ticks across subscribers under a `NSLock`.
- `MedataCore/Tests/PersistenceTests/RetentionSchedulerTests.swift`, `MedataCore/Tests/PipelineTests/EstimationFailureTests.swift`, `MedataCore/Tests/HarnessCLITests/PipelinePerformanceTests.swift` — stub `PersistenceStore` conformers extended with no-op implementations of the new `allMeals`, `deleteMeal`, and `mealsDidChange` members.
- `MeData/MeData.xcodeproj/project.pbxproj` — wired the six new `App/*.swift` files (`AppRoot`, `AppTab`, `ConfidencePill`, `MealHistoryModel`, `MealRow`, `MealsTabView`) into the `MeData` target's `Sources` build phase. Added `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` (Irish-English) to both Debug and Release configs so `PHImageManager` thumbnail fetches surface the standard iOS prompt on first use.
- `specs/ui/tasks.md` — marked tasks 29–41 complete via `rune complete`.

### Added (Agent notes — pipeline factory wiring status)

- `docs/agent-notes/pipeline-wiring-status.md` — records the parked state of the real `Pipeline` factory and the two upstream blockers discovered while scoping it: (1) no segmenter checkpoint exists (training pipeline in `tools/segmenter/` works, but the fine-tuned `.pt` doesn't exist and is days of ML work to produce), and (2) `RawFrame.imageBytes` is unusable for any RGB consumer because `ARKitCaptureEngine.copyPixelBufferBytes` reads `ARFrame.capturedImage` (biplanar YCbCr) as if it were chunky non-planar, and `detectPixelFormat` mis-reports YCbCr as `.bgra8`. Document includes ordered next steps (resolve YCbCr→RGB pipeline first, then train + export segmenter, then wire factory) with acceptance criteria for each, pointers to relevant source locations, and notes on why `VisionCardDetector` is optional on the v1 LiDAR-mandatory hardware floor.

- `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` — `bindPreviewSession` now sets `runRequested = true` before calling `applyRunStateIfNeeded`, so the session config runs synchronously on bind rather than waiting for `CaptureFlowModel.start()` to fire. The previous `bindPreviewSession`-based fix (commit `4b67cbc`) inadvertently re-opened the race that `0e77e94` had closed: `applyRunStateIfNeeded` early-exited on `runRequested == false`, leaving ARView rendering a bound-but-unconfigured session and triggering paired `FigCaptureSourceRemote err=-12784` and `Fig err=-12710` log lines on iPhone 13 Pro Max at launch. The placeholder session remains protected by the `isBound` guard. See `specs/bugfixes/arview-session-config-race/report.md` and `docs/agent-notes/camera-input-fix.md`.
- `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` — `isRunning` flag relaxed from `private` to `internal` so the regression test can assert engine state directly (the iOS Simulator does not reliably set `ARSession.configuration` on `run(_:)` without a real camera).
- `MedataCore/Tests/CaptureKitTests/ARKitCaptureEngineStreamsTests.swift` — added `testBindPreviewSessionRunsConfigImmediately` regression test.

### Fixed (Camera input rendering on iPhone 13 Pro Max)

- `App/ARPreviewView.swift` — added `ensureSessionConfigured()` method called from `makeUIView()` to synchronously configure and run the ARSession before ARView attempts to render. This eliminates a race condition where the view tried to display camera input before the session was initialized, causing FigCapture errors (err=-12710, err=-12784, err=-17281) and blank camera feed.
- `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` — updated `start()` method to check if the session is already configured (e.g., by ARPreviewView) and skip re-running if so, while still supporting LiDAR frame semantics updates. This prevents duplicate initialization and works harmoniously with the view-layer session setup.

### Added (UI spec — end-to-end verification phase, tasks 26–28)

- `MeData/UITests/RefusalFlowUITests.swift` — XCUITest for the refusal flow (task 26, Req 10.1–10.3, 12.1–12.2): drives the flow to a refusal, asserts the banner shows `EstimationFailure.noScaleAvailable.localisedMessage` verbatim, taps "Try Again", and asserts the banner dismisses and capture re-enters `.capturing` at the retry stage.
- `MeData/UITests/BackgroundingUITests.swift` — XCUITest for §8.3 backgrounding (task 27, best-effort per Decision 12): enters `.estimating` via the `stall` pipeline, backgrounds with the Home button, foregrounds, and asserts the UI resets to `.initialising` (UI state only — a `MealRecord` may still persist).
- `MeData/UITests/InterruptionUITests.swift` — XCUITest for AR-interruption recovery (task 28, Req 16.1): emits `.began` on the interruption stream and asserts `.trackingLost`, then `.ended` and asserts recovery to `.initialising`.

### Changed (UI spec — end-to-end verification phase, tasks 26–28)

- `App/App.swift` — added a `#if DEBUG` XCUITest harness (`UITestSupport`, `UITestHarness`, `UITestCaptureEngine`, `UITestControlPanel`) activated by the `-uitest` launch argument. The AR-gated flow can't reach `.ready` on the simulator, so the harness injects a gated `CaptureEngine`, a launch-arg-selected stub pipeline (`-uitestPipeline refuse|stall`), and an interruption `AsyncStream` it owns; hidden accessibility-identified controls drive the model's public commands. Not compiled into release builds.
- `App/CaptureFlowView.swift`, `App/RefusalBanner.swift` — added accessibility identifiers (`shutter`, `hint.{initialising,trackingLost,estimating,capturing}`, `refusal.message`, `refusal.tryAgain`) so the XCUITests can query state.

### Added (UI spec — UI components phase, tasks 12–24)

- `App/CaptureFlowModel.swift` — `@Observable @MainActor` orchestrator conforming to `CaptureFlowDelegate` (tasks 12–13). Implements the full state machine from design.md, the path-hint freeze-at-shutter-tap rule, `Task`-wrapped estimation with `cancelInFlight()`, interruption-stream observation, scene-phase permission re-checks, and no-op delegate conformances (Decisions 9, 11).
- `App/LiveSampleObserver.swift` — `@MainActor` observer iterating `engine.frames`, computing per-frame tilt/distance/coverage via a pure `LiveSampleMath` seam and write-gating on model state (task 15).
- `App/ARPreviewView.swift` — `UIViewRepresentable` over `ARView` with `reassertDelegate()` called from both `makeUIView` and `updateUIView` to keep the engine the sole session delegate (task 17).
- `App/RefusalBanner.swift` — inline refusal-banner overlay rendering `localisedMessage` verbatim; only "Try Again" dismisses it (task 18, Decision 5).
- `App/LiveIndicatorView.swift` — child view rendering tilt/distance/coverage/path indicators from `LiveIndicatorModel` (task 19).
- `MeData/Tests/{CaptureFlowModelTests,LiveSampleObserverTests,ARPreviewViewTests,ResultViewTests}.swift` — Swift Testing suites for the state machine (~18 transition rows plus freeze/debounce/backgrounding/permission/interruption cases), per-frame maths + write-gating, delegate-reassertion guard, and confidence-pill thresholds (tasks 12, 14, 16, 20).

### Changed (UI spec — UI components phase, tasks 12–24)

- `App/CaptureFlowView.swift` — rewritten as the `NavigationStack` root composing the AR preview, live indicators, shutter, refusal overlay, and settings entry, with the permission-denied branch and `MealRecord` navigation destination (task 23).
- `App/ResultView.swift` — rewritten to show rounded total carbs and a three-state confidence pill with an uncertain-estimate Retake prompt below σ 0.60; no per-class breakdown or clinical macros (task 21, Decision 3).
- `App/SettingsView.swift` — added the Export-archive control calling `PersistenceStore.exportArchive()` and presenting `ShareSheet` via `.sheet(item:)` (task 22).
- `MeData/MeData.xcodeproj/project.pbxproj` — wired the new `App/*.swift` files into the `MeData` target.

### Added (UI spec — asset generation phase, task 25)

- `tools/appicon/generate.sh` — renders `static/icon.svg` to all Apple-required AppIcon sizes (40–1024 px) via `rsvg-convert`/`sips` and writes the matching `Contents.json` (task 25, Req 15.2).
- `MeData/MeData/Assets.xcassets/AppIcon.appiconset/icon-*.png` — generated AppIcon PNGs (40, 58, 60, 80, 87, 120, 180, 1024).
- `docs/agent-notes/appicon-pipeline.md` — notes on the icon-generation pipeline.

### Added (UI spec — agent notes)

- `docs/agent-notes/ui-capture-flow.md` — architecture, gotchas, test setup, and the build-path caveat for the `App/` capture flow.

### Added (UI spec — UI building blocks phase, tasks 5–11)

- `App/Colors.swift` — brand colour tokens (task 5, Req 15.1, 9.2): `Color.medataAccent = #63ff00`, plus `confidenceHigh` (= accent), `confidenceModerate` (.orange), and `confidenceLow` (.red) for the result-view confidence pill.
- `App/GatingSnapshot.swift` — `struct GatingSnapshot: Equatable, Sendable` (task 6, Req 4.1, 7.2): carries `pathHint`, `tiltInRange`, `distanceCm`, `lidarCoveragePercent` plus `withPath(_:)` helper. Frozen at shutter-tap to satisfy the design's path-hint freeze rule.
- `App/CaptureState.swift` — nine-case `CaptureState` enum plus `CaptureStage` and `PermissionSubject` sub-enums (task 7, Req 1.6, 5.5, 5.6, 13.3, 16.1). Manual `Equatable` conformance because `CaptureResult` (and its inner `RawFrame`) is not `Equatable`; the `.estimating` case compares case-only.
- `MeData/Tests/CapturePathDeciderTests.swift` — Swift Testing boundary table for `CapturePathDecider.decide` (task 8, Req 4.1): five rows covering (no LiDAR), (LiDAR + 0% / 79.99% / 80% / 100% coverage).
- `App/CapturePathDecider.swift` — pure decider `decide(supportsLiDAR:latestCoveragePercent:) -> CapturePath` (task 9, Req 4.1); returns `.singleViewLidar` only when LiDAR is present and coverage ≥ 80%, else `.twoViewSfS`.
- `App/LiveIndicatorModel.swift` — `@Observable @MainActor final class LiveIndicatorModel` (task 10, Req 2.1, 3.1, 4.1) holding `liveTiltDegrees`, `liveDistanceCm`, `liveLiDARCoveragePercent`. Split from `CaptureFlowModel` per design.md so 60 Hz frame-stream writes don't retrigger `CaptureFlowView.body`.
- `App/ShareSheet.swift` — `UIViewControllerRepresentable` wrapping `UIActivityViewController` (task 11, Req 11.4) for Settings → Export archive.

### Changed (UI spec — UI building blocks phase, tasks 5–11)

- `MeData/MeData.xcodeproj/project.pbxproj` — wired the six new `App/*.swift` files into the `MeData` target's `Sources` build phase (file references under `SOURCE_ROOT` via `../App/...`, matching the existing pattern for `App.swift`, `CaptureFlowView.swift`, etc.).
- `specs/ui/tasks.md` — marked tasks 5–11 complete via `rune complete`.

### Added (UI spec — SPM prerequisites phase, tasks 1–4)

- `MedataCore/Tests/CaptureKitTests/ARKitCaptureEngineStreamsTests.swift` — contract tests for the new `ARKitCaptureEngine` accessors (task 1): delegate identity on init, identical `arSession` instance, delegate preservation after `frames` subscription, interruption ordering (`.began` → `.ended`), cancellation cleanup on both streams, and multi-subscriber fan-out. Guarded with `#if canImport(ARKit) && os(iOS)`. ARFrame end-to-end yield is documented as on-device-only because `ARFrame` has no public initialiser.
- `MedataCore/Sources/Pipeline/PipelineEstimator.swift` — `public protocol PipelineEstimator: Sendable` with `func estimate(captureResult:) async throws -> MealRecord`, plus `extension Pipeline: PipelineEstimator {}` (task 3, Decision 13). Test seam used by `CaptureFlowModel` so unit tests can inject a mock without spinning up the real `Pipeline` / segmenter weights / `FoodDatabase`.
- `static/icon.svg` — brand master logo ported from `main` (task 4, Decision 7); 1024×1024 SVG with `stroke="#63ff00"`, the canonical accent colour consumed by AppIcon generation (task 5) and SwiftUI `Color.medataAccent` (task 25).

### Changed (UI spec — SPM prerequisites phase, tasks 1–4)

- `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` — added three additive public accessors per design §3.1 (task 2): `var arSession: ARSession` (for `ARView` preview binding), `var frames: AsyncStream<ARFrame>` and `var interruptions: AsyncStream<InterruptionEvent>` (both per-subscriber with `BufferingPolicy.bufferingNewest(1)`). Implemented `ARSessionObserver.sessionWasInterrupted/Ended` to feed the interruption stream and extended `session(_:didUpdate:)` to fan out to all frame subscribers alongside the existing single-shot capture continuation. New `public enum InterruptionEvent: Sendable, Equatable { case began, ended }`. The engine remains the sole `ARSessionDelegate`.

### Added (Performance and Cleanup phase — tasks 65–70)

- `MedataCore/Tests/HarnessCLITests/PipelinePerformanceTests.swift` — XCTest P95 latency assertions for single-view (≤ 1000 ms, task 65) and two-view (≤ 1800 ms, task 66) end-to-end pipelines; device-gated with `#if !os(iOS)` + `XCTSkip`; 10-iteration `XCTClockMetric` measurement with synthetic FP16 probability tensors, depth maps, and calibration fixtures built inline.
- `tools/check_spelling.sh` — Irish/British English spelling linter (Req 19.2, task 69); scans `*.swift` files under `MedataCore/Sources`, `HarnessCore`, `HarnessCLI`, and `App`, plus `.xcstrings` catalogs; exits 0 if clean, 1 on violations; ~80 banned US-English words with `\b` word-boundary anchors; respects `REPO_ROOT` env-var override for test isolation.
- `MedataCore/Tests/SpellingLinterTests/SpellingLinterTests.swift` — 23 XCTest cases for `check_spelling.sh` (task 68): rejected US spellings (recognized, color, fiber, …), accepted British/Irish equivalents (recognised, colour, fibre, …), word-boundary edge cases, empty file, and multiple-violation detection; uses `Process` with a temp-dir `REPO_ROOT` wrapper for isolation; macOS-only via `XCTSkip`.
- `legacy/svelte-mvp/` — archived SvelteKit MVP (task 70, Req 1.4): moved from repo root to `legacy/` to make way for the iOS-native project structure.

### Changed (Performance and Cleanup phase — tasks 65–70)

- `MedataCore/Sources/Pipeline/Pipeline.swift` — added `#if DEBUG` OSSignpost instrumentation (`OSSignposter`, subsystem `ie.medata.pipeline`, category `Stages`) across all 8 pipeline stages (task 67, Req 16.5); each stage is wrapped with `beginInterval`/`endInterval` including on throw paths to prevent unclosed intervals in Instruments.
- `Package.swift` — added `Volume`, `CaptureKit`, `SupportPlane`, `Macros` to `HarnessCLITests` dependencies for performance-test fixture construction; added new `SpellingLinterTests` target (no dependencies).
- `README.md` — rewritten to describe the iOS-native project structure (task 70); includes module table, build commands, and CI-script reference.
- `MedataCore/Sources/Persistence/MealRecord.swift` — fixed US spellings in comments: `denormalised`, `serialisation` (Req 19.2).

### Added (Volume Estimation phase — tasks 24–34)

- `MedataCore/Sources/Volume/{VolumeTypes,VoxelCarveEstimator,HeightFieldEstimator,InterClassOcclusionDetector,VoxelGridSizer,MaskMatcher}.swift` — complete Volume module per design §6.6–6.11: shared types (`VoxelGrid`, `BetaCorrection`, `VolumeError`, `VoxelCarveView`/`VoxelCarveEstimate`/`HeightFieldEstimate`/`MaskMatchingResult`) plus internal helpers (`projectCamera1`, `applyMat4`, `signedDistanceToPlane`, `sampleDepthBilinearMm`, `sampleConfidenceUInt8`); two-view voxel-carving estimator with FP32-promoted per-pixel argmax, τ_sil/τ_v thresholds, single-view-only degraded fallback (silhouette extrusion at 30 mm prior height), and β-correction; single-view height-field integrator with 1/cos³θ off-axis pixel-area correction (Decision 29), per-class LiDAR-coverage tracking, and ≥50% coverage enforcement; inter-class occlusion detector (single-pass 4-neighbour scan, 10 mm depth-discontinuity threshold); gravity-aligned voxel-grid sizer with threadgroup-multiple rounding and 360 mm horizontal / 120 mm vertical caps; pure class-equivalence mask matcher producing matched/single-view-only class sets.
- `MedataCore/Sources/Volume/Kernels/voxel_carve.metal` — GPU compute kernel (one thread per voxel, 8×8×8 threadgroups): two-view projection, silhouette test, FP32-product argmax, per-class `atomic_uint` counts, ambiguous-count and silhouette-count accumulators.
- `MedataCore/Sources/Volume/Kernels/height_field.metal` — GPU compute kernel (one thread per nadir-view pixel): off-axis pixel-area integration with fixed-point `atomic_uint` volume accumulator, LiDAR confidence gate, and inline inter-class occlusion detection (4-neighbour scan, satisfies §6.8 Req 13.2 in a single GPU pass).
- `MedataCore/Tests/VolumeTests/{Helpers,VoxelCarveEstimatorTests,HeightFieldEstimatorTests,VoxelGridSizerTests,MaskMatcherTests,VoxelOwnershipDisjointnessTests,InterClassOcclusionDetectorTests}.swift` — 37 new tests: synthetic cube volume within 5% (two-view), silhouette-test exclusion, FP32 promotion winner, ownership disjointness, single-view fallback in `degradedClasses`, τ_v = 0.04 ambiguous discard, `noFoodVolumeRecovered` refusal; flat-food volume within 3% (height-field), off-axis area inflation, coverage-fraction tracking, `lidarCoverageTooLow` refusal; bbox back-projection, multiples-of-8 rounding, gravity-aligned axes, 360 mm cap, centroid origin, summary proto; mask-matcher intersection and symmetric difference; 7-seed PBT for voxel disjointness; 7 occlusion detector cases covering discontinuity thresholds, single class, background boundary, and flat surfaces.

### Changed

- `Package.swift` — added `Volume` library target (depends on `PortableContracts`, `CaptureKit`, `Segmentation`, `SupportPlane`, `MetricScale`) with `.copy("Kernels")` resource bundle; added `VolumeTests` test target.
- `MedataCore/Sources/Volume/VolumeTypes.swift` — added `import Segmentation` to expose `ProbabilityTensor` used by internal helpers.

### Added

- `MedataCore/Sources/Segmentation/{ClassPalette,SegmentationTypes,FP16Bytes,PreProcessing,PostProcessing,CoreMLSegmenter}.swift` — Segmentation module per design §3.5 / §6.5: Swift `ClassPalette` with `Pb*` bridges and `isFoodClass(_:)` that excludes the three special indices; `ProbabilityTensor` / `ArgmaxMap` / `SegmentationResult` Swift wrappers enforcing the portable FP16-LE HWC-row-major byte contract; pre-processing pipeline (canonicalise BGRA8/RGBA8 → RGB8, aspect-preserving letterbox bilinear resize with pixel-centre alignment, ImageNet normalisation, FP16 cast, pad with `(0 − mean[c]) / std[c]`); post-processing pipeline (max-subtracted FP32 softmax, crop letterbox, bilinear resize back to original W × H, argmax → UInt8 label map, σ_seg = mean top-class probability over food pixels per M8 pin, refusal predicate aligned with silhouette test `(1 − q[bg]) ≥ τ_sil` rather than argmax = bg per edge case 3); `SegmenterInferenceEngine` protocol + `CoreMLSegmenter` wrapper taking a string model path (P8) + `CoreMLInferenceEngine` that auto-detects CHW vs HWC input/output layout from the `MLMultiArrayConstraint.shape` so the same wrapper consumes models exported by `coremltools` or `ai-edge-torch` without per-tool code paths; `SegmenterWeightsBudget.validate(at:)` that walks `.mlpackage` directories recursively to enforce Req 8.2 (≤ 10 MB) (research tasks 19, 20, 21, 22).
- `MedataCore/Tests/SegmentationTests/{PreProcessingTests,PostProcessingTests,CoreMLSegmenterTests}.swift` — 22 new tests covering BGRA8 / RGBA8 / RGB8 canonicalisation, letterbox dimension calculation for wide/tall/square aspect, post-normalisation pad-value verification (black input matches pad value), σ_seg exclusion of background / unknown_food / unsupported_liquid, `noFoodPixels` refusal aligned with silhouette test (NOT argmax = bg), refusal-not-triggered when argmax = bg but silhouette holds, perClassMeanProb food-only inclusion, resize-back pixel-centre alignment, string-not-URL model path, portable FP16-LE byte layout regardless of inference backend, pre-processed FP16 buffer wiring, and weights-budget validation for files and recursive `.mlpackage` directories.
- `tools/segmenter/{export.py,requirements.txt,README.md}` — Python export pipeline (research task 23) per Decision 28: torchvision DeepLabV3 + MobileNetV3-Large checkpoint → `coremltools.convert(...)` → `MedataCore/Resources/segmenter.mlpackage` with FP16 compute and weights; same checkpoint → `ai-edge-torch` → TFLite (validation only in v1). ONNX hop bypassed. Reference-image run through both artefacts asserts per-pixel argmax agreement >99% with max-abs logit error <0.05; disagreement fails the export.
- `MedataCore/Resources/README.md` — placeholder + intent for bundled segmenter/database artefacts (Decision 27); heavy artefacts excluded from version control via `.gitignore`.

### Changed

- `Package.swift` — `SegmentationTests` target now depends on `Segmentation`, `CaptureKit`, `PortableContracts`.
- `MedataCore/Sources/Segmentation/Module.swift` — placeholder replaced with a file-map comment for the module's public surface.
- `MedataCore/Tests/SegmentationTests/SegmentationModuleTests.swift` — placeholder test expanded to cover `ClassPalette` `Pb*` round-trip and `isFoodClass` boundary cases.
- `.gitignore` — added segmenter / database build artefacts (`MedataCore/Resources/segmenter.mlpackage/`, `food_db.sqlite`, `ifcdb_overlay.sqlite`, `tools/segmenter/build/`, `tools/segmenter/.venv/`).
- `docs/agent-notes/swift-package.md` — appended a "Segmentation phase is complete" section documenting the new module file map, the σ_seg silhouette-AND-food-argmax filter rule, the FP16 round-trip accuracy tolerance, and the manually-unrolled channel loop in the resize hot path.
- `specs/research/tasks.md` — Segmentation phase tasks 19–23 marked complete.

### Added (Capture and Detection phase)

- `MedataCore/Sources/CaptureKit/{RawFrame,Bridges,CaptureSession,ARKitCaptureEngine,MockCaptureEngine}.swift` — Swift-ergonomic `RawFrame` (Int64 ns timestamps, explicit `PixelFormat`/`ColourSpace`, EXIF-style orientation), Pb-bridge extensions, `CaptureSession` actor with a 200 ms `stop()` ceiling per Req 2.5, an iOS-only ARKit + Core Motion engine that maps `ARConfidenceLevel.{low,medium,high}` to UInt8 `{0,127,255}` and refuses devices without rear LiDAR per Req 1.3, and a `MockCaptureEngine` for tests/HarnessCLI (research tasks 8, 9).
- `MedataCore/Sources/CardDetection/{LinearAlgebra,CardPoseSolver}.swift` — Accelerate-backed SVD wrapper (`sgesvd_` + 3×3 helpers, made `public` so SupportPlane can reuse) and a custom no-OpenCV P4P solver per design §6.1: 8×9 DLT with the −Z-forward sign convention, sign-of-λ enforcement, SO(3) projection with `det(UV^T)` fix-up, edge-on refusal at `|r3·ẑ_cam| < 0.2`, and an SVD numerical-stability gate at σ_min/σ_max < 1e−6 (research tasks 10, 11).
- `MedataCore/Sources/SupportPlane/{SupportPlane,Hash,LiDARPlaneFitter,CardOnlyPlaneFitter}.swift` — `SupportPlane` Swift struct + `BinaryMask`, an FNV-1a-based deterministic seed and `SplitMix64` RNG for the §6.0 reproducibility requirement, a 256-iteration RANSAC fitter per design §6.2 with gravity-bias filtering and inlier-covariance stability gate, and the iterative card-only fixed-point per §6.3 with strict-1mm convergence and best-of-5 fallback (research tasks 13, 14, 15, 16).
- `MedataCore/Sources/MetricScale/MetricScaleResolver.swift` — pure-function symmetric agreement formula per design §6.4 (M4 fix; symmetric in inputs), σ_s clamped to [ε, 1] per Req 13.1, and a `LiDARScaleAdapter.mmPerPx(fromMetresPerPx:)` helper that performs the m/px → mm/px conversion at the resolver boundary per §6.4 (research tasks 17, 18).
- `MedataCore/Tests/CaptureKitTests/{RawFrameTests,CaptureSessionTests}.swift` — 11 new tests covering portable RawFrame/protobuf round-trip, the simd boundary rule, `LidarConfidenceLevel` mapping, and the 200 ms `stop()` budget under both fast and slow engines.
- `MedataCore/Tests/CardDetectionTests/{CardPoseSolverTests,CardPosePropertyTests}.swift` — 10 tests covering noise-robustness (≤1 px → < 2 mm), sign-of-λ, SO(3) properness, cardTooOblique refusal, degenerate H, scale at the card plane, and 400 deterministic property-based round-trip samples in a realistic intrinsics/pose envelope.
- `MedataCore/Tests/SupportPlaneTests/{LiDARPlaneFitterTests,CardOnlyPlaneFitterTests}.swift` — 8 tests covering plane recovery within 1°/2 mm of ground truth, deterministic-seed reproducibility, degenerate-covariance refusal, residual-cap refusal, h_food=0/π_sup-at-card-depth initialisation, 5-iteration convergence, best-of-5 fallback, and iterationDiverged refusal.
- `MedataCore/Tests/MetricScaleTests/MetricScaleResolverTests.swift` — 7 tests covering all four cases of Req 7, symmetric-agreement input-swap invariance, the noScaleAvailable refusal, the LiDARScaleAdapter unit conversion, and σ_s floor/ceiling clamping.
- `Package.swift`, `MedataCore/Sources/{12 modules}/`, `HarnessCLI/main.swift` — Swift Package skeleton per design §2.1 (research tasks 1, 7); twelve module targets plus a macOS executable target and three test bundles, building with `swift build` and `swift test` on macOS 14 / iOS 17.
- `MedataCore/Sources/PortableContracts/Schemas/*.proto` — 27 canonical schemas covering every record that crosses a module boundary per design §4.3 and Decision 31; `generate.sh` regenerates the committed `Generated/*.pb.swift` sources via `protoc-gen-swift` (research tasks 2, 3).
- `MedataCore/Sources/PortableContracts/{Vec3,Mat4,Projection}.swift` — Swift-ergonomic types per design §3.1 with right-handed cross product, column-major Mat4 storage, `−Z`-forward projection, and bridges to/from the generated `Pb*` types (research task 5).
- `MedataCore/Sources/CaptureKit/SimdAdapter.swift` — `simd_float3` ↔ `Vec3` and `simd_float4x4` ↔ `Mat4` conversions, scoped to `CaptureKit` only per the design boundary rule.
- `MedataCore/Sources/CaptureKit/MetalContext.swift` — `@unchecked Sendable` shared device/queue/library context per design §3.1.1; falls back to an empty in-memory library so the lifecycle test runs on hosts without a bundled metallib (research tasks 6, 7).
- `MedataCore/Tests/PortableContractsTests/` — 21 round-trip and convention tests covering protobuf binary, deterministic protobuf-JSON, Vec3/Mat4 conventions, and the `Pb` ↔ Swift bridge (research tasks 2, 4).
- `MedataCore/Tests/CaptureKitTests/` — 5 tests covering simd interop and the MetalContext lifecycle (research tasks 4, 6); skip gracefully when no Metal device is available.
- `.swiftformat`, `.gitattributes` — Swift formatting config and Git LFS rules for fixture artefacts and the bundled segmenter package per task 1.
- `docs/agent-notes/swift-package.md` — agent context note describing the package topology, generated-protobuf naming, and build/test entry points.

### Changed

- `Package.swift` — added three test targets (`CardDetectionTests`, `SupportPlaneTests`, `MetricScaleTests`) for the Capture and Detection phase.
- `.gitignore` — added Swift / Xcode build artefact patterns (`.build/`, `.swiftpm/`, `DerivedData/`, `*.xcodeproj/xcuserdata/`, `Package.resolved`).
- `docs/agent-notes/swift-package.md` — appended a "Capture and Detection phase is complete" section documenting the new modules, key gotchas (−Z-forward DLT signs, FNV-1a vs xxh64, residual-threshold testability), and the next phase's entry point.
- `specs/research/tasks.md` — Foundation phase tasks 1–7 and Capture and Detection tasks 8–18 marked complete.

### Previously added

- `src/routes/capture/+page.svelte` — full capture page wiring: fetch `/api/recognition/status` on mount with skeleton loading state, conditional ManualEntryCTA/MockModeBanner rendering, 10MB client-side image size check, `handleSave()` wired to `POST /api/meals` with Blob Storage image upload (Req 6.4, 11.1, 11.3)

### Added

- `src/routes/capture/page.test.ts` — 7 tests for capture page status detection and conditional rendering: skeleton/loading state, ManualEntryCTA for unconfigured/error states, MockModeBanner for mock mode, recognition path for configured state (Task 22)

### Removed

- `@anthropic-ai/sdk` dependency — removed from `package.json` and `pnpm-lock.yaml` (D-MVR-013)
- `src/lib/services/claude-food-recognition.ts` — old Anthropic SDK-based service (replaced by `HttpRecognitionService`)
- `src/lib/services/food-recognition.ts` — old interface with `LabelContext`, `IFoodRecognitionService` (replaced by `recognition.ts`)
- `src/routes/api/ai/recognise/+server.ts` — old API route (replaced by `/api/recognition/analyse`)

### Changed

- `src/routes/capture/+page.svelte` — updated to call `/api/recognition/analyse` instead of `/api/ai/recognise`, removed label scanning references
- `src/lib/services/index.ts` — removed barrel exports for deleted `food-recognition` and `claude-food-recognition` modules
- Renamed route test files from `+page.test.ts` to `page.test.ts` to fix SvelteKit build compatibility

### Previously added

- `createRecognitionService()` factory in `src/lib/services/recognition.ts` — returns `MockRecognitionService` when `RECOGNITION_MOCK_MODE=true`, `HttpRecognitionService` otherwise
- `recognition.test.ts` — unit tests for `createRecognitionService()` factory (3 tests)
- `/api/recognition/status` endpoint (`src/routes/api/recognition/status/+server.ts`) — returns `{ configured, mockMode }` with fail-safe default on error
- `/api/recognition/status` tests — 5 tests covering configured/unconfigured/mock/error scenarios
- `/api/recognition/analyse` endpoint (`src/routes/api/recognition/analyse/+server.ts`) — POST handler with image size validation, base64→Blob conversion, `RecognitionError` → HTTP status mapping, Irish English error messages (Req 11.4)
- `/api/recognition/analyse` tests — 9 tests covering success, 503/504/422/413/429/502 error codes, and Irish English spelling validation
- `IRecognitionService` interface, `RecognitionError` class, and canonical types in `src/lib/services/recognition.ts` — provider-agnostic recognition layer (D-MVR-013, D-MVR-015)
- `MockModeBanner.svelte` component — amber banner indicating mock mode is active
- `ManualEntryCTA.svelte` component — call-to-action when recognition is not configured
- `CameraCapture.test.ts` — tests for stream cleanup, camera detection via `enumerateDevices`, and gallery upload parity
- Property-based tests for `sumMacros` using `fast-check` — validates macro sum identity, zero totals, and non-negativity invariants
- `MockRecognitionService` implementation (`src/lib/services/mock-recognition.ts`) — returns realistic fake food data with 500–1500ms simulated delay (Req 5.1–5.5)
- `mock-recognition.test.ts` — unit tests for `MockRecognitionService` covering schema, delay, notes prefix, and macro validity
- `MealEditor.svelte` — `mockMode` prop with `MockModeBanner` rendering, error toast with state retention on failed save (Req 5.5, 11.1)
- `src/routes/manual/+page.test.ts` — manual entry flow tests (Req 7.1–7.3)
- `src/routes/+page.test.ts` — logbook display, meal edit/delete tests (Req 8.1–8.5)
- `src/routes/presets/+page.test.ts` — preset save, apply, edit, delete tests (Req 9.1–9.4)
- HTTPS dev server via `@vitejs/plugin-basic-ssl` with LAN binding (`server.host: true`) for mobile camera access (Req 1.1, 1.2)
- Provider-agnostic environment variables: `RECOGNITION_BASE_URL`, `RECOGNITION_MODEL`, `RECOGNITION_API_KEY`, `RECOGNITION_MOCK_MODE`, `RECOGNITION_TIMEOUT_MS`
- Developer setup guide with Ollama, cloud model, and mock mode configuration options
- `HttpRecognitionService` implementation (`src/lib/services/http-recognition.ts`) — OpenAI-compatible `/v1/chat/completions` client with configurable timeout, optional auth, and AbortController support (Req 4.3, 11.2)
- `parseAnalysisResult()` function — validates and extracts `FoodAnalysisResult` from OpenAI-compat response envelopes, handles markdown-fenced JSON and pre-parsed objects
- `http-recognition.test.ts` — 23 unit tests covering `parseAnalysisResult` (JSON extraction, markdown fence stripping, schema validation, error codes) and `HttpRecognitionService` (isReady, auth headers, request shape, timeout, backend errors)

### Changed

- `CameraCapture.svelte` — replaced UA-string detection with `enumerateDevices()` feature detection; added `onDestroy`/`beforeNavigate` stream cleanup (Req 2.4, D-MVR-011, D-MVR-018); gallery-only mode when no camera detected
- `RecognisedFoodItem` no longer extends with `quantity` and `unit` fields (D-MVR-017)
- `FoodRecognitionResult` no longer includes `totalMacros`, `provider`, or `processingTimeMs` fields
- `MealDataSource` type removes `label_scan` value — label scanning deferred (D-MVR-017)
- `RecognisedFoodItemSchema` and `MealDataSourceSchema` updated to match type changes
- `/api/ai/recognise` endpoint response simplified to return only `items` and `confidence`
- `FoodRecognitionResult.svelte` computes totals locally instead of receiving from API
- Dev server now serves HTTPS-only at `https://localhost:5173` (D-MVR-010)

### Removed

- `ANTHROPIC_API_KEY` from `.env.example` — replaced by `RECOGNITION_API_KEY`
- `label_scan` source type from `MealDataSource`, schemas, and UI components
- `quantity`/`unit` display from `FoodRecognitionResult.svelte`
