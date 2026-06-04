# Decision Log: LiDAR Plane Fit OOM on Device 1920×1440

## Decision 1: Replace the 3×n SVD in `LiDARPlaneFitter.refine` with a 3×3 scatter-matrix SVD

**Date**: 2026-06-04
**Status**: accepted

### Context

`LiDARPlaneFitter.refine` (`MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift:197-229`) builds a column-major 3×n matrix `A` of centred inlier points and calls `LinearAlgebra.svdFull(A, rows: 3, cols: n)` to recover the plane normal (the left singular vector of A corresponding to the smallest singular value) and to check the SVD stability ratio. `LinearAlgebra.svdFull` (`MedataCore/Sources/CardDetection/LinearAlgebra.swift:25-54`) always requests full SVD with `JOBU='A'` and `JOBVT='A'` and unconditionally allocates an n×n `vt` Float matrix.

On iPhone 13 Pro Max iOS 26.5 (2026-06-04 fruit-plate test capture, device log archived at `nextup.md` lines 80-101), the 1920×1440 capture flow now reaches `LiDARPlaneFitter.refine` with ~89 720 inliers. The `vt` allocation request is `89,720² × 4 ≈ 32.2 GB` (matches the `Fatal error: failed to allocate 32198713632 bytes of memory with alignment 8` line exactly), the iOS allocator returns failure, and the process aborts. `refine` never reads `svd.vt`; only `svd.u` (3×3) and `svd.s` (length 3) are used.

The prior bugfix (`specs/bugfixes/lidar-plane-fit-degenerate-on-clean-capture/`, commit `ecf0211`, landed 2026-06-03) made this defect reachable for the first time. Before that commit, `LiDARPlaneFitter` threw `noLidarPoints` on the all-ones placeholder mask before `refine` ran. The defect itself has been latent since `LiDARPlaneFitter` was first introduced — the same call would have OOM'd on any prior caller that passed a real food-region mask at 1920×1440 resolution.

### Decision

In `LiDARPlaneFitter.refine`, replace the `LinearAlgebra.svdFull(A, rows: 3, cols: n)` call with a SVD of the 3×3 symmetric scatter matrix `M = Σᵢ (pᵢ − c)(pᵢ − c)ᵀ`. Accumulate M's six unique entries in a single O(n) pass directly from the inlier array (no intermediate 3×n buffer). The plane normal is `svd.u[:, 2]` of M's SVD (same column index as before); the stability gate becomes `√M.s[2] / √M.s[0] ≥ stabilityRatioMin` (preserving the 1e-6 threshold against A's singular-value ratio). `LinearAlgebra.svdFull` is unchanged so `CardPoseSolver`'s 8×9 and 3×3 call sites are unaffected.

### Rationale

For a 3×n column-major matrix A whose columns are centred 3-D points, the plane fit needs only A's smallest left singular vector. The left singular vectors of A equal the eigenvectors of A·Aᵀ = M (a 3×3 symmetric PSD matrix), and A's singular values are the square roots of M's. Computing M directly avoids materialising the n×n V matrix entirely:

- **Memory**: O(n) for the inlier array (which already existed) plus 9 Floats for M plus the 3×3 SVD's tiny `u`/`vt`/`s`. The pre-fix code allocated O(n²) on top of that.
- **Compute**: O(n) for the scatter accumulation plus a 3×3 SVD (constant). The pre-fix code did an O(n²) SVD step inside `sgesvd_`.
- **Mathematical equivalence**: exact in real arithmetic. Float32 rounding may differ in the last few low-order bits of the singular values; the regression test asserts the recovered normal and d match the synthesised plane to 0.5 mm.

This is the minimum-surface fix: one function rewritten, no public API changes, no changes to `LinearAlgebra.svdFull` (so `CardPoseSolver` and its tests are untouched), no new dependencies. The 3×3 SVD path is exercised by `CardPoseSolver` already and is known to work.

### Alternatives Considered

- **Add a `svdSmallM` variant returning only U and S (`JOBU='A'`, `JOBVT='N'`)**: Skips the n×n V allocation while keeping the existing 3×n call shape in `refine` — Rejected because the SVD work itself is still O(n) for sgesvd's bidiagonalisation and the API change is broader than the fix needs. The scatter-matrix path is simpler, requires no `LinearAlgebra` API addition, and is mathematically what we want.
- **Subsample inliers before SVD (cap at ~5 000 points)**: Bounds the allocation by truncating the inlier set — Rejected because it discards information available to the least-squares refinement, makes the result stochastic-by-budget, and doesn't address the algorithmic waste; the same `svdFull` shape with `JOBVT='A'` is still wrong.
- **Use Accelerate's `vDSP_svd` or `LAPACKE_sgesdd_` directly**: Lower-level call avoiding the full-V allocation — Rejected as adding a new Accelerate code path for one call site when the scatter-matrix path uses the existing `svdFull` and is provably equivalent.
- **Reorder the pipeline so segmentation runs first and the food-region mask shrinks the inlier band**: Reduces n upstream — Rejected because (a) it doesn't fix the latent O(n²) bug, it only papers over it for one mask shape; (b) it reorders the pipeline stages, which is the same out-of-scope move the prior bugfix decision rejected.
- **Hold the fix and run on-device with a reduced fillFraction to bound n**: Tune `centreRectangleFillFraction` downward so the band yields fewer candidates — Rejected because it changes the documented geometry of the rough mask for a perf workaround and still has an O(n²) trap waiting on the next caller.

### Consequences

**Positive:**

- The `Fatal error: failed to allocate ...` abort stops firing on the iPhone 13 Pro Max capture envelope.
- The fix is localised: one function in one file, ~25 LOC of rewrite, no API changes.
- Compute drops from O(n²) work in LAPACK to O(n) accumulation plus a constant-time 3×3 SVD. On 1920×1440 inputs this is several orders of magnitude faster as well as smaller.
- Regression coverage via RSS-delta probe in `LiDARPlaneFitterRefineScaleTests` catches any future re-introduction of an O(n²) buffer in `refine`.

**Negative:**

- Float32 numerical precision: accumulating M's entries as `Σ p.x²` etc. can lose low-order bits when the partial sum grows large relative to the per-point contributions. The existing 3×n SVD path also suffered from float32 precision at scale (and produced numerically degenerate σ_min at the precision floor — see the test-author's note in `LiDARPlaneFitterRefineScaleTests.swift`). On the synthesised tilted-plane fixture the recovered normal and d match the synthesised plane to within 0.5 mm at n = 10 000. If a future user reports a residual jump on very large inlier sets, the mitigation is Kahan-compensated summation (~10 LOC) or accumulating in Double.
- The plane-normal index `svd.u[6..8]` now indexes M's eigenvectors rather than A's left singular vectors. Mathematically the same column; future readers must follow the new comment block in `refine` rather than relying on the prior "smallest right singular vector" comment.

### Impact

`MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift` only. No call-site changes; `LiDARPlaneFitter.fit`, the RANSAC stage, and `Pipeline.fitSupportPlane` are unchanged. `LinearAlgebra.svdFull` is unchanged, so `CardDetection`/`CardPoseSolver` callers are unaffected. Test coverage adds one new file: `MedataCore/Tests/SupportPlaneTests/LiDARPlaneFitterRefineScaleTests.swift`.

---
