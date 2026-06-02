# Decision Log: Clean Build Baseline

## Decision 1: Drop iPad support; ship iPhone-only

**Date**: 2026-06-02
**Status**: accepted

### Context

The validator emits the warning "All interface orientations must be supported unless the app requires full screen" because `TARGETED_DEVICE_FAMILY = "1,2"` declares iPad support while `INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad` lists only portrait orientations. The same universal-target declaration causes the App Icon validator to require iPad icons (76×76 @2x and 83.5×83.5 @2x) which are not in the asset catalog. Two warnings, one root cause: the project claims to support iPad but has never been designed or tested for iPad.

### Decision

Set `TARGETED_DEVICE_FAMILY = "1"` (iPhone-only) in both Debug and Release configurations of the `MeData` app target. Leave the iPad orientation key dead in `project.pbxproj` (removing it is out of scope and Xcode tolerates it on iPhone-only targets).

### Rationale

The AR capture flow, the Live Indicators overlay, the orientation contract with the pipeline (`Decisions 17–19` of the tilt-tolerant-capture-ui spec), and the entire visual design are portrait-iPhone-only. Universal targeting was a default carried from the Xcode template, not a deliberate product choice. Dropping it eliminates two validator warnings with a one-character edit, sidesteps the App Store reviewer scrutiny that `UIRequiresFullScreen=YES` attracts on non-game iPad apps, and removes the need to produce or maintain iPad icon variants.

### Alternatives Considered

- **Set `INFOPLIST_KEY_UIRequiresFullScreen = YES` and add the missing iPad icons**: Original proposal — Rejected because it preserves a target the app does not actually support, requires generating and maintaining two new app-icon assets, and exposes the app to App Store reviewer pushback (Apple actively challenges `UIRequiresFullScreen` for non-game iPad apps).
- **Support all orientations including landscape**: Add `UIInterfaceOrientationLandscapeLeft` and `UIInterfaceOrientationLandscapeRight` to both idioms — Rejected because the AR capture and Live Indicator UI is portrait-locked by design and landscape support would require substantial UI rework with no product benefit.
- **Keep universal, support landscape on iPad only**: Add landscape only on the iPad idiom — Rejected for the same UI-rework reason as above, plus it preserves a target nobody is testing.

### Consequences

**Positive:**
- Two warnings eliminated by a one-character edit (`"1,2"` → `"1"`), repeated for Debug + Release.
- No new icon assets to generate, store, or maintain.
- App Store reviewer surface area reduced (no `UIRequiresFullScreen` to defend).
- Product positioning is now honest: a portrait-iPhone AR capture app.

**Negative:**
- The app will not install on iPad. If iPad becomes a real product target later, this decision must be revisited along with the icon work and a landscape/Stage Manager UI design pass.
- Existing TestFlight builds on iPad continue to run until uninstalled; the App Store listing will need an iPhone-only update before the next TestFlight push.

### Impact

`MeData/MeData.xcodeproj/project.pbxproj` (two configuration blocks). No code changes. No asset changes.

---

## Decision 2: Mark `defaultCaptureModeReader` as `nonisolated`

**Date**: 2026-06-02
**Status**: accepted

### Context

`App/CaptureFlowModel.swift` declares the free function `defaultCaptureModeReader()` (currently at line 13) with `@Sendable` so it can serve as the default value for the `captureModeReader: @Sendable () -> CaptureMode` parameter on `CaptureFlowModel.init`. The project sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` (verified at `project.pbxproj` lines 390 and 428), which makes file-scope functions implicitly MainActor-isolated. The Swift 6 compiler reports two diagnostics from this single cause: (a) a MainActor-isolated function cannot be `@Sendable`, and (b) converting the implicitly-MainActor function reference to the parameter's `@Sendable () -> CaptureMode` type loses the MainActor isolation.

### Decision

Replace `@Sendable` with `nonisolated` on the `defaultCaptureModeReader()` declaration. Update the existing explanatory comment immediately above the function to record why `nonisolated` is required.

### Rationale

`defaultCaptureModeReader()` reads `UserDefaults.standard.string(forKey:)`, which Apple documents as thread-safe (UserDefaults uses internal locking). The function captures no state, has no isolated dependencies, and performs no UI work, so MainActor isolation is gratuitous — it exists only because the default-isolation build setting put it there. Marking the function `nonisolated` makes the intent explicit, eliminates both diagnostics at the source, and produces a function reference that is automatically `Sendable` for the closure conversion at the `init` default-arg site. No call-site changes are required.

### Alternatives Considered

- **Wrap the read in `MainActor.assumeIsolated`**: Keep the function MainActor-isolated and bridge at the closure boundary — Rejected because it adds a runtime assertion at every closure invocation and obscures the thread-safety of the underlying read.
- **Move the reader to a `static` method on a non-isolated type**: Hide the reader inside an enum or non-isolated struct — Rejected because it scatters the implementation across an additional declaration without benefit; the file-scope comment already explains why the reader lives outside the class.
- **Convert to a `static let` constant**: Cache the value at module load — Rejected because the reader is intentionally called at shutter-tap time (per Decision 35 of the UI spec) so it must observe live UserDefaults changes between toggles.

### Consequences

**Positive:**
- Both Swift 6 diagnostics resolved by a single keyword change.
- Intent is explicit and discoverable.
- No runtime overhead, no isolation-bridging boilerplate, no call-site changes.

**Negative:**
- Future readers must understand the `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` build setting to know why `nonisolated` is required for what looks like a trivial free function. Addressed by updating the existing comment as part of this change (see Implementation Approach in `smolspec.md`).

### Impact

`App/CaptureFlowModel.swift` (single keyword change + comment update). No call-site changes anywhere in the project or its packages.

---

## Decision 3: Source `MealRow` thumbnail width from the connected window scene

**Date**: 2026-06-02
**Status**: accepted

### Context

`MealRow.loadThumbnail` (currently around line 123 of `App/MealRow.swift`) computes its thumbnail target size with `MainActor.run { UIScreen.main.bounds.width - 32 }`. iOS 26 deprecates `UIScreen.main`, recommending access through a window or window scene found in context. The deprecation produces a build warning.

### Decision

Replace the `UIScreen.main` lookup with `UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first?.screen.bounds.width`, falling back to a conservative `393` pt iPhone width when no scene is connected. The `- 32` horizontal-padding subtraction stays inside the same `MainActor.run` block so the resulting target size is unchanged.

### Rationale

The deprecation message explicitly suggests "a UIScreen instance found through context (i.e. `view.window.windowScene.screen`)" as the replacement. `UIScreen` itself is not deprecated — only the singleton `.main` accessor — so resolving the screen via the connected window scene satisfies the deprecation without rewriting the surrounding code or introducing a new SwiftUI infrastructure layer. The change is mechanically tiny (one block of code, no new types, no new state) and preserves behaviour exactly because `connectedScenes.first?.screen.bounds.width` returns the same value on iPhone as `UIScreen.main.bounds.width` once a scene is active.

### Alternatives Considered

- **PreferenceKey + GeometryReader overlay on `MealRow.body`**: Add a `@State private var rowWidth: CGFloat?`, drive it from a `GeometryReader` background, and change `loadThumbnail` to take `rowWidth` as a parameter — Rejected because `MealRow`'s existing `GeometryReader` is scoped to the `photo` subview, so this approach would add a new top-level layout-measurement infrastructure to clear a one-line deprecation. Larger surface area than the scene-based read for no behaviour gain.
- **Hard-code a fixed thumbnail target size**: Use a constant like `CGSize(width: 800, height: 600)` — Rejected because it bloats `PHImageManager` allocations on small iPhones and loses responsive sizing on smaller models.
- **Read from `@Environment(\.horizontalSizeClass)` with a sized lookup table**: Map size class to a constant width — Rejected because it produces step-function widths that don't match actual screen size and adds an environment dependency for no benefit.

### Consequences

**Positive:**
- Deprecation warning resolved.
- Identical behaviour on every device once a scene is active (same value as `UIScreen.main`).
- No changes to `MealRow`'s view layout, signature, or callers.

**Negative:**
- The `connectedScenes` lookup is verbose; a future SwiftUI-native screen API could simplify this. Acceptable because the call site is contained to one block.
- The `393` pt fallback is iPhone-portrait-specific. Aligned with Decision 1 (iPhone-only) so this is no longer a leaky assumption.

### Impact

`App/MealRow.swift` (one block of code inside `loadThumbnail`). No view-layout changes; no parameter or signature changes.

---
