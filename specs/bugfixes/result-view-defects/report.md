# Bugfix Report: Result-View Defects (dead Carbs button, image tearing, misclassification)

**Date:** 2026-07-06
**Status:** Fixed (dead button) / Root-caused, not a code bug (tearing + misclassification)

## Description of the Issue

On-device testing of the deployed `research` build (post-`09aab63` gravity fix, both
capture modes now succeed) surfaced three distinct reports on the segmentation-review /
result surface:

1. **Dead "Carbs" button.** The primary action on the segmentation-review screen (labelled
   "Carbs", advances to the Result screen) did nothing when tapped, leaving the user stuck on
   the review screen. The user refers to this screen loosely as "the result view" — it is the
   screen that shows the detected foods, per-food carbs, and the captured food image with the
   mask overlay (`SegmentationReviewView`), whose `Carbs` action pushes `.result`.

2. **Visual tearing / lines across the food image** on the same screen.

3. **Misclassification.** 2-view classified two slices of brown multigrain bread as brown
   rice; 1-view classified two pieces of bread as "white" and produced multiple false
   positives.

**Reproduction steps:**
1. Capture a meal (either mode) — capture succeeds and the flow lands on the segmentation
   review screen.
2. Tap anywhere on the wide "Carbs" pill except the centred text → nothing happens (defect 1).
3. Observe the food image with the mask overlay → scattered coloured lines/speckle (defect 2).
4. Observe the detected-food list → wrong food classes (defect 3).

**Impact:**
- Defect 1 is a **hard blocker**: the capture flow cannot advance past segmentation review to
  the Result screen, so the whole estimate is unreachable. High severity.
- Defects 2 and 3 are **estimate-quality** symptoms of the under-performing segmenter, not
  functional blockers.

## Investigation Summary

- **Symptoms examined:** dead pill button; coloured lines over the food photo; wrong food
  labels.
- **Code inspected:** `App/SegmentationReviewView.swift`, `App/ResultView.swift`,
  `App/CaptureFlowView.swift` (route wiring), `App/MaskOverlayLoader.swift` (mask decode/tint),
  `App/PhotoLibrarySaver.swift` (captured-frame → Photos), `MedataCore/.../PixelBufferAdapter.swift`
  (camera → RawFrame stride handling), `MedataCore/.../MaskArtefactWriter.swift` (mask encode),
  `MedataCore/.../PostProcessing.swift` (argmax build + letterbox undo), and the device log at
  `/tmp/medata-device.log`.
- **Hypotheses tested and ruled out:**
  - *Stride/`bytesPerRow` shear as the tearing cause* — **ruled out.** Every buffer path is
    tightly packed and dimension-correct: `PixelBufferAdapter.copyContiguous`/`convertYCbCr`
    collapse row padding to `width*4`; `PhotoKitSaver.uiImage` guards `count == bytesPerRow*height`;
    `PostProcessing` builds the argmax at `originalWidth × originalHeight` (letterbox cropped and
    resized back) as tightly-packed 1 byte/px; `MaskArtefactWriter` encodes with `bytesPerRow: width`;
    `MaskOverlayDecoder` reads back with the CGImage's own `bytesPerRow` (padding-safe) and writes a
    tightly-packed `width*4` overlay. Capture is a consistent 1920×1440 (4:3), matching the photo.
  - *ARView stealing the Carbs tap* (the `09aab63` mechanism) — **ruled out.** The deployed build
    already sets `ARView.isUserInteractionEnabled = false`, and `SegmentationReviewView` has no
    ARView behind it.

## Discovered Root Cause

**Defect 1 (dead Carbs button) — the fixable code bug.**

`SegmentationReviewView.carbsAction` used the SwiftUI anti-pattern where the pill sizing/background
is applied **outside** `Button(...)`:

```swift
Button("Carbs", action: onCarbs)
    .frame(maxWidth: .infinity).frame(height: 48)
    .background(Color.medataAccent, in: RoundedRectangle(cornerRadius: 12))
```

A `Button`'s tap gesture only covers its **label**. With a bare-string label, the hit region is
just the centred "Carbs" text (~50 pt wide); the wide coloured pill drawn by the outside `.frame`
is dead. A user tapping the pill (the natural target) hits nothing → "button does not work". This
is the **exact** trap that was fixed for `CaptureErrorOverlay` in `09aab63`; that sweep did not
extend to this screen or to the other plain-text pill buttons in the app.

**Defect type:** SwiftUI hit-testing / view-composition error (dead tap surface).

**Why it occurred:** the `09aab63` fix documented the pattern and fixed only the ARView-adjacent
error overlay. The same anti-pattern remained on every other plain-text pill button
(`SegmentationReviewView`, `ResultView`, `MealOverviewView`, `ManualCorrectionView`). Because the
Carbs button blocks reaching the Result screen, the sibling buttons were never exercised on
device, so they read as "working" only by not having been reached.

**Defects 2 and 3 (tearing + misclassification) — model quality, NOT a code bug.**

The device log is decisive:

```
event=segmenter.mask foodCoveragePercent=0..9 topClass=34 topClassPercent=87..99 distinctClasses=17..25
```

`topClass=34` is background, dominating at 87–99% of pixels, with food coverage of only 0–9% and
17–25 distinct classes scattered as noise. The segmenter (held-out food-class mIoU ≈0.40, model
`24e0b022241a`) barely detects food and mislabels what it does detect. Two consequences:
- **Misclassification** (bread→rice, bread→"white", false positives) is the direct output of this
  weak argmax.
- **"Tearing / lines"** is the same weak argmax rendered through `MaskOverlayLoader`: ~20 scattered
  mislabelled classes, each tinted at α0.55 and composited over the photo, appear as coloured
  speckle/lines across the food image. It is a faithful rendering of a noisy mask, not a rendering
  defect.

These two are **model-driven** and are tracked in the `mvp-capture-pipeline-status` memory. They
are not resolved by a code change; the levers are model retraining / recipe iteration, a
single-dominant β re-fit (model-production Bucket C), and the cross-dataset-calibration spec.

## Resolution for the Issue

**Changes made (defect 1 — move the pill sizing INSIDE each Button label + add `contentShape`,
matching the `09aab63` pattern):**
- `App/SegmentationReviewView.swift` — `carbsAction` "Carbs" button (the reported defect).
- `App/ResultView.swift` — `actionRow` "Adjust"/"Done"; `veryLowSurface` "Retake"/"Keep as-is".
- `App/MealOverviewView.swift` — `actionRow` "Adjust"/"Full result".
- `App/ManualCorrectionView.swift` — `saveAction` "Save".

**Approach rationale:** this is the project's own device-verified fix from `09aab63`. Wrapping the
sizing/background/`contentShape` inside `Button { Text(...)… }` makes the entire pill the tap
target. Applied consistently to all plain-text pill buttons so the user does not immediately hit
the same dead surface on the very next screen (Adjust/Done/Save) after Carbs is fixed. Pure
view-layer change; no logic, copy, or accessibility-identifier change.

**Alternatives considered:**
- *Fix only the Carbs button* — rejected: the identical latent bug on Adjust/Done/Save/Full result
  would surface the moment the user advances past the now-working Carbs button.
- *Add `.contentShape` outside the Button* — rejected: `09aab63` recorded this as the ineffective
  shape of the first (`3429ddc`) fix; `contentShape` must be inside the label.

**Defects 2 & 3:** no code change. Documented as model-quality limitations with the log evidence
above; deferred to the model/β work-stream.

## Regression Test

**None added — deliberate.** Per the project MVP test gate (`CLAUDE.md`: "does it build + does it
look right on device"; app-target `Tests/` are documentation contracts, not an executable suite)
and the `testing-mvp-minimal` memory, no committed target runs UI tests, and a SwiftUI
modifier-placement / hit-testing bug is not expressible as a MedataCore unit test. This mirrors
`09aab63`, which added math tests for the gravity bug and verified the dead buttons on device.
Verification for this class of fix is **build-app green + on-device tap**.

## Affected Files

| File | Change |
|------|--------|
| `App/SegmentationReviewView.swift` | Carbs button: pill sizing/background/contentShape moved inside the Button label |
| `App/ResultView.swift` | Adjust/Done + Retake/Keep-as-is buttons: same label-wrapping fix |
| `App/MealOverviewView.swift` | Adjust/Full-result buttons: same label-wrapping fix |
| `App/ManualCorrectionView.swift` | Save button: same label-wrapping fix |

## Verification

**Automated:**
- [x] `make build-app` — BUILD SUCCEEDED (stamp `5cedacc-20260706-164009`)
- [x] `make spell` — OK, no US-English spellings
- [x] `make test` — XCTest 381 (3 skipped, 0 failures); swift-testing 114 in 18 suites, 0 failures
- [x] Regression test — N/A (see above)

**Manual verification (on-device — user's gate):**
- Capture a meal → on the segmentation-review screen, tap anywhere on the "Carbs" pill (not just
  the text) → advances to the Result screen.
- On Result, tap anywhere on the "Adjust"/"Done" pills → each responds across its full width.
- The "tearing/lines" and misclassification are expected to persist — they are model-driven and
  out of scope for this fix.

## Prevention

- **Never apply `.frame`/`.background`/`.contentShape` to a bare-string `Button(_:action:)`.** Use
  `Button(action:) { Text(...).frame(...).background(...).contentShape(...) }` so the whole pill is
  tappable. This is now the pattern on every plain-text pill button in `App/`.
- Consider a lightweight shared `PillButton` style/component so the tap-surface contract cannot be
  reintroduced per call site (follow-up, not done here to keep the fix minimal).

## Related

- `specs/bugfixes/capture-no-flat-surface-gravity-frame/report.md` — `09aab63`, the origin of this
  fix pattern (CaptureErrorOverlay dead buttons).
- `mvp-capture-pipeline-status` memory — tracks the segmenter mIoU ≈0.40 / β-unity estimate-quality
  work that owns defects 2 and 3.
- `docs/agent-notes/ui-capture-flow.md` — dead-surface gotcha note.
