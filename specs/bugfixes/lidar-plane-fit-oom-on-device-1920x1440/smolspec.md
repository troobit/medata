# LiDAR Plane Fit OOM on Device 1920×1440

## Overview

On iPhone 13 Pro Max iOS 26.5, the support-plane fit now aborts the app immediately after the new DEBUG `event=supportplane.start width=1920 height=1440 fillFraction=0.7` log fires. The fix shipped under `specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/` (commit `ecf0211`) unblocked the prior `noLidarPoints` early return, exposing a latent integer-scaling defect in `LiDARPlaneFitter.refine` that requests an n²-Float V^T matrix from LAPACK. At 1920×1440 with the 0.7 fillFraction centre-rectangle mask, the resulting inlier count puts the allocation at ~32 GB and the process aborts. Stacked on top of the prior bug branch because the prior fix is the prerequisite for this defect to ever surface.

## Evidence

Device log captured 2026-06-04 (archived at `nextup.md` lines 80-101, iPhone 13 Pro Max iOS 26.5, fruit-plate test capture, bananas / grapes / orange):

```
event=fired state=ready tiltDegrees=5.2 distanceCm=44.4 lidarCoveragePercent=80.0
  supportsLiDAR=true canShutter=true mode=double stage=nadir
event=capture.start stage=nadir
event=capture.end   stage=nadir   success=true width=1920 height=1440
event=fired state=ready tiltDegrees=6.0 ... stage=oblique
event=capture.start stage=oblique
event=capture.end   stage=oblique success=true width=1920 height=1440
event=estimate.start capturePath=two_view_sfs
event=supportplane.start width=1920 height=1440 fillFraction=0.700000
Fatal error: failed to allocate 32198713632 bytes of memory with alignment 8
Fatal error: failed to allocate 32198713632 bytes of memory with alignment 8
Fatal error: failed to allocate 32198713632 bytes of memory with alignment 8
```

Note `event=supportplane.end` is absent — the fatal occurs synchronously inside `LiDARPlaneFitter.fit` before the catch blocks in `Pipeline.fitSupportPlane` can run. Swift's allocator-failure path is `fatalError`, which is uncatchable.

Number sanity check: `32,198,713,632 / 4 = 8,049,678,408` Float32 elements; `√8.05e9 ≈ 89,721`. So an n×n Float matrix at n ≈ 89,720 was requested — consistent with an inlier count produced by a 1920×1440 frame under the 70% centre-rectangle mask.

## Root cause

`LiDARPlaneFitter.refine` (`MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift:197-229`) builds a column-major 3×n centred matrix from the RANSAC inliers and calls `LinearAlgebra.svdFull(a, rows: 3, cols: n)` to recover the smallest left singular vector as the plane normal. `LinearAlgebra.svdFull` (`MedataCore/Sources/CardDetection/LinearAlgebra.swift:25-54`) always requests full SVD with `JOBU='A'` and `JOBVT='A'`, and unconditionally allocates:

```swift
var vt = [Float](repeating: 0, count: n * n)
```

For the device frame (1920×1440, 0.7 fillFraction):

- The fitter's lower-edge scan band is `y ∈ [bbox.maxY, min(height-1, bbox.maxY + bbox.heightPx)]` with `xMin..xMax` from the bbox.
- At 1920×1440 the band is ~217 rows × ~1344 cols ≈ 291 k candidate pixels.
- With a clean synthetic-like table region (high confidence and a real LiDAR plane), most candidates land within the ±5 mm RANSAC inlier band — ~90 k inliers.
- `vt` then demands `89,720² × 4 ≈ 32 GB`. The phone's allocator returns failure; Swift fatalErrors.

`refine` never reads `svd.vt`; only `svd.u` (3×3) and `svd.s` (length 3) are consumed. The entire n×n V^T computation is pure waste.

This is unrelated to `arview-session-config-race` (the FigCaptureSourceRemote `-12784` / `-12710` and `VideoLightSpillGenerator` `MTLPixelFormatYCBCR8_420_2P` lines earlier in the log are pre-existing, separate concerns).

## Requirements

- The system MUST complete `LiDARPlaneFitter.fit(_:)` on the iPhone 13 Pro Max capture envelope (1920×1440 nadir + oblique frames, 0.7 fillFraction centre-rectangle mask) without aborting on a memory allocation.
- The system MUST preserve the existing plane-normal contract: `LiDARPlaneFitter.refine` returns the smallest left singular vector of the centred inlier matrix as the plane normal, sign-aligned with the seed.
- The system MUST preserve the existing stability gate: ratio of smallest to largest singular values of the centred inlier matrix ≥ `LiDARPlaneFitter.stabilityRatioMin` (1e-6).
- The fix SHOULD touch only `LiDARPlaneFitter.refine`. `LinearAlgebra.svdFull`'s contract is shared with `CardPoseSolver` (8×9 and 3×3 inputs) and should not be changed.
- The system MUST have regression coverage that prevents reintroduction of an O(n²) allocation in `refine`.

## Implementation Approach

### Chosen fix (see Decision 1 in `decision_log.md`)

Replace the 3×n SVD with a 3×3 SVD of the symmetric scatter matrix `M = Σ (pᵢ − c)(pᵢ − c)ᵀ`. The left singular vectors of M are the left singular vectors of A; M's singular values are A's squared. So:

- Plane normal = `svd.u[:, 2]` of M's SVD (same column index as before).
- Stability gate: `sqrt(svd.s[2]) / sqrt(svd.s[0]) ≥ stabilityRatioMin` (preserves the 1e-6 threshold against A's singular-value ratio).
- Centroid and d computation unchanged.

Computational cost drops from `O(n²)` memory and `O(n²)` SVD work to `O(n)` scatter accumulation and a 9-element SVD.

### Affected files

- **`MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift`** (~25 LOC) — rewrite the body of `refine(inliers:seedNormal:)` to accumulate `m00..m22` in one pass and call `LinearAlgebra.svdFull(mCol, rows: 3, cols: 3)`. No API change.
- **`MedataCore/Tests/SupportPlaneTests/LiDARPlaneFitterRefineScaleTests.swift`** (new, ~90 LOC) — Swift Testing suite with two cases: (a) small-scale equivalence — 300 points on a perturbed plane recover the seed normal at d ≈ 100; (b) moderate-scale allocation bound — 10 000 points on a 3°-tilted plane recover the plane and the test wraps the call in a `mach_task_basic_info` RSS-delta probe asserting `delta < 64 MB`. Pre-fix the V^T allocation is ~400 MB and the assertion fails; post-fix the call uses negligible memory.

### Patterns to follow

- `LiDARPlaneFitter`'s public API and the rest of the fit() pipeline are unchanged. Only the internal `refine` helper is rewritten.
- The 3×3 scatter accumulation mirrors the existing `LiDARPlaneFitter.computeResidual` style: a tight `for p in inliers` loop with scalar accumulators.
- Sentinel logging is unchanged — the prior bugfix's `event=supportplane.start` / `event=supportplane.end` events already report `inliers`, `candidates`, and `residual_mm`. Post-fix the device will start emitting `supportplane.end success=true` for the first time.

### Verification

1. `swift test --filter LiDARPlaneFitterRefineScaleTests` — both cases pass post-fix; the allocation-bound case fails pre-fix with `delta ≈ 400 MB`.
2. Full `MedataCore` suite (`swift test`) — no regressions in `LiDARPlaneFitterTests`, `SupportPlaneRoughMaskTests`, `CardOnlyPlaneFitterTests`, or anywhere else.
3. `swift build -c release` — Release build clean.
4. On-device verification on iPhone 13 Pro Max iOS 26.5 (the fruit-plate test): expected device log shows `event=supportplane.end success=true residual_mm=... inliers=... candidates=...` instead of the `Fatal error: failed to allocate ...` abort. Append the captured log to `report.md` once observed.

### Out of scope

- Replacing `LinearAlgebra.svdFull` with a thin-SVD variant (`JOBVT='S'` or `'N'`). The shared API is also used by `CardPoseSolver` on 8×9 and 3×3 inputs where it works fine. Tracked as a future optimisation if more callers hit the V^T tax.
- The shutter-button-flash + `FigCaptureSourceRemote -12784` / `(Fig) -12710` bursts at launch in the same device log. Covered by `specs/bugfixes/arview-session-config-race/`.
- The `VideoLightSpillGenerator … Failed to create input texture with MTLPixelFormat MTLPixelFormatYCBCR8_420_2P` RealityKit-prewarm line. Cosmetic, no pipeline impact.
- Replacing the centre-rectangle approximation with a real food-region mask from a pre-shutter segmentation pass. Same follow-on spec referenced by the prior bug (`specs/estimation/pipeline-real-device-correctness/`, now landed — its Req 1/2 produce the pre-shutter mask that feeds `LiDARPlaneFitter.Inputs.foodRegionMask`).
- A general audit of every `svdFull` call site for similar quadratic-V^T waste. The only at-risk caller is `LiDARPlaneFitter`; the two `CardPoseSolver` call sites are at fixed 8×9 and 3×3 dimensions.

## Risks and Assumptions

- **Risk**: Numerical precision loss in float32 when accumulating the scatter matrix over very large inlier sets. `m00 += p.x * p.x` could lose low-order bits as the partial sum grows. **Mitigation**: post-fix `refineSmallEquivalence` (300 points) and `refineAllocationBoundedAtModerateN` (10 000 points) both recover the synthesised normal and d within 0.5 mm / 1.0 mm tolerances. On-device verification will confirm the residual stays below the existing 20 mm cap.
- **Risk**: The stability ratio interpretation changes — we now compare `√M.s[2] / √M.s[0]` instead of `A.s[2] / A.s[0]`. **Mitigation**: `M.s[i] = A.s[i]²` by construction (M is symmetric PSD; singular values equal eigenvalues equal squared singular values of A), so `√M.s[2]/√M.s[0] = A.s[2]/A.s[0]` exactly in real arithmetic. The 1e-6 threshold is preserved.
- **Risk**: The `Vec3(svd.u[6], svd.u[7], svd.u[8])` indexing for "column 2 of U in column-major layout" depended on `svdFull` returning A's left singular vectors. Now it returns M's. **Mitigation**: M's eigenvectors are A's left singular vectors (since M = A·Aᵀ → eigendecomposition M = U Σ² Uᵀ uses the same U). Column index 2 still corresponds to the smallest singular value because both A and M return singular values in descending order.
- **Assumption**: `LinearAlgebra.svdFull` is correct for symmetric 3×3 inputs. **Validation**: `CardPoseSolver` already calls `svdFull(_, rows: 3, cols: 3)` twice with non-symmetric 3×3 inputs and the existing `CardPoseSolverTests` cover it.
- **Prerequisite**: The prior fix (`ecf0211`) is in place — without the centre-rectangle mask the pre-existing `noLidarPoints` early return masks this defect.
