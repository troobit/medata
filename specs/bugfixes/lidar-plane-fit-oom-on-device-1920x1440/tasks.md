---
references:
    - specs/bugfixes/lidar-plane-fit-oom-on-device-1920x1440/smolspec.md
    - specs/bugfixes/lidar-plane-fit-oom-on-device-1920x1440/decision_log.md
---
# LiDAR Plane Fit OOM on Device 1920×1440 — Tasks

- [x] 1. `LiDARPlaneFitter.refine` uses a 3×3 scatter-matrix SVD instead of a 3×n SVD <!-- id:oom-001 -->
  - **Outcome:** `MedataCore/Sources/SupportPlane/LiDARPlaneFitter.swift:197-229` no longer constructs a 3×n `[Float]` buffer or calls `LinearAlgebra.svdFull(_, rows: 3, cols: n)`. It accumulates the symmetric 3×3 scatter matrix `M = Σᵢ (pᵢ − c)(pᵢ − c)ᵀ` in one O(n) pass over the inliers, calls `LinearAlgebra.svdFull(mCol, rows: 3, cols: 3)`, and recovers the plane normal as column 2 of `svd.u`. The stability gate compares `√svd.s[2] / √svd.s[0]` against `stabilityRatioMin` to preserve the existing 1e-6 threshold against A's singular-value ratio. `LinearAlgebra.svdFull` is unchanged.
  - **Approach:** scalar accumulators `m00..m22` summed in a single `for idx in 0..<n` loop, packed into a column-major `[Float]` of length 9. Centroid computation and the seed-aligned sign flip and `d = nHat·centroid` are unchanged.
  - **Verification:** `swift build` and `swift build -c release` are clean; `swift test --filter LiDARPlaneFitterTests` passes (the existing small-fixture suite covers correctness on the 64×48 grid).
  - **References:** smolspec.md (Implementation Approach > Chosen fix), decision_log.md (Decision 1).

- [x] 2. Regression test reproduces the O(n²) allocation pre-fix and is bounded post-fix <!-- id:oom-002 -->
  - **Outcome:** `MedataCore/Tests/SupportPlaneTests/LiDARPlaneFitterRefineScaleTests.swift` contains two Swift Testing cases. Case (a) `refineSmallEquivalence` puts 300 perturbed-planar points through `LiDARPlaneFitter.refine` and asserts the recovered normal aligns with the +y seed and d ≈ 100 mm (anchors the algebraic substitution). Case (b) `refineAllocationBoundedAtModerateN` puts 10 000 points on a 3°-tilted plane (the same fixture style as `SupportPlaneRoughMaskTests`) through `refine`, reads RSS via `mach_task_basic_info` before and after the call, and asserts the delta is below 64 MB. Pre-fix, the n×n V^T buffer is `10,000² × 4 ≈ 400 MB` and the delta assertion fails; post-fix, RSS growth is sub-MB.
  - **Approach:** use `@testable import SupportPlane` to call the internal `refine`. Use `Darwin`'s `task_info(... MACH_TASK_BASIC_INFO ...)` to read `resident_size`. The tilted-plane fixture keeps σ_min above the float32 precision floor at n = 10 000 so the stability gate is not the failing assertion.
  - **Verification:** `swift test --filter LiDARPlaneFitterRefineScaleTests` — both cases pass; full `swift test` shows no regressions (271 XCTest + 9 Swift Testing all green).
  - **References:** smolspec.md (Implementation Approach > Affected files; Verification item 1), decision_log.md (Decision 1 — Consequences > Positive).
  - Blocked-by: oom-001

- [x] 3. CHANGELOG records the fix under [Unreleased] in the existing Bugfix-spec format <!-- id:oom-003 -->
  - **Outcome:** `CHANGELOG.md`'s `[Unreleased]` section gains a new `Fixed (Bugfix spec — lidar-plane-fit-oom-on-device-1920x1440)` subsection naming the user-visible symptom (`Fatal error: failed to allocate 32198713632 bytes ...` after `event=supportplane.start width=1920 height=1440`), the root cause one-liner (`LiDARPlaneFitter.refine`'s 3×n SVD requests an n×n V^T it never reads), and the resolution (3×3 scatter-matrix SVD). One bullet per affected production source file, matching the style of the existing `Fixed (Bugfix spec — lidar-plane-fit-degenerate-on-clean-capture)` block.
  - **Approach:** insert the new subsection immediately under the prior bug's subsection — the two are conceptually sequential (the prior fix unblocked this defect).
  - **Verification:** `git diff CHANGELOG.md` shows only an addition under `[Unreleased]`.
  - **References:** smolspec.md (Overview), decision_log.md (Decision 1 — Impact).
  - Blocked-by: oom-001, oom-002

- [ ] 4. On-device verification on iPhone 13 Pro Max captures a clean run and `report.md` is finalised with the device log <!-- id:oom-004 -->
  - **Outcome:** A fresh device-log capture on iPhone 13 Pro Max iOS 26.5 from a fruit-plate test (bananas, grapes, orange on a flat table at ~30-45 cm, the same framing that produced the original OOM) shows `event=supportplane.end success=true residual_mm=... inliers=... candidates=...` instead of the `Fatal error: failed to allocate ...` abort. The captured log block is appended to `specs/bugfixes/lidar-plane-fit-oom-on-device-1920x1440/report.md` under Verification.
  - **Approach:** rebuild the Debug variant from the new branch, install on device, capture via Xcode's Console window or `log stream --predicate 'subsystem == "ie.medata.app"'`.
  - **Verification:** `report.md` shows no `Fatal error: failed to allocate ...` lines in the appended log block; `event=supportplane.end success=true` is present.
  - **References:** smolspec.md (Implementation Approach > Verification, item 4), decision_log.md (Decision 1).
  - Blocked-by: oom-001, oom-002, oom-003
