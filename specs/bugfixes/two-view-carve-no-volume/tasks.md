# Two-View Carve No Volume

## Verification

- [ ] 1. STOP — on-device verification of a well-aimed two-view trail
  - Human-gated device pass on the iPhone 16 Pro; no agent may attempt it. The carve was exonerated — the root cause was a mis-aimed oblique because the tilt aim guide was unwired; TiltBubbleGuide has since been wired into CaptureFlowView (commits 96465d1 and 9f64576)
  - Capture a two-view trail with the oblique aimed inside the 10-40 degree band using the on-screen guide; confirm it reaches event=estimate.end success=true and persists a meal rather than refusing noFoodVolumeRecovered
  - Match the launch buildStamp before trusting any device output
  - Report status: the report.md header stays Open until this passes
