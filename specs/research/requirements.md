# Research — Requirements

**Version:** 0.2
**Date:** 2026-05-05
**Status:** Draft (post-review revision)
**Branch:** research

## Introduction

This spec defines a low-compute, on-device system for estimating the carbohydrate content of a meal from one or two photographs taken on a modern iPhone. It supersedes the LLM-based MVP described in `specs/mvp-refinement` (see `decision_log.md` Decision 1) and grounds every step in the academic literature it inherits from:

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
4. **Liquids and semi-liquids are out of scope for v1.** Clear liquids (water, tea), opaque liquids (soup, smoothies), pourable semi-liquids (yoghurt, custard, gravy) are excluded. The segmenter palette includes an `unsupported_liquid` class that surfaces an explicit Irish-English message and disables the carb estimate for that region.

### Out of scope (deferred to other specs)

- `specs/clinical`: atomic event log, AWAP cycle, active-carb-load decay model, CGM (Dexcom / LibreView) synchronisation. The research spec defines the data hooks the clinical track will consume but does not implement clinical features.
- `specs/cloud-validation` (future): the optional cloud cross-check fallback (Option D in Decision 3).
- Liquids and semi-liquids (see assumption 4).

### Hardware floor

V1 hardware floor: iPhone 12 Pro and later Pro / Pro Max devices (any rear-LiDAR iPhone). V1 OS floor: iOS 17. The architecture is platform-portable so a future Android implementation can re-use the algorithms, data formats and segmenter without re-deriving the mathematics.

### Spelling

All user-facing strings, identifiers, comments and documentation use Irish / British English spelling (e.g. "recognised", "fibre", "colour", "programme"). HSE Language Matters and person-first language are out of scope (see Decision 4).

---

## Requirements

### 1. Native iOS Application Foundation

**User Story:** As a developer, I want a clean native iOS Swift application as the only user-facing implementation, so that v1 ships with a deterministic on-device pipeline and no legacy code paths.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL ship as a native iOS application written in Swift.
2. <a name="1.2"></a>The application SHALL target iOS 17 or later and SHALL run on iPhone 12 Pro and later Pro / Pro Max devices that ship a rear-facing LiDAR scanner.
3. <a name="1.3"></a>The application SHALL refuse to launch the capture flow on a device without a rear LiDAR scanner and SHALL surface an Irish-English message naming the supported device range.
4. <a name="1.4"></a>The application SHALL NOT include or invoke any code path from the prior SvelteKit-based MVP. The Svelte source tree SHALL be moved to a `legacy/` directory (or a tagged historical branch) prior to v1 release.
5. <a name="1.5"></a>The application SHALL operate entirely offline in its core estimation path. No network call SHALL be required for capture, segmentation, voxel carving, density lookup, or macronutrient calculation.

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

1. <a name="3.1"></a>The capture flow SHALL display a real-time tilt indicator driven by the device's gravity vector, showing deviation in degrees of the device's optical axis from the target angle.
2. <a name="3.2"></a>The first view SHALL target nadir (0° from vertical, top-down). The system SHALL accept a capture only when the device tilt is within ±5° of vertical.
3. <a name="3.3"></a>WHEN the canonical two-view path is in use, the second view SHALL target an oblique angle of 25° from vertical (within the 20°–30° envelope justified by Dehais 2017 §III.B). The system SHALL accept the second capture only when the device tilt is within ±5° of 25°.
4. <a name="3.4"></a>The system SHALL prompt the user to hold the device at a working distance of 30–40 cm from the food. WHERE LiDAR depth is available, the system SHALL measure actual distance and refuse capture outside 25–50 cm.
5. <a name="3.5"></a>WHEN LiDAR depth is available AND a support plane has been detected (see [4](#4-support-plane-detection-and-closure)) AND valid metric depth covers ≥80% of the food region, the system MAY skip the oblique view and proceed with the **single-view depth-augmented path** (see [9.4](#9.4)). The system SHALL surface a clear UI affordance for the user to opt back into a two-view capture.
6. <a name="3.6"></a>The two captured views, when both are taken, SHALL share a world coordinate frame so that the relative pose of the second view with respect to the first is recorded as a 6-DOF transform $T_{1 \to 2} \in SE(3)$.
7. <a name="3.7"></a>IF world tracking confidence falls below the platform-defined "normal" threshold between the two views, THEN the system SHALL discard the second view and prompt the user to retake it.
8. <a name="3.8"></a>The meal record SHALL persist a `capturePath` enum with values `single_view_lidar` or `two_view_sfs` so that downstream consumers can interpret the estimate's error characteristics.

**Portability Notes:** iOS uses Core Motion gravity, ARKit world tracking, ARKit `sceneDepth` for LiDAR. Android uses `SensorManager` gravity, ARCore world tracking, ARCore Depth API (note: ARCore Depth on most Android devices is software-derived multi-view stereo, not LiDAR — the single-view shortcut in [3.5](#3.5) requires *true* time-of-flight depth and is currently iOS-only).

### 4. Support Plane Detection and Closure

**User Story:** As the system, I need the plate / table support plane in the scene's metric coordinate frame, so that voxel carving has a lower bound and the visual hull can be closed from below.

**Acceptance Criteria:**

1. <a name="4.1"></a>For every estimation, the system SHALL detect a support plane $\pi_{\text{sup}}$ defined by a unit normal $\hat{n}$ (close to the gravity vector) and a signed distance $d$ from the camera origin, expressed in the same coordinate frame as the voxel grid.
2. <a name="4.2"></a>WHERE LiDAR depth is available, $\pi_{\text{sup}}$ SHALL be fit to depth points at and around the lower edge of the food bounding region using RANSAC plane fitting.
3. <a name="4.3"></a>WHERE LiDAR depth is unavailable but the canonical two-view path is in use, $\pi_{\text{sup}}$ SHALL be inferred from the lower silhouette edges across views together with the gravity vector and the metric scale (see [7](#7-metric-scale-establishment)).
4. <a name="4.4"></a>The detected support plane SHALL be used as a lower carving bound: any voxel whose centre lies on the negative side of $\pi_{\text{sup}}$ (below the plate) SHALL be excluded from $H_c$ for every class $c$.
5. <a name="4.5"></a>IF support-plane detection fails (LiDAR plane fit residuals above a documented threshold OR no support edges visible across views), THEN the pipeline SHALL surface a "place the meal on a flat surface" message and refuse to compute.
6. <a name="4.6"></a>The plane-fit residual standard deviation SHALL be persisted as a sub-confidence input to [13](#13-confidence-reporting).

**Portability Notes:** iOS uses ARKit `ARPlaneAnchor` for LiDAR-backed plane detection as a starting heuristic, refined by RANSAC on the depth point cloud. Android uses ARCore `Plane` similarly.

### 5. ID-1 Reference Card Detection and Pose

**User Story:** As the system, I want a metric pose for an ID-1 card in the scene, so that I have an independent metric scale that does not require LiDAR.

**Acceptance Criteria:**

1. <a name="5.1"></a>The card detector SHALL locate a quadrilateral matching the ISO/IEC 7810 ID-1 form factor (85.60 × 53.98 mm) in the input image using contour detection followed by quadrilateral fitting (Hough lines as a fallback when contour fitting fails).
2. <a name="5.2"></a>WHEN a card is detected, the detector SHALL recover the 6-DOF pose of the card relative to the camera by solving Perspective-n-Point with the four corner pixel coordinates, the known 85.60 × 53.98 mm physical dimensions, and the calibration intrinsics from [2.3](#2.3).
3. <a name="5.3"></a>The recovered card pose SHALL yield a metric scale $s_{\text{card}}$ defined at the food plane (parallel to the card plane, offset by the food's mean height above the support plane).
4. <a name="5.4"></a>The card detector SHALL operate on every captured view. The detector behaviour SHALL be specified once in mathematical form and implemented identically across views.
5. <a name="5.5"></a>IF no card is detected, THEN the detector SHALL return a "no-card" outcome rather than fail. The downstream pipeline SHALL treat this as a metric-scale degradation, not an error (see [7](#7-metric-scale-establishment)).
6. <a name="5.6"></a>The card detector SHALL run in under 80 ms per view on the v1 hardware floor.
7. <a name="5.7"></a>The card detector specification SHALL be expressible without reference to any iOS-only API; the iOS implementation MAY use the Vision framework.

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
4. <a name="8.4"></a>The segmenter class palette SHALL contain exactly 24 food classes for v1 (curated jointly with the density coverage in [11](#11-density-and-macronutrient-database)) plus a `background` class, an `unknown_food` class, and an `unsupported_liquid` class.
5. <a name="8.5"></a>The segmenter SHALL be sourced from a single source-of-truth model that exports cleanly to both the iOS inference runtime and the Android inference runtime via ONNX or an equivalent intermediate representation.
6. <a name="8.6"></a>IF a pixel is labelled `unknown_food`, THEN the pipeline SHALL include those voxels in volume estimation but SHALL flag the meal as containing unrecognised food, and the macro contribution from those voxels SHALL be reported as "unknown carbs" with a confidence of 0.
7. <a name="8.7"></a>IF a pixel is labelled `unsupported_liquid`, THEN the pipeline SHALL exclude those voxels from volume estimation, SHALL flag the meal as containing an unsupported liquid, and SHALL surface an Irish-English message stating that liquids are not estimated in v1.
8. <a name="8.8"></a>The segmenter input SHALL be a fixed-size resized colour image (aspect-preserving with letterboxing); the resize procedure SHALL be specified once and applied identically on both platforms.
9. <a name="8.9"></a>The segmenter SHALL meet a minimum mean Intersection-over-Union (mIoU) of **0.60 averaged across food classes** on the held-out segmenter test set, evaluated separately from the end-to-end accuracy bar in [21.3](#21.3).

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
5. <a name="9.5"></a>**Multi-class voxel ownership:** WHEN the silhouettes of two or more classes overlap from a given view (two-view path) or two classes' nadir-view masks overlap (single-view path), each pixel SHALL be assigned to exactly one class by per-pixel argmax over the segmenter class probability vector from [8.1](#8.1). No voxel and no nadir-view pixel SHALL contribute mass to more than one class.
6. <a name="9.6"></a>The volume estimator SHALL produce, per class, the corrected metric volume $V_c$ in cubic centimetres and a compressed bounding-set representation of the carved/integrated region for persistence.
7. <a name="9.7"></a>The two-view voxel carver SHALL complete in under 300 ms per meal on the v1 hardware floor; the single-view height-field integrator SHALL complete in under 80 ms per meal.
8. <a name="9.8"></a>The volume estimator algorithm SHALL be specified in pseudocode in the design document, with the back-projection equation, height-field integration equation, and ownership rule written explicitly, and SHALL NOT depend on any iOS-only API in its specification.
9. <a name="9.9"></a>**Visual hull bias.** The two-view path produces the visual hull, which is provably an upper bound on the true volume (Laurentini 1994). The bulk-correction factor $\beta_c$ from [11.7](#11.7) is the v1 mechanism for compensating residual bias; the single-view path's LiDAR top surface compensates more directly but $\beta_c$ still applies to absorb packing fraction.

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

1. <a name="11.1"></a>The application SHALL bundle a portable food composition database. The default source SHALL be the McCance and Widdowson CoFID dataset (latest published edition), released under the Open Government Licence v3 and bundled with attribution per OGL v3 terms. Attribution SHALL appear on the application's About / Legal screen and in every exported meal record.
2. <a name="11.2"></a>FOR each segmenter class in [8.4](#8.4), the database SHALL contain at least: class name, served-portion bulk density $\rho$ in g/cm³, energy in kJ per 100 g, carbohydrate (monosaccharide-equivalent) in g per 100 g, protein in g per 100 g, fat in g per 100 g, fibre (AOAC) in g per 100 g, and the bulk-correction factor $\beta$ from [11.7](#11.7).
3. <a name="11.3"></a>The database SHALL support an optional regional overlay. The IFCDB (Irish Food Composition Database) values SHALL be packaged as an overlay that can be loaded over CoFID without modifying the base table.
4. <a name="11.4"></a>The segmenter class palette in [8.4](#8.4) SHALL be co-curated with this database so that every class has measured density and bulk-correction values; the palette and the database SHALL be released as a versioned pair.
5. <a name="11.5"></a>Density and bulk-correction values SHALL be sourced from cited literature where available (Dehais 2017 Table II, Anthimopoulos 2014, FAO/INFOODS density tables) and from project-internal gravimetric measurement on the v1 test set otherwise. The decision log SHALL record the source for each value.
6. <a name="11.6"></a>Carbohydrate values SHALL be expressed as monosaccharide equivalents per FSAI guidance. WHERE a source provides "available carbohydrate by difference", the value SHALL be converted to monosaccharide equivalents by the documented FSAI conversion before inclusion.
7. <a name="11.7"></a>**Bulk-correction factor $\beta_c$.** For each class $c$, the database SHALL contain a unitless factor $\beta_c \in (0, 1]$ that scales the visual-hull volume to the corrected volume per [9.4](#9.4). $\beta_c$ SHALL be calibrated against the v1 test set by minimising MAE over carbohydrate totals for that class. The factor folds together: visual-hull concavity bias, packing fraction (for granular foods), and internal-void bias. Calibration procedure SHALL be specified in the design document.
8. <a name="11.8"></a>The database SHALL be packaged as a single SQLite file, which is the chosen portable format (FlatBuffers was considered and rejected for this v1 — see decision log). The schema SHALL be documented and usable verbatim on Android.
9. <a name="11.9"></a>Each meal record SHALL persist the database edition / version identifier (e.g. "CoFID 2024 + IFCDB 2023 overlay") used to compute its macros, so that re-derivation across database updates is reproducible.

### 12. Macronutrient Calculation

**User Story:** As a user, I want a per-meal carbohydrate total derived from measured volumes, densities and per-100 g coefficients, so that I have a value with traceable provenance instead of a model guess.

**Acceptance Criteria:**

1. <a name="12.1"></a>FOR each segmenter class $c$ present in the meal with corrected volume $V_c$ from [9.6](#9.6), the system SHALL compute mass $m_c = V_c \cdot \rho_c$ where $\rho_c$ is the served-portion bulk density from the bundled database.
2. <a name="12.2"></a>FOR each class $c$, the system SHALL compute carbohydrates $C_c = m_c \cdot \kappa_c / 100$ where $\kappa_c$ is the monosaccharide-equivalent carbohydrate per 100 g for that class.
3. <a name="12.3"></a>The meal-level carbohydrate total SHALL be $C_{\text{meal}} = \sum_c C_c$.
4. <a name="12.4"></a>$C_{\text{meal}}$ SHALL be displayed to the nearest **1 gram** (consistent with the 10 g MAE target in [21.3](#21.3) and with diabetes-bolus-calculator conventions).
5. <a name="12.5"></a>$C_{\text{meal}}$ and all per-class values SHALL be persisted at full machine precision regardless of display rounding.
6. <a name="12.6"></a>The system SHALL also compute and persist meal-level totals for energy, protein, fat and fibre using the same per-class formula. These totals are computed for clinical-track consumption and are NOT displayed to the user in v1.
7. <a name="12.7"></a>The meal record SHALL include the per-class breakdown ($V_c$, $m_c$, $C_c$, density source, coefficient source, $\beta_c$ used) so that any later audit can reconstruct how the meal-level total was derived.
8. <a name="12.8"></a>The macronutrient calculation SHALL be specified in pseudocode and SHALL NOT depend on any iOS-only construct.

### 13. Confidence Reporting

**User Story:** As a user, I want each carbohydrate estimate annotated with a confidence value, so that I know when to manually correct it.

**Acceptance Criteria:**

1. <a name="13.1"></a>The system SHALL compute and report a per-meal confidence $\sigma_{\text{meal}} \in [0, 1]$ as the geometric mean of three sub-confidences:
   $$\sigma_{\text{meal}} = (\sigma_s \cdot \sigma_{\text{seg}} \cdot \sigma_{\text{geom}})^{1/3}$$
   where $\sigma_s$ is the metric-scale sub-confidence from [7.1](#7.1), $\sigma_{\text{seg}}$ is the segmenter's mean class probability over food pixels, and $\sigma_{\text{geom}}$ is the geometric-completeness sub-confidence defined in [13.2](#13.2).
2. <a name="13.2"></a>The geometric-completeness sub-confidence $\sigma_{\text{geom}}$ SHALL be defined as: 1.00 for a clean two-view capture with full silhouette agreement; 0.90 for the single-view LiDAR path with ≥80% LiDAR coverage of the food region; 0.75 for a two-view capture where one or more classes appear in only one view (per [10.2](#10.2)); 0.60 for a single-view LiDAR capture with 50–80% LiDAR coverage; and refusal (no estimate) below 50% coverage.
3. <a name="13.3"></a>The system SHALL also compute a per-class confidence $\sigma_c$ using the same combination function with class-specific inputs.
4. <a name="13.4"></a>The meal record SHALL persist all sub-confidences ($\sigma_s$, $\sigma_{\text{seg}}$, $\sigma_{\text{geom}}$) so that the combination function can be revisited without re-capturing the photograph.
5. <a name="13.5"></a>WHEN $\sigma_{\text{meal}} < 0.6$ the UI SHALL display an "uncertain estimate" affordance prompting the user to either retake the photograph or manually correct the carbohydrate value.
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

**User Story:** As a user, I want the carbohydrate estimate displayed within one second of confirming the photograph in the LiDAR single-view path, so that the system is faster than manual estimation.

**Acceptance Criteria:**

1. <a name="16.1"></a>End-to-end latency from confirming the captured photograph(s) to displaying the meal-level carbohydrate total SHALL be:
   - **Single-view LiDAR path** (`capturePath = single_view_lidar`): under **1000 ms at the 95th percentile** on the v1 hardware floor.
   - **Two-view canonical path** (`capturePath = two_view_sfs`): under **1800 ms at the 95th percentile** on the v1 hardware floor.
2. <a name="16.2"></a>Per-stage P95 budgets, single-view path: card detect ≤ 80 ms, support plane fit ≤ 60 ms, segmentation ≤ 250 ms, height-field integration ≤ 80 ms, macro lookup ≤ 20 ms, persistence + UI commit ≤ 100 ms. Sum: 590 ms; remaining 410 ms absorbs P95 variance and unbudgeted overhead.
3. <a name="16.3"></a>Per-stage P95 budgets, two-view path: card detect 2 × 80 = 160 ms, support plane fit ≤ 60 ms, segmentation 2 × 250 = 500 ms, mask matching ≤ 50 ms, voxel carving ≤ 300 ms, macro lookup ≤ 20 ms, persistence + UI commit ≤ 100 ms. Sum: 1190 ms; remaining 610 ms absorbs P95 variance.
4. <a name="16.4"></a>The end-to-end path SHALL NOT issue any network call.
5. <a name="16.5"></a>The segmenter SHALL run on the device's neural accelerator where available; CPU-only fallback SHALL be permitted for development builds only.
6. <a name="16.6"></a>Memory peak per estimation SHALL not exceed 300 MB.
7. <a name="16.7"></a>A performance harness SHALL record per-stage latencies in development builds and SHALL be runnable as a CI step against a fixture set.

### 17. Privacy and Photo Handling

**User Story:** As a user, I want my food photographs to stay on my device, so that I can use the app without leaking images of my home, hands or surroundings.

**Acceptance Criteria:**

1. <a name="17.1"></a>Captured frames, depth maps, and segmentation masks SHALL be persisted only in the application's private container.
2. <a name="17.2"></a>The application SHALL NOT upload, sync, or otherwise transmit any captured frame, depth map, mask or derived voxel grid to any network endpoint in the v1 core path.
3. <a name="17.3"></a>The default photo, depth, and mask retention period SHALL be **30 days**, after which all artefacts in the per-meal artefact directory are deleted while the macro values, confidences, and meal metadata in the SQLite database are retained.
4. <a name="17.4"></a>Users SHALL be able to set retention to 90 days, 365 days, or "retain indefinitely (clinical-track participation)" via a setting; users SHALL be able to delete any individual meal's artefacts manually at any time.
5. <a name="17.5"></a>Optional cloud-validation fallback (Option D, deferred), if implemented in a future release, SHALL be off by default, opt-in per capture, and SHALL be specified separately.

### 18. Portable Pipeline Contracts

**User Story:** As a future Android co-developer, I want every algorithm, data format and contract specified in a platform-neutral form, so that I can implement the Android version without re-deriving the mathematics, re-curating the database, or re-training the segmenter.

**Acceptance Criteria:**

1. <a name="18.1"></a>Every algorithm in this spec (card detection, support-plane fit, metric scale resolver, segmenter pre/post-processing, voxel carving, height-field integration, multi-class ownership, macronutrient calculation, confidence combination) SHALL be specified in pseudocode plus mathematical equations, never in iOS-only language constructs, in the design document.
2. <a name="18.2"></a>Every data structure crossing a pipeline boundary (calibration record, depth map, mask record, support-plane record, volume summary, macro record, correction record) SHALL be defined once in a platform-neutral schema (Protocol Buffers, FlatBuffers, or documented SQLite schema).
3. <a name="18.3"></a>The segmenter SHALL be exportable to both the iOS and Android inference runtimes from a single source-of-truth checkpoint (per [8.5](#8.5)).
4. <a name="18.4"></a>The bundled food database SHALL be a single SQLite file usable verbatim on Android (per [11.8](#11.8)).
5. <a name="18.5"></a>The design document SHALL include a "Portability Notes" subsection per algorithm that lists the iOS-only API used in v1 and the equivalent Android API expected to be used in a future port.

### 19. Localisation — Irish / British English

**User Story:** As a user, I want all text in the app spelled in Irish / British English, so that the application reads correctly in its market.

**Acceptance Criteria:**

1. <a name="19.1"></a>All user-facing strings in the application, including UI labels, error messages, log lines, and bundled documentation, SHALL use Irish / British English spelling: "recognised", "fibre", "colour", "favourite", "centre", etc.
2. <a name="19.2"></a>A linter or string audit step SHALL be part of the CI pipeline, rejecting common US-English spellings ("recognized", "color", "fiber", "favorite", "center").
3. <a name="19.3"></a>Person-first language guidelines and HSE Language Matters terminology requirements are explicitly out of scope for v1 (Decision 4 in `decision_log.md`).
4. <a name="19.4"></a>This requirement does NOT extend to Irish-specific clinical content or food databases beyond the optional IFCDB overlay; the application's primary market assumption is "English-speaking" not "Ireland-only".

### 20. Training-Data Acquisition (Open Risk — Promoted from Open Items)

**User Story:** As a project owner, I need a concrete plan to acquire the labelled image dataset that the segmenter requires, so that the segmenter accuracy bar in [8.9](#8.9) and the end-to-end accuracy bar in [21.3](#21.3) are achievable.

**Acceptance Criteria:**

1. <a name="20.1"></a>The project SHALL have a documented training-data acquisition plan before the segmenter base model is selected, covering: target images per class (initial bar: 1,000 labelled instances per class minimum), labelling protocol (polygon masks at the food/background boundary, class label per polygon), licensing of source images (own-photographed or permissively licensed), and split strategy (training / validation / held-out segmenter test).
2. <a name="20.2"></a>The plan SHALL identify which existing public food-segmentation datasets (e.g. UECFOOD-256, Recipe1M+, FoodSeg103) overlap with the v1 class palette and which classes require new collection.
3. <a name="20.3"></a>The plan's deliverable SHALL be reviewed and accepted before the design phase locks the segmenter architecture.
4. <a name="20.4"></a>This requirement is the single largest project risk acknowledged at the spec level.

### 21. Test Harness and Validation

**User Story:** As a maintainer, I want a documented test set and a numeric accuracy harness, so that the v1 accuracy target is measurable and the pipeline is regression-tested.

**Acceptance Criteria:**

1. <a name="21.1"></a>The project SHALL maintain a labelled internal test set of meal photographs with: (a) ground-truth per-class mass measured by gravimetric weighing on a calibrated scale, (b) ground-truth per-class carbohydrate computed from those masses and the bundled CoFID coefficients, and (c) ground-truth meal-total carbohydrate as the sum. Water displacement SHALL NOT be used for foods that absorb, float, dissolve, or contain voids.
2. <a name="21.2"></a>The accuracy harness SHALL compute, on the test set: mean absolute percentage error (MAPE) of total carbohydrate, mean absolute error (MAE) in grams, and per-class breakdowns of the same.
3. <a name="21.3"></a>The v1 acceptance bar SHALL be MAPE < 20% AND MAE ≤ 10 g of carbohydrate per meal photograph, computed on the test set with the bulk-correction factors $\beta_c$ from [11.7](#11.7) calibrated.
4. <a name="21.4"></a>$\beta_c$ calibration and the accuracy bar evaluation SHALL be performed on disjoint subsets of the test set to avoid trivially fitting $\beta_c$ to the eval set; the design document SHALL specify the cross-validation procedure.
5. <a name="21.5"></a>The harness SHALL also produce per-stage latency statistics matching [16.1](#16.1) for both `capturePath` values.
6. <a name="21.6"></a>The harness SHALL also compute the segmenter mIoU bar from [8.9](#8.9) on the held-out segmenter test set.
7. <a name="21.7"></a>The harness SHALL be runnable on a developer Mac and (if hardware-bound stages are mocked) in CI.
8. <a name="21.8"></a>WHERE the test set is too small to support a 95% confidence interval on the accuracy bar, the harness SHALL report the confidence interval explicitly rather than a point estimate alone.

### 22. Optional Cloud Validation Fallback (Deferred — Non-Core)

**User Story:** As a future maintainer, I want the option to invoke an external cloud model on demand to cross-check on-device estimates, so that ambiguous captures can be validated without changing the core pipeline.

**Acceptance Criteria:**

1. <a name="22.1"></a>This requirement is explicitly DEFERRED. Implementation is NOT in scope for v1.
2. <a name="22.2"></a>WHEN the optional fallback is later implemented, it SHALL be off by default and opt-in per capture.
3. <a name="22.3"></a>WHEN invoked, the fallback SHALL submit only the captured frames and the on-device macro estimate, never the segmentation masks, depth map, or voxel grid (to preserve forward portability).
4. <a name="22.4"></a>The fallback's response SHALL never overwrite the on-device estimate; the cloud value SHALL be persisted as a parallel field for comparison and clinical-track use.
5. <a name="22.5"></a>The interface to the fallback SHALL be specified as a separate spec in the future, not in this document.

---

## Open Items for Design Phase

These items are deliberately deferred to the design document rather than the requirements:

- The voxel-grid edge length sensitivity study (3 mm default per [9.3](#9.3), evaluate 2 mm and 5 mm).
- The exact mask-matching algorithm in [10.4](#10.4) (greedy pixel overlap vs Hungarian assignment vs simple class-equivalence).
- The selection of the segmenter base architecture and the precise input resolution vs latency trade-off.
- The exact $\beta_c$ calibration procedure and cross-validation split.
- The exact serialisation format for persisted artefacts (Protocol Buffers vs FlatBuffers vs documented SQLite schema for non-blob data).
- Selection of which composite dishes (stew, curry, mixed salad) get dedicated segmenter classes vs being routed to `unknown_food`.
