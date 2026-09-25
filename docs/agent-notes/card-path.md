# ID-1 card path

The card is the metric-scale reference for phones without LiDAR and a
corroborating signal when LiDAR is present. Spec: `specs/estimation/two-view-trust/`
Req 4; audit of its history in `two-view-geometry-audit.md` §3.

## Flow

1. `Pipeline` stage C runs `cardDetector.detect(in: nadir)` (Vision
   `VNDetectRectanglesRequest`, ID-1 aspect envelope 0.55–0.70, one observation)
   and `CardPoseSolver.solve` (PnP on four corners). The nadir only; the oblique
   is never searched.
2. Stage E `MetricScaleResolver.resolve(card:lidar:)`. With both signals, a
   disagreement above `maxCardLidarDisagreement` (0.15) returns the LiDAR-only
   result: the rectangle was not the card. `scaleSource` then says `lidar`.
3. Stage F: if the card was kept, `SegmentationResult.excluding(quad:)` clears
   its quadrilateral to background in the nadir probabilities and labels before
   coverage, growth and volume. The bundle keeps the raw segmenter output
   (`diagnostics.debugNadirSegmentation`), so a harness replay must apply the
   exclusion itself.
4. Every detected rectangle lands on the outcome row as `card {...}` with
   `accepted` and `clearedPixels`; `event=card` on the support-plane log channel
   carries the same in Release builds.

## Gotchas

- Vision finds a "card" on most plates: every `card+lidar` row before 2026-09-25
  with no card in frame is a plate rim or packaging (17–66 % off LiDAR). Read
  `scaleSource=card+lidar` on older rows as "a rectangle was seen", nothing more.
- The segmenter labels a card as food (cheese on 2026-08-11). Without the
  exclusion it is integrated with a solid density.
- Both estimators take the silhouette from the background probability, not the
  label map; clearing labels alone changes nothing.
- The card-only plane fitter (`LiDARSupportPlaneFitter`, no-depth branch) still
  seeds from the card corners plus a constant offset (Req 4.4, open).
