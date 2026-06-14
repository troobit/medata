# No Food Pixels Refusal On Fruit Plate Double-Mode Capture

## Overview

On 2026-06-14, iPhone 13 Pro Max iOS 26.5 (Debug-iphoneos build off `research` @ fdeab9d), the `shutter-blocked-feedback` task-5 verification run produced an unexpected outcome: a double-mode capture of a fruit plate completed both nadir and oblique frames successfully, but estimation refused with `failure=noFoodPixels` and `estimate.start` reported `maskAgeMs=-1`. The diagnostic added by `shutter-blocked-feedback` correctly surfaced the failure mode — this bug captures the trail so the failure can be fixed in its own scope.

## Observed log trail

```
event=fired state=ready tiltDegrees=4.6 targetTilt=0 tiltInRange=true distanceCm=39.5 lidarCoveragePercent=90.3 supportsLiDAR=true canShutter=true flowTaskActive=false startTaskActive=true mode=double stage=nadir
event=capture.start stage=nadir
event=capture.end stage=nadir success=true width=1920 height=1440
event=fired state=ready tiltDegrees=3.5 targetTilt=25 tiltInRange=false distanceCm=39.9 lidarCoveragePercent=88.7 supportsLiDAR=true canShutter=true flowTaskActive=true startTaskActive=true mode=double stage=oblique
event=capture.start stage=oblique
event=capture.end stage=oblique success=true width=1920 height=1440
event=estimate.start capturePath=two_view_sfs
event=estimate.start maskAgeMs=-1
event=pipeline.stage.start name=CardDetection
event=carddetect.end success=false cornerCount=0 latencyMs=29
event=pipeline.stage.start name=SupportPlane
event=supportplane.start width=1920 height=1440 source=pre_shutter
event=estimate.end success=false failure=noFoodPixels
```

## Expected vs observed

- Expected: `event=estimate.end success=true` and navigation to `ResultView`.
- Observed: `event=estimate.end success=false failure=noFoodPixels`, preceded by `event=estimate.start maskAgeMs=-1` despite pre-shutter `segmenter.substage.*` events firing for both captured frames.

## Suspected scope

Pre-shutter segmenter mask is not arriving at estimation: `maskAgeMs=-1` is the sentinel for "no mask attached," which would force the segmentation-derived food-pixel count to zero regardless of scene content. Triage should start at the boundary between `PreShutterSegmenter` output and the `RawFrame` / `EstimationInput` handed into the pipeline.

## Out of scope

Fixing this bug. This file is a capture-and-handoff note; the fix belongs in its own commit.
