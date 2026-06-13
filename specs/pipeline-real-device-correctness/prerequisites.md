# Prerequisites for Pipeline Real-Device Correctness

These tasks must be completed by the user before or during implementation. The coding agent cannot perform any of them.

## Before Starting

- [ ] **iPhone 13 Pro Max iOS 26.5** (or newer Pro with LiDAR) tethered to the dev Mac for on-device verification of the fruit-plate capture flow. Simulator builds cannot exercise LiDAR, ARSession `ARFrame` delivery, or Vision card detection at production resolution.
- [ ] **ID-1 reference card** physically present on the test bench. Any expired credit / library / printed ID-1 calibration target works; needed to exercise the card-only fallback path under [Requirement 5.4](requirements.md#5.4).
- [ ] **Console.app or `log stream --predicate 'subsystem == "ie.medata.app"'`** access on the dev Mac so the new `preshutter.mask.update`, `carddetect.end`, and amended `estimate.start` events can be captured during on-device runs.
- [ ] **Xcode 26+** with the existing project scheme (`MeData` / `MedataCore-Package`). No new dependencies are anticipated; if Vision capability requires a deployment-target bump, raise it in the design phase before tasks start.

## During Implementation

- [ ] **Confirm `Vision` framework availability** on the iPhone 13 Pro Max iOS 26.5 deployment target. The Vision rectangle-detection API surface used by the new `CardDetector` conformance must be present on the documented iOS floor (currently iOS 17 per `specs/research/`). If a higher floor is required for a specific API, that's a design-phase decision.
- [ ] **Capture a fruit-plate fixture** on iPhone 13 Pro Max with the ID-1 card visible in the nadir frame. The fixture serves the regression tests under [Requirement 8.5](requirements.md#8.5) (Vision detector) and the on-device verification of the full flow.
- [ ] **Re-run `event=supportplane.end success=true` capture** after the centre-rectangle mask is deleted, to confirm the real food-region mask produces a finite, gravity-aligned plane fit with bounded inlier count per [Requirement 2.3](requirements.md#2.3).

## Before Testing

- [ ] **Capture a "no food in frame" fixture** (camera framed at an empty table or wall) so the empty-mask refusal path can be exercised end-to-end on device per [Requirement 3.1](requirements.md#3.1) / [Decision 2](decision_log.md).
- [ ] **Baseline measurements** of peak resident memory and shutter-tap → `estimate.start` latency on iPhone 13 Pro Max iOS 26.5 with the pre-spec build, so the regressions in [Requirements 6.1](requirements.md#6.1) and [6.2](requirements.md#6.2) can be measured against a defined baseline.

## Notes

- **No new training data, model, or palette work is required.** The pre-shutter pass uses whichever engine `PipelineFactory.makeForDevice` wires (`StubInferenceEngine` in Phase 1 dev builds, `CoreMLInferenceEngine` in Phase 3 Release builds).
- **No cloud API keys, App Store provisioning, or background-task identifiers are required.** All changes are local to the App + MedataCore targets.
