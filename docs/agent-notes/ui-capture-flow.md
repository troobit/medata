# UI capture flow (App/)

> **Post-capture flow re-merged by `specs/ui/meal-review/` (2026-08-09, superseding
> design-handoff-00 §5 and the capture-step Result; implemented on the App side in the
> same cycle).** The two-screen split — `SegmentationReviewView` then
> `ResultView(.justCaptured)` — is replaced by one review surface (`MealReviewView` +
> `MealReviewModel`, both registered in the four pbxproj places): `CaptureRoute` is the
> single `.result` case, estimation completion pushes the surface directly,
> `SegmentationReviewView` is deleted, and `ResultView` serves only the Records/Graph
> history read path (the `ResultPresentation` enum, `onRetake`, and the very-low retake
> surface are gone from it — the very-low surface lives on `MealReviewView`, where it owns
> the fold below σ 0.20). The surface permits relabel, reject, absent-food and amount
> corrections; each is persisted per detected food in the **`correction_records`** table
> the moment it is made (mutators call `updateCorrectionRecord(_:upsertingCorrection:)` so
> the corpus row and the reconciling `corrections` row share one transaction; amount edits
> debounce the store write 500 ms per food; `discard()` stamps `capture_abandoned` with NO
> corrections upsert so an abandoned meal never gains the corrected marker).
> **`correction_records` is the one store exempt from every deletion path** — no
> `deleteMeal`/`deleteRecords` cascade, no age or count bound, excluded from the artefact
> sweep's reach, and **must never be added to the Settings Debug reset
> (`deleteAllData()`)** — the corpus is the deliverable, not test data (meal-review
> Req 9.9/9.10, Decision 16). The four-place `project.pbxproj` registration checklist below
> still applies to any new `App/` file (e.g. `MealReviewView.swift`,
> `MealReviewModel.swift`). Mentions of `CaptureRoute` "(review/result)" and the
> `SegmentationReviewView` "Carbs" button below predate this merge and are historical.

> **Shell re-rooted by `specs/ui/home-router/` (2026-07-10, superseding design-handoff-00
> Decision 20's Graph root).** The launch root is **`HomeView`** — a pure router with six
> controls (Capture primary, then Intake / Dose / Records / Graph / Settings). Capture /
> Intake / Records / Graph / Settings present as mutually-exclusive `.fullScreenCover`s
> (`AppRoot.ActiveSheet`); Dose stays the insulin `.sheet`, presented from `AppRoot`
> (home-router Decision 10). **Graph** (`TrendsView`, renamed in UI only — Decision 21) is
> visualisation-only: no entry-point toolbar controls, no delete affordance (the day-insulin
> `.onDelete` is gone; `TrendsModel.deleteDose` is now unreferenced but deliberately left in
> the perf-sensitive file). `RecordsView`/`RecordsModel`/`RecordRow` replaced the meal-only
> `DataView` (deleted); the shared `mealRouteDestination`/`CloseCoverButton` live in
> `App/MealRouting.swift`. `App/IntakeView.swift` is now the real Intake surface, landed
> by `manual-carb-intake` (`IntakeView` + `IntakeModel` + `CarbEntrySheet`/`CarbEntryModel`
> + `QuickPresetEditSheet`; quick-add presets live in the new `quick_presets` table). The AR session still runs ONLY while the Capture cover is frontmost:
> `CaptureFlowModel.capturePresented()` arms (via `.initialising`),
> `captureDismissed()` releases; `evaluatePermissions` is gated on `isCapturePresented`, so
> launch shows no camera prompt. The old `tabSelectionChanged`/`sheetDidPresent` hooks are
> these same bodies renamed. Capture chrome: close control (top-leading, returns home),
> mode capsule (`1-VIEW · LiDAR` / `2-VIEW · NADIR` / `2-VIEW · OBLIQUE`), 76 pt bubble level
> (stage-relative, non-gating), telemetry capsule, bottom row = mode + shutter (torch,
> Trends/Data/Settings buttons all gone). Navigation: route enums only — `CaptureRoute`
> (review/result) on the capture stack, `MealRoute` (overview/result) on Graph/Records
> stacks — the `.correction` routes and `ManualCorrectionView` were retired by
> `specs/serving-adjust/` (2026-07-18): the Result screen's per-food serving rows are the
> adjustment surface (steppers per household unit, plate-fraction control, per-row gram
> reveal; corrections persist via one appended `PbUserCorrection` whose note carries the
> machine-readable `servings …` stamp from `ServingNote` in MedataCore Foods, with legacy
> `portion N/M` notes still parsed for seeding);
> `navigationDestination(for: MealRecord.self)` no longer exists, and an `.onChange` on
> `navigationPath` resyncs `.showingResult` if the user pops via back-gesture (soft-lock fix).
> Developer-phase copy rule (CLAUDE.md / Req 14.5): no reassurance/disclaimer strings.
> Retired dead files: `CaptureTopBar`, `CaptureModeToggle`, `RefusalSheet` (replaced by
> `CaptureErrorOverlay`), `MealsTabView`, `MealRow`. The architecture notes below (state
> machine, gating, pre-shutter mask, one-ARSession rule) remain accurate.

The iOS SwiftUI capture flow per `specs/ui/iphone-experience/` (shell/chrome now per
`design-handoff-00`, see banner). New code lives in `App/`; the
Xcode project (`MeData/MeData.xcodeproj`) references the files in place via
`../App/*.swift`. All spec tasks (1–28) are implemented.

## Architecture

`CaptureFlowModel` (`@Observable @MainActor`) is the single source of truth.
It owns the `CaptureState` state machine, a `CaptureSession`, an
`any PipelineEstimator`, and the child `LiveIndicatorModel`. The view layer is
composition only; all behaviour is in the model and is unit-tested.

- **CaptureFlowModel** — drives the state machine from `specs/ui/iphone-experience/design.md`.
  Public commands: `shutter()`, `forceTwoView()`, `tryAgain()`,
  `dismissResult()`, `scenePhaseChanged(_:)`, `liveSampleDidUpdate(...)`,
  `trackingDegraded()`, `handleInterruption(_:)`. Derived view state:
  `canShutter`, `currentSnapshot`, `isBusy`, `awaitingObliqueView`. Conforms to
  `CaptureFlowDelegate` with no-op `didUpdateTilt`/`didUpdateLiDARCoverage`/
  `didDetectInterClassOcclusion` (Decisions 9, 11).
- **LiveSampleObserver** — iterates `engine.frames`, computes per-frame
  tilt/distance/coverage via `LiveSampleMath` (pure, testable on simd +
  CVPixelBuffer because `ARFrame` has no public init), forwards to the model.
  Write-gating lives in `apply(_:)`: samples are dropped unless state is
  `.ready`/`.forcingTwoView`/`.initialising`/`.trackingLost`.
- **ARPreviewView** — `UIViewRepresentable` over `ARView`. `ARView.session` is
  get-only, so the engine's own session can't be injected into the view.
  Instead the engine **adopts the ARView's session** as the one authoritative
  `ARSession` via `engine.bindPreviewSession(_:)` (called from both makeUIView
  and updateUIView through the testable `bind(to:)` seam). The engine becomes
  that session's sole delegate and runs the world-tracking config on it. This
  is the single-session realisation of Decision 11/14. Tests drive `bind(to:)`
  with a plain `ARSession` because the SwiftUI `Context` has no public init.

## Gotchas / non-obvious behaviour

- **Captured buffers are landscape; the capture screen turns them to portrait for
  display only.** `RawFrame.imageBytes` is ARKit's sensor-native 1920×1440 buffer
  (`orientation: 1`), while the live `ARView` rotates the same feed to the portrait
  interface itself. Drawn as-is, the frozen frames during `.estimating` and the nadir
  thumbnail showed the photo turned 90° from the viewfinder (the owner read it as a
  "flip" and it likely nudged them into laying the ID-1 card in portrait).
  `CapturedFramesView` and `NadirThumbnailView` now pass
  `RawFrameImage.portraitOrientation` (`.right`) to `Image(decorative:scale:orientation:)`;
  nothing in the buffer, the intrinsics or the mask artefact moved. The saved Photos
  asset (`PhotoKitSaver`) is still written landscape — only the display turns.

- **The review and detail surfaces turn the same way, through one mapping:
  `App/Shared/ReviewPhotoOrientation.swift`.** It holds exactly two things and nothing
  else is allowed a transpose of its own: `displayRotation` (a quarter turn clockwise,
  the same turn `RawFrameImage.portraitOrientation` names) for whole raster layers, and
  `displayPoint`, which sends a unit-square point in buffer space to `(1 - y, x)` in
  upright display space. `MealReviewView` applies it in two places — `loadContours()`
  calls `MaskContourSet.uprightForDisplay()` once, so outlines, dimming, badges, the
  VoiceOver shadow and `handlePhotoTap` all read already-upright coordinates with no
  further turn; and `cardQuad(_:)` normalises `cardCornersImagePx` by the raster
  dimensions and then takes the same `displayPoint`. `MaskContourSet.rasterWidth/Height`
  deliberately stay **buffer** dimensions after `uprightForDisplay()` — they exist only
  to normalise pipeline pixel geometry, which is also buffer-space, and that result is
  then turned like everything else. The photo itself is laid out at the transposed
  (landscape) size, given `displayRotation`, and put back in a portrait frame; 4:3
  turned is an exact fit for a 3:4 box, so nothing is cropped. `ResultView`'s 64 pt
  thumbnail turns the photo and the `MaskOverlayLoader` tint separately about the same
  square centre (the aspect-fill crop is the same pixels either way); the `fork.knife`
  placeholder is not a capture and does not turn. If a future change disagrees with the
  mapping, the giveaway is the dashed "Reference card" marker sitting somewhere other
  than the card.

- **Settings is a list of submenus, not one long Form**
  (`specs/ui/settings-information-architecture`, 2026-09-25). The top level is rows
  only — Account, Glucose, Capture, Insulin, Estimation log, Benchmark, Export, About,
  and Developer in the field builds — each `NavigationLink`ing to its own file under
  `App/Pages/Settings/`. Every editable control lives on the pushed screen, so a new
  control goes in `GlucoseSettingsView` / `CaptureSettingsView` / `InsulinSettingsView`
  / `DeveloperSettingsView`, never back in `SettingsView`. Insulin owns the per-band
  carbohydrate ratios AND the dose schedule, and the outstanding-dose deep link
  (`scrollToDoseSchedule`) pushes it automatically on appear. `DeveloperSettingsView.swift`
  is wholly `#if FIELD_LOOP` (Debug and Release, absent from ProductRelease); the
  demo-seed and clear-data buttons are `#if DEBUG` nested inside that, because their
  store methods are Debug-only. Estimation log and Benchmark stay outside both guards —
  Req 2.3 wants them in Release. Accessibility identifiers are unchanged; the submenu
  rows added `settings.glucose`, `settings.capture`, `settings.insulin`,
  `settings.developer`.

- **Review photo attempts 1 and 2 coexist in the Debug binary.** The 3:4 photo no longer
  fills the column at the 40% height budget, which is the one thing worth a look.
  Settings › Developer › **Review photo fills width**
  (`DeveloperFlags.reviewPhotoFillsWidthKey`, `#if FIELD_LOOP`) flips between attempt 1
  (off, and what ProductRelease compiles): the whole photo, centred, with side gutters; and
  attempt 2 (on): the photo widened to the full column with the rounded clip taking the
  top and bottom off. `MealReviewView.photoGeometry(in:)` is the whole of the
  difference — it returns the photo's full drawn extent and the window it is seen
  through, equal in attempt 1 and not in attempt 2. Overlays are always positioned
  against the *extent*, never the window, so the crop cannot pull them off the food. The
  height budget is identical in both, so the total, the action, the scale control and the
  scrolling rows below are untouched by the choice.

- **Review swap loop (specs/ui/review-swap-loop, MD-29) — two attempts in one
  build.** Attempt 1 is the `RelabelSheet` alone: shortlist section first
  (header `model.shortlistHeader` — "Recent" only when the pure recency
  ordering returned an entry, "Suggested" otherwise), then "All foods" under a
  pinned `.searchable`, "Not in the database" last. A "Keep <predicted>" row
  heads the shortlist when the row is relabelled and calls `reverseRelabel`,
  because `eligibleFoods` filters the predicted class out and the reversal
  was otherwise unreachable. Every row's shortlist is built by
  `prepareShortlists()` as the FIRST thing `start()` does (before the outcome
  lookup's 500 ms retry), so `openAlternatives` sets `shortlist` from the
  cache before it sets `alternativesFor` — the sheet never reflows. Attempt 2
  is Settings › Developer › **Inline food chips**
  (`DeveloperFlags.inlineFoodChipsKey`, `#if FIELD_LOOP`, default off):
  `chipLine` draws the predicted food plus the top three prepared entries
  (`chipCandidates`, fixed for the session so a tap never reshuffles them);
  the current class is the filled chip, the predicted chip is the one-tap
  undo, and `chooseChip` records the shortlist position as the rank the sheet
  would have. **Add a food** (not behind the switch) appends a row keyed
  `added_<n>` (`ReviewFood.addedPrefix`): predicted side empty — zero
  figures, unity β, `classIndex` = `unknown_food` — corrected side the chosen
  solid at one serving or 100 g, user-set, persisted by the ordinary upsert.
  Two things follow from that key. `adoptStoredRows` appends stored `added_`
  rows on a re-push, or the display would drop a food the reconciling total
  still counts; and history (`ResultView`) never lists it per row because its
  rows come from `record.macros.perClass` — the corrected total and the dose
  do include it. `reverseRelabel` and `markAbsent` refuse added rows; reject
  is their removal. `tools/shortlist_hit_rate.py` will read an added row as a
  rank-0 relabel until it filters the prefix.

- **The review's Record / Retake / Delete do not require `.showingResult`.**
  `dismissResult()` and `deleteAndDismiss` act whenever the capture stack has
  the review pushed: locking the phone mid-review delivers an AR interruption
  that moves the state to `.trackingLost`, and gated on the state alone all
  three buttons went dead. `captureDismissed()` clears the path, so a review
  interrupted by a deep link or the dose reminder's Adjust closes with the
  cover (meal-review Q1). Under a standing plate scale, `setAmount` takes the
  amount the row should show and divides the scale back out (Q2).

- **`ARPreviewView`'s ARView must stay `isUserInteractionEnabled = false`.** RealityKit's
  `ARView` is a real UIView with its own gesture recognisers; UIKit resolves touches to it
  ahead of SwiftUI-drawn siblings, and `allowsHitTesting(false)`/`zIndex` on the
  representable are NOT reliable across that boundary (the 3429ddc fix that didn't take on
  device — Retry/2-view dead, Cancel alive). The preview is render-only; all controls are
  SwiftUI. Regression: `specs/bugfixes/capture-no-flat-surface-gravity-frame/report.md`.
- **Full-width SwiftUI buttons: sizing/`contentShape` go INSIDE the Button label.** A
  Button's tap gesture covers only its label; `.frame(maxWidth:)`/`.contentShape` applied
  outside the Button draw a wide pill whose surface is dead. `CaptureErrorOverlay` is the
  reference pattern. This is NOT ARView-specific — it bites any bare-string
  `Button(_:action:)` with outside modifiers. The `09aab63` sweep fixed only
  `CaptureErrorOverlay`; the same dead pill later blocked the whole capture flow via the
  `SegmentationReviewView` "Carbs" button (advances to Result), and the identical latent bug
  sat on `ResultView` Adjust/Done/Retake/Keep-as-is, `MealOverviewView` Adjust/Full-result,
  and `ManualCorrectionView` Save. All fixed to the label-wrapping pattern in one pass —
  regression: `specs/bugfixes/result-view-defects/report.md`. Rule: never put
  `.frame`/`.background`/`.contentShape` on a bare-string Button; wrap the label.
- **`RawFrame.gravity` is world-up in the §6.0 camera frame — pose-dependent.** Derived
  per-frame via `CameraGravity.worldUpInCameraFrame(worldFromCamera:)` (CaptureKit); a
  constant only looks right at the identity pose and kills the plane fitter's ±15° gravity
  gate on every real capture (`supportplane.end candidates=N inliers=0` → "no flat
  surface" in both modes). Treat `inliers=0` with large `candidates` as a convention/input
  bug, never a scene problem. Same bugfix report as above.
- **"No flat surface" specifically on a *matte* table = LiDAR confidence starvation, not
  gravity.** `LiDARPlaneFitter` seeds RANSAC only from table pixels clearing `τ_conf`.
  ARKit maps `ARConfidenceLevel.{low,medium,high}` → bytes `{0,127,255}`; the old
  `τ_conf = 0.66` admitted **only HIGH (255)**. Matte / low-reflectance surfaces return a
  weaker signal → mostly **MEDIUM (127 = 0.498)** → every candidate filtered → `candidates≈0`
  / `noLidarPoints` → "no flat surface". Lowered to `0.40` (Decision 49) to accept
  MEDIUM-or-better and drop only LOW/zero. Diagnostic tell vs the gravity bug: gravity =
  large `candidates`, `inliers=0`; confidence starvation = `candidates≈0` outright. Regression:
  `specs/bugfixes/lidar-plane-fit-matte-table-confidence/report.md`.
- **Device logs for a capture refusal look empty because the pre-shutter mask log floods
  them.** The pre-shutter segmenter calls `CoreMLSegmenter.segment()` at ~2–3.5 Hz, and
  `segment()` emits `event=segmenter.mask` at `.info` every call. Over a `log collect --last`
  window that floods the persisted unified-log store and EVICTS the low-frequency `.info`
  lines you actually need — `event=launch` (buildStamp) and `event=supportplane.end
  success=false` (on a MEASURED refusal: `candidates`/`inliers`/`residual_mm`/`bbox`; on a
  refusal that precedes any fit, just `failure=` and `stats=unfitted`).
  Symptom: `/tmp/medata-device.log` is only `segmenter.mask` lines in a few-second window,
  no launch/supportplane/estimate. Fixed (Decision 18 / `capture-log-flood-…`): the
  pre-shutter instance is built with `CoreMLSegmenter.MaskLogCadence.livePreview` → `.debug`
  (in-memory tier, does not evict persisted `.info`); the Pipeline's shutter-time segmenter
  keeps `.perCapture` → `.info`. Rule: a per-frame diagnostic MUST be `.debug`, never `.info`.
  Note: Stage D (SupportPlane) runs BEFORE Stage F (Segmentation), so on a "no flat surface"
  refusal there is NO shutter-time `segmenter.mask` — on a MEASURED refusal the
  `supportplane.end` bbox counters are your mask-quality proxy. **`stats=unfitted` means
  there is no proxy**: the branch refused before collecting a candidate, so the counters do
  not exist (they were formerly printed as `candidates=0 … bbox=-1`, which read as a
  measurement and misled two diagnoses on 2026-09-29). Read the outcome row instead — an
  `EstimationAttemptRecord` still carries `planeResidualMm = -1` for that case.
- **Speckled-coloured mask over the food photo is a MODEL artefact, not a stride/format
  bug.** The whole image pipeline (YCbCr→BGRA `PixelBufferAdapter`, `canonicaliseToRGB8`,
  letterbox preprocess, `CoreMLSegmenter` CHW↔HWC auto-detect, `PostProcessing` argmax,
  `MaskArtefactWriter` encode, `MaskOverlayLoader` colourise) has been re-audited
  stride-by-stride and is clean. Tell: `segmenter.mask` shows a **coherent 92–99% background**
  (`topClass=34`) with 4–20 scattered classes — coherent background = valid model input
  (a corrupted input gives *random* argmax). It is the under-trained segmenter's food-region
  noise, correctly colourised. Track in the model work-stream; do not hunt for a code bug.

- **`LiveSampleMath.nearSurfaceDistanceCm` (formerly `medianDistanceCm`) is a
  near-side percentile, not a median — deliberately.** The working-distance
  gate (`distanceGateOK`, `App/CaptureFlowModel.swift`) blocked the shutter on
  a genuine in-range ~25 cm one-view LiDAR capture (task 61; field notes
  C257CA10-81A8-4206-B140-8A205D7D1E94 / C577EE9D-8F5A-480A-9F33-96E7163A16B8
  in `specs/estimation/ml-feedback-loop/triage.md`). The gate arithmetic
  (`cm >= 25 && cm <= 50`, both inclusive) and the ARKit units (metres from
  `frame.sceneDepth`, ×100 for cm) were both already correct; the bug was the
  reduction of the centre-crop depth window to one number. In a top-down
  capture the food is always the *closest* surface in the crop and the table
  around it is always farther, but the crop is centred on the frame, not on
  the food — a loosely framed or small item can put the farther table over
  half the crop, and a **median** then reports the table's distance, not the
  food's (the in-crop majority wins). This is the same "two-surface mixture"
  failure the support-plane fitter already documents at
  `specs/estimation/pipeline/design.md` §6.2.1 ("the in-band majority puts
  the median on the supported surface") — search for that write-up before
  adding any new median-of-a-region computation in this codebase. Fix: take
  the near-side 10th percentile instead of the median, which keeps tracking
  the food even when it is a minority of the crop while still absorbing a
  stray near-zero noise sample. Tell vs. a genuine boundary/units/label bug:
  `failingShutterGate` only ever has one string (`too far`) for the whole
  gate — the design system (`design-system/pages/capture.md`,
  `specs/ui/design-handoff-00/copy-inventory.md`) never defines a "too close"
  string to invert, so a mislabelled direction was never the right diagnosis
  here.
- **The review outline marks the ID-1 card as a reference, and that marker is
  driven off the OUTCOME ROW, not the mask.** An accepted card's quadrilateral is
  cleared to background before volume (two-view-trust Req 4.6), so the mask
  carries no trace of it — the outline just showed an unexplained hole. The quad
  arrives instead as `EstimationAttemptRecord.CardMeasurements.cornersImagePx`
  (eight floats, TL TR BR BL) inside the outcome row's `measurements` JSON;
  `MealReviewModel.resolveOutcomeID()` decodes it into `cardCornersImagePx`, and
  `MealReviewView.cardReference` draws a muted neutral fill with a DASHED neutral
  edge plus a `Reference card` capsule. Two things make it non-obvious:
  - **The coordinate space is the label raster's, not the photo's.**
    `cornersImagePx` indexes the argmax directly (`QuadExclusion` clears by those
    very pixel coordinates), so it is normalised by `MaskContourSet.rasterWidth/
    rasterHeight` — added for exactly this — and then lands in the same unit
    square the contours already use. Do NOT normalise by the displayed photo or
    by a hard-coded 1920x1440.
  - **The outcome row is written by a detached task**, so on a just-captured meal
    it can still be in flight when the review appears. `resolveOutcomeID()` now
    retries once after 500 ms; without it both the card marker and the capture
    bundle link intermittently resolved to nothing on the first push.
  The distinctness is by construction, not by taste: every food colour comes off
  `ClassColourTable` at saturation 0.62, so the desaturated `Color.referenceMarker`
  cannot collide with any of the 35, and every food edge is solid, so the dash is a
  second independent channel. `ResultView` does NOT share this overlay — it stacks
  the colourised `MaskOverlayLoader` bitmap in a 64 pt thumbnail, where a label
  would be illegible — so the marker is review-only. nil corners draw nothing.

- **The ID-1 card has a live shutter gate now, and it rides the pre-shutter
  segmenter rather than a second per-frame pipeline** (two-view-trust Req 4.3,
  which reopened iphone-experience Req 6.1 / task 23 — `includeCardThisCapture`
  had existed since the fork sheet landed with *no readers at all*, so nothing
  had ever shipped). `PreShutterSegmenter` now takes the same `VisionCardDetector`
  instance App.swift hands `Pipeline`, and its existing inference loop runs
  `detect(in:)` + `CardPoseSolver.pick(candidates:intrinsics:)` on the RawFrame it
  has already converted, publishing `latestCardSighting`. Three things about that
  are load-bearing. It reuses the loop's `bufferingNewest(1)` coalescing, its
  pause/drain and its off-MainActor hop (`detectCard` is `nonisolated static`,
  the same shape as `makeRawFrame`) — adding a second `engine.frames` subscriber
  would have leaked a continuation per resume, which is smolspec H4 all over
  again. It runs only while `setCardDetectionEnabled(true)`, driven from
  `CaptureFlowView` off `model.needsLiveCardDetection`, so a 1-view or
  LiDAR-scaled session pays nothing and the mask cadence is untouched. And the
  verdict is `pick`, not "Vision found a quadrilateral": the gate must not arm on
  a rectangle the shutter-time solve would then reject, and a `cardTooOblique`
  throw is deliberately *not* a sighting. Model side: `cardIsRequired`
  (Double + no depth — `Pipeline.estimate` branches on `nadir.depth == nil`, so
  without a card there is no scale at all) or `cardIsRequested`
  (`includeCardThisCapture`, finally its reader) arms `cardGateBlocking`, which
  holds the NADIR shutter only — the card is read off the nadir frame, so by the
  oblique tap the question is settled — and names itself `card needed` in
  `failingShutterGate`. `cardReminder` is the one-line Double-mode surface
  (`hint.card`): `card needed` while held, `Include an ID-1 card` when the card
  is optional, and nothing once a required card is in view. Freshness is 1500 ms,
  not the mask's 750 ms: a card on a table does not move and a tighter bound
  flickered the shutter between two consecutive cycles. `capturePresented()` now
  seeds `includeCardThisCapture` from `SettingsKeys.alwaysIncludeCard` — before,
  the Settings default produced no guidance until the fork sheet had been opened
  once.

- **Two developer-phase capture switches live in `App/Shared/DeveloperFlags.swift`
  and Settings › Developer, and the whole file plus every call site is `#if FIELD_LOOP`
  — Debug and Release both, absent from ProductRelease.**
  They are `UserDefaults`-backed rather than compile-time flags on purpose:
  `HARNESS_ENABLED` / `DEV_STUB_SEGMENTER` gate code that must not be *compiled*
  into the shipping binary, whereas these are flipped between two captures while
  standing over a plate, so ProductRelease compiles nothing at all and there is
  no branch to fold. **`Capture without depth`** (Req 4.5) makes `supportsLiDAR` a
  computed property that returns false, and `performFlow` calls
  `RawFrame.clearingDepth()` on the captured frame before anything reads it —
  that one mutation is what puts `Pipeline.estimate` on the card branch, and it
  also forces two-view, locks the mode button, drops the depth-derived distance
  gate (a real non-LiDAR phone publishes no distance) and sets
  `LiDARStatus.available = false`. Without it the non-LiDAR path is simply
  unreachable on an iPhone 16 Pro. **`Oblique tilt unlocked`** splits the old
  `obliqueTiltOk` into `obliqueTiltInBand` (measurement / `obliqueTiltMessage` /
  bubble level / the recorded `obliqueAngleAtCaptureDeg`, all unchanged) and
  `obliqueTiltOk` (the shutter gate alone, the only thing the switch touches).
  It exists because the shipped band is |Δθ − 25°| ≤ 15°, i.e. 10–40°, and a
  synthetic control measured 2026-09-25 (exact silhouettes, real intrinsics,
  real baseline) carves a 337 cm³ box as 801 cm³ at 26°, 712 at 40° and 552 at
  60° — two silhouette cones close the top of the hull only once h·tan(θ)
  exceeds the object's extent along the tilt direction, about 74° for that roll.
  So the band guarantees the hull never closes and, with no depth, leaves height
  unbounded; measuring what a wider band buys needs a capture the shutter
  currently refuses to take. Do not read the switch as a decision to widen the
  band — nothing about how the tilt is measured, shown or recorded moved.

- **RefusalSheet dismissal is wired through `dismissRefusal()`, not the binding setter (Decision 20).** `model.refusal` is strictly derived from `state == .refused` — the setter on the model is gone. The view-side `refusalBinding` calls `model.dismissRefusal()` when SwiftUI writes nil (swipe-down on the sheet). The model transitions `.refused → .ready(freshSnapshot())`, clearing `firstFrame`/`firstFrameTiltDeg`/`inFlightMode`. `tabSelectionChanged(to: nonPhoto)` also dismisses `.refused` (same shape as `.ready`/`.trackingLost`); `.permissionDenied` still preserves across tab switches. The explicit `tryAgain()` path is unchanged. Regression: `specs/bugfixes/surface-not-detected/report.md`.


- **One ARSession only — the engine adopts the ARView's session.** A regression
  (fixed, Decision 14) had `ARKitCaptureEngine` running its OWN `ARSession` while
  `ARView` ran a second one. Two AR sessions contend for the single camera capture
  source → repeated `FigCaptureSourceRemote` failures (`err=-12784`/`-17281` in the
  device log) and a `sessionWasInterrupted ↔ Ended` loop that flashed the UI between
  `.initialising`/`.trackingLost`. Fix: the engine no longer runs its placeholder
  session; `bindPreviewSession(_:)` swaps in the ARView's session and runs the config
  there (gated by `isRunning` so repeated `updateUIView` calls don't reset tracking).
  `start()` records intent and defers the run to bind if the view isn't up yet. **Do
  not reintroduce a second `ARSession`.** All session mutation happens on the main
  actor (`bindPreviewSession`/`start`/`release` via `MainActor.run`).
- **`performFlow` awaits `startTask` before capturing.** `CaptureSession`
  throws `.sessionNotStarted` if `captureNadir/Oblique` races ahead of the
  fire-and-forget `session.start()` kicked off on `.initialising` entry. In
  production start finishes during initialising; tests forced the race.
- **Tilt target depends on stage.** `liveSampleDidUpdate` takes raw
  `tiltDegrees` (angle from straight-down); the model computes in-range against
  0° for nadir and 25° once `firstFrame != nil` (awaiting oblique, §2.2/§2.3).
- **Nadir shutter is gated on a usable pre-shutter mask (`hasUsablePreShutterMask`).**
  `canShutter` (and the `shutter()` command) refuse the nadir stage until
  `preShutterSegmenter.latest` exists, is within the same 750 ms freshness
  bound `performFlow` applies at the nadir-capture instant, and carries at
  least one 1-bit (`TimestampedMask.foodPixelCount`; a fresh all-zero mask
  would arm into a guaranteed `noFoodPixels`, field session 2026-09-23 —
  the chip then reads "no food in view"). Without the freshness half, the
  first tap of a session could fire while `latest` was still nil →
  `maskAgeMs=-1` → `emptyFoodMask` → `noFoodPixels` refusal; the second tap then
  succeeded. The gate is bypassed when no segmenter is injected (tests / legacy;
  `App.swift` always passes one) so the shutter is never permanently disabled.
  Disabled-nadir state reuses the existing `ShutterButtonState.disabled` "waiting"
  UX. Regression: `specs/bugfixes/first-shot-nofoodpixels-race/report.md`.
- **Path hint is frozen at shutter tap** and locked to `.twoViewSfS` while
  awaiting the oblique view (so a coverage flip can't switch paths mid-sequence).
- **§8.3 is best-effort (Decision 12).** Backgrounding cancels the in-flight
  `flowTask` and resets UI to `.initialising`; the pipeline has no cooperative
  cancellation so a `MealRecord` may still be persisted.
- **Real pipeline, dev-stub segmenter.** `App.swift` now wires
  `Pipeline.makeForDevice(store:cardDetector:)` (the `PendingPipeline` stand-in
  was deleted — research task 81). Under `DEV_STUB_SEGMENTER` (Phase 1) the
  pipeline runs end-to-end with `StubInferenceEngine`, producing a placeholder
  carb value rather than a refusal. Capture, gating, refusal, and persistence all
  work; real estimates await the Phase 3 trained model (Blocker 1 in
  [`pipeline-wiring-status.md`](pipeline-wiring-status.md)).

## Tests

Unit tests are in `MeData/Tests/` using Swift Testing (`@Test`/`#expect`) with
`@testable import MeData`. XCUITests are in `MeData/UITests/` (XCTest).
**Neither is wired into the committed Xcode project** (no test targets exist —
the pre-existing `CapturePathDeciderTests.swift` is the same).

**Convention (2026-07-03): the files in `MeData/Tests/` and `MeData/UITests/`
are documentation contracts, not an executable suite.** They compile against
the app source and record intended behaviour, but no committed target runs
them. Agents MUST NOT claim to have "run" them, count them in test totals
(`make test` covers the SwiftPM core only), or write new app-target tests
expecting execution — the MVP gate for app/UI work is "does it build + does it
look right on device" (see CLAUDE.md). If execution is ever genuinely needed,
the historical recipe is a temporary unit-test target with
`TEST_HOST = $(BUILT_PRODUCTS_DIR)/MeData.app/MeData` (validated once: all 40
passed on the iPhone 17 Pro simulator).

## Adding a new file under `App/` — nothing to do

**`App/` is a `PBXFileSystemSynchronizedRootGroup` as of 2026-08-28.** Drop a
`.swift` file anywhere under `App/` and it is in the MeData target. Create a
folder and it appears in Xcode's navigator. There is no registration step.

This replaced a four-place `project.pbxproj` checklist (`PBXBuildFile`,
`PBXFileReference`, the `PBXGroup` children list, the `PBXSourcesBuildPhase`
files list) that had to be repeated per file, where missing one made the build
either fail or — worse — silently omit the file. `tools/pbx_add_app_file.py`
existed to automate it and is deleted; 324 lines left `project.pbxproj` with it.

The group is declared with `path = ../App; sourceTree = SOURCE_ROOT`, which
resolves from the project directory (`MeData/`) up to the repo root. A relative
path in a synchronised root group is unusual but works — it was verified by
putting a deliberate type error in a file under a new folder and confirming the
compiler reported it.

Two consequences worth knowing:

- **Every file under `App/` is now compiled**, including any that were
  previously on disk but unregistered. `App/Pages/Capture/CapturePathDecider.swift`
  was exactly that — it survives only because its whole body sits behind
  `#if AUTO_CAPTURE_MODE`, a flag defined nowhere.
- **Non-Swift files join Copy Bundle Resources automatically**, and that bites
  immediately: `App/README.md` and `App/Design/README.md` both tried to copy to
  `MeData.app/README.md` and the build failed with *"Multiple commands produce
  … /MeData.app/README.md"*. Two files with the same basename anywhere under
  `App/` will collide, however deep their folders.
- **To exclude a file** you need a `PBXFileSystemSynchronizedBuildFileExceptionSet`
  with a `membershipExceptions` entry, listed on the root group's `exceptions`
  array, the way `MeDataWidgets` excludes its `Info.plist`. Paths in
  `membershipExceptions` are relative to the synchronised folder — `README.md`
  and `Design/README.md`, not `App/README.md`. Deleting a reference no longer
  works, because there are none.

Files dropped INSIDE `MeData/MeData/` are likewise auto-added, including to
Copy Bundle Resources — which is why `MeData/Info.plist` (build stamp) lives
outside that folder ("Multiple commands produce Info.plist" otherwise).

### XCUITests and the DEBUG harness (tasks 26–28)

The capture flow is AR-gated — the shutter only arms once a live `ARSession`
reaches `.ready`, and ARKit does not run on the simulator. So the three XCUITests
launch the app with `-uitest` and drive the flow through a `#if DEBUG` harness in
`App.swift` rather than a real camera:

- **`UITestSupport`** — reads launch args. `-uitest` activates the harness;
  `-uitestPipeline refuse|stall` selects the stub pipeline (refuse is default).
- **`UITestHarness`** — builds the `CaptureFlowModel` with a `UITestCaptureEngine`
  (capture blocks until released, so `.capturing` is observable), a stub pipeline,
  and an interruption `AsyncStream` it owns. Exposes `driveToReady()`,
  `releaseCapture()`, `emitInterruptionBegan/Ended()`.
- **`UITestControlPanel`** — hidden buttons (leading edge, clear of shutter/banner)
  that call those harness methods, queried by accessibility identifier
  (`uitest.driveToReady`, `uitest.releaseCapture`, `uitest.interruptionBegan/Ended`).

Other accessibility identifiers the tests query: `shutter`,
`hint.{initialising,trackingLost,estimating,capturing}`, `refusal.message`
(also asserted by verbatim text per §12.2), `refusal.tryAgain`. Note: an
`accessibilityIdentifier` on a plain SwiftUI container (e.g. the refusal banner
`VStack`) does not reliably surface as a queryable element — query the Label/Button
inside instead, which is why the refusal test keys off `refusal.message` not the
banner container.

`driveToReady()` calls `model.liveSampleDidUpdate(...)` directly because `ARFrame`
has no public init, so `LiveSampleObserver`'s real path can't be exercised on the
simulator. The interruption test asserts the UI proxy (`.initialising` hint) for
the `engine.start()` re-call, which is itself covered by the CaptureFlowModel unit
tests. Running these requires a device + a UI-test target (same separate-validation
pattern as the unit tests). Compilation was validated by building the app target
for the iPhone 17 Pro simulator after temporarily repointing the SPM to the local
`MedataCore` (see Build-path caveat).

## Build-path caveat

The Xcode project's `XCLocalSwiftPackageReference` is `relativePath = ../../medata`
— it only resolves when the repo is checked out at a directory literally named
`medata`. In a checkout named otherwise (e.g. `ui`), the package resolves to a
stale sibling and the SPM-prerequisite symbols (`ARKitCaptureEngine.frames`/
`.interruptions`/`InterruptionEvent`, `PipelineEstimator`) go missing. Point the
path at the actual checkout to build locally; do not commit that change.
