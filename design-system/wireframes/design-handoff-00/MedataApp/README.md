# Medata — SwiftUI Wireframe Scaffold

Static SwiftUI scaffold of the Medata research wireframes (per `specs/research/requirements.md`, v0.2). UI is wired up; pipeline modules are protocol stubs that return canned values so other devs can plug real implementations behind them.

## What's here

```
MedataApp/
  App/
    MedataApp.swift            // @main, root NavigationStack
    AppEnvironment.swift       // dependency container
  Models/
    Meal.swift                 // Meal, FoodClass, Confidence, CapturePath
    MealStore.swift            // protocol + InMemoryMealStore (mock data)
    DesignSystem.swift         // colors, spacing, typography tokens
  Pipeline/
    CaptureService.swift       // protocol; AVFoundation/ARKit lives behind it
    LidarService.swift         // protocol; ARKit sceneDepth lives behind it
    CardDetector.swift         // protocol; ID-1 quad detection
    SupportPlaneDetector.swift // protocol; RANSAC plane fit
    Segmenter.swift            // protocol; CoreML semantic seg
    VolumeEstimator.swift      // protocol; voxel carve / height-field
    DensityDatabase.swift      // protocol; CoFID + IFCDB lookup
    MacroCalculator.swift      // protocol; V·ρ·κ
    ConfidenceCombiner.swift   // protocol; geometric mean of sub-σ
    EstimationPipeline.swift   // orchestrates the 9 stages
  Views/
    Capture/
      CaptureView.swift        // variant B — combined / progressive
      CaptureGuideOverlay.swift
      LidarForkSheet.swift
      CaptureErrorView.swift
    Review/
      SegmentationReviewView.swift
    Result/
      ResultView.swift         // variant A — single-number hero
      ConfidenceChip.swift
      ClassBreakdownRow.swift
    Correction/
      ManualCorrectionView.swift
    History/
      HistoryView.swift
    Settings/
      SettingsView.swift
      AboutView.swift
    Components/
      WireframeStyle.swift     // SF Symbols-friendly modifiers
```

## Run

Open `MedataApp.xcodeproj` in Xcode 16+ targeting iOS 26. Or drop the folder into a new SwiftUI app target. All pipeline calls return mock values via `MockEstimationPipeline`; replace with concrete implementations as work proceeds.

## Notes

- All user-facing strings use Irish/British English per req §19.
- No real camera, ML, or persistence — `Mock*` types front every protocol.
- The single `EstimationPipeline.estimate(_:)` entry point matches the spec's pipeline diagram and is the boundary other devs implement against.
