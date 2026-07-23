# CLOUT — the stride bugfix and the road to the MVP

Status, 2026-07-23, branch `bugfix/segmenter-output-stride-ignored`. Two questions:
what this branch fixes, and what still stands between here and a shippable MVP.
Full bugfix detail: [report.md](specs/bugfixes/segmenter-output-stride-ignored/report.md).
Estimation-accuracy sequencing: [snaq-parity spec](specs/estimation/snaq-parity/) and
[estimation-improvement-avenues](docs/agent-notes/estimation-improvement-avenues.md).

## The bugfix: segmenter output stride ignored

**Symptom.** Every on-device capture with the real Core ML segmenter produced
garbage: 87–99 % of the frame classified as `unsupported_liquid`, mask overlays
sheared into diagonal streaks, and result rows listing foods that were not on the
plate (a bowl of Weetabix yielded milk, pork, mashed potato, salad leaves, pasta…).
The same photo through the same checkpoint on the Mac — both PyTorch and the
exported `.mlpackage` via coremltools — was sane (≈ 91 % background). So the model,
the export pipeline, and the harness were all fine; only the device path was wrong.

**Root cause.** Core ML pads output rows for memory alignment: the segmenter's
513-wide output `MLMultiArray` comes back with a 544-element row stride
(`strides=[9767520, 279072, 544, 1]` for `shape=[1, 35, 513, 513]`).
`CoreMLInferenceEngine.unpackLogits` read the raw buffer with dense linear
indexing (`c*h*w + y*w + x`), ignoring `.strides` entirely. Each row read
therefore drifted 31 elements further into the buffer — every logit plane sheared
diagonally, per-pixel class vectors were assembled from unrelated spatial
positions, and the argmax collapsed into the liquid flood.

**Why it survived so long.** The export-time equivalence oracle runs through
coremltools, which honours strides; every Swift test drives the pipeline through
stub/canned engines that return dense arrays; and Debug builds use the stub
segmenter. The defect only manifests on Release + real model — the least-observed
configuration until the capture-bundle recorder (commit `75b254d`) made field
captures replayable and the shear visible.

**The fix.** `unpackLogits` now derives (class, row, column) element strides from
`MLMultiArray.shape`/`.strides` for both CHW and HWC layouts and gathers through
them; `writeLogits` collapsed to a single strided-gather loop. Dense arrays are
just the case where the strides happen to be dense, so contiguous outputs are
unchanged. A shape/strides count mismatch now throws instead of reading garbage.

**Verification.** Regression tests with row-padded, NaN-sentinelled
`MLMultiArray`s went red → green; full suite green (XCTest 502, 3 skipped;
swift-testing 151 in 21 suites); Mac replay of the field capture matches the
coremltools reference to FP16 noise (90.65 % background); on-device re-capture
segments 2 Weetabix as one coherent region — 75.4 % background, 24.6 %
`bread_white`, no flood, no shear.

**What it means.** Every prior on-device real-model result was meaningless — the
"estimation work isn't yielding positive results" field experience was
substantially this defect, not (only) model quality. On-device estimation is now
producing its first trustworthy outputs. The re-capture also surfaced the next
two real gaps: the palette has no cereal class (Weetabix maps to `bread_white`),
and the ~100 g carb read is the known uncalibrated β = 1.0 overestimate.

## What is left for the MVP

The bundled model is still `24e0b022241a` (leak-free mean food IoU 0.3776 against
the 0.48 gate). With the stride fix in, on-device numbers are finally *measurable*
— which is what the remaining sequence depends on.

1. **Land this branch.** Merge to `research`; pushing is the user's call
   (denied in settings).
2. **On-device capture verify — the MVP gate** (model-production Req 6.3,
   [prerequisites](specs/estimation/model-production/prerequisites.md)). Blocked
   until now by this very bug; the 2026-07-23 re-capture is the first credible
   pass at it. Also closes capture-bundle-recorder task 4 (bundle → Files app →
   Mac → HarnessCLI replay), which is already part-proven by this investigation.
3. **The device-pass checklist backlog** — one iPhone 16 Pro session covers the
   human-gated "looks right" verifies across the In Progress specs: home-router
   task 9, cgm-connect task 14, the manual-carb-intake checklist (design.md tail),
   loading-symbol task 5, shutter-blocked task 5, snaqui task 8, and the
   design-handoff-00 checklist.
4. **The snaq-parity exit condition** ([Req 8](specs/estimation/snaq-parity/requirements.md),
   ordered per [prerequisites](specs/estimation/snaq-parity/prerequisites.md)) —
   all tooling is built; what remains is running it:
   - tail-profile capture session + latency-budget derivation (before any
     bake-off verdict);
   - architecture bake-off (`spike_convert.py` over EfficientViT-B0/B1,
     SeaFormer-Base, PP-MobileSeg, measured on the 16 Pro);
   - training runs: winner-architecture via the `archs.py` registry, and the
     external co-occurrence run (blocked on the Recipe1M+ licence check);
   - **≥ 20 weighed-meal benchmark** via `BenchmarkView` (±1 g kitchen scale) —
     without it there is no end-to-end carb-MAE number at all;
   - model promotion only through the `promotionVerdict` gate.
5. **Known accuracy gaps to log, not necessarily fix, for MVP:** no cereal class
   in the palette (candidate for the MyFoodRepo-273 bridge, the contingent big
   move if ≤ ~13 g carb MAE is unmet); β_c gravimetric calibration is explicitly
   deferred past the MVP, so carb magnitudes stay coarse.
6. **Resolved decisions (2026-07-24):** the non-LiDAR two-view + ID-1-card mode is
   **retained, not descoped** (segmenter-foundation Decision 26) — availability
   wins, LiDAR is used when present; the OS-floor discrepancy is **reconciled** —
   the app floor is iOS 26.5 and `CLAUDE.md` now says so (the MedataCore SwiftPM
   package keeps its loose iOS 17 / macOS 14 target). Still open: the
   capture-bundle recorder's pre-release removal is a checklist item before any
   non-developer build.
7. **Close-out mechanics:** record verdicts (positive *and* negative) in the
   snaq-parity decision log, regenerate `specs/OVERVIEW.md` statuses, then merge
   `research` → `main` and push — both the user's call.

Items 2–4 are human-gated (device in hand, kitchen scale, detached training
runs); nothing in them is blocked on unwritten code.
