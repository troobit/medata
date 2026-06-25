# Research — Requirements

**Version:** 0.4.1
**Date:** 2026-06-20
**Status:** Draft (device-MVP phasing pass — Phase 1 dev-stub segmenter; 2026-06-20 consistency pass propagated the §0 deltas through design.md, tasks.md, and prerequisites.md)
**Branch:** research
**Mode:** full · per-class β_c bulk-correction and confidence thresholds are **iterative/target-driven** — tuned toward the v1 test-set accuracy target, not enumerated as discrete tasks (see [PROCESS.md §5](../PROCESS.md#5-choosing-the-mode-full-spec-smolspec-or-iterative)).

## Introduction

This spec is the root of the application. It defines a low-compute, on-device system for estimating the carbohydrate content of a meal from one or two photographs taken on a modern iPhone. It grounds every step in the academic literature it inherits from:

- Anthimopoulos, M., et al. *A Food Recognition System for Diabetic Patients Based on an Optimized Bag of Features Model.* IEEE Journal of Biomedical and Health Informatics, 2014.
- Dehais, J., Anthimopoulos, M., Shevchik, S., Mougiakakou, S. *Two-View 3D Reconstruction for Food Volume Estimation.* IEEE Transactions on Multimedia, 2017.
- Anthimopoulos, M., et al. *Computer Vision-Based Carbohydrate Estimation for Type 1 Diabetic Patients Using Smartphones.* 2015 (the GoCARB clinical evaluation series).
- Laurentini, A. *The Visual Hull Concept for Silhouette-Based Image Understanding.* IEEE TPAMI, 1994.
- Food Standards Agency. *McCance and Widdowson's The Composition of Foods Integrated Dataset (CoFID).* Crown Copyright, latest published edition, Open Government Licence v3.
- Food Safety Authority of Ireland. *Carbohydrate as monosaccharide equivalents — labelling and analytical guidance.*
- ISO/IEC 7810:2003, Identification cards — Physical characteristics, ID-1 format (85.60 × 53.98 mm).

### Mathematical pipeline

The core transformation is:

$$\text{photo(s)} \longrightarrow \text{silhouettes} \longrightarrow \text{visual hull } H \longrightarrow V_c = f_c(H_c, \pi_{\text{sup}}, D_{\text{lidar}}) \longrightarrow m_c = V_c \rho_c \longrightarrow C = \sum_c m_c \cdot \kappa_c / 100$$

where:

- $H_c$ is the per-class visual hull from silhouette back-projection (Laurentini 1994).
- $\pi_{\text{sup}}$ is the support plane (plate / table) detected in the scene.
- $D_{\text{lidar}}$ is the LiDAR depth map (where available).
- $f_c$ is a per-class **volume corrector** that closes the hull against $\pi_{\text{sup}}$ from below, intersects it with $D_{\text{lidar}}$ from above (where available), and applies a per-class bulk-correction factor (see [9](#9-volume-estimation-and-visual-hull-correction)).
- $\rho_c$ is the per-class served-portion bulk density.
- $\kappa_c$ is the per-class monosaccharide-equivalent carbohydrate per 100 g.

### Key modelling assumptions (made explicit, not implicit)

1. **Visual hull is an upper bound on volume.** Pure Shape-from-Silhouette without depth produces a strict superset of the true food shape (Laurentini 1994). The pipeline closes the hull (a) from below against a detected support plane, (b) from above against LiDAR depth where available, and (c) by per-class bulk-correction calibrated against the v1 test set. Without these three corrections the volume estimate is systematically biased high.
2. **Constant per-class bulk density.** $m = V \rho$ assumes uniform $\rho$ within a class region. This is approximate for layered foods, foods with internal voids, and granular foods. Densities in the bundled database are *served-portion bulk densities* (with packing fraction folded in), not pure-substance densities.
3. **Foods rest on a level support plane.** The voxel grid is gravity-aligned. A markedly tilted tray or plate breaks the assumption silently.
4. **Standalone liquids and semi-liquids are out of scope for v1.** Clear liquids served on their own (water, tea, fruit juice), opaque liquids served on their own (soup, smoothies, milk), and pourable semi-liquids served on their own (yoghurt, custard) are excluded. **Pourable accompaniments served on a solid food are NOT excluded:** curry sauce on rice, gravy on roast, baked-bean tomato sauce, pasta sauce on pasta — these are part of the composite class with the solid (per Decision 8) and are estimated normally. The segmenter palette includes an `unsupported_liquid` class that catches *standalone* liquids and surfaces an explicit Irish-English message disabling the carb estimate for that region only.
5. **Single-view path silently undercounts inter-class occlusion.** When a tall food occludes a shorter food in the nadir view (rice partly behind a chicken breast), the height-field integration in the single-view path produces zero volume for the occluded portion. The two-view path partially recovers occluded food via the oblique silhouette. The single-view path's geometric-completeness sub-confidence (Req 13.2) is reduced when inter-class occlusion is detected, and the user is prompted to recapture using the two-view path.

### Out of scope (deferred to other specs)

- `specs/clinical`: atomic event log, AWAP cycle, active-carb-load decay model, CGM (Dexcom / LibreView) synchronisation. The research spec defines the data hooks the clinical track will consume but does not implement clinical features.
- `specs/cloud-validation` (future): the optional cloud cross-check fallback (Option D in Decision 3).
- Liquids and semi-liquids (see assumption 4).

### Delivery phases

V1 work proceeds in three ordered phases. Each phase has an acceptance bar; later phases SHALL NOT block earlier ones. Numeric accuracy targets ([21.3](#21.3)) and segmenter quality targets ([8.9](#8.9)) apply to **Phase 3 only** — they are not gates on Phase 1 or Phase 2 sign-off.

1. **Phase 1 — RUNNING DEVICE (current).** A working pipeline on the developer device (iPhone 13 Pro Max) end-to-end: capture → segmentation (dev-stub) → volume → macros → result. The segmenter is a development stub per [23](#23-phased-delivery-and-development-stubs); numeric outputs are placeholders. The capture flow, persistence, gating, refusal paths, and confidence combination are all real. Success: tap shutter on device, see a placeholder carbohydrate value on the result view, meal persists.
2. **Phase 2 — UI/UX iteration.** Once Phase 1 is on device, the capture flow, gating affordances, result view, settings, and history view are refined against real-device usage. The dev-stub segmenter is still in use. No new pipeline algorithms.
3. **Phase 3 — Data veracity and modelling.** The trained Core ML segmenter ([8](#8-food-semantic-segmentation)) is bundled, β_c calibration ([11.7](#11.7)) is run, the accuracy harness ([21](#21-test-harness-and-validation)) is exercised, and the [21.3](#21.3) reference is measured. The placeholder banner from [23.3](#23.3) is removed.

### Hardware floor

V1 hardware floor: iPhone 13 Pro Max. V1 OS floor: iOS 26.5. The architecture is platform-portable so a future Android implementation can re-use the algorithms, data formats and segmenter without re-deriving the mathematics.

### Spelling

All user-facing strings, identifiers, comments and documentation use Irish / British English spelling (e.g. "recognised", "fibre", "colour", "programme"). HSE Language Matters and person-first language are out of scope (see Decision 4).

---

## Requirements

REQUIREMENT IS AN MVP WITH AN UPPER BOUND - allowing for overestimation caused by voxel carving process.

### 1. Native iOS Application Foundation

**User Story:** As a developer, I want a clean native iOS Swift application as the only user-facing implementation, so that v1 ships with a deterministic on-device pipeline and no legacy code paths.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL ship as a native iOS application written in Swift.
2. <a name="1.2"></a>The application SHALL target iOS 26.5 or later and SHALL run on iPhone 13 Pro Max devices that ship a rear-facing LiDAR scanner.
3. <a name="1.5"></a>The application SHALL operate entirely offline in its core estimation path. No network call SHALL be required for capture, segmentation, voxel carving, density lookup, or macronutrient calculation.

**Portability Notes (iOS v1 implementation):** SwiftUI for UI, AVFoundation for camera capture, ARKit for scene tracking and LiDAR depth, Core Motion for IMU, Core ML for segmentation inference, and the Vision framework for classical detection. Section 1 is the iOS-shell specification; Sections 2–17 are platform-neutral and confine iOS API names to their own Portability Notes.

### 2. Camera Capture Session and Intrinsics

**User Story:** As the system, I want every captured frame paired with its calibrated camera intrinsics, so that downstream projective geometry has the data it needs to back-project pixels into world coordinates.

**Acceptance Criteria:**

1. <a name="2.1"></a>The capture session SHALL request the rear-facing camera at the highest resolution that maintains at least 30 frames per second preview.
2. <a name="2.2"></a>The system SHALL record the chosen capture resolution on each captured frame.
3. <a name="2.3"></a>WHEN a still frame is captured, the system SHALL persist the intrinsic matrix $K = \begin{pmatrix} f_x & 0 & c_x \\ 0 & f_y & c_y \\ 0 & 0 & 1 \end{pmatrix}$ alongside the image bytes.
4. <a name="2.4"></a>WHERE the platform reports lens distortion data, the system SHALL persist the distortion polynomial coefficients with the calibration record so that undistortion can be applied portably.
5. <a name="2.5"></a>The capture session SHALL release the camera within 200 ms of the user navigating away from the capture flow.
6. <a name="2.6"></a>The calibration record SHALL be a platform-neutral structure (plain key/value, serialisable to Protocol Buffers or JSON) and SHALL NOT depend on any iOS-only type.

**Portability Notes:** iOS sources intrinsics from `AVCaptureDevice` and `AVCameraCalibrationData`. Android sources from `Camera2` `CameraCharacteristics.LENS_INTRINSIC_CALIBRATION` and `LENS_DISTORTION`.

### 3. IMU-Guided Capture (Two-View Canonical, LiDAR Single-View Shortcut)

**User Story:** As a user, I want the app to guide me to the correct camera angles, so that the photographs satisfy the geometric constraints required by the literature without me having to think about angles.

**Acceptance Criteria:**

1. <a name="3.1"></a>The capture flow SHALL display a real-time tilt indicator driven by the device's gravity vector, showing deviation in degrees of the device's optical axis from the target angle AND the live $\sigma_{\text{tilt}} = \cos(\Delta\theta)$ value (per [13.2](#13-confidence-reporting)) so the user can see, before tapping the shutter, the angular-error penalty they would incur.
2. <a name="3.2"></a>The first view SHALL target nadir (0° from vertical, top-down). The system SHALL accept a capture at any tilt; no hard angular gate applies. The angular error $\Delta\theta_{\text{nadir}} = \angle(\text{optical axis}, \text{gravity}^{-1})$ SHALL be persisted on the meal record and SHALL feed $\sigma_{\text{tilt}}$ per [13.2](#13-confidence-reporting). Rationale: per Decision 43, an estimate at any angle (with honest confidence reporting) is preferable to refusing capture.
3. <a name="3.3"></a>WHEN the canonical two-view path is in use, the second view SHALL target an oblique angle of 25° from vertical (within the 20°–30° envelope justified by Dehais 2017 §III.B). The system SHALL accept the second capture when $|\theta_{\text{measured}} - 25°| \leq 30°$ (i.e. 0°–55° absolute from vertical) and SHALL refuse beyond that bound with a "tilt closer to 25°" message. The angular error $\Delta\theta_{\text{oblique}} = |\theta_{\text{measured}} - 25°|$ SHALL be persisted and SHALL feed $\sigma_{\text{tilt}}$.
4. <a name="3.4"></a>The system SHALL prompt the user to hold the device at a working distance of 30–40 cm from the food. WHERE LiDAR depth is available, the system SHALL measure actual distance and refuse capture outside 25–50 cm.
5. <a name="3.5"></a>The capture path SHALL be selected via a persistent user toggle (`Single` / `Double`) displayed on the capture view and bound to `SettingsKeys.captureMode` in `UserDefaults`. The default on first install is `Double`. `Single` mode SHALL be greyed out on devices without a rear LiDAR scanner. The mode SHALL be read at shutter-tap time; changes during an in-flight estimation SHALL be ignored until the result view is shown. Per Decision 35. See [3.9](#3.9) for the deferred auto-selection variant.
6. <a name="3.6"></a>The two captured views, when both are taken, SHALL share a world coordinate frame so that the relative pose of the second view with respect to the first is recorded as a 6-DOF transform $T_{1 \to 2} \in SE(3)$.
7. <a name="3.7"></a>IF world tracking confidence falls below the platform-defined "normal" threshold between the two views, THEN the system SHALL discard the second view and prompt the user to retake it.
8. <a name="3.8"></a>The meal record SHALL persist a `capturePath` enum with values `single_view_lidar` or `two_view_sfs` so that downstream consumers can interpret the estimate's error characteristics.
9. <a name="3.9"></a>[DEFERRED — compile flag `AUTO_CAPTURE_MODE`] When the `AUTO_CAPTURE_MODE` compile flag is enabled, the system SHALL automatically select the single-view path when LiDAR depth is available, a support plane has been detected, and valid metric depth covers ≥80% of the food region, overriding the user toggle. This logic is preserved in `CapturePathDecider` behind the compile flag for future activation. See [3.5](#3.5) for the v1 user-selected toggle behaviour.

**Portability Notes:** iOS uses Core Motion gravity, ARKit world tracking, ARKit `sceneDepth` for LiDAR. Android uses `SensorManager` gravity, ARCore world tracking, ARCore Depth API (note: ARCore Depth on most Android devices is software-derived multi-view stereo, not LiDAR — the single-view shortcut in [3.5](#3.5) requires *true* time-of-flight depth and is currently iOS-only).

### 4. Support Plane Detection and Closure

**User Story:** As the system, I need the plate / table support plane in the scene's metric coordinate frame, so that voxel carving has a lower bound and the visual hull can be closed from below.

**Acceptance Criteria:**

1. <a name="4.1"></a>For every estimation, the system SHALL detect a support plane $\pi_{\text{sup}}$ defined by a unit normal $\hat{n}$ (close to the gravity vector) and a signed distance $d$ from the camera origin, expressed in the same coordinate frame as the voxel grid.
2. <a name="4.2"></a>WHERE LiDAR depth is available, $\pi_{\text{sup}}$ SHALL be fit to depth points at and around the lower edge of the food bounding region using RANSAC plane fitting.
3. <a name="4.3"></a>WHERE LiDAR depth is unavailable but the canonical two-view path is in use AND a card has been detected per [5.2](#5.2), $\pi_{\text{sup}}$ SHALL be recovered as follows: (a) initialise the metric scale at the *card plane* using $s_{\text{card,init}}$ from the recovered card pose ([5.3](#5.3) initial value); (b) back-project the lower silhouette edges across both views using $s_{\text{card,init}}$ and the gravity vector to obtain a candidate $\pi_{\text{sup}}^{(0)}$; (c) iterate by lifting $s_{\text{card}}$ from the card plane to the food plane (offset by the food's mean height above $\pi_{\text{sup}}^{(k)}$) and re-fitting $\pi_{\text{sup}}^{(k+1)}$ until $\|\pi_{\text{sup}}^{(k+1)} - \pi_{\text{sup}}^{(k)}\| < 1$ mm or 5 iterations are exhausted. Convergence SHALL be persisted as a sub-confidence signal.
4. <a name="4.4"></a>The detected support plane SHALL be used as a lower carving bound: any voxel whose centre lies on the negative side of $\pi_{\text{sup}}$ (below the plate) SHALL be excluded from $H_c$ for every class $c$.
5. <a name="4.5"></a>IF support-plane detection produces a residual standard deviation $r > 20$ mm OR the LiDAR plane-fit covariance is singular OR there are zero depth points in the food region, THEN the pipeline SHALL surface a "place the meal on a flat surface" message and refuse to compute. For $r \in (8, 20]$ mm the system SHALL accept the fit; the existing $\sigma_{\text{plane}} = \exp(-r / r_0)$ formula in [13.2](#13.2) carries the degradation (at $r = 20$ mm, $\sigma_{\text{plane}} \approx 0.018$, near the $\varepsilon$ floor). Per Decision 46.
6. <a name="4.6"></a>The plane-fit residual standard deviation SHALL be persisted as a sub-confidence input to [13](#13-confidence-reporting).

**Portability Notes:** iOS uses ARKit `ARPlaneAnchor` for LiDAR-backed plane detection as a starting heuristic, refined by RANSAC on the depth point cloud. Android uses ARCore `Plane` similarly.

### 5. ID-1 Reference Card Detection and Pose

**User Story:** As the system, I want a metric pose for an ID-1 card in the scene, so that I have an independent metric scale that does not require LiDAR.

**Acceptance Criteria:**

1. <a name="5.1"></a>The card detector SHALL locate a quadrilateral matching the ISO/IEC 7810 ID-1 form factor (85.60 × 53.98 mm) in the input image using contour detection followed by quadrilateral fitting (Hough lines as a fallback when contour fitting fails).
2. <a name="5.2"></a>WHEN a card is detected, the detector SHALL recover the 6-DOF pose of the card relative to the camera by solving Perspective-n-Point with the four corner pixel coordinates, the known 85.60 × 53.98 mm physical dimensions, and the calibration intrinsics from [2.3](#2.3).
3. <a name="5.3"></a>The recovered card pose SHALL yield two metric scale values: $s_{\text{card,init}}$ defined at the *card plane* (computed directly from the PnP solution, requires no support-plane knowledge) and $s_{\text{card}}$ defined at the *food plane* (lifted from the card plane by the food's mean height above $\pi_{\text{sup}}$, requires $\pi_{\text{sup}}$ to be known). $s_{\text{card,init}}$ is the input to the iterative support-plane fit in [4.3](#4.3); $s_{\text{card}}$ is the value passed to the metric scale resolver in [7](#7-metric-scale-establishment).
4. <a name="5.4"></a>The card detector SHALL operate on every captured view. The detector behaviour SHALL be specified once in mathematical form and implemented identically across views.
5. <a name="5.5"></a>IF no card is detected, THEN the detector SHALL return a "no-card" outcome rather than fail. The downstream pipeline SHALL treat this as a metric-scale degradation, not an error (see [7](#7-metric-scale-establishment)).
6. <a name="5.7"></a>The card detector specification SHALL be expressible without reference to any iOS-only API; the iOS implementation MAY use the Vision framework.

### 6. LiDAR Depth Acquisition

**User Story:** As the system, I want metric depth aligned with each captured colour frame, so that I can constrain voxel occupancy from above and detect the support plane.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN a still frame is captured, the system SHALL record the time-synchronised metric depth map and the depth-to-colour transform.
2. <a name="6.2"></a>The depth map SHALL be persisted as a portable 2-D array of metric depth values in metres, with associated depth-sensor intrinsics.
3. <a name="6.3"></a>WHERE the depth confidence map indicates low-confidence pixels over the food region, the system SHALL flag those pixels and SHALL exclude them from voxel-occupancy decisions.
4. <a name="6.4"></a>Depth values SHALL be normalised to metres before persistence; the system SHALL NOT depend on platform-specific depth scaling at the contract layer.
5. <a name="6.5"></a>IF the depth sensor is reported unavailable for the current capture (occluded, thermally throttled), THEN the system SHALL fall back to the two-view canonical path and require an oblique view per [3.3](#3.3).

**Portability Notes:** iOS uses ARKit `ARFrame.sceneDepth` (LiDAR). Android uses ARCore Depth API; on devices without ToF this is software-derived stereo and the canonical two-view path applies.

### 7. Metric Scale Establishment

**User Story:** As the system, I want a single deterministic procedure that produces a metric scale at the food plane, so that voxel carving has a unique unit length regardless of which sensor cues are available.

**Acceptance Criteria:**

1. <a name="7.1"></a>The metric scale resolver SHALL accept up to two scale signals — $s_{\text{card}}$ from [5.3](#5.3) and $s_{\text{lidar}}$ derived from depth statistics over the food region — and SHALL produce a single metric scale $s_{\text{meal}}$ along with a sub-confidence $\sigma_s \in [0, 1]$.
2. <a name="7.2"></a>WHEN both signals are present, $s_{\text{meal}}$ SHALL be the LiDAR-derived metric scale and $\sigma_s$ SHALL be raised toward 1 in proportion to agreement with the card scale, where agreement is $a = 1 - \min(1, |s_{\text{lidar}} - s_{\text{card}}| / s_{\text{card}})$ and $\sigma_s = 0.85 + 0.15 a$.
3. <a name="7.3"></a>WHEN only LiDAR is present, $\sigma_s$ SHALL be 0.85 and the meal record SHALL carry a `noCardConfidence` flag.
4. <a name="7.4"></a>WHEN only the card is present, $\sigma_s$ SHALL be 0.85 and the meal record SHALL carry a `noLidarConfidence` flag.
5. <a name="7.5"></a>IF neither LiDAR nor a card is available, THEN the resolver SHALL return a failure outcome and the pipeline SHALL surface an actionable Irish-English message instructing the user to include a card or capture on a LiDAR device.
6. <a name="7.6"></a>The metric scale resolver SHALL be specified in pseudocode and SHALL NOT use any iOS-only construct.

### 8. Food Semantic Segmentation

**User Story:** As the system, I want each pixel in each captured view labelled with a food class, so that I can carve a separate voxel volume per class and look up its density.

**Acceptance Criteria:**

1. <a name="8.1"></a>The segmenter SHALL be a single on-device convolutional semantic segmentation network producing a per-pixel class label and a per-pixel probability vector over classes.
2. <a name="8.2"></a>The segmenter weights file, after post-training quantisation, SHALL be 10 MB or smaller.
3. <a name="8.3"></a>The segmenter inference SHALL complete in under 250 ms per view on the v1 hardware floor.
4. <a name="8.4"></a>The segmenter class palette SHALL contain at least 24, and mo more than 40 food classes for v1 (curated jointly with the density coverage in [11](#11-density-and-macronutrient-database)) plus a `background` class, an `unknown_food` class, and an `unsupported_liquid` class.
5. <a name="8.5"></a>The segmenter SHALL be sourced from a single source-of-truth model that exports cleanly to both the iOS inference runtime and the Android inference runtime via ONNX or an equivalent intermediate representation.
6. <a name="8.6"></a>IF a pixel is labelled `unknown_food`, THEN the pipeline SHALL include those voxels in volume estimation but SHALL flag the meal as containing unrecognised food, and the macro contribution from those voxels SHALL be reported as "unknown carbs" with a confidence of 0.
7. <a name="8.7"></a>IF a pixel is labelled `unsupported_liquid`, THEN the pipeline SHALL exclude those voxels from volume estimation, SHALL flag the meal as containing an unsupported liquid, and SHALL surface an Irish-English message stating that standalone liquids are not estimated in v1. The `unsupported_liquid` class SHALL match *standalone* liquids only (a glass of water, a bowl of soup, a glass of milk); pourable accompaniments served on a solid food (curry sauce on rice, gravy on roast, baked-bean tomato sauce, pasta sauce on pasta) SHALL be assigned to the composite class for that dish per Decision 8 and estimated normally.
8. <a name="8.8"></a>The segmenter input SHALL be a fixed-size resized colour image (aspect-preserving with letterboxing); the resize procedure SHALL be specified once and applied identically on both platforms.
9. <a name="8.9"></a>The segmenter SHALL meet a minimum mean Intersection-over-Union (mIoU) of **0.60 averaged across food classes** on the held-out segmenter test set, evaluated separately from the end-to-end accuracy bar in [21.3](#21.3). This bar applies to the Phase 3 trained model only ([23](#23-phased-delivery-and-development-stubs)); Phase 1 ships with a dev-stub segmenter and does NOT meet this bar.
10. <a name="8.10"></a>WHEN a Phase 1 build (per [23.1](#23.1)) is running, the segmenter implementation SHALL be the development stub from [23.2](#23.2). The dev stub SHALL satisfy the same `SegmenterInferenceEngine` contract as the real Core ML segmenter so that downstream stages (volume, ownership, macros, confidence) execute unchanged.

**Portability Notes:** iOS runs the segmenter via Core ML on the Apple Neural Engine where available. Android runs the same model via TensorFlow Lite with the NNAPI / GPU delegate.

### 9. Volume Estimation and Visual Hull Correction

**User Story:** As the system, I want a corrected per-class metric volume in cubic centimetres derived from silhouettes, depth, and the support plane, so that I have a physical input the density and carb maths can rely on.

**Acceptance Criteria:**

1. <a name="9.1"></a>The voxel grid SHALL be constructed in world coordinates, axis-aligned with the gravity vector, with origin at the centroid of the food region in the nadir view.
2. <a name="9.2"></a>The voxel grid horizontal extent SHALL cover the union of food silhouettes back-projected to the support plane plus a 30 mm margin, capped at 360 mm × 360 mm (a 360 mm horizontal extent fits a 270 mm dinner plate plus margin). The vertical extent SHALL be 12 cm above the support plane.
3. <a name="9.3"></a>The voxel edge length SHALL default to 3 mm; the design phase MAY revise this in the range 2–5 mm based on a sensitivity study. With a 3 mm edge and the grid in [9.2](#9.2), the grid is at most $120 \times 120 \times 40 = 576{,}000$ voxels.
4. <a name="9.4"></a>The volume estimation algorithm SHALL be one of two paths, selected per [3.5](#3.5):
   - **Two-view canonical path** (`capturePath = two_view_sfs`): For each class $c$, compute the visual hull $H_c$ by silhouette back-projection from the nadir and oblique views (Dehais 2017 §III.D). Close $H_c$ from below against $\pi_{\text{sup}}$ per [4.4](#4.4). The carved set is $H_c$ after support-plane closure; the corrected volume is $V_c = |H_c| \cdot \Delta x \Delta y \Delta z \cdot \beta_c$ where $\beta_c \in (0, 1]$ is the per-class bulk-correction factor from [11.7](#11.7).
   - **Single-view depth-augmented path** (`capturePath = single_view_lidar`): For each class $c$, define the corrected volume by integrating, over the class's nadir-view pixels $p \in M_c$, the height between the LiDAR-observed top surface $z_{\text{top}}(p)$ and the support plane $\pi_{\text{sup}}$: $V_c = \beta_c \cdot \sum_{p \in M_c} (z_{\text{top}}(p) - z_{\text{sup}}(p)) \cdot a(p)$ where $a(p)$ is the metric area of pixel $p$ at the food plane. This is **not** voxel carving; it is height-field integration and is the v1 single-view algorithm.
5. <a name="9.5"></a>**Multi-class ownership:**
   - **Single-view path** (`single_view_lidar`): WHEN two classes' nadir-view masks overlap, each pixel SHALL be assigned to exactly one class by per-pixel argmax over the segmenter class probability vector from [8.1](#8.1). Pixels labelled `background` or `unsupported_liquid` (per [8.7](#8.7)) SHALL contribute zero mass to all food classes.
   - **Two-view path** (`two_view_sfs`): For each voxel $v$ in the carved set, let $p_1(v), p_2(v)$ be its projections in views 1 and 2 with per-class probability vectors $\mathbf{q}_1(v), \mathbf{q}_2(v)$ from the segmenter. The voxel class SHALL be $c^*(v) = \arg\max_c [\mathbf{q}_1(v)]_c \cdot [\mathbf{q}_2(v)]_c$ (argmax of the per-class probability product across the two projections). IF $\max_c [\mathbf{q}_1(v)]_c \cdot [\mathbf{q}_2(v)]_c$ is below a documented threshold $\tau_v$ (default 0.04, equivalent to both views agreeing on a class with probability ≥ 0.2), THEN the voxel SHALL be discarded as a class-ambiguous voxel and its share SHALL contribute to a per-meal `ambiguousVoxelFraction` metric persisted with the meal record.
   - No voxel and no nadir-view pixel SHALL contribute mass to more than one class.
6. <a name="9.6"></a>The volume estimator SHALL produce, per class, the corrected metric volume $V_c$ in cubic centimetres and a compressed bounding-set representation of the carved/integrated region for persistence.
7. <a name="9.8"></a>The volume estimator algorithm SHALL be specified in pseudocode in the design document, with the back-projection equation, height-field integration equation, and ownership rule written explicitly, and SHALL NOT depend on any iOS-only API in its specification.
8. <a name="9.9"></a>**Visual hull bias.** The two-view path produces the visual hull, which is provably an upper bound on the true volume (Laurentini 1994). The bulk-correction factor $\beta_c$ from [11.7](#11.7) is the v1 mechanism for compensating residual bias; the single-view path's LiDAR top surface compensates more directly but $\beta_c$ still applies to absorb packing fraction.

### 10. Multi-View Mask Consistency

**User Story:** As the system, I want the per-class masks in the two-view path to correspond consistently to the same food regions across views, so that voxel carving combines silhouettes that bound the same physical food.

**Acceptance Criteria:**

1. <a name="10.1"></a>WHEN the canonical two-view path is in use, the system SHALL run the segmenter on both views and SHALL match per-class masks across views by class label.
2. <a name="10.2"></a>IF a class appears in only one of the two views, THEN the system SHALL treat that class as present with a single-view silhouette only and SHALL flag it with reduced confidence.
3. <a name="10.3"></a>The system SHALL use the recorded $T_{1 \to 2}$ pose from [3.6](#3.6) to back-project both silhouettes into the shared voxel grid.
4. <a name="10.4"></a>The mask matching procedure SHALL be specified in pseudocode and SHALL NOT depend on iOS-only data structures.

### 11. Density and Macronutrient Database

**User Story:** As the system, I want a bundled portable database of per-class densities, per-100 g macronutrient coefficients, and per-class bulk-correction factors, so that the macro calculation is a deterministic lookup once corrected volume is known.

**Acceptance Criteria:**

1. <a name="11.1"></a>The application SHALL bundle a portable food composition database. The default sources SHALL be the McCance and Widdowson CoFID dataset and the Australian Food Composition Database (AFCD)(latest published editions), released under the Open Government Licence v3 and bundled with attribution per OGL v3 terms. Attributions SHALL appear on the application's About / Legal screen.
2. <a name="11.2"></a>FOR each segmenter class in [8.4](#8.4), the database SHALL contain at least: class name, served-portion bulk density $\rho$ in g/cm³, energy in kJ per 100 g, carbohydrate (monosaccharide-equivalent) in g per 100 g, protein in g per 100 g, fat in g per 100 g, fibre (AOAC) in g per 100 g, and the bulk-correction factor $\beta$ from [11.7](#11.7).
3. <a name="11.4"></a>The segmenter class palette in [8.4](#8.4) SHALL be co-curated with these databases so that every class has measured density and bulk-correction values; the palette and the database SHALL be released as a versioned pair.
4. <a name="11.5"></a>Density and bulk-correction values SHALL be sourced from cited literature where available (Dehais 2017 Table II, Anthimopoulos 2014, FAO/INFOODS density tables) and from project-internal gravimetric measurement on the v1 test set otherwise. The decision log SHALL record the source for each value.
5. <a name="11.6"></a>Carbohydrate values SHOULD be expressed as monosaccharide equivalents. WHERE a source provides "available carbohydrate by difference", the value SHOULD be converted to monosaccharide equivalents.
6. <a name="11.7"></a>**Bulk-correction factor $\beta_c$.** For each class $c$, the database SHALL contain a unitless factor $\beta_c \in (0, 1]$ that scales the visual-hull volume to the corrected volume per [9.4](#9.4). $\beta_c$ SHALL be calibrated against the v1 test set by minimising MAE over carbohydrate totals for that class on the calibration subset only (per [21.4](#21.4)). The factor folds together: visual-hull concavity bias, packing fraction (for granular foods), and internal-void bias.

   **Minimum calibration sample size.** A class $c$ SHALL be considered calibrated only if its calibration subset contains at least **30 meals** in which class $c$ is present and gravimetrically weighed. Classes that do not meet this bar SHALL receive $\beta_c = 1.0$ and SHALL be marked as `uncalibrated` in the bundled database. WHEN any class in a meal is `uncalibrated`, the meal record SHALL persist a per-class `betaCalibrationStatus` field with values `calibrated`, `uncalibrated_pooled` (using a class-pooled β as a fallback default — see below), or `uncalibrated_unity` (β = 1.0). Calibration procedure SHALL be specified in the design document.

   **Pooled fallback.** Where a class is `uncalibrated`, the design document MAY define a class-pooled β (a single β computed across all uncalibrated classes' calibration meals together) as a softer fallback than $\beta_c = 1.0$.
7. <a name="11.8"></a>The database SHALL be packaged as a single SQLite file, which is the chosen portable format (FlatBuffers was considered and rejected for this v1 — see decision log). The schema SHALL be documented and usable verbatim on Android.
8. <a name="11.9"></a>Each meal record SHALL persist the database edition / version identifier (e.g. "CoFID 2024 + AFCD 2024") used to compute its macros, so that re-derivation across database updates is reproducible.
9.  <a name="11.10"></a>**Palette migration.** WHEN a newer palette / database version splits, merges, or renames classes, the system SHALL preserve the original class assignments on existing meal records and SHALL NOT silently remap them. Re-derivation of an existing meal under a newer palette is permitted only if the design document specifies an explicit class mapping (e.g. v1 `rice` → v2 `white_rice`) and the user is informed that the record has been re-derived. Meals whose original class has no mapping in the new palette SHALL remain on the old palette / database edition for that class.

### 12. Macronutrient Calculation

**User Story:** As a user, I want a per-meal carbohydrate total derived from measured volumes, densities and per-100 g coefficients, so that I have a value with traceable provenance instead of a model guess.

**Acceptance Criteria:**

1. <a name="12.1"></a>FOR each segmenter class $c$ present in the meal with corrected volume $V_c$ from [9.6](#9.6), the system SHALL compute mass $m_c = V_c \cdot \rho_c$ where $\rho_c$ is the served-portion bulk density from the bundled database.
2. <a name="12.2"></a>FOR each class $c$, the system SHALL compute carbohydrates $C_c = m_c \cdot \kappa_c / 100$ where $\kappa_c$ is the monosaccharide-equivalent carbohydrate per 100 g for that class.
3. <a name="12.3"></a>The meal-level carbohydrate total SHALL be $C_{\text{meal}} = \sum_c C_c$.
4. <a name="12.4"></a>$C_{\text{meal}}$ SHALL be displayed to the nearest **1 gram** (consistent with the 25 g MAE reference in [21.3](#21.3) and with diabetes-bolus-calculator conventions).
5. <a name="12.5"></a>$C_{\text{meal}}$ and all per-class values SHALL be persisted at full machine precision regardless of display rounding.
6. <a name="12.6"></a>The system SHALL also compute and persist meal-level totals for energy, protein, fat and fibre using the same per-class formula. These totals are computed for clinical-track consumption and are NOT displayed to the user in v1.
7. <a name="12.7"></a>The meal record SHALL include the per-class breakdown ($V_c$, $m_c$, $C_c$, density source, coefficient source, $\beta_c$ used) so that any later audit can reconstruct how the meal-level total was derived.
8. <a name="12.8"></a>The macronutrient calculation SHALL be specified in pseudocode and SHALL NOT depend on any iOS-only construct.

### 13. Confidence Reporting

**User Story:** As a user, I want each carbohydrate estimate annotated with a confidence value, so that I know when to examine it.

**Acceptance Criteria:**

1. <a name="13.1"></a>The system SHALL compute and report a per-meal confidence $\sigma_{\text{meal}} \in [\varepsilon, 1]$ as the geometric mean of three sub-confidences:
   $$\sigma_{\text{meal}} = \left( \tilde{\sigma}_s \cdot \tilde{\sigma}_{\text{seg}} \cdot \tilde{\sigma}_{\text{geom}} \right)^{1/3}$$
   where each $\tilde{\sigma}_x = \max(\varepsilon, \sigma_x)$ is the floored sub-confidence with **floor $\varepsilon = 0.01$** (per Decision 45), $\sigma_s$ is the metric-scale sub-confidence from [7.1](#7.1), $\sigma_{\text{seg}}$ is the segmenter's mean class probability over food pixels (excluding `background`, `unknown_food`, and `unsupported_liquid`), and $\sigma_{\text{geom}}$ is the geometric-completeness sub-confidence defined in [13.2](#13.2). IF no food pixels exist after exclusions, THEN the system SHALL refuse to compute and produce no estimate; $\sigma_{\text{meal}}$ is undefined in that case (no meal record is persisted). The "no food pixels" refusal is retained because there is no estimate target — qualitatively different from a degraded estimate; see Decision 43.
2. <a name="13.2"></a>The geometric-completeness sub-confidence $\sigma_{\text{geom}}$ SHALL be computed as the product of four independent factors $\sigma_{\text{geom}} = \sigma_{\text{view}} \cdot \sigma_{\text{plane}} \cdot \sigma_{\text{occl}} \cdot \sigma_{\text{tilt}}$, each in $(0, 1]$:
   - $\sigma_{\text{view}}$ — view-coverage factor: 1.00 for a clean two-view capture with full silhouette agreement; 0.90 for the single-view LiDAR path with ≥80% LiDAR coverage of the food region; 0.75 for a two-view capture where one or more classes appear in only one view (per [10.2](#10.2)); 0.60 for a single-view LiDAR capture with 50–80% LiDAR coverage; 0.30 for a single-view LiDAR capture with 30–50% LiDAR coverage (per Decision 47). Below 30% LiDAR coverage the system SHALL refuse to compute.
   - $\sigma_{\text{plane}}$ — support-plane fit factor: derived from the plane-fit residual standard deviation $r$ persisted per [4.6](#4.6) as $\sigma_{\text{plane}} = \exp(-r / r_0)$ with $r_0 = 5\text{ mm}$. Where the card-only iterative path of [4.3](#4.3) is used, $\sigma_{\text{plane}}$ SHALL additionally be reduced by a factor 0.9 if the iteration did not converge within 5 iterations. Per [4.5](#4.5), fits with $r > 20$ mm trigger refusal rather than degradation.
   - $\sigma_{\text{occl}}$ — occlusion factor (single-view path only; 1.00 for two-view path): 1.00 if no inter-class occlusion is detected; 0.80 if any class boundary in the nadir-view mask shares a depth discontinuity > 10 mm with another class within 5 px (heuristic for tall food occluding shorter food); the user is prompted to recapture using the two-view path. The two-view path uses 1.00 here because the oblique view recovers most occluded regions.
   - <a name="13.2.4"></a>$\sigma_{\text{tilt}}$ — angular-error factor (per Decision 44): $\sigma_{\text{tilt}} = \max(\varepsilon, \cos(\Delta\theta_{\text{capture}}))$, where $\Delta\theta_{\text{capture}}$ is the per-stage angular deviation from the target axis ($\Delta\theta_{\text{nadir}}$ per [3.2](#3.2) for single-view; $\max(\Delta\theta_{\text{nadir}}, \Delta\theta_{\text{oblique}})$ per [3.3](#3.3) for two-view, taking the worse of the two views). The cosine curve is geometrically motivated: a tilted camera's nadir height-field footprint scales by $\cos(\Delta\theta)$.
   The PnP card-pose fit residual from [5.2](#5.2) is persisted with the meal record but is NOT a direct input to $\sigma_{\text{meal}}$ in v1 — it is informational and reserved for clinical-track analysis.
3. <a name="13.3"></a>The system SHALL also compute a per-class confidence $\sigma_c$ using the same combination function with class-specific inputs.
4. <a name="13.4"></a>The meal record SHALL persist all sub-confidences ($\sigma_s$, $\sigma_{\text{seg}}$, $\sigma_{\text{geom}}$, including the new $\sigma_{\text{tilt}}$ sub-factor of $\sigma_{\text{geom}}$) and the per-stage angular errors ($\Delta\theta_{\text{nadir}}$, $\Delta\theta_{\text{oblique}}$ where applicable) so that the combination function can be revisited without re-capturing the photograph. Legacy records persisted before the $\sigma_{\text{tilt}}$ field was added SHALL be re-derived with $\sigma_{\text{tilt}} = 1.0$ (the identity multiplier) so historical confidences are not retroactively penalised.
5. <a name="13.5"></a>WHEN $\sigma_{\text{meal}} < 0.2$ the UI SHALL display a "Very Low" affordance prompting the user to either retake the photograph or accept the rough estimate, and SHALL surface an inline explanation that the estimate may be wrong by orders of magnitude. The "manually correct" branch from a prior revision is out of scope per the UI spec's Non-Goals.
6. <a name="13.6"></a>The combination function SHALL be testable against fixed input vectors documented in the design document.

### 14. User Correction Hooks (Data Only)

**User Story:** As a future clinical track maintainer, I want every meal record to carry the data hooks needed for a HITL learning loop, so that the clinical track can implement density and bulk-correction refinement without changes to the research pipeline.

**Acceptance Criteria:**

1. <a name="14.1"></a>The meal record SHALL include an optional `userCorrection` field with: corrected total carbohydrate, corrected per-class carbohydrate (where the user identified the correction at class level), free-text note, and timestamp.
2. <a name="14.2"></a>The meal record SHALL persist the original computed values immutably alongside any user correction; corrections SHALL never overwrite the original derivation.
3. <a name="14.3"></a>The system SHALL NOT use the corrections to refine any model, density value, or $\beta_c$ in v1. The hooks exist only to capture data for the clinical track.
4. <a name="14.4"></a>The correction record schema SHALL be portable (Protocol Buffers / JSON / SQLite columns) and shared verbatim with the future clinical track.

### 15. Persistence and Data Model

**User Story:** As the system, I want all artefacts of an estimation persisted in a portable form, so that the meal can be re-examined, audited or migrated without iOS lock-in.

**Acceptance Criteria:**

1. <a name="15.1"></a>FOR each completed estimation, the system SHALL persist the original captured frame(s) as image files in the artefact directory.
2. <a name="15.2"></a>FOR each completed estimation, the system SHALL persist the calibration record from [2.3](#2.3) in the SQLite database.
3. <a name="15.3"></a>FOR each completed estimation that used LiDAR, the system SHALL persist the LiDAR depth map as a binary file in the artefact directory.
4. <a name="15.4"></a>FOR each completed estimation, the system SHALL persist the segmenter masks per view as image files in the artefact directory.
5. <a name="15.5"></a>FOR each completed estimation, the system SHALL persist the metric scale record from [7](#7-metric-scale-establishment), the support-plane record from [4](#4-support-plane-detection-and-closure), the volume summary (per-class corrected volumes and a compressed bounding-set representation), the macro record from [12](#12-macronutrient-calculation), the confidence record from [13](#13-confidence-reporting), the `capturePath` from [3.8](#3.8), the database edition from [11.9](#11.9), and the optional correction record from [14](#14-user-correction-hooks-data-only) in the SQLite database.
6. <a name="15.6"></a>The persistence format SHALL be a single SQLite database for tabular data plus a directory of immutable per-meal artefact files (image bytes, depth bytes, mask bytes). Image, depth, and mask bytes are NOT stored as SQLite blobs because they are large and benefit from filesystem-level handling.
7. <a name="15.7"></a>The application SHALL NOT use Core Data or any iOS-only ORM.
8. <a name="15.8"></a>The application SHALL provide a local export of the entire dataset to a single archive (zip of the SQLite file plus the artefact directory), suitable for the clinical track's data export feature.

### 16. Performance and Compute Budget

**User Story:** As a user, I want the carbohydrate estimate displayed within 30 seconds of confirming the photograph in the LiDAR single-view path for usability. The primary target is accuracy and consistency of estimates, rather than speed.

**Acceptance Criteria:**

1. <a name="16.1"></a>End-to-end latency from confirming the captured photograph(s) to displaying the meal-level carbohydrate total SHOULD be under **30 seconds** on the v1 hardware floor for both `capturePath` values. This is a soft target — accuracy and consistency are the primary v1 acceptance criteria; the 30 s figure is a usability ceiling, not a CI gate.
2. <a name="16.2"></a>Per-stage P95 budgets are not specified for v1. Per-stage timing MAY be captured via `os_signpost` intervals for ad-hoc Instruments inspection but SHALL NOT gate CI.
3. <a name="16.4"></a>The end-to-end path SHALL NOT issue any network call.
4. <a name="16.5"></a>The segmenter SHALL run on the device's neural accelerator where available; CPU-only fallback SHALL be permitted for development builds only.
5. <a name="16.6"></a>Memory peak per estimation SHALL not exceed 300 MB.

### 17. Privacy and Photo Handling

**User Story:** As a user, I want my food photographs to stay on my device, so that I can use the app without leaking images of my home, hands or surroundings.

**Acceptance Criteria:**

1. <a name="17.1"></a>Captured frames, depth maps, and segmentation masks SHALL be persisted only in the application's private container.
2. <a name="17.2"></a>The application SHALL NOT upload, sync, or otherwise transmit any captured frame, depth map, mask or derived voxel grid to any network endpoint in the v1 core path.
3. <a name="17.3"></a>The photo may remain on the device, and what is retained by the application is a pointer to the photo. Permissions can be managed at system level.
4. <a name="17.5"></a>Optional cloud-validation fallback (Option D, deferred), if implemented in a future release, SHALL be off by default, opt-in per capture, and SHALL be specified separately.
5. <a name="17.6"></a>[DEFERRED — compile flag `RETENTION_SCHEDULER_ENABLED`] When the `RETENTION_SCHEDULER_ENABLED` compile flag is enabled, the application SHALL enforce configurable retention windows (30 / 90 / 365 days, or indefinite) for locally stored artefacts via `RetentionScheduler`, using a background sweep registered with `BGProcessingTask` and a foreground fallback. This feature is disabled in v1. It will be re-evaluated when cloud storage handoff (see [17.5](#17.5)) is designed; at that point the scheduler becomes the trigger for local-to-remote migration and on-device deletion.

### 18. Portable Pipeline Contracts

**User Story:** As a future Android co-developer, I want every algorithm, data format and contract specified in a platform-neutral form, so that I can implement the Android version without re-deriving the mathematics, re-curating the database, or re-training the segmenter.

**Acceptance Criteria:**

1. <a name="18.1"></a>Every algorithm in this spec (card detection, support-plane fit, metric scale resolver, segmenter pre/post-processing, voxel carving, height-field integration, multi-class ownership, macronutrient calculation, confidence combination) SHALL be specified in pseudocode plus mathematical equations, never in iOS-only language constructs, in the design document.
2. <a name="18.2"></a>Every data structure crossing a pipeline boundary (calibration record, depth map, mask record, support-plane record, volume summary, macro record, correction record) SHALL be defined once in a platform-neutral schema (Protocol Buffers, FlatBuffers, or documented SQLite schema).
3. <a name="18.3"></a>The segmenter SHALL be exportable to both the iOS and Android inference runtimes from a single source-of-truth checkpoint (per [8.5](#8.5)).
4. <a name="18.4"></a>The bundled food database SHALL be a single SQLite file usable verbatim on Android (per [11.8](#11.8)).
5. <a name="18.5"></a>The design document SHALL include a "Portability Notes" subsection per algorithm that lists the iOS-only API used in v1 and the equivalent Android API expected to be used in a future port.

### 19. Localisation — Irish / British English

**User Story:** As a user, I want all text in the app spelled in Irish / British English.

**Acceptance Criteria:**

1. <a name="19.1"></a>All user-facing strings in the application, including UI labels, error messages, log lines, and bundled documentation, SHALL use Irish / British English spelling: "recognised", "fibre", "colour", "favourite", "centre", etc.
2. <a name="19.2"></a>A linter or string audit step SHALL be part of the CI pipeline, rejecting common US-English abberations ("recognized", "color", "fiber", "favorite", "center").
3. <a name="19.3"></a>Person-first language are explicitly out of scope for v1 (Decision 4 in `decision_log.md`).

### 20. Training-Data Acquisition (Open Risk — Promoted from Open Items)

**User Story:** As a project owner, I need a concrete plan to acquire the labelled image dataset that the segmenter requires, so that the segmenter accuracy bar in [8.9](#8.9) and the end-to-end accuracy bar in [21.3](#21.3) are achievable.

**Acceptance Criteria:**

1. <a name="20.1"></a>The project SHALL have a documented training-data acquisition plan before the segmenter base model is selected, covering: target images per class (initial bar: 1,000 labelled instances per class minimum), labelling protocol (polygon masks at the food/background boundary, class label per polygon), licensing of source images (own-photographed or permissively licensed), and split strategy (training / validation / held-out segmenter test).
2. <a name="20.2"></a>The plan SHALL identify which existing public food-segmentation datasets (e.g. UECFOOD-256, Recipe1M+, FoodSeg103) overlap with the v1 class palette and which classes require new collections.

### 21. Test Harness and Validation

**Feature-flagged off in v1 (developer-only validation tool).** The harness SHALL exist in source and be implemented per the criteria below, but SHALL be gated behind the `HARNESS_ENABLED` Swift compile flag and SHALL NOT be compiled into shipping app builds. The MVP shipping app MUST operate without the harness being active. No CI gate SHALL be wired on its outputs in v1; the harness is run by the developer on demand to validate that the pipeline behaves correctly. See `decision_log.md` Decision 41 (which supersedes Decision 34).

This application is a single-developer data and context tool. Interpretation of estimates is the developer's responsibility; the app makes no clinical or safety claim. The harness exists to give the developer confidence that the pipeline works, not as a user-facing safety gate.

**User Story:** As the sole developer of this tool, I want a documented test set and a numeric accuracy harness available behind a compile flag, so that I can validate the v1 pipeline locally without shipping the harness code in the app.

**Acceptance Criteria:**

1. <a name="21.1"></a>The project SHALL maintain a labelled internal test set of meal photographs with: (a) ground-truth per-class mass measured by gravimetric weighing on a calibrated scale, (b) ground-truth per-class carbohydrate computed from those masses and the bundled CoFID coefficients, and (c) ground-truth meal-total carbohydrate as the sum. Water displacement SHALL NOT be used for foods that absorb, float, dissolve, or contain voids.
2. <a name="21.2"></a>The accuracy harness SHALL compute, on the test set: mean absolute percentage error (MAPE) of total carbohydrate, mean absolute error (MAE) in grams, and per-class breakdowns of the same.
3. <a name="21.3"></a>The v1 informational accuracy reference SHALL be MAPE < 20% AND MAE ≤ 25 g of carbohydrate per meal photograph on the evaluation subset of the test set, expressed as a **point estimate**, with the bulk-correction factors $\beta_c$ from [11.7](#11.7) calibrated on the disjoint calibration subset per [21.4](#21.4). This is a target the developer uses to interpret harness output; it is NOT a CI gate and NOT a user-facing claim.
4. <a name="21.4"></a>$\beta_c$ calibration and the accuracy reference evaluation SHALL be performed on disjoint subsets of the test set to avoid trivially fitting $\beta_c$ to the eval set; the design document SHALL specify the cross-validation procedure. The calibration subset SHALL contain at least 30 meals per class for that class to be marked `calibrated` per [11.7](#11.7); classes not meeting this bar SHALL use $\beta_c = 1.0$ or the design-document-defined pooled fallback. The harness output SHALL report per-class statistics that distinguish `calibrated` from `uncalibrated` classes.
5. <a name="21.5"></a>The harness SHALL also produce per-stage latency statistics matching [16.1](#16.1) for both `capturePath` values.
6. <a name="21.6"></a>The harness SHALL also compute the segmenter mIoU bar from [8.9](#8.9) on the held-out segmenter test set.
7. <a name="21.7"></a>The harness SHALL be runnable on a developer Mac under `-D HARNESS_ENABLED` and SHALL NOT be required to be runnable in shared CI for v1.
8. <a name="21.8"></a>WHERE the test set is too small to support a 95% confidence interval on the accuracy reference, the harness SHALL report the confidence interval explicitly rather than a point estimate alone.
9. <a name="21.9"></a>All harness source (the `HarnessCLI` SPM target, `AccuracyHarness`, `BetaCalibrator`, `FixtureLoader`, `FixtureRunner`, `SegBench`, and the corresponding test target) SHALL be gated behind `#if HARNESS_ENABLED`. The default build configuration (Debug and Release for the iOS app target) SHALL NOT define `HARNESS_ENABLED`. The `HarnessCLI` SPM executable target SHALL define `HARNESS_ENABLED` in its own `swiftSettings` so it always builds when explicitly targeted.

### 22. Optional Cloud Validation Fallback (Deferred — Non-Core)

**User Story:** As a future maintainer, I want the option to invoke an external cloud model on demand to cross-check on-device estimates, so that ambiguous captures can be validated without changing the core pipeline.

**Acceptance Criteria:**

1. <a name="22.1"></a>This requirement is explicitly DEFERRED. Implementation is NOT in scope for v1.
2. <a name="22.2"></a>WHEN the optional fallback is later implemented, it SHALL be off by default and opt-in per capture.
3. <a name="22.3"></a>WHEN invoked, the fallback SHALL submit only the captured frames and the on-device macro estimate, never the segmentation masks, depth map, or voxel grid (to preserve forward portability).
4. <a name="22.4"></a>The fallback's response SHALL never overwrite the on-device estimate; the cloud value SHALL be persisted as a parallel field for comparison and clinical-track use.
5. <a name="22.5"></a>The interface to the fallback SHALL be specified as a separate spec in the future, not in this document.

### 23. Phased Delivery and Development Stubs

**User Story:** As the sole developer, I want the pipeline to run end-to-end on the device with a placeholder segmenter, so that capture, persistence, gating, and UI plumbing can be exercised on real hardware before the trained Core ML model is ready.

**Acceptance Criteria:**

1. <a name="23.1"></a>The application SHALL build and run on the v1 hardware floor ([1.2](#1.2)) without requiring a bundled trained `.mlpackage`. Phase 1 builds (as defined under "Delivery phases" in the introduction) are the default development configuration; they SHALL run the full pipeline using the dev stub from [23.2](#23.2).
2. <a name="23.2"></a>A `StubInferenceEngine` SHALL exist in `MedataCore/Sources/Segmentation/` and conform to the same `SegmenterInferenceEngine` contract as `CoreMLInferenceEngine`. The stub SHALL emit a deterministic per-pixel probability tensor that assigns ≥0.99 probability to a single non-background class (default: `class index 0` from `ClassPalette.v1Standard`) and SHALL NOT depend on any external model file. It SHALL complete in under 50 ms per view on the v1 hardware floor.
3. <a name="23.3"></a>WHEN the application is built with the dev stub active, the result view SHALL display a visible Irish-English banner stating that the macronutrient values are placeholders produced by a development segmenter. The banner SHALL be unmistakable (high-contrast colour, persistent above the carbohydrate total). It SHALL be removed only when the trained Core ML model is bundled per Phase 3.
4. <a name="23.4"></a>Selection between the dev stub and the real Core ML segmenter SHALL be controlled by a compile-time mechanism (Swift compile flag) defined in `Package.swift` for the iOS app target. The flag SHALL be defined in Debug configurations by default and SHALL NOT be defined in Release configurations once the trained model is bundled. The selection SHALL NOT be a runtime toggle.
5. <a name="23.5"></a>Phase 1 SHALL NOT modify any algorithm, data structure, or persisted contract specified in [2](#2-camera-capture-session-and-intrinsics) through [22](#22-optional-cloud-validation-fallback-deferred-non-core). The dev stub substitutes only the inference engine; pre-processing, post-processing, ownership ([9.5](#9.5)), confidence ([13](#13-confidence-reporting)), and persistence ([15](#15-persistence-and-data-model)) SHALL be the same code paths that Phase 3 will exercise.
6. <a name="23.6"></a>Each meal record produced by a Phase 1 build SHALL persist a `segmenterSource` field with values `dev_stub` or `coreml_<modelVersion>` so that an audit can distinguish placeholder records from real ones. Phase 1 records SHALL NOT be admitted to any Phase 3 accuracy harness output.

---

## Open Items for Design Phase

These items are deliberately deferred to the design document rather than the requirements:

- The voxel-grid edge length sensitivity study (3 mm default per [9.3](#9.3), evaluate 2 mm and 5 mm).
- The exact mask-matching algorithm in [10.4](#10.4) (greedy pixel overlap vs Hungarian assignment vs simple class-equivalence).
- The selection of the segmenter base architecture and the precise input resolution vs latency trade-off.
- The exact $\beta_c$ calibration procedure and cross-validation split.
- The exact serialisation format for persisted artefacts (Protocol Buffers vs FlatBuffers vs documented SQLite schema for non-blob data).
- Selection of which composite dishes (stew, curry, mixed salad) get dedicated segmenter classes vs being routed to `unknown_food`.
