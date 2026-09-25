# ID-1 card path

The card is the metric-scale reference for phones without LiDAR and a
corroborating signal when LiDAR is present. Spec: `specs/estimation/two-view-trust/`
Req 4; audit of its history in `two-view-geometry-audit.md` §3.

## Flow

1. `Pipeline` stage C runs `cardDetector.detect(in: nadir)` (Vision
   `VNDetectRectanglesRequest`, ID-1 aspect envelope 0.55–0.70, up to 8 ranked
   observations) and `CardPoseSolver.pick`: the first candidate whose P4P
   reprojection residual is within `maxResidualPx` (6 px) is the card. The
   nadir only; the oblique is never searched. Replay off-device with
   `HarnessCLI cards <bundle.fixture>` (macOS Vision, ~15 s per bundle).
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

- Vision's top-ranked rectangle was never the card on the corpus, with or
  without a card in frame (bread, plate phantoms: residual 12–145 px, 25–94 %
  off LiDAR; the real card 2.7 px, 9 %). Read `scaleSource=card+lidar` on rows
  before 2026-09-25 as "a rectangle was seen", nothing more.
- A yellow card at ~35° on pale wood was not among Vision's candidates at all
  on `1786439234576`, even with the aspect band opened; detection recall on
  the card is the next open question for the non-LiDAR path.
- The segmenter labels a card as food (cheese on 2026-08-11). Without the
  exclusion it is integrated with a solid density.
- Both estimators take the silhouette from the background probability, not the
  label map; clearing labels alone changes nothing.
- The card-only plane fitter (`LiDARSupportPlaneFitter`, no-depth branch) still
  seeds from the card corners plus a constant offset (Req 4.4, open).
