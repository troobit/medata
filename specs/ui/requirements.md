# UI — Requirements

**Version:** 1.0
**Date:** 2026-05-20
**Status:** Draft

## Introduction

The MeData iOS app currently ships an algorithmic pipeline (`Pipeline.estimate(_:)`) and placeholder SwiftUI views with no real capture flow. This spec defines the v1 user-facing capture experience: a live AR camera preview with state indicators, a manual shutter, an immediate result view, and the settings + export controls that the persistence layer already supports. The algorithm pipeline and data contracts are implemented per `specs/research/`; this spec consumes them.

## Out of Scope

- Bundling the Core ML segmenter weights (separate smolspec)
- Cloud sync or multi-device
- Onboarding / tutorial flows beyond the standard iOS permission dialog
- Localisation beyond Irish/British English
- iPad-optimised or Apple Watch layouts (iPhone first)
- User-correction UI — research Req 14.2 persistence support is unchanged; surfacing deferred to a future spec
- Persistent meal-history list / browsing — v1 ends at the post-capture result view; archive export is the only persistent egress
- Liquid Glass / iOS 26-specific styling — UI targets iOS 17 baseline; iOS 26 refinements deferred
- Per-class carb breakdown on the result view — v1 displays meal total only (research Req 12.4)
- Clinical macros (energy/protein/fat/fibre) on any user-facing view (research Req 12.6)
- Accessibility / VoiceOver work (labels, announcements, focus order) — deferred to a future spec; research spec carries no accessibility requirement and adding it during MVP would inflate scope without a forcing reason. See `decision_log.md` Decision 10.

## Requirements

### 1. Capture-flow main view

**User Story:** As a user, I want a live camera view with the indicators I need to take a usable photo, so that I know when conditions are right to capture.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN the app launches, THEN the system SHALL present a capture view containing a live AR camera feed, the indicators specified in §2–§4, and the shutter specified in §7.  
2. <a name="1.2"></a>WHEN the user backgrounds the app or navigates away from the capture view, THEN the system SHALL release the AR session within 200 ms (consistent with research Req 2.5).  
3. <a name="1.3"></a>WHEN camera permission has been denied, THEN the capture view SHALL display the localised refusal message and a control that opens the app's iOS Settings entry instead of the live preview.  
4. <a name="1.4"></a>The capture view SHALL be the app's first screen on launch; no onboarding or tutorial screen precedes it.  
5. <a name="1.5"></a>The app SHALL support portrait orientation only.  
6. <a name="1.6"></a>WHEN the AR session has started but `ARSession` has not yet reported a "normal" tracking state, THEN the capture view SHALL display an "Initialising" indicator and SHALL disable the shutter until tracking becomes normal.  

### 2. Tilt indicator

**User Story:** As a user, I want to know how level the camera is, so that I can hold it correctly before tapping the shutter.

**Acceptance Criteria:**

1. <a name="2.1"></a>The capture view SHALL display the current tilt angle in degrees, updated at the rate `CaptureFlowDelegate.didUpdateTilt(angleDegrees:)` publishes.  
2. <a name="2.2"></a>WHEN the active capture stage targets nadir AND the device tilt is within ±5° of vertical (research Req 3.2), THEN the indicator SHALL render in an in-range state visually distinct from the out-of-range state.  
3. <a name="2.3"></a>WHEN the active capture stage targets oblique AND the device tilt is within ±5° of 25° from vertical (research Req 3.3), THEN the indicator SHALL render in the in-range state.  
4. <a name="2.4"></a>The shutter (§7) SHALL be disabled while the tilt indicator is out of range.  

### 3. Working-distance gate

**User Story:** As a user, I want the app to stop me from capturing when I'm too close or too far, so that the depth pipeline can do its job.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHERE LiDAR is available on the device, the system SHALL compute the camera-to-food distance from `ARFrame.sceneDepth` and SHALL disable the shutter when measured distance is outside 25–50 cm (research Req 3.4).  
2. <a name="3.2"></a>WHERE LiDAR is unavailable, the capture view SHALL display a static 30–40 cm guidance hint and SHALL NOT gate the shutter on distance.  
3. <a name="3.3"></a>The capture view SHALL surface which gating mode is active (measured vs guidance) so the user understands why the shutter is or isn't enabled.  

### 4. Capture-path indicator

**User Story:** As a user, I want to see whether the app is using its faster LiDAR shortcut or its two-view path, so that I understand what's being asked of me.

**Acceptance Criteria:**

1. <a name="4.1"></a>The capture view SHALL display a capture-path hint with one of two values — `single_view_lidar` or `two_view_sfs` — computed before each capture from (a) the device's LiDAR-supported state and (b) the latest LiDAR coverage observed from the live AR frame stream. The path hint SHALL show `single_view_lidar` only when the device supports LiDAR and the latest observed coverage is ≥ 80% (research Req 3.5).  
2. <a name="4.2"></a>WHEN the path hint is `single_view_lidar`, THEN the capture view SHALL display a control that forces the next capture onto the two-view path regardless of LiDAR coverage (research Req 3.5).  
3. <a name="4.3"></a>WHEN `Pipeline.estimate(_:)` completes successfully, THEN the system SHALL treat `MealRecord.capturePath` as the authoritative path actually used and SHALL pass it to the result view (§9).  

### 5. Two-view capture sequence

**User Story:** As a user, I want a clear two-step prompt when two views are needed, so that I don't take the same shot twice.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN the active capture path is `two_view_sfs`, THEN the system SHALL prompt the user for the nadir view first, then the oblique view.  
2. <a name="5.2"></a>Each view's prompt SHALL show a single-line instruction in Irish-English (e.g. "Top-down view", "Angled view").  
3. <a name="5.3"></a>The capture stage SHALL advance to the next view (or to estimation) only after a successful capture completes; no auto-advance from a non-captured state.  
4. <a name="5.4"></a>WHEN the user has captured the first view AND a refusal subsequently occurs at the second view, THEN the system SHALL allow the user to retry the second view without retaking the first.  
5. <a name="5.5"></a>IF world-tracking confidence falls below the platform-defined "normal" threshold between the two views, THEN the system SHALL discard the second view and prompt the user to retake it (research Req 3.7).  
6. <a name="5.6"></a>IF world-tracking confidence falls below "normal" during or immediately after the first view's capture (before estimation begins), THEN the system SHALL discard the first view and prompt the user to retake from the beginning.  

### 6. ID-1 card guidance

**User Story:** As a user, when the app needs a card for metric scale I want a clear reminder to include one, so that the capture doesn't get refused.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN the capture-path hint from §4.1 is `two_view_sfs`, THEN the capture view SHALL display a single-line reminder to include an ID-1 reference card flat in the scene. This covers both non-LiDAR devices and LiDAR devices whose current LiDAR coverage falls below the §4.1 threshold (research Req 4.3, 5).  
2. <a name="6.2"></a>WHEN the capture-path hint from §4.1 is `single_view_lidar`, THEN the card reminder SHALL NOT be shown.  

### 7. Shutter button

**User Story:** As a user, I want a single obvious button to capture the photo, so that there's no doubt about what triggers the capture.

**Acceptance Criteria:**

1. <a name="7.1"></a>The capture view SHALL contain exactly one shutter control whose primary action triggers a frame capture for the current stage.  
2. <a name="7.2"></a>The shutter SHALL be enabled only when the tilt indicator is in range (§2) AND the working-distance gate is satisfied (§3) AND no estimation is in flight (§8).  
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
2. <a name="9.2"></a>The result view SHALL display the meal's `σ_meal` confidence as a labelled pill with three discrete states: "High" (σ ≥ 0.75), "Moderate" (0.60 ≤ σ < 0.75), "Low" (σ < 0.60). The 0.60 boundary aligns with research Req 13.5's uncertain-estimate threshold; the 0.75 boundary is documented in `decision_log.md` Decision 8.  
3. <a name="9.3"></a>WHEN `σ_meal < 0.60`, THEN the result view SHALL display an uncertain-estimate prompt offering the user a control to retake the photograph (research Req 13.5; the "manually correct" branch of Req 13.5 is out of scope per the Non-Goals section).  
4. <a name="9.4"></a>The result view SHALL provide a control that returns the user to a fresh capture view, ready to capture a new meal.  
5. <a name="9.5"></a>The result view SHALL NOT display per-class breakdown, clinical macros (energy, protein, fat, fibre), or any persistence-layer fields beyond the carb total and confidence pill.  

### 10. Refusal handling

**User Story:** As a user, when capture fails I want to know why and try again without restarting, so that I can correct what I did wrong.

**Acceptance Criteria:**

1. <a name="10.1"></a>WHEN `Pipeline.estimate(_:)` throws an `EstimationFailure`, THEN the capture view SHALL display the case's `localisedMessage` as an inline banner.  
2. <a name="10.2"></a>The refusal banner SHALL provide a control that re-arms the shutter at the same capture stage (nadir or oblique) and dismisses the banner.  
3. <a name="10.3"></a>The AR session SHALL remain live while the refusal banner is displayed; the user SHALL NOT be required to leave and re-enter the capture view to retry.  

### 11. Settings

**User Story:** As a user, I want a settings screen to choose how long meals are kept and to export my data, so that I have control over local storage.

**Acceptance Criteria:**

1. <a name="11.1"></a>The app SHALL expose a Settings view reachable from the capture view via a single navigation control.  
2. <a name="11.2"></a>The Settings view SHALL contain a retention-period picker with the values 30 / 90 / 365 days and Indefinite (research Req 17.4), bound to `SettingsKeys.retentionDays`.  
3. <a name="11.3"></a>The Settings view SHALL contain an IFCDB-overlay toggle bound to `SettingsKeys.ifcdbOverlayEnabled`; a change SHALL take effect on the next app launch (research Req 11.3).  
4. <a name="11.4"></a>The Settings view SHALL contain an "Export archive" control that invokes the persistence-layer archive export (research Req 15.8) and presents the produced file via the standard iOS share sheet.  

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
