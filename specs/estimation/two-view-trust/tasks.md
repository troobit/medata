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

- [ ] 8. The card's projection into the oblique view is cleared once the Req 1.3 transform is verified (Req 4.6, oblique half)

- [ ] 9. Double mode shows the card reminder; without LiDAR the shutter does not arm until a card is detected live (Req 4.3)

- [ ] 10. Card-only plane fit takes the food's lower silhouette edges or refuses (Req 4.4)

- [ ] 11. Debug switch runs the non-LiDAR path on a LiDAR phone (Req 4.5, device half)

## User-identified regions

- [ ] 12. Cross-view label reconciliation before the carve (Req 2)

- [ ] 13. Two-tap confirmation of the food in both photos (Req 3)
