---
references:
    - prd.md
---
# MVP estimation quality — Mask post-processing cleanup

## Cleanup

- [ ] 1. Add a deterministic spatial-regularisation pass over the argmax label map in MedataCore/Sources/Segmentation/PostProcessing.swift (connected-component / morphological majority filter with a minimum-region threshold) that reassigns sub-threshold speckle pixels to their dominant neighbour class; identical input -> identical output

- [ ] 2. Ensure the cleanup runs on the label map only and preserves the sigma_seg / top-probability computation contract described in PostProcessing.swift, or make any change to that contract explicit and covered by a test

- [ ] 3. Make the minimum-region threshold a named constant/parameter; a no-op/passthrough configuration reproduces pre-change behaviour exactly

- [ ] 4. Add a unit test that constructs a synthetic speckled label map and asserts the cleanup removes sub-threshold isolated regions while preserving a large contiguous food region within a stated area tolerance

- [ ] 5. Gate: make build, make test (report BOTH XCTest and swift-testing totals), make spell — all green; no new UI test target
