# MVP gap analysis — working-model readiness

**Date:** 2026-06-28
**Method:** one validation agent per active iOS spec (9 specs), each cross-checking its
spec against the code tree in an isolated worktree. This note synthesises their findings
into the path to an MVP that produces a *real* carb number (not a dev-stub placeholder).
Per-spec detail lives in each `specs/<domain>/<capability>/decision_log.md`; the meta log
is `specs/DECISIONS.md`.

## Verdict

**The MVP is blocked on exactly one thing: there is no trained CoreML segmenter.** Every
other subsystem — capture, YCbCr→BGRA conversion, pre-shutter masking, card/LiDAR scale,
volume geometry, persistence, and the full three-tab UI — is implemented and verified
against the dev-stub. Estimates are garbage *only* because `StubInferenceEngine`
(`MedataCore/Sources/Segmentation/StubInferenceEngine.swift`, behind `DEV_STUB_SEGMENTER`)
paints a deterministic centred ellipse instead of real food masks. Swap in a real model
and the pipeline produces a real number; nothing else is on the critical path.

Two myths to retire:

- **The "~22 s freeze" is not a code defect.** It is a Debug `-Onone` artifact; the
  Release build runs a full estimate in ~827 ms with no AR-frame starvation
  (`pipeline-rdc` D16 → `DECISIONS.md` MD-28). Do not schedule a perf fix for it.
- **OVERVIEW "Done" ≠ "shipped and trusted."** Several specs are code-complete but their
  *accuracy* is unverifiable until a real model and a labelled dataset exist (below).

## Per-spec MVP status

| Spec | Code state | On the MVP critical path? |
|---|---|---|
| `estimation/pipeline` | Complete behind the stub; harness restored but never run | **Yes** — owns the missing model + β_c calibration |
| `estimation/pipeline-real-device-correctness` | Done & verified (single-view LiDAR) | No — two-view on-device verify still open |
| `estimation/mv-volume-estimator` | **Superseded**, no code landed | No — premise was invalid (see below) |
| `estimation/lidar-first-scale-fallback` | Done & verified, 4/4 tasks | No |
| `capture/rawframe-rgb-conversion` | Done; one latent colour gap | No — gap is dormant on ARKit |
| `data/event-log-schema` | Done & verified, 15/15; carb result persists today | No |
| `ui/iphone-experience` | Done & verified, 60/60; degraded path handled | No — one cosmetic readout gap |
| `ui/shutter-blocked-feedback` | 4/5; success path unobserved | Indirectly — gated on the model |
| `ui/bubble-only-cleanup` | Done & verified | No — pure UI hygiene |

## The critical path (P0) — not agent-actionable

Reaching a real estimate requires work that is **data- and human-gated**, outside what a
coding agent can produce:

1. **Train + bundle the segmenter.** No `segmenter.mlpackage` exists anywhere in the tree;
   Release builds throw `segmenterModelMissing` (`PipelineFactory.swift`). Needs:
   FoodSeg103 (or equivalent) transfer-learn of DeepLabV3+MobileNetV3-Large, the
   `tools/segmenter/export.py` Core ML export, and ANE-residency verification. Bars:
   mean IoU ≥ 0.60 on a held-out set (MD-12).
2. **Calibrate β_c against a gravimetric dataset.** Every class currently ships
   `β = 1.0 / uncalibrated_unity`, so even with a good segmenter the carb number carries
   the visual-hull upward bias. Needs ≥ 30 gravimetric meals/class. `prerequisites.md`
   flags dataset acquisition as the single largest project risk; it is the true long pole.
3. **Then** the accuracy bar (MAPE < 20%, MD-25) becomes measurable for the first time —
   today it is structurally unverifiable.

## Agent/dev-actionable cleanups (P1) — small, independent

These are real spec↔code drifts the validation surfaced; none block the model but all are
cheap and worth clearing:

1. **Delete dead retention code.** `RetentionScheduler.swift` +
   `RetentionSchedulerTests.swift` remain in `MedataCore/Sources/Persistence/` although
   `estimation/pipeline` tasks 43/44 mark them DEFERRED-REMOVED.
2. **Δθ readout is inert (cross-spec contract gap).** `ResultView.maxDeltaThetaDeg` is
   hardcoded `0` because the persisted `PbConfidenceResult` lacks
   `deltaThetaNadirDeg`/`deltaThetaObliqueDeg`. The fix is on the **estimation** side
   (persist the fields); the UI is ready to consume them. (`ui` D21 / MD-19.)
3. **Video-range YCbCr colour gap (latent).** `PixelBufferAdapter` decodes both full- and
   video-range YCbCr with the full-range matrix. Dormant because ARKit emits full-range,
   but it will colour-shift any non-ARKit caller (e.g. the macOS `HarnessCLI`). Fix:
   select the matrix on the four-CC, or refuse `420v` per Req 1.5. (`rawframe` D8 / MD-17.)
4. **Shutter log subsystem split.** Two `estimate.end success=false` lines log under
   `ie.medata.captureflow`/`Estimation`, not the `Shutter` logger, so a single Console
   predicate misses them (`shutter` validation note).

## Verification debt (P2) — needs a device + (for accuracy) the model

- **Two-view SfS path never confirmed end-to-end on device** (iPhone 13 Pro Max, iOS 26.5).
  Tracked in `bugfixes/closeout-trail-mvp-cleanup` Phase 5 and
  `bugfixes/two-view-carve-no-volume` — the latter pins the real two-view
  `noFoodVolumeRecovered` symptom on a mis-aimed oblique capture / unwired tilt aim guide,
  **not** a segmenter or carve defect.
- **Success path never observed to complete** (`shutter` task 5 stays Pending) — the
  dev-stub refuses with `noFoodPixels`/garbage, so a clean `estimate.end success=true` +
  ResultView render is unconfirmed. Unblocks when the real model lands.
- **Single-view LiDAR success-path** on-device verification still untested.

## Why `mv-volume-estimator` is superseded (not a gap)

It proposed decoupling the volume path from the segmenter so two-view capture returns a
rough number instead of refusing. A static read invalidated its premise: the dev-stub
already paints a *food* class (`white_rice`) at ~0.99999 in both views, so the silhouette
is already carveable — the decouple solved a non-problem. The real two-view defect is
geometric/capture-side and lives in the bugfix above. Marked Superseded in OVERVIEW.

## Bottom line

Spec hygiene is now clean (references fixed, ledgers rune-valid, decision logs current).
The product gap is **not** in the specs or the Swift — it is the **absence of a trained
model and a gravimetric calibration set**. That is the whole MVP. The P1 cleanups can
proceed in parallel and independently; the P2 verifications mostly wait on the model.
