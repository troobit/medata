# Two-View Trust — Requirements (draft for the 2026-09-25 10:00 decision)

## Introduction

Two-view capture (nadir + oblique photo, voxel carve, scale from LiDAR or an ID-1 card) is the path every phone without LiDAR must use and the path a LiDAR phone takes in Double mode. The night audit (`docs/agent-notes/two-view-geometry-audit.md`) found that no two-view volume in the corpus has ever come from the carve: the stored inter-view transform does not match the photos, so the two silhouettes never intersect and every number is the 30 mm single-view extrusion. On top of that, the segmenter labels an unfamiliar food differently in the two views, so even a working carve would not have run; and the ID-1 card scale path has never executed end to end. The product owner's proposal — the user identifies the food in both photos — is the right lever for the segmenter half, and useless until the geometry half is fixed.

This spec orders the work so each step is verifiable on the phone within a sitting.

## Requirements

### 1. Two-view geometry is verified before anything is built on it

1.1 The system MUST record, for every two-view attempt, the nadir and oblique `camera.transform`, frame timestamps, tracking state and the session run count in the capture bundle, so a stored transform can be audited against the photos offline.
1.2 The inter-view transform applied by the carve MUST be in millimetres and in the camera frame the pixel model uses (u right, v down, −Z forward); the conversion point MUST be one function with a unit test that maps a known 3-D point between two synthetic poses.
1.3 A device verification MUST show, on a printed checkerboard or ID-1 card visible in both views, that the corners back-projected from the nadir land on the oblique corners within 10 px after the transform; the carve is not trusted before this passes.
1.4 Until 1.3 passes, the two-view record MUST carry a degraded flag (the existing `singleViewOnly` σ_view tier is not enough: the carve itself never ran) and the review MUST show it.

### 2. Cross-view reconciliation before the carve

2.1 When the nadir and the oblique each contain at most one named food-like class (with or without `unknown_food` patches) and the classes differ, the system MUST treat them as the same object and carve with both silhouettes under one class: a named class wins over `unknown_food`, the nadir's named class wins over the oblique's, and the user's choice (Req 3) wins over both. The reconciliation MUST be recorded on the outcome row (both views' classes and the chosen one).
2.2 A class present in only one view MUST NOT be extruded from the oblique view alone (kept from bugfix two-view-unknown-carve); extrusion from the nadir alone MUST be flagged degraded on the row.
2.3 On multi-food plates the reconciliation MUST NOT merge regions across a real boundary: it applies only to the single-region case until instance matching exists.

### 3. The user identifies the food in both photos (Double mode)

3.1 Between the two shots, the system MUST show the nadir frame with the food-like region outlined and let the user tap a region to confirm it, or tap an unoutlined area to seed one; the confirmed region becomes the nadir silhouette and the plane-fit mask (`CaptureResult.preShutterFoodMask` already carries it).
3.2 After the oblique shot, the system MUST show the oblique frame with the food-like region outlined and require the same confirmation before the estimate runs; the two confirmations assert "same object here and here".
3.3 A tap-seeded region on a phone without depth MUST grow by colour/edge continuity from the tap, with the outline shown for acceptance; on a LiDAR phone the depth-grown region (depth-grown-food-region) is the outline offered.
3.4 The user MUST be able to name the food once, from the existing relabel shortlist and full list, and the name MUST apply to both silhouettes; naming alone (without confirmed regions) MUST NOT change the geometry.
3.5 Both confirmed silhouettes MUST be stored per view (`meal_artefacts` has the per-view key; the capture bundle needs two new fields) with provenance `user_confirmed`, and the record MUST show the estimate was user-assisted.
3.6 Painting (brush, lasso) MUST NOT be offered; boundary edits are a tap-and-accept interaction (meal-review Decision 4 stands).
3.7 The confirmation steps MUST be skippable in one tap when the outlines are right, so a well-recognised plate costs at most two taps more than today.

### 4. The ID-1 card path is honest and verifiable

4.1 `scaleSource` MUST say `card` only when a card was actually used for scale, and a detected rectangle whose scale disagrees with LiDAR by more than a bound MUST NOT raise σ_scale.
4.2 The card's PnP residual and derived distance MUST be persisted on the outcome row.
4.3 Double mode MUST show the "include an ID-1 card" reminder that iphone-experience Req 6.1 promised, and on a phone without LiDAR the shutter MUST NOT arm until a card is detected live.
4.4 `CardOnlyPlaneFitter` MUST be fed the food's lower silhouette edges (pipeline Req 4.3), not the card's corners and a constant; until then the card-only path MUST refuse rather than return an invented plane.
4.5 A Debug switch MUST let a LiDAR phone run the non-LiDAR path (depth cleared, card branch taken) so the card path is verifiable on the phones in hand; the harness MUST be able to replay it.
4.6 A detected card MUST NOT contribute food pixels: its solved image quadrilateral (nadir) and its projection into the oblique view (via the Req 1 transform and the card plane) MUST be cleared to background in both argmax maps before region growth and volume, and the outcome row MUST record the pixel count removed. Evidence: 2026-08-11 capture `1786439234576`, bank card integrated as `cheese` 43.7 g.

## Out of scope

Instance segmentation; spatial matching of multiple foods across views; brush or lasso editing; any change to the single-view LiDAR path; model retraining.
