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

- [ ] 15. Two-tap confirmation of the food in both photos (Req 3)

## Carve height

- [x] 16. The voxel grid's vertical extent is bounded by the LiDAR-measured food height, not a constant (backlog 29)

- [x] 17. The carve's silhouette test agrees with the regularised argmax the rest of the pipeline uses (28 % halo, −217 cm³)

- [x] 18. A two-view estimate taken without depth is flagged degraded on the row and in review, and its carb figure is not offered for dosing (Decision 8)

- [x] 19. Developer-phase shutter arms outside the 10–40° tilt band so a near-side-on oblique can be captured (Decision 8 experiment)

- [ ] 20. Device capture of a known object with the oblique near side-on decides whether a wider aim band bounds height (Decision 8)
