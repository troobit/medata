---
references:
    - specs/estimation/estimation-quality/prd.md
---
# MVP estimation quality — Estimation runtime consistency

## Robustness

- [x] 1. Reduce run-to-run carb-reading variance via a conservative additive guard on at least one identified source (plane-fit inlier selection in LiDARPlaneFitter.swift, voxel-carve boundary sensitivity in Volume/, or beta application on near-empty masks); state the rationale in the diff/commit and the module agent note; keep the path deterministic + offline

- [x] 2. Fail closed and legibly when food coverage is below a stated threshold rather than emitting a wildly variable number, reusing existing EstimationFailure semantics; cover it with a unit test

- [x] 3. Gate: make build, make test (report BOTH totals), make spell — all green; change is individually reviewable without this conversation
