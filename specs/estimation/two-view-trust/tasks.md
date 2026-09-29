---
references:
    - requirements.md
    - decision_log.md
---
# two-view-trust

## Geometry

- [x] 1. Inter-view transform is in mm, conjugated into the §6.0 frame, inverted correctly; grid axis is +gravity (Req 1.1, 1.2)

- [x] 2. Both poses and the mm transform are recorded on every two-view outcome; cross-generation pairs refuse (Req 1.4, 1.5)

- [x] 3. Device verification: card or checkerboard corners back-project between views within 10 px (Req 1.3)

## Card path

- [x] 4. A rectangle whose scale disagrees with LiDAR beyond the bound is dropped from scale and never raises σ_scale (Req 4.1)

- [x] 5. The card's PnP residual, distance and disagreement are on the outcome row (Req 4.2)

- [x] 6. An accepted card's quadrilateral is cleared from the nadir probabilities and labels before volume (Req 4.6, nadir half)

- [x] 7. Card detection replays in the harness (macOS Vision) and the bound is set from real-card and no-card bundles (Req 4.5, harness half)

- [x] 8. The card's projection into the oblique view is cleared once the Req 1.3 transform is verified (Req 4.6, oblique half)

- [x] 9. Double mode shows the card reminder; without LiDAR the shutter does not arm until a card is detected live (Req 4.3)

- [x] 10. Card-only plane fit takes the food's lower silhouette edges or refuses (Req 4.4)

- [x] 11. Debug switch runs the non-LiDAR path on a LiDAR phone (Req 4.5, device half)

- [x] 12. The review outline shades the accepted card's quadrilateral as the reference, distinct from food (owner note 2026-09-25)

- [x] 13. A card-only capture that refuses for want of a support plane says so, not noScaleAvailable (Pipeline.swift:880)

## User-identified regions

- [x] 14. Cross-view label reconciliation before the carve (Req 2)

- [ ] 15. Two-tap confirmation of the food in both photos (Req 3) — REJECTED by its own gate 2026-09-25 (Decision 7): a hand-placed seed changes the leak by under 1 %, because the plate is reached from the food's own component. Req 3 is back for re-decision

## Carve height

- [x] 16. The voxel grid's vertical extent is bounded by the LiDAR-measured food height, not a constant (backlog 29)

- [x] 17. The carve's silhouette test agrees with the regularised argmax the rest of the pipeline uses (28 % halo, −217 cm³)

- [x] 18. A two-view estimate taken without depth is flagged degraded on the row and in review, and its carb figure is not offered for dosing (Decision 8)

- [x] 19. Developer-phase shutter arms outside the 10–40° tilt band so a near-side-on oblique can be captured (Decision 8 experiment)

- [ ] 20. Device capture of a known object with the oblique near side-on decides whether a wider aim band bounds height (Decision 8)

- [ ] 21. Two-view plane refit from the grown region — Decision 10; device round pending
  - [x] 21.1. Pipeline two-view branch, harness twin and carve-audit share GrownRegionPlaneRefit; offline replay measured
    - Before → after (cm³) on the §7 bundles: 1790318627741 397.1 → 397.1 (edgeBand refit held by Decision 3); 1790315814452 509.8 → 390.1; 1790310086654 351.4 → 350.3; 1790315734391 284.1 → 268.0; 1790325380366 358.8 → 358.9; hull ÷ surface ≥ 1.099 on all five; single-view controls 298.9 and 309.5 unchanged
  - [ ] 21.2. STOP: device round — capture the roll in Double mode and read event=region.grow planeOnly=true before Decision 10 leaves proposed

- [x] 22. Class height cap on the non-LiDAR carve — Decision 11
  - No-depth carve at the adopted plane, 120 mm → class cap 85.9 (cm³, LiDAR reference): 1790318627741 709.8 → 583.1 (397.1); 1790315814452 690.0 → 610.7 (390.1); 1790310086654 678.9 → 595.4 (350.3); 1790315734391 632.8 → 534.7 (268.0); 1790325380366 749.6 → 663.6 (358.9). Ratio to LiDAR improves on all five (1.77–2.36 → 1.47–2.00), none under the 1.3 pass line. LiDAR path and single-view controls byte-identical

- [x] 23. Footprint-scaled class height cap — Decision 12
  - height_priors.v2 with ratio_p90 and cap_mode (bread, broccoli, carrot, tomato, pork in ratio mode); no-depth carve at the adopted plane, class cap 87 → ratio cap (footprint mm², cap mm; cm³, LiDAR reference): 1790318627741 10267, 56.8: 583.1 → 416.5 (397.1, 1.05); 1790315814452 12051, 61.1: 610.7 → 502.3 (390.1, 1.29); 1790310086654 12234, 61.5: 595.4 → 485.2 (350.3, 1.39); 1790315734391 10635, 57.7: 534.7 → 412.7 (268.0, 1.54); 1790325380366 12417, 61.9: 663.6 → 550.2 (358.9, 1.53). Two of five under the 1.3 pass line, so the decision stays proposed; the ratio cap is not applied where a height is measured and the LiDAR replay is byte-identical on all seven bundles
