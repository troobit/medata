# Bugfix Report: lidar-plane-fit-matte-table-confidence

**Date:** 2026-07-06
**Status:** Fixed (code); on-device retest on a matte table is the acceptance gate

## Description of the Issue

A fresh on-device session reported three symptoms. Only one is a code defect; the
other two are the known under-trained segmenter and are recorded here for
completeness (no code change).

1. **Single-view (LiDAR) capture failed "no flat surface" on a matte table.** ← the code bug fixed here.
2. Two-view capture misclassified the food. → model quality (see below).
3. The captured images show "speckled coloured lines … maybe a model artefact". → model quality (see below).

**Reproduction steps (symptom 1):**
1. Single (LiDAR) capture mode, iPhone 16 Pro.
2. Point at a plate on a **matte / low-reflectance table** (weak LiDAR return).
3. Shutter → capture refuses with "no flat surface" (`SupportPlaneError.noLidarPoints`).

**Impact:** High for single-view capture on matte surfaces — the primary capture
path refuses outright and the user cannot get an estimate. Glossy/well-lit tables
(which return HIGH confidence) were unaffected, which is why the earlier gravity
fix (`09aab63`) appeared to resolve 1-view capture.

## Investigation Summary

The on-device `.logarchive` collected this round was effectively empty (1 line;
same clipping seen in prior sessions), so root-causing was done from the code plus
the 8 surviving `event=segmenter.mask` lines.

- **Symptoms examined:** `segmenter.mask` showed `topClass=34` (background) at
  92–99 %, `foodCoveragePercent` 0–5 %, `distinctClasses` 4–20 — a mostly-background
  mask with scattered noise classes.
- **Code inspected — full image pipeline (symptoms 2 & 3):** `PixelBufferAdapter`
  (YCbCr→BGRA via vImage, per-plane `rowBytes`), `PreProcessing.canonicaliseToRGB8`
  + letterbox/normalise, `CoreMLSegmenter` I/O layout (CHW↔HWC auto-detect +
  `writeLogits` transpose), `PostProcessing` (softmax/argmax/resize, HWC), mask
  encode (`MaskArtefactWriter`, 8-bit greyscale index PNG) and read-time colourise
  (`MaskOverlayLoader`, honours `bytesPerRow`). **Every stride and format path is
  correct.**
- **Code inspected — plane fit (symptom 1):** `LiDARPlaneFitter.collectCandidatePoints`
  gates candidate table pixels on `confidence/255 ≥ τ_conf = 0.66`;
  `ARKitCaptureEngine` maps `ARConfidenceLevel.{low,medium,high}` → bytes
  `{0,127,255}`.
- **Hypotheses tested:**
  - *Speckled lines = a stride/YCbCr format bug corrupting the model input* (the
    steering hypothesis, and the standing `pipeline-factory-parked` warning) —
    **ruled out.** A corrupted input produces a *random* argmax; the mask is instead
    a **coherent 92–99 % background** classification. Coherent background detection
    is positive evidence the model receives a valid image and simply fails to find
    food — the known 0.43-mIoU weakness (bread/potato short per Decision 11). The
    scattered 4–20 classes are the weak model's low-confidence food-region noise,
    faithfully colourised by the (correct) overlay.
  - *Matte-table refusal = confidence starvation* — **confirmed by mechanism and a
    reproducing unit test.** `0.66` admits only HIGH (255); MEDIUM (`127/255 = 0.498`)
    is rejected. A matte table returns a weaker LiDAR signal dominated by MEDIUM, so
    every candidate point is discarded → `noLidarPoints`.

## Discovered Root Cause

The support-plane fitter required **HIGH-only** LiDAR confidence. `τ_conf = 0.66`
on the normalised 0..255 confidence byte clears only 255; ARKit reports MEDIUM
(127) across most of a matte / low-reflectance table because the return signal is
weaker there. With all MEDIUM points filtered out, `collectCandidatePoints`
returned fewer than three points and `LiDARPlaneFitter.fit` threw
`noLidarPoints`, surfaced as "no flat surface".

**Defect type:** Over-strict threshold / robustness gap (not a logic or memory error).

**Why it occurred:** §6.2 defined the confidence gate as "HIGH", chosen when
high-confidence points were assumed plentiful. Matte surfaces — common in practice
— violate that assumption; the design never revisited the gate for weak-return
tables.

**Contributing factors:** The empty log archive hid the `debugLastCandidatePointCount`
counter that would have shown the starvation directly, so the diagnosis was made
from the confidence-byte mapping and reproduced in a unit test.

## Resolution for the Issue

**Changes made:**
- `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift` — `confidenceThreshold`
  (τ_conf) lowered `0.66 → 0.40` so MEDIUM-or-better confidence is accepted and only
  genuine LOW/zero returns are dropped. Comment documents the mechanism and Decision 49.

**Approach rationale:** MEDIUM-confidence depth on a flat table is noisier but
approximately planar. The existing RANSAC ±5 mm inlier band, gravity-angle gate,
and 20 mm residual gate (Decision 46) still reject a bad plane, and `σ_plane =
exp(−r/5)` carries the extra noise into the confidence surface — the same
degradation channel Decision 46 introduced. Refusing on a flat matte table is
strictly worse than fitting a slightly noisier, honestly-down-weighted plane.
`0.40` sits below MEDIUM (0.498) and above LOW (0), so MEDIUM always clears and
LOW never does. See Decision 49 in `specs/estimation/pipeline/decision_log.md`.

**Alternatives considered:**
- Keep HIGH-only (0.66) — brittle to the common matte table; forces a needless refusal.
- Accept all incl. LOW (0.0) — lets a garbage plane through on truly unreliable depth.
- `CardOnlyPlaneFitter` fallback — heavier and orthogonal; no card is in frame in single-view LiDAR mode.

## Symptoms 2 & 3 — model quality, no code change

The two-view misclassification and the speckled-coloured mask are the same
under-trained segmenter (`coreml_0295ea61edd9`, 0.43 heldout mIoU). The entire
image pipeline was re-audited stride-by-stride and is clean; the coherent 92–99 %
background classification is positive evidence the model input is valid. These stay
tracked in the model / β work-stream (`mvp-capture-pipeline-status`,
`cross-dataset-calibration`), not fixed as code. The user's own guess — "maybe a
model artefact" — is correct.

## Regression Test

**Test file:** `MedataCore/Tests/SupportPlaneTests/LiDARPlaneFitterTests.swift`
**Test names:** `testFitsMatteTableWithUniformMediumConfidence`, `testRejectsUniformLowConfidenceTable`

**What they verify:**
- A synthetic flat plane at **uniform MEDIUM confidence (127)** — a matte table —
  now fits (recovered normal within 1°, distance within 2 mm). This test failed
  `noLidarPoints` before the fix.
- A plane at **uniform LOW confidence (0)** still refuses with `noLidarPoints`, so
  the lower bound is guarded — the fix does not let garbage depth through.

**Run command:** `swift test --filter LiDARPlaneFitterTests`

## Affected Files

| File | Change |
|------|--------|
| `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift` | τ_conf 0.66 → 0.40 + documenting comment |
| `MedataCore/Tests/SupportPlaneTests/LiDARPlaneFitterTests.swift` | +2 regression tests, `uniformConfidence` helper knob |
| `specs/estimation/pipeline/design.md` | §6 confidence-gate references updated to 0.40 |
| `specs/estimation/pipeline/decision_log.md` | Decision 49 |
| `CHANGELOG.md` | Fix entry |
| `docs/agent-notes/*` | Gotcha note |

## Verification

**Automated:**
- [x] Regression tests pass (matte-table fits; low-confidence still refuses)
- [x] Full test suite passes — XCTest 383 (3 skipped, 0 failures), swift-testing 114
- [x] `make build` green, `make spell` clean

**Manual verification:**
- On-device retest on a **matte table** (single-view mode, device `you`) is the real
  acceptance gate — the unit test proves the mechanism, but the exact confidence
  distribution of the user's table can only be confirmed on device. If that surface
  turns out to return only LOW confidence (e.g. a black matte), it will still
  refuse; that harder case is out of scope here (see Decision 49 negatives).

## Prevention

- When a threshold gates a hardware signal, encode the device's discrete levels in
  the test (here ARKit's `{0,127,255}`) so an over-strict gate is caught in CI, not
  only on a specific physical surface.
- Keep the `LiDARPlaneFitter.debugLast*` counters emitting in Release; they are the
  branch-deciding evidence when a capture refuses, but only if the log archive is
  captured intact (the archive was empty this round).

## Related

- Decision 46 — residual ceiling 8→20 mm, the "tolerate degraded fit, carry via σ_plane" precedent.
- `specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/` — the four-edge band scan; same fitter, different starvation mode.
- `09aab63` — gravity-frame fix; resolved 1-view failure on glossy (HIGH-confidence) tables, leaving this matte-table (MEDIUM) mode.
- `mvp-capture-pipeline-status` — where symptoms 2 & 3 (model quality) are tracked.
