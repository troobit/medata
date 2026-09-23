# Bugfix Report: capture-log-flood-evicts-plane-fit-diagnostics

**Date:** 2026-07-06
**Status:** Fixed (the diagnostic-blindness bug). The matte-table plane-fit refusal itself is NOT fixed this round — it is now *diagnosable*; root-causing it needs one device capture with the fix deployed.

## Description of the Issue

On-device round after commit `06b86fa` (τ_conf 0.66→0.40). The user retested and reported the matte-table single-view capture **still** fails "no flat surface" ("again"), and the food images **still** show speckled coloured lines. So `06b86fa` did not resolve the matte-table failure on device.

Investigating why revealed a deeper, recurring problem: **every plane-fit investigation this session has been blind.** The device log collected for a "no flat surface" refusal never contains the one line that explains it — `event=supportplane.end success=false` (with `candidates`/`inliers`/`bbox` counters) — nor the `event=launch buildStamp=…` line needed to confirm which build was tested.

**Reproduction (the blindness):**
1. Run the app on device, point at a scene (pre-shutter live segmentation runs).
2. `make logs-device` (collects the last N minutes).
3. Observe: the filtered log is **only** `event=segmenter.mask` lines in a short window — no `launch`, no `supportplane.end`, no `estimate.*`.

**Impact:** High (meta). Without `supportplane.end` and `launch`, the matte-table refusal cannot be root-caused and the deployed build cannot be confirmed — so fixes are guesses. Two plane-fit changes this session (gravity `09aab63`, confidence `06b86fa`) were made without this evidence.

## Investigation Summary

- **Symptoms examined:** fresh `/tmp/medata-device.log` (19:12) = 22 `segmenter.mask` lines across a **6-second** window, nothing else. `foodCoveragePercent` 0–8%, `topClass=34` (bg) 87–99%, `distinctClasses` 3–31.
- **Code inspected:** `App/PreShutterSegmenter.swift` (calls `segmenter.segment` per live frame at ~2–3.5 Hz), `MedataCore/Sources/Segmentation/CoreMLSegmenter.swift` (emits `event=segmenter.mask` at `Logger.info` on *every* `segment()`, Release included), `MedataCore/Sources/Pipeline/Pipeline.swift` (Stage D SupportPlane runs *before* Stage F Segmentation; `supportplane.end` is Release-logged at `.info`), `Makefile` (`log collect --last`; predicate `subsystem == "ie.medata.app"`).
- **Hypotheses tested:**
  - *The confidence fix (`06b86fa`) failed on device* — **unconfirmable**: no `launch` line means it's unknown whether `06b86fa` was even the running build.
  - *Empty/scattered mask starves the plane fit's band scan* — **rejected on analysis.** With 0–8% food coverage, the frame is overwhelmingly non-food, so the table-band scan (which collects non-food pixels *around* the food bbox) has abundant candidate points — it does not starve. So the plane-fit refusal is NOT explained by mask emptiness, and its true cause cannot be determined without the `supportplane.end` counters.
  - *Why the counters never appear* — **confirmed.** The pre-shutter segmenter logs a `segmenter.mask` line at `.info` ~2–3.5×/second continuously. Over a multi-minute `log collect` window that is thousands of `.info` lines flooding the persisted unified-log store and **evicting** the low-frequency `.info` events (`launch`, `supportplane.end`, `estimate.*`) before collection. The 6-second, mask-only survivor window is the signature of that eviction.

## Discovered Root Cause

The high-frequency pre-shutter `event=segmenter.mask` log (`.info`, ~2–3.5 Hz) floods the persisted unified-log store and evicts the low-frequency `.info` diagnostics that matter on device (`launch` buildStamp, `supportplane.end` plane-fit refusal trace). Every plane-fit investigation was therefore working without its key evidence.

**Defect type:** Observability defect (log-volume starvation), not a logic error.

**Why it occurred:** `event=segmenter.mask` is emitted inside the shared `CoreMLSegmenter.segment()`, used by both the one-shot shutter-time capture (where a persisted `.info` line is wanted) and the continuous pre-shutter live preview (where ~3 Hz `.info` logging floods the store). The two callers were never distinguished.

## Resolution for the Issue

**Changes made (observability only — no estimation-path behaviour change):**
- `MedataCore/Sources/Segmentation/CoreMLSegmenter.swift` — new `MaskLogCadence` (`.perCapture` default → `.info`; `.livePreview` → `.debug`). The `segmenter.mask` line is emitted at the instance's chosen level.
- `MedataCore/Sources/Pipeline/PipelineFactory.swift` — `makeSegmenter(maskLog:)` plumbs the cadence through; `makeForDevice` keeps the `.perCapture` default.
- `App/App.swift` — the pre-shutter segmenter is built with `maskLog: .livePreview`.
- `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift` + `Pipeline.swift` — added `debugLastResidualMm` counter and `residual_mm=` to the `supportplane.end success=false` trace, so a residual-too-high refusal is distinguishable from point-starvation/degeneracy on the next capture.

**Why this works:** `.debug` logs live in the in-memory debug tier, not the persisted tracev3 store, so they cannot evict the persisted `.info` events. The pre-shutter flood stops; `launch` and `supportplane.end` survive `log collect`. The shutter-time capture keeps its single persisted `.info` mask line. `make logs-device` already passes `--debug`, so pre-shutter masks remain visible when a fresh capture is collected before the debug ring rolls over — just no longer at flood volume.

**Why the plane fit was NOT changed again:** the leading hypotheses (gravity, confidence, empty-mask starvation) do not survive analysis of the current evidence, and the deciding counters are exactly what the flood evicted. A third blind plane-fit change would repeat the pattern that produced "again". The honest fix is to make the failure diagnosable and root-cause it from real counters.

## Symptoms carried over (unchanged this round)

- **Matte-table "no flat surface":** now *diagnosable*, not fixed. Acceptance path below.
- **Speckled coloured lines + 2-view misclassification:** the under-trained segmenter (audited clean last round; coherent 92–99% background = valid model input). Tracked in the model work-stream (`mvp-capture-pipeline-status`).

## Regression Test

**Test file:** `MedataCore/Tests/SegmentationTests/CoreMLSegmenterTests.swift`, `MedataCore/Tests/SupportPlaneTests/LiDARPlaneFitterTests.swift`
**Test names:** `testMaskLogDefaultsToPerCapture`, `testResidualCounterReflectsFitOutcome`

**What they verify:**
- The mask log defaults to `.perCapture` (persisted `.info`) — a regression flipping the default would silently drop the shutter-time capture diagnostic.
- `debugLastResidualMm` carries the RMS residual on a completed fit and the `-1` sentinel on a pre-residual refusal — so the new `supportplane.end` field is meaningful.

**Run command:** `swift test --filter 'testMaskLogDefaultsToPerCapture|testResidualCounterReflectsFitOutcome'`

**Not unit-tested:** the flood/eviction itself is OSLog runtime behaviour, not unit-testable; its fix is verified on-device (below).

## Affected Files

| File | Change |
|------|--------|
| `MedataCore/Sources/Segmentation/CoreMLSegmenter.swift` | `MaskLogCadence`; live path → `.debug` |
| `MedataCore/Sources/Pipeline/PipelineFactory.swift` | `makeSegmenter(maskLog:)` plumbing |
| `App/App.swift` | pre-shutter segmenter uses `.livePreview` |
| `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift` | `debugLastResidualMm` counter |
| `MedataCore/Sources/Pipeline/Pipeline.swift` | `residual_mm=` in `supportplane.end` trace |
| tests, CHANGELOG, decision_log (Decision 18), agent-notes | as listed |

## Verification

**Automated:**
- [x] New tests pass
- [x] Full suite: XCTest 385 (3 skipped, 0 failures), swift-testing 114
- [x] `swift build`, `make build-app` (BUILD SUCCEEDED), `make spell` clean

**Manual / on-device (the acceptance gate — user step):**
1. `make deploy-release` to put THIS build (with the logging fix + `06b86fa`) on device `you`; note the printed build stamp.
2. Capture on the matte table (single-view). It will still refuse if the plane-fit bug is unfixed — that is expected this round.
3. `make logs-device`. It should now show `event=launch buildStamp=<matches step 1>` AND `event=supportplane.end success=false failure=… candidates=… inliers=… residual_mm=… bboxW=… bboxH=…`.
4. Those counters pinpoint the refusal (point-starvation vs degeneracy vs residual-too-high vs bbox geometry) → the plane-fit fix follows precisely, next round.

## Prevention

- High-frequency diagnostics belong at `.debug`, never `.info` — an `.info` log inside a per-frame loop starves the persisted store of low-frequency events. Rule added to `docs/agent-notes/ui-capture-flow.md`.
- When a capture "fails on device", confirm the `launch` buildStamp before trusting the result (CLAUDE.md already says this; the flood made it impossible until now).

## Related

- `06b86fa` — τ_conf 0.66→0.40; its on-device effect is still unconfirmed for want of the `launch` line this fix restores.
- `09aab63` — gravity-frame fix (earlier plane-fit change, same blindness).
- `specs/estimation/pipeline-real-device-correctness/decision_log.md` Decision 18 — logging cadence.
- `mvp-capture-pipeline-status` — model-quality symptoms (lines, misclassification).
