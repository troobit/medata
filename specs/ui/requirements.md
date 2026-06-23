# UI — Requirements

**Version:** 1.1
**Date:** 2026-05-29
**Status:** Done (v1.1 — all 60 tasks landed; tab navigation, meal history, settings tab; tracks the Apple "Organize your features" tutorial pattern at <https://developer.apple.com/tutorials/develop-in-swift/organize-your-features>). The 2026-06-20 consistency pass (GAPS Group C) reconciled `design.md`/`tasks.md` with the as-built code: four-tier confidence pill (Decision 17), iOS 26.5 floor (Decision 4 superseded), `CapturePathDecider` behind the deferred `AUTO_CAPTURE_MODE` flag, retention/IFCDB removed, and the `eventsDidChange` / `events`-table persistence shape. Superseded v1.0 task content is retained with inline markers for history.

## Introduction

The MeData iOS app currently ships an algorithmic pipeline (`Pipeline.estimate(_:)`) and placeholder SwiftUI views with no real capture flow. This spec defines the v1 user-facing iPhone experience: a three-tab `TabView` root (Photo → Meals → Settings), a live AR camera preview inside the Photo tab with state indicators and a manual shutter, an immediate result view, a persistent meal-history list in the Meals tab, and the settings + export controls that the persistence layer already supports. The algorithm pipeline and data contracts are implemented per `specs/research/`; this spec consumes them. The tab shell, meal history list, and settings tab can be implemented in parallel with `specs/research/` Phase 1 (device MVP); both delivery slots share the same persistence store — the long-form `events` table (event-log-schema spec), where each meal is one `event_type = meal` row carrying the verbatim `MealRecord` (including `segmenterSource` from research task 82) inside the `metadata` JSON, not a per-field SQL column.

## Out of Scope

- Bundling the Core ML segmenter weights (separate smolspec)
- Cloud sync or multi-device
- Onboarding / tutorial flows beyond the standard iOS permission dialog
- Localisation beyond Irish/British English
- iPad-optimised or Apple Watch layouts (iPhone first)
- User-correction UI — research Req 14.2 persistence support is unchanged; surfacing deferred to a future spec
- Data import (restoring from a previously exported archive) — export remains in scope (§11.4); import is deferred
- Model / inference info panel (segmenter source, model version, palette version) — deferred; the placeholder banner from research Req 23.3 carries the dev-stub provenance for v1
- Debug info panel (compile-flag state, last-error log, LiDAR availability) — deferred; ad-hoc Xcode inspection remains the developer's tool
- Per-class carb breakdown on the result view — v1 displays meal total only (research Req 12.4)
- Clinical macros (energy/protein/fat/fibre) on any user-facing view (research Req 12.6)
- Accessibility / VoiceOver work (labels, announcements, focus order) — deferred to a future spec; research spec carries no accessibility requirement and adding it during MVP would inflate scope without a forcing reason. See `decision_log.md` Decision 10.

## Requirements

### 1. Capture-flow main view

**User Story:** As a user, I want a live camera view with the indicators I need to take a usable photo, so that I know when conditions are right to capture.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN the app launches, THEN the Photo tab SHALL be the selected tab (per [18.2](#18.2)) and SHALL present a capture view containing a live AR camera feed, the indicators specified in §2–§4, and the shutter specified in §7.  
2. <a name="1.2"></a>WHEN the user backgrounds the app or switches to a different tab, THEN the capture view SHALL release the AR session within 200 ms (consistent with research Req 2.5).  
3. <a name="1.3"></a>WHEN camera permission has been denied, THEN the capture view SHALL display the localised refusal message and a control that opens the app's iOS Settings entry instead of the live preview. The tab bar SHALL remain visible so the user can navigate to other tabs.
4. <a name="1.4"></a>No onboarding or tutorial screen SHALL precede the tab shell on launch.  
5. <a name="1.5"></a>The app SHALL support portrait orientation only.  
6. <a name="1.6"></a>WHEN the AR session has started but `ARSession` has not yet reported a "normal" tracking state, THEN the capture view SHALL display an "Initialising" indicator and SHALL disable the shutter until tracking becomes normal.
7. <a name="1.7"></a>WHEN the user switches away from the Photo tab while the capture view is in any state other than `.estimating`, THEN the capture view SHALL release the AR session and SHALL reset to `.initialising` on re-entry. WHEN the user switches away during `.estimating`, THEN the estimation SHALL continue to completion in the background and the result view SHALL be shown on the next return to the Photo tab.  

### 2. Tilt indicator

**User Story:** As a user, I want to see how much my camera tilt will reduce my estimate's accuracy, so that I can decide whether to steady the device or accept the trade-off and capture now.

**Acceptance Criteria:**

1. <a name="2.1"></a>The capture view SHALL display the current per-stage angular error Δθ in degrees AND the live σ_tilt = cos(Δθ) value as a percentage, updated at the rate `CaptureFlowDelegate.didUpdateTilt(angleDegrees:)` publishes. The values are informational only — the shutter (§7) is no longer gated on tilt (research Req 3.2 / Decision 43; UI `decision_log.md` Decision 19).
2. <a name="2.2"></a>The tilt readout SHALL NOT use a binary in-range / out-of-range visual treatment. Per UI `decision_log.md` Decision 19 the indicator SHALL be a continuous greyscale readout; the prior ±5° colour-coded state is superseded.
3. <a name="2.3"></a>WHEN the active capture stage targets oblique AND |measured − 25°| > 30° (research Req 3.3), the capture view SHALL surface a "tilt closer to 25°" inline message and SHALL block the shutter for that stage only. This is the only tilt-driven shutter gate that remains.

### 3. Working-distance gate

**User Story:** As a user, I want the app to stop me from capturing when I'm too close or too far, so that the depth pipeline can do its job.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHERE LiDAR is available on the device, the system SHALL compute the camera-to-food distance from `ARFrame.sceneDepth` and SHALL disable the shutter when measured distance is outside 25–50 cm (research Req 3.4).  
2. <a name="3.2"></a>WHERE LiDAR is unavailable, the capture view SHALL display a static 30–40 cm guidance hint and SHALL NOT gate the shutter on distance.  
3. <a name="3.3"></a>The capture view SHALL surface which gating mode is active (measured vs guidance) so the user understands why the shutter is or isn't enabled.  

### 4. Capture-mode toggle (persistent, user-selected)

**User Story:** As a user, I want a persistent toggle on the capture view to choose between single-photo (LiDAR) and double-photo (with reference card) capture, so I'm not surprised by a floating modal mid-session and the chosen mode survives across launches.

**Acceptance Criteria:**

1. <a name="4.1"></a>The capture view SHALL display a persistent segmented control with exactly two options, `Single` and `Double`, bound to `SettingsKeys.captureMode` in `UserDefaults`. The default for a fresh install SHALL be `Double`. The chosen mode SHALL persist across app launches (research Decision 35).
2. <a name="4.2"></a>WHEN the device does not support LiDAR, THEN the `Single` segment SHALL be disabled (greyed) and a single-line hint SHALL state that Single mode requires a LiDAR-equipped iPhone. Tapping the disabled segment SHALL NOT change the mode.
3. <a name="4.3"></a>WHEN the user taps the shutter, THEN the active `CaptureMode` SHALL be passed to `Pipeline.estimate(_:mode:)` and `MealRecord.capturePath` SHALL be `single_view_lidar` for `Single`, `two_view_sfs` for `Double`.
4. <a name="4.4"></a>WHILE `Pipeline.estimate(_:mode:)` is in flight (§8), the segmented control SHALL be visually disabled and SHALL ignore taps. Mode switches SHALL only take effect for the next capture, never mid-pipeline.
5. <a name="4.5"></a>The previously-specified floating capture-path hint and the inline "force two-view" control SHALL NOT be displayed. The mode toggle is the single source of truth.

### 5. Two-view capture sequence

**User Story:** As a user, I want a clear two-step prompt when two views are needed, so that I don't take the same shot twice.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN the active `CaptureMode` is `Double` (resulting in `two_view_sfs`), THEN the system SHALL prompt the user for the nadir view first, then the oblique view.
2. <a name="5.2"></a>Each view's prompt SHALL show a single-line instruction in Irish-English (e.g. "Top-down view", "Angled view").  
3. <a name="5.3"></a>The capture stage SHALL advance to the next view (or to estimation) only after a successful capture completes; no auto-advance from a non-captured state.  
4. <a name="5.4"></a>WHEN the user has captured the first view AND a refusal subsequently occurs at the second view, THEN the system SHALL allow the user to retry the second view without retaking the first.  
5. <a name="5.5"></a>IF world-tracking confidence falls below the platform-defined "normal" threshold between the two views, THEN the system SHALL discard the second view and prompt the user to retake it (research Req 3.7).  
6. <a name="5.6"></a>IF world-tracking confidence falls below "normal" during or immediately after the first view's capture (before estimation begins), THEN the system SHALL discard the first view and prompt the user to retake from the beginning.  

### 6. ID-1 card guidance

**User Story:** As a user, when the app needs a card for metric scale I want a clear reminder to include one, so that the capture doesn't get refused.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN the active `CaptureMode` (§4.1) is `Double`, THEN the capture view SHALL display a single-line reminder to include an ID-1 reference card flat in the scene (research Req 4.3, 5).
2. <a name="6.2"></a>WHEN the active `CaptureMode` (§4.1) is `Single`, THEN the card reminder SHALL NOT be shown.

### 7. Shutter button

**User Story:** As a user, I want a single obvious button to capture the photo, so that there's no doubt about what triggers the capture.

**Acceptance Criteria:**

1. <a name="7.1"></a>The capture view SHALL contain exactly one shutter control whose primary action triggers a frame capture for the current stage.  
2. <a name="7.2"></a>The shutter SHALL be enabled when the working-distance gate is satisfied (§3) AND no estimation is in flight (§8) AND ARSession tracking is normal AND the oblique-stage hard cap from §2.3 is satisfied (when applicable). Tilt no longer affects shutter arming (research Req 3.2 / Decision 43; UI `decision_log.md` Decision 18).
3. <a name="7.3"></a>WHEN the shutter is disabled, THEN its visual state SHALL communicate disablement without surfacing a separate error message.  
4. <a name="7.4"></a>The shutter SHALL ignore any subsequent tap until the in-progress capture's outcome is observable (next-view prompt, busy state, or refusal banner). No frame SHALL be captured twice from a rapid double-tap.  

### 8. Estimation in flight

**User Story:** As a user, I want to know the app is working after I tap the shutter, so that I don't tap again or assume it crashed.

**Acceptance Criteria:**

1. <a name="8.1"></a>WHEN `Pipeline.estimate(_:)` is in flight, THEN the capture view SHALL display a busy state that visually disables further input and the shutter.  
2. <a name="8.2"></a>The busy state SHALL be cleared only by `Pipeline.estimate(_:)` completing (success → §9 result view) or failing (§10 refusal banner).  
3. <a name="8.3"></a>IF the app is backgrounded while `Pipeline.estimate(_:)` is in flight, THEN on foregrounding the system SHALL discard any partial in-flight estimation and return the user to a fresh capture view with no banner. No persisted partial `MealRecord` SHALL be written from a cancelled estimation. **Known limitation (best-effort enforcement):** `MedataCore`'s `Pipeline` does not currently implement cooperative cancellation; an in-flight `estimate(_:)` will run to completion regardless of `Task.cancel()`, including the persistence INSERT. Until a sibling spec adds `Task.checkCancellation()` checkpoints inside `Pipeline.swift`, this AC is satisfied for the *UI state* (the user sees a fresh capture view) but the cancelled meal may still appear in the persisted store. Tracked in `decision_log.md` Decision 12.  

### 9. Result view

**User Story:** As a user, I want to see the carb estimate and how confident the app is, so that I can decide whether to trust it.

**Acceptance Criteria:**

1. <a name="9.1"></a>WHEN `Pipeline.estimate(_:)` completes successfully, THEN the system SHALL navigate to a result view showing the total meal carbohydrates in grams rounded to 1 g (research Req 12.4).  
2. <a name="9.2"></a>The result view SHALL display the meal's `σ_meal` confidence as a labelled pill with four discrete states: "High" (σ ≥ 0.75), "Moderate" (0.50 ≤ σ < 0.75), "Low" (0.20 ≤ σ < 0.50), "Very Low" (σ < 0.20). The 0.20 boundary aligns with the revised research Req 13.5 threshold (research Decision 43); the other boundaries are documented in UI `decision_log.md` Decision 17 (supersedes Decision 8).
3. <a name="9.3"></a>WHEN `σ_meal < 0.20`, THEN the result view SHALL display an inline explanation that the estimate may be wrong by orders of magnitude AND SHALL surface the per-stage angular error Δθ that contributed to the low confidence, alongside a "Retake" control and a "Keep as-is" control (research Req 13.5; the "manually correct" branch is out of scope per the Non-Goals section).
4. <a name="9.4"></a>The result view SHALL provide a control that returns the user to a fresh capture view, ready to capture a new meal.  
5. <a name="9.5"></a>The result view SHALL NOT display per-class breakdown, clinical macros (energy, protein, fat, fibre), or any persistence-layer fields beyond the carb total and confidence pill.  

### 10. Refusal handling

**User Story:** As a user, when capture fails I want to know why and try again without restarting, so that I can correct what I did wrong.

**Acceptance Criteria:**

1. <a name="10.1"></a>WHEN `Pipeline.estimate(_:)` throws an `EstimationFailure`, THEN the capture view SHALL display the case's `localisedMessage` as an inline banner.  
2. <a name="10.2"></a>The refusal banner SHALL provide a control that re-arms the shutter at the same capture stage (nadir or oblique) and dismisses the banner.  
3. <a name="10.3"></a>The AR session SHALL remain live while the refusal banner is displayed; the user SHALL NOT be required to leave and re-enter the capture view to retry.  

### 11. Settings

**User Story:** As a user, I want a Settings tab to see which macro databases the app uses and to export my data, so that I have control over my dataset.

**Acceptance Criteria:**

1. <a name="11.1"></a>The app SHALL expose a Settings tab as the rightmost tab in the tab bar (per [18.1](#18.1)). The previous navigation-control entry point from the capture view SHALL be removed.
2. <a name="11.2"></a>The Settings view SHALL contain a read-only "Macros" row stating which macronutrient databases are bundled (e.g. "CoFID 2024 + AFCD 2024", per research Req 11.1). No retention picker SHALL be shown (research Req 17.3, May 2026: retention removed).
3. <a name="11.3"></a>The previous IFCDB-overlay toggle SHALL NOT be present. The Settings view SHALL NOT expose any food-database toggle (research Decision 39, May 2026).
4. <a name="11.4"></a>The Settings view SHALL contain an "Export archive" control that invokes the persistence-layer archive export (research Req 15.8) and presents the produced file via the standard iOS share sheet. The archive SHALL reference photos by `PHAsset.localIdentifier`, not embed image bytes (research Req 17.3).
5. <a name="11.5"></a>The Settings view SHALL NOT expose data import, model/inference info, or debug info controls in v1 (per Out of Scope above).

### 12. Localisation

**User Story:** As an Irish-English user, I want every visible string to read in my dialect, so that the app feels like it was made for me.

**Acceptance Criteria:**

1. <a name="12.1"></a>Every user-facing string the app shows SHALL be Irish/British English per research Req 19.1 (e.g. "colour", "centre", "recognise", "favourite").  
2. <a name="12.2"></a>WHERE a user-facing string originates from an `EstimationFailure.localisedMessage`, the app SHALL surface that string verbatim without rewording.  

### 13. Permissions

**User Story:** As a user, I want permission prompts to appear naturally as features are first used, so that I'm not surprised.

**Acceptance Criteria:**

1. <a name="13.1"></a>WHEN the app first starts the AR session, THEN the system SHALL trigger the standard iOS camera permission dialog backed by the `NSCameraUsageDescription` Info.plist string.  
2. <a name="13.2"></a>WHEN the app first accesses Core Motion (for the tilt indicator), THEN the system SHALL trigger the standard iOS motion permission dialog backed by `NSMotionUsageDescription`.  
3. <a name="13.3"></a>WHEN either permission is denied, THEN the capture view SHALL display the §1.3 refusal message + Settings deep-link instead of the live preview.  

### 14. Responsiveness

**User Story:** As a user, I want the UI to never freeze while the pipeline is doing heavy work, so that the app feels responsive.

**Acceptance Criteria:**

1. <a name="14.1"></a>WHILE a `Pipeline.estimate(_:)` call is in flight on the single-view-LiDAR path, the camera-preview frame rate SHALL stay at or above 30 fps measured on the iPhone 13 Pro test device.  
2. <a name="14.2"></a>The capture view SHALL maintain a camera-preview frame rate of at least 30 fps on the iPhone 13 Pro test device while no estimation is in flight.  
3. <a name="14.3"></a>The shutter tap-to-busy-state-visible latency SHALL be under 100 ms on the iPhone 13 Pro test device.  

(The 30 fps and 100 ms figures are this spec's UI-responsiveness floors; they are independent of and complementary to research Req 16.1 / 16.7 which constrain the pipeline's end-to-end wall-clock budget. Rationale in `decision_log.md` Decision 8.)

### 15. Branding

**User Story:** As a user, I want the iOS app to look like the same product as the rest of the MeData brand, so that the experience feels consistent.

**Acceptance Criteria:**

1. <a name="15.1"></a>The app's accent colour, used at minimum for the shutter active state, the result-view confidence pill in the "High" state (§9.2), and selected toggles in Settings (§11), SHALL be `#63ff00`.  
2. <a name="15.2"></a>The app SHALL ship an `AppIcon` whose visual identity is derived from the same vector source as the existing favicons in `static/` on the repo's `main` branch (specifically `static/icon.svg`). The visual identity SHALL match the existing favicon mark — no new logo is introduced by this spec.  

(Note: the *mechanics* of porting assets from `main`, generating PNG renditions, and configuring `Assets.xcassets` are implementation tasks captured in `tasks.md`, not user-facing requirements.)

### 16. System interruptions and lifecycle

**User Story:** As a user, I want the app to handle phone calls, lock-screen, low-power state, and rotation gracefully, so that I don't lose my capture or end up in a broken state.

**Acceptance Criteria:**

1. <a name="16.1"></a>WHEN the user receives a phone call, the screen locks, or the system otherwise interrupts the AR session, THEN the capture view SHALL release the AR session and SHALL re-acquire it on the user's next foreground entry without requiring an app restart.  
2. <a name="16.2"></a>WHEN the device is rotated away from portrait while the capture view is visible, the system SHALL keep the layout locked to portrait (per §1.5); no requirement is made for landscape rendering.  
3. <a name="16.3"></a>WHEN iOS reports a low-power state, the capture view SHALL continue to function at the §14.2 frame-rate floor; no automatic degradation of preview or pipeline behaviour is introduced by this spec.  

### 17. Privacy and on-device guarantees

**User Story:** As a user with sensitive food and health data, I want certainty that my captures don't leave my phone, so that I can trust the app.

**Acceptance Criteria:**

1. <a name="17.1"></a>The app SHALL NOT transmit any captured frame, depth map, segmentation mask, or `MealRecord` field to any network endpoint (research Req 17.2). This is enforced by the absence of any network-bound module rather than by a runtime guard.  
2. <a name="17.2"></a>The archive export from §11.4 SHALL include only the user's persisted meals (the `meals.sqlite` file and per-meal artefact directories produced by the persistence layer) and SHALL NOT include device identifiers, IP addresses, user account information, or any telemetry-style fields not already present in `MealRecord`.

### 18. Tab navigation shell

**User Story:** As a user, I want a tab bar at the bottom of the screen so that I can move between capturing a meal, reviewing past meals, and managing settings without losing context, following Apple's standard navigation pattern.

**Acceptance Criteria:**

1. <a name="18.1"></a>The root view of the application SHALL be a SwiftUI `TabView` containing exactly three tabs, in this order: Photo (§1), Meals (§19), Settings (§11). The tab order SHALL NOT be user-configurable in v1.
2. <a name="18.2"></a>The Photo tab SHALL be the selected tab on cold launch. On warm launch (the app returning from the background), the previously selected tab SHALL be restored.
3. <a name="18.3"></a>Each tab SHALL be labelled with a SF Symbol and an Irish-English label: Photo = `camera.fill` + "Photo"; Meals = `fork.knife` + "Meals"; Settings = `gearshape.fill` + "Settings".
4. <a name="18.4"></a>The tab bar SHALL use the system-default Liquid Glass material on iOS 26.5. No custom tab-bar background SHALL be applied; the app SHALL NOT call `toolbarBackground()` or set a tab-bar appearance proxy.
5. <a name="18.5"></a>WHEN the user taps a tab while it is already the selected tab, THEN the tab's navigation stack SHALL pop to root (the standard iOS behaviour) and the tab's state SHALL otherwise be preserved.
6. <a name="18.6"></a>The selected-tab state SHALL persist across app cold/warm launches via `@AppStorage("selectedTab")` in `App/AppRoot.swift` (or the equivalent owner of the `TabView`). The default value SHALL be the Photo tab.
7. <a name="18.7"></a>Tab switching SHALL NOT cancel an in-flight `Pipeline.estimate(_:mode:)` call (per [1.7](#1.7)); the estimation SHALL run to completion and the result SHALL be presented on the next return to the Photo tab.

### 19. Meals tab

**User Story:** As a user, I want to see a list of the meals I've captured and tap one to see the result view I saw at the time, so that I can review prior estimates without leaving the app.

**Acceptance Criteria:**

1. <a name="19.1"></a>The Meals tab SHALL display a list of all `MealRecord`s currently persisted in `meals.sqlite`, sorted by `capturedAt` descending (newest first). The list SHALL be wrapped in its own `NavigationStack` per the platform navigation rules (one stack per tab).
2. <a name="19.2"></a>Each list row SHALL show: the captured-at timestamp formatted as `dd MMM yyyy, HH:mm` (Irish/British locale), the meal-level carbohydrate total to the nearest 1 g (per research Req 12.4), the meal's confidence pill in the same three-tier styling as the result view (§9.2), and a thumbnail of the captured photo where one is available (resolved via `PHImageManager.requestImage(for:)` using `MealRecord.photoAssetID`).
3. <a name="19.3"></a>WHEN `MealRecord.segmenterSource == "dev_stub"`, THEN the list row SHALL display a small yellow "Placeholder" chip next to the carb value, matching the meaning of the result-view placeholder banner from research Req 23.3. The chip SHALL be present even when the current build is a Phase 3 build (the chip reads from the persisted field, not the build flag).
4. <a name="19.4"></a>WHEN the user taps a row, THEN the system SHALL push a meal-detail view onto the Meals tab's navigation stack. The detail view SHALL reuse `ResultView` and SHALL display the same content the user saw immediately after the original capture (confidence pill, carbohydrate total, photo thumbnail, placeholder banner where applicable).
5. <a name="19.5"></a>WHEN no meals have been captured yet, THEN the list SHALL display an Irish-English empty-state message ("No meals yet. Tap the Photo tab to capture your first meal.") and a `fork.knife` SF Symbol; no placeholder rows SHALL be shown.
6. <a name="19.6"></a>WHEN a new meal is persisted by the Photo tab while the user is on the Meals tab, THEN the list SHALL update to show the new row within 500 ms without the user needing to refresh.
7. <a name="19.7"></a>The list SHALL support `swipeActions(edge: .trailing)` providing a single "Delete" action per row. WHEN the user confirms a delete, THEN the corresponding `MealRecord` SHALL be removed from `meals.sqlite` and its on-disk mask / depth artefacts SHALL be removed from the per-meal artefact directory. The associated `PHAsset` in the user's Photos library SHALL NOT be deleted; the user manages their Photos library separately (research Req 17.3).
8. <a name="19.8"></a>The Meals tab SHALL NOT expose: per-class carbohydrate breakdowns, per-meal note editing, user-correction entry, search, filtering, multi-select, or bulk export. These are deferred to a future spec.

### 20. Visual design — clean capture aesthetic

**User Story:** As a user, I want a clean, professional capture screen where only the photograph and the carbohydrate value compete for my attention, so that the chrome never gets in the way of seeing what I'm photographing.

**Acceptance Criteria:**

1. <a name="20.1"></a>The visual design SHALL be specified in `design-system/MASTER.md` plus page-specific overrides in `design-system/pages/<page>.md`. The implementation SHALL consume those tokens (colour, type, spacing, motion) verbatim and SHALL NOT introduce parallel values inline in views.
2. <a name="20.2"></a>The Photo tab and ResultView SHALL use a pure-black (`#000000`) full-bleed background (`captureBackground` token); the AR preview is the content and chrome SHALL NOT compete with it.
3. <a name="20.3"></a>All Photo-tab chrome (close button, flash toggle, indicator badge, capture-mode pill, shutter) SHALL be flat — no drop shadows, no gradients other than the result-view scrim, no glassmorphism over the AR feed.
4. <a name="20.4"></a>The Photo tab's live indicators (tilt, distance, LiDAR coverage) SHALL be consolidated into a single chip per `design-system/pages/photo-tab.md` — NOT scattered across three corners. The chip SHALL auto-hide after 5 s of `.ready` state with σ_tilt > 0.95 (≈Δθ < 18°) AND all other indicators in-range, and SHALL re-show on tap or whenever any indicator leaves its preferred range. The tilt sub-element of the chip SHALL render the continuous Δθ + σ_tilt% readout from §2.1 in greyscale, NOT a binary green/red treatment (UI `decision_log.md` Decision 19).
5. <a name="20.5"></a>The capture-mode toggle (Req §4) SHALL be rendered as a capsule pill above the shutter (active label inside an inner accent pill that slides between positions), NOT as the v1.0 segmented control. The previous segmented-control spec is superseded.
6. <a name="20.6"></a>The shutter button SHALL be 76pt diameter (white ring + inner white circle), centred horizontally, ≥24pt above the tab bar top edge. Press feedback SHALL be a 100ms inner-circle shrink + 150ms spring restoration; the visible shutter SHALL never shift the layout of surrounding chrome.
7. <a name="20.7"></a>The refusal surface SHALL be a bottom sheet (`.presentationDetents([.fraction(0.35)])`) with a single primary CTA, NOT a top banner. The v1.0 `RefusalBanner` overlay is superseded.
8. <a name="20.8"></a>The ResultView SHALL render the carbohydrate total at the `display` type-scale (72pt heavy monospaced) centred over a dimmed full-bleed photo background, with the confidence pill immediately below and (where applicable) the placeholder chip from research Req §23.3 as a small pill — NOT a full-width yellow banner.
9. <a name="20.9"></a>The Meals tab SHALL render rows photo-led: full-width 4:3 photo (rounded 14pt) with carb total + confidence pill + optional placeholder chip + timestamp as a caption below the photo, with 24pt between rows. A 3-column thumbnail grid SHALL NOT be used (per `design-system/pages/meals-tab.md` rationale).
10. <a name="20.10"></a>All interactive controls SHALL meet a ≥48pt touch target (use `hitSlop` when the visual size is smaller). Press feedback SHALL appear within 100ms of touch-down. These rules SHALL apply uniformly across the tab bar, the shutter, indicator chips, capture-mode pill, list rows, and toolbar buttons.
11. <a name="20.11"></a>The implementation SHALL respect `accessibilityReduceMotion`: spring animations SHALL be replaced by a single crossfade; the carb-total `contentTransition(.numericText())` SHALL fall back to a snap-in.
12. <a name="20.12"></a>The implementation SHALL respect Dynamic Type up to size `AX5`; the carb total's `display` style SHALL clamp at 88pt to prevent the value running off-screen.  
