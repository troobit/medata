# Bugfix Report: LiDAR Plane Fit OOM on Device 1920×1440

**Date:** 2026-06-04
**Status:** Fixed (automated); on-device verification pending

## Description of the Issue

On iPhone 13 Pro Max iOS 26.5 (build of branch `bugfix_lidar-plane-fit-degenerate-on-clean-capture` after the prior fix at commit `ecf0211`), photographing a plate of fruit (bananas, grapes, orange) aborted the app immediately after the new DEBUG `event=supportplane.start width=1920 height=1440 fillFraction=0.700000` log line. Both capture stages completed at 1920×1440 with the camera flow indicating live LiDAR coverage at ~80% and tilt within the envelope. The process exited with `Fatal error: failed to allocate 32198713632 bytes of memory with alignment 8` — repeated three times in the log — before `event=supportplane.end` could fire.

**Reproduction steps:**

1. Stand on branch `bugfix_lidar-plane-fit-degenerate-on-clean-capture` at commit `ecf0211` (the prior bug's fix).
2. Build the iOS Debug variant and install on iPhone 13 Pro Max iOS 26.5.
3. Launch, grant camera + photo permissions.
4. Frame a plate of fruit (or any plate-of-food) on a flat table at ~30-45 cm with the centring guide; tilt ≈ 0° at the nadir stage and 25° at the oblique.
5. Tap the shutter.

**Observed device log (2026-06-04, archived at `nextup.md` lines 80-101):**

```
event=fired state=ready tiltDegrees=5.2 targetTilt=0 tiltInRange=true distanceCm=44.4
  lidarCoveragePercent=80.0 supportsLiDAR=true canShutter=true flowTaskActive=false
  startTaskActive=true mode=double stage=nadir
event=capture.start stage=nadir
event=capture.end   stage=nadir   success=true width=1920 height=1440
event=fired state=ready tiltDegrees=6.0 targetTilt=25 tiltInRange=false distanceCm=44.7
  ... stage=oblique
event=capture.start stage=oblique
event=capture.end   stage=oblique success=true width=1920 height=1440
event=estimate.start capturePath=two_view_sfs
event=supportplane.start width=1920 height=1440 fillFraction=0.700000
Fatal error: failed to allocate 32198713632 bytes of memory with alignment 8
Fatal error: failed to allocate 32198713632 bytes of memory with alignment 8
Fatal error: failed to allocate 32198713632 bytes of memory with alignment 8
```

`event=supportplane.end` is absent because the abort happens synchronously inside `LiDARPlaneFitter.fit` before the catch blocks in `Pipeline.fitSupportPlane` can run. Swift's allocation-failure path is uncatchable `fatalError`.

**Impact:** the app is unusable end-to-end on a device — the abort fires on every shutter tap that reaches the LiDAR plane fit. The prior bugfix unblocked the `lidarFitDegenerate` modal but the next stage now aborts the process. Until this is fixed the prior fix gives the user no observable progress.

## Investigation Summary

- **Symptoms examined:** the `event=supportplane.start` log line confirms the new centre-rectangle mask is being passed to `LiDARPlaneFitter.fit` (the prior bug's fix is doing its job); the absent `event=supportplane.end` and the triplet `Fatal error: failed to allocate 32198713632 bytes ...` placed the abort inside `LiDARPlaneFitter.fit`.
- **Number-sanity sieve:** `32,198,713,632 ÷ 4 ≈ 8.05 × 10⁹` Float32 elements; `√8.05e9 ≈ 89,721`. The allocator was asked for an n×n Float matrix at n ≈ 89,720. That ruled out random buffer corruption and pointed at a matrix-dimensioned allocation inside the support-plane path.
- **Code inspected:**
  - `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift` — `fit`, `collectCandidatePoints`, `ransac`, and `refine`. The candidate-point count (~290 k at 1920×1440 with the 0.7 fillFraction mask) and RANSAC retain rate (~⅓) put the inlier count near 90 k — matching the √-derived n.
  - `MedataCore/Sources/CardDetection/LinearAlgebra.swift` — `svdFull`. The unconditional `var vt = [Float](repeating: 0, count: n * n)` is the allocation site.
  - `Pipeline.fitSupportPlane` (`MedataCore/Sources/Pipeline/Pipeline.swift:372-449`) — confirmed it's a thin wrapper around `LiDARPlaneFitter.fit`; the allocation cannot originate from the Pipeline layer.
- **Hypotheses tested:**
  - Hypothesis A: a buffer in `collectCandidatePoints` overflows at 1920×1440. **Ruled out** — `points: [Vec3]` with 290 k entries is ~3.5 MB. Not 32 GB.
  - Hypothesis B: the RANSAC inlier reservations balloon. **Ruled out** — each `inliers: [Int]` of capacity n at 256 iterations is ~2.3 MB per iteration; ARC frees them.
  - Hypothesis C (confirmed): `LiDARPlaneFitter.refine` calls `LinearAlgebra.svdFull(_, rows: 3, cols: n)` which always allocates an n×n V^T. At n ≈ 89 720 this is ~32 GB. `refine` never reads `svd.vt`; the entire allocation is waste.

## Discovered Root Cause

`LiDARPlaneFitter.refine` (`MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift:197-229` pre-fix) builds the centred inlier matrix and asks LAPACK for the full SVD:

```swift
var a = [Float](repeating: 0, count: 3 * n)
for idx in 0..<n {
    let p = inliers[idx] - centroid
    a[idx * 3 + 0] = p.x
    a[idx * 3 + 1] = p.y
    a[idx * 3 + 2] = p.z
}
let svd = try LinearAlgebra.svdFull(a, rows: 3, cols: n)
```

`LinearAlgebra.svdFull` (`MedataCore/Sources/CardDetection/LinearAlgebra.swift:25-54`) requests `JOBU='A'`, `JOBVT='A'` and unconditionally allocates:

```swift
var u  = [Float](repeating: 0, count: m * m)   // 3 × 3 = 9
var vt = [Float](repeating: 0, count: n * n)   // ~89,720² ≈ 8.05e9
```

For the device input:

- 1920×1440 frame, 0.7 fillFraction centre-rectangle mask → scan band ~217 rows × ~1344 cols ≈ 291 k candidate pixels.
- A clean LiDAR plane with high confidence retains most candidates as inliers (~⅓ within ±5 mm).
- `n ≈ 89 720` inliers → `vt = 89,720² × 4 ≈ 32 GB`.
- iOS allocator returns failure → Swift `fatalError` → process abort.

`refine` reads only `svd.u` (3 left singular vectors) and `svd.s` (3 singular values); `svd.vt` is never consumed. The entire n×n V^T computation is dead work.

**Defect type:** Algorithmic — using a full-matrix LAPACK routine where only the small-side singular vectors are needed.

**Why it occurred:** when `LiDARPlaneFitter` was first written, the same `LinearAlgebra.svdFull` helper used by `CardPoseSolver` (8×9 and 3×3 matrices, both safe) was reused for a 3×n matrix. At test-fixture scales (n in the hundreds) the n×n V^T allocation is invisible (~tens of KB). At device scales (n in the tens of thousands) it explodes quadratically. The prior bug's `noLidarPoints` early return masked this for the entire history of the codebase; `ecf0211` was the first commit to ever call `refine` with a non-trivial inlier set on a 1920×1440 frame.

**Contributing factors:** `LinearAlgebra.svdFull`'s name and signature don't telegraph that V^T allocation is unconditional. A reader inspecting `refine` would have to follow the helper into LAPACK-flag territory to spot the cost. The new comment block in the fixed `refine` explains the algorithmic substitution and references this spec.

## Resolution for the Issue

**Changes made:**

- `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift` — rewrite the body of `refine(inliers:seedNormal:)`. Replace the 3×n column-major matrix and `LinearAlgebra.svdFull(_, rows: 3, cols: n)` with:
  1. A single O(n) pass over the inliers that accumulates the symmetric 3×3 scatter matrix `M = Σ (pᵢ − c)(pᵢ − c)ᵀ` into six scalar accumulators `m00..m22`.
  2. `LinearAlgebra.svdFull(mCol, rows: 3, cols: 3)` on M packed into a 9-element column-major Float array.
  3. Plane normal = column 2 of `svd.u` (smallest singular value of M = smallest singular value of A, same column index as before).
  4. Stability gate updated to `√svd.s[2] / √svd.s[0] ≥ stabilityRatioMin` — preserves the existing 1e-6 threshold against A's singular-value ratio (since M's singular values are A's squared).
- `MedataCore/Tests/SupportPlaneTests/LiDARPlaneFitterRefineScaleTests.swift` (new) — two Swift Testing cases: small-scale equivalence (300 perturbed-planar points → recovers seed normal and d ≈ 100 mm) and moderate-scale allocation bound (10 000 tilted-plane points → recovers normal/d and asserts RSS delta < 64 MB via `mach_task_basic_info`).

**Approach rationale:** the smallest surgical change that closes the root cause. The 3×3 scatter-matrix path is mathematically equivalent in real arithmetic (M's eigenvectors are A's left singular vectors; M's singular values are A's squared), and reuses the existing `LinearAlgebra.svdFull` helper (which is correct and tested at the 3×3 size by `CardPoseSolver`'s call sites). No new dependencies; no `LinearAlgebra` API change so `CardDetection`/`CardPoseSolver` are unaffected; no `LiDARPlaneFitter` public-API change so `Pipeline.fitSupportPlane` is unchanged. Compute also drops from O(n²) to O(n) as a side-benefit.

**Alternatives considered:** see `decision_log.md` Decision 1. Briefly: adding a `svdLeft` variant (`JOBVT='N'`) was rejected as a broader API change for one call site when the scatter-matrix path is provably equivalent and simpler; subsampling inliers was rejected as discarding information and not addressing the algorithmic defect; using Accelerate `vDSP_svd` directly was rejected as adding a new code path when the existing helper at 3×3 works.

## Regression Test

**Test file:** `MedataCore/Tests/SupportPlaneTests/LiDARPlaneFitterRefineScaleTests.swift`.

**What it verifies:**

- **Case (a) — `refineSmallEquivalence` (correctness anchor):** 300 points on a perturbed plane at y = 100 mm with 0.05 mm jitter. After `refine`, the recovered normal aligns with the +y seed to within `abs(normal.y) > 0.999`, and d is within 0.5 mm of 100. Pins that the algebraic substitution gives the same answer as the prior code on a small input.
- **Case (b) — `refineAllocationBoundedAtModerateN` (OOM sentinel):** 10 000 points on a 3°-tilted plane at d = 200 mm with 0.2 mm jitter (the same fixture style as `SupportPlaneRoughMaskTests`). The call to `refine` is wrapped in a `mach_task_basic_info`-based RSS-delta probe. Asserts the delta is below 64 MB. Pre-fix, the n×n V^T buffer is `10,000² × 4 ≈ 400 MB` and the delta assertion fails with the actual measured ~383 MB; post-fix the RSS growth is sub-MB.

**Run command:**

```
swift test --filter LiDARPlaneFitterRefineScaleTests
```

Or equivalent Xcode-based test:

```
xcodebuild test \
  -scheme MedataCore-Package \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,arch=arm64' \
  -only-testing:SupportPlaneTests/LiDARPlaneFitterRefineScaleTests
```

## Affected Files

| File | Change |
|------|--------|
| `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift` | `refine(inliers:seedNormal:)` rewritten to use 3×3 scatter-matrix SVD instead of 3×n full SVD; comment block now references this spec |
| `MedataCore/Tests/SupportPlaneTests/LiDARPlaneFitterRefineScaleTests.swift` | New file — 2 Swift Testing cases: small-scale equivalence; moderate-scale RSS-bound OOM sentinel |

## Verification

**Automated (complete):**

- [x] `swift build` — clean Debug build, no new warnings.
- [x] `swift build -c release` — clean Release build (the pre-existing build warning in `Volume`/`SimdAdapter` is unrelated; introduced by an earlier branch).
- [x] `swift test --filter LiDARPlaneFitterRefineScaleTests` — 2/2 pass.
- [x] `swift test` — full `MedataCore` package: 271 XCTest cases (0 failures, 2 pre-existing skips) plus 9 Swift Testing cases all pass. The prior bug's `CentreRectangleMaskTests` and `SupportPlaneRoughMaskTests` remain green; the existing `LiDARPlaneFitterTests` (XCTest) suite — including correctness, deterministic-seed, and residual-cap cases — all pass against the new `refine` implementation.

**Manual / on-device (pending):**

- [ ] Install the Debug build of the new branch on iPhone 13 Pro Max iOS 26.5; tap the shutter on a fruit-plate test capture (bananas, grapes, orange on a flat table at ~30-45 cm); capture the device log via Xcode Console or `log stream --predicate 'subsystem == "ie.medata.app"'`.
- [ ] Expected log shape (Debug build):

  ```
  event=fired state=ready ... stage=nadir
  event=capture.start stage=nadir
  event=capture.end   stage=nadir   success=true width=1920 height=1440
  event=capture.start stage=oblique
  event=capture.end   stage=oblique success=true width=1920 height=1440
  event=estimate.start capturePath=two_view_sfs
  event=supportplane.start width=1920 height=1440 fillFraction=0.7
  event=supportplane.end   success=true residual_mm=... inliers=... candidates=...
  event=estimate.end   ...
  ```

- [ ] The `Fatal error: failed to allocate ...` line must NOT appear. (A different downstream failure such as `noFoodVolumeRecovered` is acceptable for Phase 1, since the dev-stub segmenter does not produce real food classes.)
- [ ] Append the captured on-device log block to this report's Verification section once the run is observed.

## Prevention

**Recommendations to avoid similar bugs:**

- `LinearAlgebra.svdFull`'s contract — that it unconditionally allocates an n×n V^T regardless of caller need — is invisible at the call site. If `svdFull` gains another caller in future, add a doc comment on the function itself flagging the O(n²) allocation and pointing the reader at the scatter-matrix recipe in `LiDARPlaneFitter.refine` for the small-side-only case. Even better: introduce a sibling `svdLeftOnly(_:rows:cols:)` that calls `sgesvd_` with `JOBVT='N'` and rename the existing helper `svdFullUV` so the cost is explicit in the name. Out of scope for this bugfix.
- The regression test in `LiDARPlaneFitterRefineScaleTests` uses `mach_task_basic_info` RSS-delta probing. Consider extracting this into a shared `MemoryProbe` test helper under `MedataCore/Tests/Helpers/` if a second test needs the same pattern.
- Whenever a bugfix unblocks a previously-unreachable downstream code path, schedule a quick on-device run on the largest input size the field exercises (here: 1920×1440 main wide camera). The prior bugfix could not have caught this — the simulator's smaller fixtures don't surface the quadratic cost — but a single device run after merge would have.
- The follow-on full spec `specs/pipeline-real-device-correctness/` (not yet created) is now more attractive: a real food-region mask from segmentation would shrink the candidate band substantially. That's still a perf-not-correctness win; the algorithmic fix here is the durable one.
