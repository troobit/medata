# MeData surface catalogue

Every renderable surface in the app, one row per surface x state — the iOS app on `research`, and the
SvelteKit app frozen on `main`. This is the file that defines the app **as it is** — the baseline the
wireframe library moves forward from, and the thing `tools/check_surfaces.sh` ratchets against.

**The `id` is the citation key.** `<surface>/<state>`, kebab-case, e.g. `meal-review/very-low`. Specs,
rune tasks, agent prompts, wireframe filenames (`design-system/wireframes/<surface>/<attempt>.html`) and
archive filenames (`design-system/archive/ios-v0/<id>.png`) all use the same key. One key, everywhere. Cite
a row by its id and quote the state; never by row number.

**Cross-layer rule.** The `data` column is a **documentation join**, nothing more. It names the MedataCore
product and type a surface is *intended* to be bound to, so a human or an agent can translate between the UI
and the data without opening both. It introduces no import, no generated binding and no build-time coupling —
the mechanism `specs/PROCESS.md` prescribes for cross-domain work, which "references the other domains'
specs rather than duplicating them". The column records the **intended** binding, not the observed one:
18 of the 22 `App/*View.swift` and `App/*Sheet.swift` files import one of the six named data products
directly, and 19 import some module under `MedataCore/Sources/` — the number `tools/check_surfaces.sh`
prints as `layer_violations`. Deriving this column from actual imports would bake that violation in as if it
were the design. Where a surface genuinely touches no data the cell is `—`.

**Scope.** Both branches, one file. The **iOS** half — `App/*.swift` plus `MeData/MeDataWidgets/*.swift` on
`research` — runs from **Shell** to **Widgets**, and is the half `tools/check_surfaces.sh` ratchets. The
**SvelteKit web-v0** half, after the exemptions, catalogues the web app preserved on `main`, every row at
`status: web-v0`. It is frozen historical record rather than a build target, and it is here because it is the
second half of the "define the app as-is" baseline and the only written record of the capabilities the
rewrite dropped; its **Successor mapping** subsection is what makes taking the best of each a deliberate act
rather than an accident. Counts are reported separately in **Coverage**, because only the iOS half is
ratcheted.

---

## Zones

A **zone** is a named region of a surface — the part a person points at when comparing two versions of the
same screen: `total-row`, `scale-control`, `food-rows`. Zone names are declared **once per surface, here**,
and every option for that surface reuses them, so the vocabulary is shared rather than reinvented per
wireframe. In a wireframe the zone is marked in the markup — `<section data-zone="total-row">` — and the
catalogue only declares which names exist.

**What they are for.** An option becomes expressible as **a set of zone choices**: `total-row` from
attempt 2, `scale-control` from attempt 1, `food-rows` from attempt 3. That short table is the description of
what you want to see next — unambiguous, writable in a minute, and directly usable as the brief for the next
wireframe or for the SwiftUI implementation. It is also what makes parts of one option recombinable with
parts of another, which prose cannot express and a rendered screen cannot be pointed at to supply.

**What they are not.** Zones generate no code. No Swift type has to exist for a zone, nothing imports
anything because of one, and nothing checks that an implementation respects the boundaries its wireframe
declared. They are a naming convention, and their whole value is that two people mean the same region by the
same word. A zone says what a region looks like; it never says how that region is factored in Swift.

**Where they are declared.** Zones are declared **where they earn their keep** — on surfaces that are a
plausible subject of design options. Most rows have none, and that is correct: a 76 pt shutter button, a
confidence pill, a widget family variant and a notification action have nothing to point at that a state row
does not already name. Declared zone lists sit under the section heading that owns the surface, **not** in
the table: zones are per surface, the table is per state, and an eleven-column table does not need a twelfth.

**Where the names come from.** Each list below is taken from what the code and the page files already call
these regions — `MealReviewView`'s `totalRow` / `primaryAction` / `scaleControl` / `accessoryLine`
(`App/MealReviewView.swift`), the "Layout zones" blocks in `design-system/pages/meal-review.md` and
`design-system/pages/capture.md`, and the order fixed in `specs/data/insulin-dosing/design-direction.md` §2:
"Layout order is fixed and must not change: photo (40%) / totalRow / primaryAction / scale control / 1px
divider / scrolling rows". Nothing here is invented.

---

## How to read a row

- **id** — `<surface>/<state>`, the citation key. Stable; renaming one is a breaking change to every spec
  that cites it.
- **surface** — the Swift type that renders it, or the construction site where no type exists.
- **file** — repository-relative path.
- **kind** — `screen` | `cover` | `sheet` | `overlay` | `component` | `control` | `row` | `shape` |
  `layout` | `representable` | `widget` | `bundle` | `notification`.
- **state** — the distinguishable visual state, phrased as what you would see on the phone.
- **state source** — the thing in code that produces it: an enum case, a predicate, a stored flag. This is
  what makes a row checkable against a closed enum.
- **view-model** — the `App/<X>Model.swift` that owns the surface, or `—`. This is the UI↔data seam, and
  unlike `data` it records what is **actually** there: `—` means no model owns the surface today. Those rows
  are exactly where the view holds a `PersistenceStore` and its own `@State` instead — `ResultView`,
  `MealOverviewView`, `MaskOverlayLoader`, `QuickPresetEditSheet`, most of `SettingsView`. `MealHistoryModel`
  is the mirror image: a live model that no view currently instantiates. The check's layer report is what
  tracks these; the catalogue only has to stop pretending they are bound.
- **data** — MedataCore product and type, names only. Never a code dependency.
- **direction** — `read` | `write` | `read-write` | `none`.
- **archive** — where the rendered screenshot will land, under `design-system/archive/ios-v0/`. The path is
  `<id>.png` with the id's slash flattened to a hyphen — `capture/tracking-lost` becomes
  `capture-tracking-lost.png` — so the cell carries only `pending` (screenshot owed) or `n/a` (nothing
  photographable in isolation, or retired). No PNG exists yet — this generation has not been captured. The
  web-v0 rows spell their path out in full (`archive/web-v0/<id>.png · pending`) because they land in a
  different generation directory and their ids already carry the `web/` prefix.
- **status** — `shipped` | `planned` | `retired` | `web-v0`. `web-v0` means frozen: not shipped, not planned,
  and not a thing to build from without a decision that says so. Every row in the SvelteKit section carries
  it, and no iOS row does.

Two columns read differently in the web-v0 section, and the section's own preamble says so: **view-model**
names the SvelteKit service or store (`meal-api`, `toast.svelte.ts`) rather than an `App/<X>Model.swift`, and
**data** names a repository or endpoint module (`cosmos-meal-repository · Meal`) rather than a MedataCore
product. Both remain names only, on both halves.

---

## Shell

**Zones:** none declared. These rows describe launch, routing and presentation — which cover is up, which
deep link is pending — not regions of a screen. `AppRoot` renders no chrome of its own, so there is nothing
here for an option to rearrange.

| id | surface | file | kind | state | state source | view-model | data | direction | archive | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| app-shell/launch | MedataApp | App/App.swift | screen | Normal launch: store opened, AR engine built, `AppRoot` shown | `MedataApp.init()` non-harness path | CaptureFlowModel | Persistence · PersistenceStore | read | pending | shipped |
| app-shell/harness-launch | MedataApp | App/App.swift | screen | UI-test launch: hermetic store, stub pipeline, control panel overlaid | `UITestSupport.isActive` under `#if DEBUG` | CaptureFlowModel | — | none | n/a | shipped |
| app-shell/refusing-pipeline | MedataApp | App/App.swift | screen | Harness pipeline that always refuses, for driving the refusal overlay | `UITestSupport.PipelineMode` (`RefusingPipeline`) | CaptureFlowModel | Pipeline · EstimationFailure | none | n/a | shipped |
| app-shell/stalling-pipeline | MedataApp | App/App.swift | screen | Harness pipeline that never returns, for holding `.estimating` | `UITestSupport.PipelineMode` (`StallingPipeline`) | CaptureFlowModel | Pipeline · CaptureResult | none | n/a | shipped |
| app-shell/background-dose-launch | MedataApp | App/App.swift | screen | Woken by the `LOG_NOMINAL` notification action with no UI presented | `DoseNotificationDelegate` handling with no `.foreground` option | DoseScheduleModel | Persistence · DoseOccurrence | write | n/a | shipped |
| uitest-panel/present | UITestControlPanel | App/App.swift | overlay | Four leading-edge trigger buttons (Ready / Release / Began / Ended) | `-uitest` argument under `#if DEBUG` | — | — | none | n/a | shipped |
| uitest-panel/absent | UITestControlPanel | App/App.swift | overlay | Nothing rendered in any normal build | `#if DEBUG` false or `UITestSupport.isActive` false | — | — | none | n/a | shipped |
| app-root/home | AppRoot | App/AppRoot.swift | screen | Home only, nothing presented | `activeSheet == nil` | — | — | none | pending | shipped |
| app-root/cover-capture | AppRoot | App/AppRoot.swift | cover | Capture cover presented, AR session armed | `ActiveSheet.capture` | CaptureFlowModel | CaptureKit · ARKitCaptureEngine | read | pending | shipped |
| app-root/cover-intake | AppRoot | App/AppRoot.swift | cover | Intake cover presented | `ActiveSheet.intake` | IntakeModel | Persistence · IntakeEntry | read-write | pending | shipped |
| app-root/cover-records | AppRoot | App/AppRoot.swift | cover | Records cover presented | `ActiveSheet.records` | RecordsModel | Persistence · Event | read-write | pending | shipped |
| app-root/cover-graph | AppRoot | App/AppRoot.swift | cover | Graph cover presented | `ActiveSheet.graph` | TrendsModel | Persistence · TrendsBucket | read | pending | shipped |
| app-root/cover-settings | AppRoot | App/AppRoot.swift | cover | Settings cover presented, wrapped in a `NavigationStack` | `ActiveSheet.settings` | — | — | none | pending | shipped |
| app-root/sheet-dose | AppRoot | App/AppRoot.swift | sheet | Insulin dose sheet raised from the Home Dose control | `showInsulinSheet == true`, `adjustingDose == nil` | InsulinDoseModel | Persistence · InsulinDose | write | pending | shipped |
| app-root/sheet-dose-seeded | AppRoot | App/AppRoot.swift | sheet | Insulin dose sheet pre-seeded from an outstanding dose | `adjustingDose != nil` | InsulinDoseModel, DoseScheduleModel | Persistence · DoseOccurrence, InsulinDose | read-write | pending | shipped |
| app-root/sheet-activity | AppRoot | App/AppRoot.swift | sheet | Activity entry sheet raised over home | `showActivitySheet == true` | ActivityModel | Persistence · ActivityEvent | write | pending | shipped |
| app-root/deeplink-insulin | AppRoot | App/AppRoot.swift | cover | `medata://insulin/add` presenting, possibly behind a dismissal | `DeepLinkTarget.insulinSheet` | — | — | none | n/a | shipped |
| app-root/deeplink-activity | AppRoot | App/AppRoot.swift | cover | `medata://activity/add` presenting | `DeepLinkTarget.activitySheet` | — | — | none | n/a | shipped |
| app-root/deeplink-capture | AppRoot | App/AppRoot.swift | cover | `medata://capture` presenting | `DeepLinkTarget.captureCover` | — | — | none | n/a | shipped |
| app-root/deeplink-graph | AppRoot | App/AppRoot.swift | cover | `medata://graph` presenting — the glucose widget's tap target | `DeepLinkTarget.graphCover` | — | — | none | n/a | shipped |
| app-root/deferred-deeplink | AppRoot | App/AppRoot.swift | cover | Deep link held while a conflicting cover finishes dismissing | `pendingDeepLink != nil` inside `onDismiss` | — | — | none | n/a | shipped |
| app-root/scene-active-refresh | AppRoot | App/AppRoot.swift | screen | Returning to the foreground re-resolves the outstanding dose set | `scenePhase == .active` | DoseScheduleModel | Persistence · DoseOccurrence | read | n/a | shipped |

## Home

**Zones:**

- **`home`** — `wordmark` · `glucose-header` · `dose-surface` · `capture-action` · `route-list`.
  The order of `App/HomeView.swift`'s `body`: the "MeData" title, `glucoseHeader`, `outstandingDoseSection`,
  a `Spacer()`, `captureButton`, then the `routeButton` stack. `dose-surface` is the zone the two shipped
  attempts disagree about — `.banner` fills it with `OutstandingDoseBanner` cards above every route, while
  `.doseRoute` leaves it empty and swaps the Dose entry inside `route-list` for `OutstandingDoseControl`.
  Naming it as one zone is what lets a third option be described without re-arguing the whole screen.
- **`dose-banner`** — `header` · `actions`. `App/OutstandingDoseBanner.swift`'s `header` (dose title over the
  due/lateness subtitle) and the Log / Adjust / Skip row beneath it.

Nothing else here declares zones. `OutstandingDoseControl` is one control with one subline; its states are
what vary, not its regions.

| id | surface | file | kind | state | state source | view-model | data | direction | archive | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| home/glucose-none | HomeView | App/HomeView.swift | screen | Em-dash and "No glucose reading" | `glucose.snapshot.mmolL == nil` | HomeGlucoseModel | GlucoseWidgetShared · GlucoseSnapshot | read | pending | shipped |
| home/glucose-fresh-in-range | HomeView | App/HomeView.swift | screen | Value + trend arrow, `textPrimary` tint, "just now" | age ≤ `GlucoseTimeline.staleAge`, `GlucoseBandStatus` in range | HomeGlucoseModel | GlucoseWidgetShared · GlucoseBandStatus | read | pending | shipped |
| home/glucose-fresh-low | HomeView | App/HomeView.swift | screen | Value tinted red | fresh + `GlucoseBandStatus.low` | HomeGlucoseModel | GlucoseWidgetShared · GlucoseBandStatus | read | pending | shipped |
| home/glucose-fresh-high | HomeView | App/HomeView.swift | screen | Value tinted orange | fresh + `GlucoseBandStatus.high` | HomeGlucoseModel | GlucoseWidgetShared · GlucoseBandStatus | read | pending | shipped |
| home/glucose-stale | HomeView | App/HomeView.swift | screen | Value in `textSecondary`, no arrow, no band colour | age > `GlucoseTimeline.staleAge` | HomeGlucoseModel | GlucoseWidgetShared · GlucoseTimeline | read | pending | shipped |
| home/glucose-age-ticking | HomeView | App/HomeView.swift | screen | Age label ages in place — "just now" / "N min ago" / "N h ago" | `TimelineView(.periodic(from:.now, by: 60))` | HomeGlucoseModel | GlucoseWidgetShared · GlucoseSnapshot | read | n/a | shipped |
| home/no-outstanding-dose | HomeView | App/HomeView.swift | screen | No dose surface; Dose is a plain route button | `outstandingDoses.isEmpty` | DoseScheduleModel | Persistence · DoseOccurrence | read | pending | shipped |
| home/dose-banner-attempt | HomeView | App/HomeView.swift | screen | One `OutstandingDoseBanner` card per dose, above every route | `DoseScheduleSettings.SurfaceStyle.banner` | DoseScheduleModel | Persistence · DoseOccurrence | read | pending | shipped |
| home/dose-route-attempt | HomeView | App/HomeView.swift | screen | Dose route replaced by `OutstandingDoseControl` | `DoseScheduleSettings.SurfaceStyle.doseRoute` | DoseScheduleModel | Persistence · DoseOccurrence | read | pending | shipped |
| home/multiple-doses | HomeView | App/HomeView.swift | screen | Banner stacks every dose; doseRoute shows only `outstandingDoses.first` | `outstandingDoses.count > 1` | DoseScheduleModel | Persistence · DoseOccurrence | read | pending | shipped |
| home/routes | HomeView | App/HomeView.swift | screen | Capture primary plus Intake / Dose / Activity / Records / Graph / Settings | injected `on…` closures, no local state | — | — | none | pending | shipped |
| dose-banner/due-now | OutstandingDoseBanner | App/OutstandingDoseBanner.swift | component | "Due HH:MM" with Log / Adjust / Skip | lateness < 60 s | DoseScheduleModel | Persistence · DoseOccurrence, ScheduledDose | read | pending | shipped |
| dose-banner/late-minutes | OutstandingDoseBanner | App/OutstandingDoseBanner.swift | component | "Due HH:MM · N min" | lateness in minutes | DoseScheduleModel | Persistence · DoseOccurrence | read | pending | shipped |
| dose-banner/late-hours | OutstandingDoseBanner | App/OutstandingDoseBanner.swift | component | "Due HH:MM · N h" | lateness in hours | DoseScheduleModel | Persistence · DoseOccurrence | read | pending | shipped |
| dose-banner/stacked | OutstandingDoseBanner | App/OutstandingDoseBanner.swift | component | One card per outstanding dose, stacked | `ForEach(outstandingDoses)` | DoseScheduleModel | Persistence · DoseOccurrence | read | pending | shipped |
| dose-control/outstanding | OutstandingDoseControl | App/OutstandingDoseControl.swift | control | Accent-prominent "Log N U <kind>" with a due/lateness subline | `outstandingDoses.first != nil` under `.doseRoute` | DoseScheduleModel | Persistence · DoseOccurrence, InsulinKind | read | pending | shipped |
| dose-control/long-press-menu | OutstandingDoseControl | App/OutstandingDoseControl.swift | control | Confirmation dialog: Adjust / Skip / Cancel | long-press gesture on the control | DoseScheduleModel | Persistence · DoseOccurrence | write | pending | shipped |
| dose-control/lateness-formats | OutstandingDoseControl | App/OutstandingDoseControl.swift | control | Subline as seconds / minutes / hours | lateness bucket | DoseScheduleModel | Persistence · DoseOccurrence | read | pending | shipped |
| dose-control/queued-doses | OutstandingDoseControl | App/OutstandingDoseControl.swift | control | Second and later doses have nowhere to render — they wait | `outstandingDoses.dropFirst()` unrendered | DoseScheduleModel | Persistence · DoseOccurrence | read | n/a | shipped |

## Capture

**Zones:**

- **`capture`** — `top-bar` · `preview` · `transient-status` · `telemetry` · `bottom-row`.
  Both `App/CaptureFlowView.swift` (`backgroundLayer`, `topBar`, `transientStatus`, `bottomArea` /
  `bottomRow`) and the "Layout zones" block in `design-system/pages/capture.md` already use these divisions:
  top bar carries close, mode capsule and bubble level; `preview` is the full-bleed AR layer; the hint and
  the blocked chip share `transient-status`; `telemetry` is the always-visible capsule; `bottom-row` is the
  mode button and the shutter.
- **`capture-error`** — `ghost-frame` · `chip` · `hint` · `actions`. `App/CaptureErrorOverlay.swift`: the
  dashed amber `RoundedRectangle`, the `chip`, the one-clause `errorHint`, and the Retry / 2-view / Cancel
  stack. Every failure row differs only in `chip` and `hint`, which is precisely why naming the four regions
  makes a redesign discussable without touching the twelve state rows.
- **`capture-fork`** — `lidar-banner` · `path-cards` · `card-section`. `App/LidarForkSheetView.swift`'s
  `lidarBanner`, the two `pathCard` calls, and `cardSection`.

Nothing else here declares zones. `ShutterButton`, `TelemetryCapsule`, `MedataBubbleLevel`, `ARPreviewView`,
`CapturedFramesView` and `NadirThumbnailView` are single elements inside `capture`'s zones — a 76 pt shutter
has no interior to point at, and the two retired state-only rows have no surface at all.

| id | surface | file | kind | state | state source | view-model | data | direction | archive | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| capture/initialising | CaptureFlowView | App/CaptureFlowView.swift | screen | Hint "Initialising" (hourglass), shutter disabled | `CaptureState.initialising` | CaptureFlowModel | CaptureKit · ARKitCaptureEngine | none | pending | shipped |
| capture/ready-single-view | CaptureFlowView | App/CaptureFlowView.swift | screen | Mode capsule "1-VIEW · LiDAR", shutter armed | `CaptureState.ready(GatingSnapshot)` + `CaptureMode.single` | CaptureFlowModel | CaptureKit · RawFrame, DepthMap | read | pending | shipped |
| capture/ready-two-view-nadir | CaptureFlowView | App/CaptureFlowView.swift | screen | Capsule "2-VIEW · NADIR" | `CaptureState.ready` + `CaptureStage.nadir` | CaptureFlowModel | CaptureKit · RawFrame | read | pending | shipped |
| capture/ready-awaiting-oblique | CaptureFlowView | App/CaptureFlowView.swift | screen | Capsule "2-VIEW · OBLIQUE" with the nadir thumbnail inset | `CaptureState.ready` + `CaptureStage.oblique` | CaptureFlowModel | CaptureKit · RawFrame | read | pending | shipped |
| capture/oblique-tilt-out-of-cap | CaptureFlowView | App/CaptureFlowView.swift | screen | Hint "Target 25°" (rotate.3d) | `GatingSnapshot` oblique tilt outside `TiltGuideState.toleranceDegrees` | CaptureFlowModel | CaptureKit · CameraGravity | read | pending | shipped |
| capture/no-usable-mask | CaptureFlowView | App/CaptureFlowView.swift | screen | Shutter disabled, blocked chip "wait" | `CaptureFlowModel.hasUsablePreShutterMask` false with `firstFrame == nil`, via `failingShutterGate` | CaptureFlowModel | Segmentation · ArgmaxMap | read | pending | shipped |
| capture/tracking-lost | CaptureFlowView | App/CaptureFlowView.swift | screen | Hint "hold steady", shutter disabled | `CaptureState.trackingLost` | CaptureFlowModel | CaptureKit · ARKitCaptureEngine | none | pending | shipped |
| capture/capturing | CaptureFlowView | App/CaptureFlowView.swift | screen | Hint "Capturing" (camera), shutter in its capturing state | `CaptureState.capturing(stage:frozen:)` | CaptureFlowModel | CaptureKit · RawFrame | read | pending | shipped |
| capture/estimating | CaptureFlowView | App/CaptureFlowView.swift | screen | Frozen frames blurred and dimmed, loading symbol over them, telemetry hidden | `CaptureState.estimating(captureResult:)` | CaptureFlowModel | Pipeline · CaptureResult | read | pending | shipped |
| capture/permission-denied-camera | CaptureFlowView | App/CaptureFlowView.swift | screen | Black field, "Camera access denied" + Open Settings; top bar retained | `CaptureState.permissionDenied(PermissionSubject.camera)` | CaptureFlowModel | — | none | pending | shipped |
| capture/permission-denied-motion | CaptureFlowView | App/CaptureFlowView.swift | screen | Same shape, copy "Motion access denied" | `CaptureState.permissionDenied(PermissionSubject.motion)` | CaptureFlowModel | — | none | pending | shipped |
| capture/refused | CaptureFlowView | App/CaptureFlowView.swift | screen | `CaptureErrorOverlay` composited above; AR layer hit-testing off | `CaptureState.refused(EstimationFailure, retryStage:)` | CaptureFlowModel | Pipeline · EstimationFailure | read | pending | shipped |
| capture/showing-result | CaptureFlowView | App/CaptureFlowView.swift | screen | `MealReviewView` pushed on the capture stack | `CaptureState.showingResult(MealRecord)` → `CaptureRoute.result` | CaptureFlowModel | Persistence · MealRecord | read | pending | shipped |
| capture/blocked-chip | CaptureFlowView | App/CaptureFlowView.swift | screen | Transient 1.5 s chip: "too far" / "wait" / "hold steady" | `CaptureFlowModel.failingShutterGate` written into `blockedChip` on a blocked tap | CaptureFlowModel | — | none | pending | shipped |
| capture/fork-sheet-open | CaptureFlowView | App/CaptureFlowView.swift | screen | `LidarForkSheetView` presented from a long press on the mode button | long-press gesture on the mode control | CaptureFlowModel | — | none | pending | shipped |
| capture/back-gesture-resync | CaptureFlowView | App/CaptureFlowView.swift | screen | Stack path emptied while `.showingResult` → soft-lock resync | `path.isEmpty` while `CaptureState.showingResult` | CaptureFlowModel | Persistence · MealRecord | none | n/a | shipped |
| captured-frames/single-view | CapturedFramesView | App/CaptureFlowView.swift | component | Nadir frame fills the safe area | one frame in `CaptureResult` | CaptureFlowModel | CaptureKit · RawFrame | read | pending | shipped |
| captured-frames/two-view | CapturedFramesView | App/CaptureFlowView.swift | component | Nadir top half, oblique bottom half | two frames in `CaptureResult` | CaptureFlowModel | CaptureKit · RawFrame | read | pending | shipped |
| captured-frames/decode-failure | CapturedFramesView | App/CaptureFlowView.swift | component | Flat `captureBackground` fill | image decode returns nil | CaptureFlowModel | CaptureKit · PixelBufferAdapter | read | n/a | shipped |
| nadir-thumbnail/decoded | NadirThumbnailView | App/CaptureFlowView.swift | component | 96 pt thumbnail with a "Nadir" checkmark label | banked nadir frame decodes | CaptureFlowModel | CaptureKit · RawFrame | read | pending | shipped |
| nadir-thumbnail/decode-failure | NadirThumbnailView | App/CaptureFlowView.swift | component | Renders nothing (`EmptyView`) | decode returns nil | CaptureFlowModel | CaptureKit · RawFrame | read | n/a | shipped |
| capture-error/too-tilted | CaptureErrorOverlay | App/CaptureErrorOverlay.swift | overlay | Chip "too tilted" · hint "Target 25°" | `EstimationFailure.obliqueTiltOutOfRange` | CaptureFlowModel | Pipeline · EstimationFailure | read | pending | shipped |
| capture-error/tracking-lost | CaptureErrorOverlay | App/CaptureErrorOverlay.swift | overlay | Chip "tracking lost" · "Retake second photo" | `.arWorldTrackingLost`, `.lidarUnavailableMidCapture` | CaptureFlowModel | Pipeline · EstimationFailure | read | pending | shipped |
| capture-error/no-lidar | CaptureErrorOverlay | App/CaptureErrorOverlay.swift | overlay | Chip "no LiDAR" · "2-view still works" | `EstimationFailure.noLidarDevice` | CaptureFlowModel | Pipeline · EstimationFailure | read | pending | shipped |
| capture-error/card-needed | CaptureErrorOverlay | App/CaptureErrorOverlay.swift | overlay | Chip "card needed" · "Any bank card sets scale" | `.noScaleAvailable`, `.degenerateCardPose`, `.cardTooOblique`, `.iterationDiverged` | CaptureFlowModel | Pipeline · EstimationFailure | read | pending | shipped |
| capture-error/low-depth | CaptureErrorOverlay | App/CaptureErrorOverlay.swift | overlay | Chip "low depth" · "Use two-view mode" | `EstimationFailure.lidarCoverageTooLow([String])` | CaptureFlowModel | Pipeline · EstimationFailure | read | pending | shipped |
| capture-error/no-surface | CaptureErrorOverlay | App/CaptureErrorOverlay.swift | overlay | Chip "no surface" · "Use a flat surface" | `EstimationFailure.lidarFitDegenerate` | CaptureFlowModel | Pipeline · EstimationFailure | read | pending | shipped |
| capture-error/uneven-surface | CaptureErrorOverlay | App/CaptureErrorOverlay.swift | overlay | Chip "uneven surface" · "Use a flat surface" | `EstimationFailure.lidarFitResidualTooHigh` | CaptureFlowModel | Pipeline · EstimationFailure | read | pending | shipped |
| capture-error/no-food | CaptureErrorOverlay | App/CaptureErrorOverlay.swift | overlay | Chip "no food" · "Show the meal clearly" | `EstimationFailure.noFoodPixels` | CaptureFlowModel | Pipeline · EstimationFailure | read | pending | shipped |
| capture-error/unknown-food | CaptureErrorOverlay | App/CaptureErrorOverlay.swift | overlay | Chip "unknown food" · "MeData can't name this food yet" | `EstimationFailure.unrecognisedFood` | CaptureFlowModel | Pipeline · EstimationFailure | read | pending | shipped |
| capture-error/no-volume | CaptureErrorOverlay | App/CaptureErrorOverlay.swift | overlay | Chip "no volume" · "Retake the photo" | `EstimationFailure.noFoodVolumeRecovered` | CaptureFlowModel | Pipeline · EstimationFailure | read | pending | shipped |
| capture-error/history-reset | CaptureErrorOverlay | App/CaptureErrorOverlay.swift | overlay | Chip "history reset" · "Capture still works" | `EstimationFailure.mealsDbCorrupt` | CaptureFlowModel | Pipeline · EstimationFailure | read | pending | shipped |
| capture-error/internal | CaptureErrorOverlay | App/CaptureErrorOverlay.swift | overlay | Chip "error" · "Try again" | `EstimationFailure.internalError(String)` | CaptureFlowModel | Pipeline · EstimationFailure | read | pending | shipped |
| capture-fork/lidar-available | LidarForkSheetView | App/LidarForkSheetView.swift | sheet | Banner "LiDAR available" (accent check), both path cards enabled | device LiDAR capability true | CaptureFlowModel | CaptureKit · DepthMap | none | pending | shipped |
| capture-fork/lidar-unavailable | LidarForkSheetView | App/LidarForkSheetView.swift | sheet | Banner "LiDAR unavailable" (grey x); Quick card dimmed, two-view preselected | device LiDAR capability false | CaptureFlowModel | CaptureKit · DepthMap | none | pending | shipped |
| capture-fork/quick-selected | LidarForkSheetView | App/LidarForkSheetView.swift | sheet | Quick card carries the 2 pt accent border | `CaptureMode.single` selected | CaptureFlowModel | — | none | pending | shipped |
| capture-fork/two-view-selected | LidarForkSheetView | App/LidarForkSheetView.swift | sheet | Two-view card carries the accent border | `CaptureMode.double` selected | CaptureFlowModel | — | none | pending | shipped |
| capture-fork/include-card-toggle | LidarForkSheetView | App/LidarForkSheetView.swift | sheet | Per-capture reference-card toggle, on or off | seeded from `SettingsKeys.alwaysIncludeCard`, not persisted back | CaptureFlowModel | CardDetection · card pose | none | pending | shipped |
| capture-fork/detents | LidarForkSheetView | App/LidarForkSheetView.swift | sheet | Medium and large detents | `.presentationDetents([.medium, .large])` | CaptureFlowModel | — | none | n/a | shipped |
| shutter/ready | ShutterButton | App/ShutterButton.swift | control | Full-opacity inner disc, tap fires the capture | `ShutterButtonState.ready` | CaptureFlowModel | — | none | pending | shipped |
| shutter/disabled | ShutterButton | App/ShutterButton.swift | control | Inner disc at 0.4 opacity; tap fires `onBlockedTap` + warning haptic | `ShutterButtonState.disabled` | CaptureFlowModel | — | none | pending | shipped |
| shutter/capturing | ShutterButton | App/ShutterButton.swift | control | Tap swallowed, press gesture inert | `ShutterButtonState.capturing` | CaptureFlowModel | — | none | pending | shipped |
| shutter/pressed | ShutterButton | App/ShutterButton.swift | control | Outer stroke 4→6 pt, inner 60→52 pt | `isPressed == true` (`ShutterButtonMetrics`) | CaptureFlowModel | — | none | pending | shipped |
| shutter/reduce-motion | ShutterButton | App/ShutterButton.swift | control | No press animation (linear, duration 0) | `\.accessibilityReduceMotion` | CaptureFlowModel | — | none | n/a | shipped |
| telemetry/lidar-with-distance | TelemetryCapsule | App/TelemetryCapsule.swift | component | "dist N cm" with a filled accent dot | live distance present, `supportsLiDAR` true | LiveIndicatorModel | CaptureKit · DepthMap | read | pending | shipped |
| telemetry/lidar-no-distance | TelemetryCapsule | App/TelemetryCapsule.swift | component | "— cm" with a hollow grey dot | `LiveIndicatorBadgeState.isDistanceInRange(cm: nil)` | LiveIndicatorModel | CaptureKit · DepthMap | read | pending | shipped |
| telemetry/non-lidar | TelemetryCapsule | App/TelemetryCapsule.swift | component | Static guidance band "30–40 cm", hollow grey dot | `LiveIndicatorBadgeState.elements(supportsLiDAR: false)` | LiveIndicatorModel | — | none | pending | shipped |
| telemetry/tilt-readout | TelemetryCapsule | App/TelemetryCapsule.swift | component | Tilt always shown to one decimal | `LiveIndicatorModel.liveTiltVector` | LiveIndicatorModel | CaptureKit · CameraGravity | read | pending | shipped |
| bubble-level/nadir | MedataBubbleLevel | App/MedataBubbleLevel.swift | component | Filled centre tolerance disc (target 0°) | `TiltGuideState.target(awaitingOblique: false)` | LiveIndicatorModel | CaptureKit · CameraGravity | read | pending | shipped |
| bubble-level/oblique | MedataBubbleLevel | App/MedataBubbleLevel.swift | component | Accent target ring at the 25° radius | `TiltGuideState.target(awaitingOblique: true)` | LiveIndicatorModel | CaptureKit · CameraGravity | read | pending | shipped |
| bubble-level/aligned | MedataBubbleLevel | App/MedataBubbleLevel.swift | component | Accent puck | `TiltGuideState.isAligned(tilt:target:tolerance:)` true | LiveIndicatorModel | CaptureKit · CameraGravity | read | pending | shipped |
| bubble-level/out-of-tolerance | MedataBubbleLevel | App/MedataBubbleLevel.swift | component | `systemOrange` puck | `TiltGuideState.isAligned` false | LiveIndicatorModel | CaptureKit · CameraGravity | read | pending | shipped |
| bubble-level/clamped | MedataBubbleLevel | App/MedataBubbleLevel.swift | component | Puck pinned to the field edge at 45° | tilt magnitude clamp | LiveIndicatorModel | CaptureKit · CameraGravity | read | pending | shipped |
| ar-preview/live | ARPreviewView | App/ARPreviewView.swift | representable | Live `ARView` camera feed; all touches route past it to the SwiftUI chrome | `isUserInteractionEnabled = false` | CaptureFlowModel | CaptureKit · ARKitCaptureEngine | read | pending | shipped |
| ar-preview/hit-testing-off | ARPreviewView | App/ARPreviewView.swift | representable | Hit-testing disabled by the parent while the refusal overlay is up | `CaptureState.refused` in `CaptureFlowView` | CaptureFlowModel | — | none | n/a | shipped |
| tilt-guide/state-only | TiltGuideState | App/TiltBubbleGuide.swift | component | View deleted in the handoff-00 chrome rebuild; only the pure target/tolerance maths remains, consumed by `MedataBubbleLevel` | `TiltGuideState.target` / `.toleranceDegrees` / `.isAligned` | — | — | none | n/a | retired |
| live-badge/state-only | LiveIndicatorBadgeState | App/LiveIndicatorBadge.swift | component | Auto-hiding tilt/distance/coverage chip deleted; `TelemetryCapsule` replaced it. Pure state kept — `CaptureFlowModel.tiltInRange` calls `isSigmaTiltSufficient` | `LiveIndicatorBadgeElement.tilt` / `.distance` / `.coverage` | LiveIndicatorModel | — | none | n/a | retired |

## Review

**Zones:**

- **`meal-review`** — `photo` · `total-row` · `primary-action` · `scale-control` · `accessory-line` ·
  `food-rows`. The canonical list. It is the layout order `specs/data/insulin-dosing/design-direction.md` §2
  declares fixed — "photo (40%) / totalRow / primaryAction / scale control / 1px divider / scrolling rows" —
  and it matches `App/MealReviewView.swift` member for member (`photoSection`, `totalRow`, `primaryAction`,
  `scaleControl`, `accessoryLine`, `foodRow`) and the "Layout zones" block in
  `design-system/pages/meal-review.md`. Two things the zone list encodes that a screenshot does not: the
  above-the-fold boundary falls after `scale-control`, and the very-low surface **occupies** `scale-control`
  rather than adding a region, which is why `meal-review/very-low` is a choice about that zone and not a
  seventh one.
- **`result`** — `hero` · `signals` · `plate-card` · `summary-card` · `macro-placeholders` · `action-row`.
  `App/ResultView.swift`'s `body` order: `carbTotal` with its corrected marker and confidence pill; then the
  placeholder chip, calibration banner and liquid flag, which all compete for the same slot and are therefore
  one zone; then `plateCard` (which contains `fractionControl`, the food rows and `logPill`), `summaryCard`,
  `macroPlaceholders`, and the bottom-pinned `actionRow`.
- **`meal-overview`** — `photo-card` · `total-row` · `metadata-line` · `food-rows` · `action-row`.
  `App/MealOverviewView.swift`'s `body`: `photoCard`, `totalRow`, the `metadataLine` footnote, `foods`,
  `actionRow`.
- **`relabel`** — `absent-action` · `shortlist` · `filter-field` · `all-foods`. The three `Section`s of
  `RelabelSheet` in `App/MealReviewView.swift`. The filter field is named separately from `all-foods` even
  though it sits inside that `Section`, because `relabel/filter-empty` and `relabel/filter-no-match` are
  states of the field while the section around it is unchanged.

Nothing else here declares zones. `ConfidencePill`, `MaskContourShape`, `DimOutsideShape` and
`MaskOverlayLoader` are elements drawn inside `meal-review`'s and `meal-overview`'s zones, not regions in
their own right.

| id | surface | file | kind | state | state source | view-model | data | direction | archive | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| meal-review/photo-with-contours | MealReviewView | App/MealReviewView.swift | screen | Photo with per-class contour outlines | `contours != nil` | MealReviewModel | Persistence · MealRecord, MealArtefact | read | pending | shipped |
| meal-review/photo-no-contours | MealReviewView | App/MealReviewView.swift | screen | Photo only — outlines and badges absent | `contours == nil` | MealReviewModel | Persistence · MealArtefact | read | pending | shipped |
| meal-review/photo-unavailable | MealReviewView | App/MealReviewView.swift | screen | `captureChromeBG` with a fork.knife fallback; rows and total still render | photo load returns nil | MealReviewModel | Persistence · MealRecord | read | pending | shipped |
| meal-review/food-selected | MealReviewView | App/MealReviewView.swift | screen | `DimOutsideShape` dims outside the selection; its row takes an accent border | `selectedFood != nil` | MealReviewModel | Segmentation · ClassPalette | read | pending | shipped |
| meal-review/very-low | MealReviewView | App/MealReviewView.swift | screen | Very-low surface replaces the scale control: Δθ from target, Retake / Keep as-is | `ResultFormat.showsVeryLowSurface(sigma)` and `!veryLowDecided` | MealReviewModel | Confidence · ConfidenceResult | read | pending | shipped |
| meal-review/very-low-dismissed | MealReviewView | App/MealReviewView.swift | screen | "Keep as-is" taken; the scale control returns | `veryLowDecided == true` | MealReviewModel | Confidence · ConfidenceResult | read | pending | shipped |
| meal-review/plate-all | MealReviewView | App/MealReviewView.swift | screen | PLATE control, "All" stop inverted | `PlateFraction.all` | MealReviewModel | Foods · ServingMath | read-write | pending | shipped |
| meal-review/plate-three-quarters | MealReviewView | App/MealReviewView.swift | screen | "¾" stop inverted | `PlateFraction.threeQuarters` | MealReviewModel | Foods · ServingMath | read-write | pending | shipped |
| meal-review/plate-half | MealReviewView | App/MealReviewView.swift | screen | "½" stop inverted | `PlateFraction.half` | MealReviewModel | Foods · ServingMath | read-write | pending | shipped |
| meal-review/plate-quarter | MealReviewView | App/MealReviewView.swift | screen | "¼" stop inverted | `PlateFraction.quarter` | MealReviewModel | Foods · ServingMath | read-write | pending | shipped |
| meal-review/corrected-marker | MealReviewView | App/MealReviewView.swift | screen | Corrected marker beside the total | `model.hasActualCorrections` | MealReviewModel | Persistence · MealRecord | read | pending | shipped |
| meal-review/mass-line | MealReviewView | App/MealReviewView.swift | screen | "≈ N g on plate" total mass line, always present | derived from the row grams | MealReviewModel | Macros · MacroResult | read | pending | shipped |
| meal-review/accessory-absent | MealReviewView | App/MealReviewView.swift | screen | No accessory line at all | `accessorySignals.isEmpty` | MealReviewModel | Macros · PerClassMacros | read | pending | shipped |
| meal-review/accessory-collapsed | MealReviewView | App/MealReviewView.swift | screen | Joined short labels with a chevron | accessory line collapsed | MealReviewModel | Macros · PerClassMacros | read | pending | shipped |
| meal-review/accessory-expanded | MealReviewView | App/MealReviewView.swift | screen | One card per signal | accessory line expanded | MealReviewModel | Macros · PerClassMacros | read | pending | shipped |
| meal-review/signal-calibration-full | MealReviewView | App/MealReviewView.swift | screen | Signal "Uncalibrated" | `CalibrationBannerState.full` | MealReviewModel | Macros · PerClassMacros | read | pending | shipped |
| meal-review/signal-calibration-softened | MealReviewView | App/MealReviewView.swift | screen | Signal "Population-calibrated" | `CalibrationBannerState.softened` | MealReviewModel | Macros · PerClassMacros | read | pending | shipped |
| meal-review/signal-liquid | MealReviewView | App/MealReviewView.swift | screen | Signal "Drink over-estimate" | `ResultFormat.showsLiquidOverEstimateFlag(record.macros)` | MealReviewModel | Macros · MacroResult | read | pending | shipped |
| meal-review/signal-unknown-region | MealReviewView | App/MealReviewView.swift | screen | Signal "Unknown region · counted as unknown carbs" | `contours.presentClassIds` contains `palette.unknownFood` | MealReviewModel | Segmentation · ClassPalette | read | pending | shipped |
| meal-review/signal-unsupported-liquid | MealReviewView | App/MealReviewView.swift | screen | Signal "Liquid · not estimated" | `contours.presentClassIds` contains `palette.unsupportedLiquid` | MealReviewModel | Segmentation · ClassPalette | read | pending | shipped |
| meal-review/row-normal | MealReviewView | App/MealReviewView.swift | screen | Name + carbs + amount + −/+ / relabel / reject | `ReviewFood` with no correction flags | MealReviewModel | Foods · FoodEntry | read-write | pending | shipped |
| meal-review/row-serving-unit | MealReviewView | App/MealReviewView.swift | screen | "≈ 1½ potatoes · 87 g" | `Foods.SolidServing` row resolves | MealReviewModel | Foods · SolidServing, ServingNote | read | pending | shipped |
| meal-review/row-gram-fallback | MealReviewView | App/MealReviewView.swift | screen | "120 g" — no serving row available | no `SolidServing` for the class | MealReviewModel | Foods · FoodEntry | read | pending | shipped |
| meal-review/row-gram-edit | MealReviewView | App/MealReviewView.swift | screen | Numeric `TextField` with a keyboard Done toolbar | row in gram-edit mode | MealReviewModel | Foods · ServingMath | write | pending | shipped |
| meal-review/row-relabelled | MealReviewView | App/MealReviewView.swift | screen | Struck-through predicted name → corrected name | `CorrectionFlags` relabel set | MealReviewModel | Persistence · Event (correction) | write | pending | shipped |
| meal-review/row-absent | MealReviewView | App/MealReviewView.swift | screen | "not in the database" subline | `CorrectionFlags` absent set | MealReviewModel | Foods · FoodEntry | write | pending | shipped |
| meal-review/row-rejected | MealReviewView | App/MealReviewView.swift | screen | Struck-through name and badge, contribution gone, Restore action | `CorrectionFlags` reject set | MealReviewModel | Persistence · Event (correction) | write | pending | shipped |
| meal-review/step-bounds | MealReviewView | App/MealReviewView.swift | screen | Step buttons disabled at the 0 g floor and the 5000 g ceiling | grams clamp | MealReviewModel | Foods · ServingMath | read | pending | shipped |
| meal-review/relabel-open | MealReviewView | App/MealReviewView.swift | screen | `RelabelSheet` presented over the review | relabel action on a row | MealReviewModel | Foods · FoodEntry | read | pending | shipped |
| meal-review/discard-and-leave | MealReviewView | App/MealReviewView.swift | screen | Retake or Delete chosen from the ⋯ menu — discard then leave | ⋯ menu action | MealReviewModel | Persistence · MealRecord | write | pending | shipped |
| relabel/shortlist-empty | RelabelSheet | App/MealReviewView.swift | sheet | Recent section omitted | `ShortlistOrdering` yields no rows | MealReviewModel | Foods · FoodEntry | read | pending | shipped |
| relabel/shortlist-populated | RelabelSheet | App/MealReviewView.swift | sheet | ≤5 recency-ordered candidates, no scores shown | `ShortlistOrdering` yields rows | MealReviewModel | Foods · ShortlistOrdering | read | pending | shipped |
| relabel/filter-empty | RelabelSheet | App/MealReviewView.swift | sheet | Full eligible list | filter text empty | MealReviewModel | Foods · FoodEntry | read | pending | shipped |
| relabel/filter-no-match | RelabelSheet | App/MealReviewView.swift | sheet | All foods section shows only the field | filter matches nothing | MealReviewModel | Foods · FoodEntry | read | pending | shipped |
| relabel/disabled | RelabelSheet | App/MealReviewView.swift | sheet | Candidate rows greyed (β unrecoverable); absent and reject still work | `BetaCalibrationStatus` unrecoverable | MealReviewModel | Foods · BetaCalibrationStatus | read | pending | shipped |
| relabel/title-fallback | RelabelSheet | App/MealReviewView.swift | sheet | Title falls back to "Change food" | food not resolvable | MealReviewModel | Foods · FoodEntry | read | pending | shipped |
| mask-contour/active | MaskContourShape | App/MealReviewView.swift | shape | Outline stroked at 2 pt | active `ReviewFood` | MealReviewModel | Persistence · MealArtefact | read | n/a | shipped |
| mask-contour/rejected | MaskContourShape | App/MealReviewView.swift | shape | Outline stroked at 1 pt, 0.5 opacity | rejected `ReviewFood` | MealReviewModel | Persistence · MealArtefact | read | n/a | shipped |
| mask-contour/hit-test | MaskContourShape | App/MealReviewView.swift | shape | The path is the tap target for selecting a class on the photo | `contentShape` over the contour path | MealReviewModel | Segmentation · ArgmaxMap | read | n/a | shipped |
| dim-outside/selected | DimOutsideShape | App/MealReviewView.swift | shape | Even-odd fill dimming everything outside the selected class | `selectedFood != nil` | MealReviewModel | Persistence · MealArtefact | read | n/a | shipped |
| mask-overlay/decoded | MaskOverlayLoader | App/MaskOverlayLoader.swift | component | Tinted RGBA overlay at 0.55 alpha; present class ids reported | `MaskOverlayDecoder` returns a `DecodedMask` | — | Persistence · MealArtefact | read | pending | shipped |
| mask-overlay/miss | MaskOverlayLoader | App/MaskOverlayLoader.swift | component | `Color.clear` — the photo shows through; never errors | no artefact row, unreadable file, or unexpected format | — | Persistence · MealArtefact | read | n/a | shipped |
| meal-overview/photo-with-mask | MealOverviewView | App/MealOverviewView.swift | screen | Photo with the mask overlay composited | pushed by `MealRoute.overview`; artefact decodes | — | Persistence · MealRecord, MealArtefact | read | pending | shipped |
| meal-overview/mask-missing | MealOverviewView | App/MealOverviewView.swift | screen | Photo only — the overlay renders nothing | `MaskOverlayLoader` miss | — | Persistence · MealArtefact | read | pending | shipped |
| meal-overview/photo-unavailable | MealOverviewView | App/MealOverviewView.swift | screen | `surfaceElevated` with a fork.knife fallback | photo load returns nil | — | Persistence · MealRecord | read | pending | shipped |
| meal-overview/corrected | MealOverviewView | App/MealOverviewView.swift | screen | Corrected marker present | `MealRecord` carries corrections | — | Persistence · MealRecord | read | pending | shipped |
| meal-overview/uncorrected | MealOverviewView | App/MealOverviewView.swift | screen | No corrected marker | `MealRecord` carries none | — | Persistence · MealRecord | read | pending | shipped |
| meal-overview/confidence | MealOverviewView | App/MealOverviewView.swift | screen | Confidence pill, one of four tiers | `ConfidenceLevel.forSigma(_:)` | — | Confidence · ConfidenceResult | read | pending | shipped |
| meal-overview/metadata-lidar | MealOverviewView | App/MealOverviewView.swift | screen | "1-view · LiDAR · <date>" | single-view capture with depth | — | Persistence · MealRecord | read | pending | shipped |
| meal-overview/metadata-two-view | MealOverviewView | App/MealOverviewView.swift | screen | "2-view · <date>" | two-view capture | — | Persistence · MealRecord | read | pending | shipped |
| meal-overview/per-class-rows | MealOverviewView | App/MealOverviewView.swift | screen | One row per class with its deterministic colour swatch; relabelled classes named as corrected | `PerClassRow` over `PerClassMacros` | — | Macros · PerClassMacros, Segmentation · ClassColourTable | read | pending | shipped |
| meal-overview/delete-confirm | MealOverviewView | App/MealOverviewView.swift | screen | Delete confirmation dialog | delete action | — | Persistence · MealRecord | write | pending | shipped |
| result/hero-original | ResultView | App/ResultView.swift | screen | Hero shows the original estimate | pushed by `MealRoute.result`; no correction, no pending adjustment | — | Persistence · MealRecord | read | pending | shipped |
| result/hero-corrected | ResultView | App/ResultView.swift | screen | Hero shows the corrected total + "estimated N g" second line | `isCorrected` | — | Persistence · MealRecord | read | pending | shipped |
| result/hero-pending | ResultView | App/ResultView.swift | screen | Hero shows a live pending total while adjusting | pending grams diverge from recorded | — | Foods · ServingMath | read-write | pending | shipped |
| result/mass-line | ResultView | App/ResultView.swift | screen | "≈ N g on plate", tracking the pending grams | derived from the rows | — | Macros · MacroResult | read | pending | shipped |
| result/corrected-marker | ResultView | App/ResultView.swift | screen | Corrected marker shown | `isCorrected` | — | Persistence · MealRecord | read | pending | shipped |
| result/confidence-high | ResultView | App/ResultView.swift | screen | Confidence pill "High" | `ConfidenceLevel.high` (σ ≥ 0.75) | — | Confidence · ConfidenceResult | read | pending | shipped |
| result/confidence-moderate | ResultView | App/ResultView.swift | screen | Confidence pill "Moderate" | `ConfidenceLevel.moderate` (0.50 ≤ σ < 0.75) | — | Confidence · ConfidenceResult | read | pending | shipped |
| result/confidence-low | ResultView | App/ResultView.swift | screen | Confidence pill "Low" | `ConfidenceLevel.low` (0.20 ≤ σ < 0.50) | — | Confidence · ConfidenceResult | read | pending | shipped |
| result/confidence-very-low | ResultView | App/ResultView.swift | screen | Confidence pill "Very Low" | `ConfidenceLevel.veryLow` (σ < 0.20) | — | Confidence · ConfidenceResult | read | pending | shipped |
| result/placeholder-chip | ResultView | App/ResultView.swift | screen | Placeholder chip; suppresses the calibration banner and the liquid flag | `segmenterSource == "dev_stub"` | — | Segmentation · StubInferenceEngine | read | pending | shipped |
| result/calibration-full | ResultView | App/ResultView.swift | screen | Uncalibrated banner | `CalibrationBannerState.full` | — | Macros · PerClassMacros | read | pending | shipped |
| result/calibration-softened | ResultView | App/ResultView.swift | screen | Population-calibrated banner | `CalibrationBannerState.softened` | — | Macros · PerClassMacros | read | pending | shipped |
| result/calibration-suppressed | ResultView | App/ResultView.swift | screen | No banner | `CalibrationBannerState.suppressed` | — | Macros · PerClassMacros | read | pending | shipped |
| result/calibration-none | ResultView | App/ResultView.swift | screen | No banner — standalone drink, no solid-food class contributes | `CalibrationBannerState.none` | — | Macros · PerClassMacros | read | pending | shipped |
| result/liquid-flag | ResultView | App/ResultView.swift | screen | Liquid over-estimate flag shown | `ResultFormat.showsLiquidOverEstimateFlag(_:)` | — | Macros · MacroResult | read | pending | shipped |
| result/fraction-derived | ResultView | App/ResultView.swift | screen | Fraction control with the derived active stop (All / ¾ / ½ / ¼) | `PlateFraction.allCases`, stop derived from the rows | — | Foods · ServingMath | read-write | pending | shipped |
| result/fraction-no-stop | ResultView | App/ResultView.swift | screen | No stop highlighted after a per-row nudge | derived stop resolves to nil | — | Foods · ServingMath | read | pending | shipped |
| result/row-serving-unit | ResultView | App/ResultView.swift | screen | Row shows a serving unit | `SolidServing` row resolves | — | Foods · SolidServing | read | pending | shipped |
| result/row-gram-fallback | ResultView | App/ResultView.swift | screen | Row shows grams only — liquid or no `solid_servings` row | no `SolidServing` | — | Foods · FoodEntry | read | pending | shipped |
| result/row-gram-edit | ResultView | App/ResultView.swift | screen | Row in gram-edit mode with a keyboard Done toolbar | row editing | — | Foods · ServingMath | write | pending | shipped |
| result/log-pill | ResultView | App/ResultView.swift | screen | "Log N g" pill, visible only while pending diverges from recorded | pending ≠ recorded | — | Persistence · Event (correction) | write | pending | shipped |
| result/step-bounds | ResultView | App/ResultView.swift | screen | Step buttons disabled at the 0 g and 5000 g bounds | grams clamp | — | Foods · ServingMath | read | pending | shipped |
| result/thumbnail | ResultView | App/ResultView.swift | screen | Thumbnail loaded | photo decodes | — | Persistence · MealRecord | read | pending | shipped |
| result/thumbnail-fallback | ResultView | App/ResultView.swift | screen | fork.knife placeholder | photo load returns nil | — | Persistence · MealRecord | read | pending | shipped |
| result/dynamic-type-clamp | ResultView | App/ResultView.swift | screen | Hero clamped between 72 pt base and 88 pt maximum | `ResultViewLayout.displayPoints(_:)` | — | — | none | pending | shipped |
| result/delete | ResultView | App/ResultView.swift | screen | Delete chosen from the ⋯ menu | ⋯ menu action | — | Persistence · MealRecord | write | pending | shipped |
| result/legacy-portion-note | ResultView | App/ResultView.swift | screen | Legacy `portion N/M` correction notes still seed the rows on reopen; nothing new writes them | `PortionFormat.parse(note:)` | — | Persistence · Event (correction) | read | n/a | retired |
| confidence-pill/high | ConfidencePill | App/ConfidencePill.swift | component | Accent capsule with checkmark.seal.fill | `ConfidenceLevel.high` | — | Confidence · ConfidenceResult | read | pending | shipped |
| confidence-pill/moderate | ConfidencePill | App/ConfidencePill.swift | component | Orange capsule with exclamationmark.triangle.fill | `ConfidenceLevel.moderate` | — | Confidence · ConfidenceResult | read | pending | shipped |
| confidence-pill/low | ConfidencePill | App/ConfidencePill.swift | component | Red capsule with xmark.octagon.fill | `ConfidenceLevel.low` | — | Confidence · ConfidenceResult | read | pending | shipped |
| confidence-pill/very-low | ConfidencePill | App/ConfidencePill.swift | component | Desaturated grey capsule with minus.circle.fill | `ConfidenceLevel.veryLow` | — | Confidence · ConfidenceResult | read | pending | shipped |

## Records

**Zones:**

- **`records`** — `toolbar` · `row-list` · `edit-bottom-bar`. `App/RecordsView.swift` is a `List` with a
  `toolbarContent` that has three placements: leading close, trailing Select / ⋯, and a `.bottomBar` group
  that exists only in edit mode. The screen is deliberately untitled, so there is no title zone.
- **`row-meal`, `row-insulin`, `row-glucose`, `row-intake`, `row-activity`** — one shared list:
  `kind-glyph` · `value-line` · `time-line`. All five render the same three-part shape in
  `App/RecordsView.swift`, so they share a vocabulary rather than each inventing one; the trailing
  "corrected" capsule of `row-meal/corrected` sits in `value-line`.
  Worth declaring because the shape of a history row is a live question: the web app grouped rows under
  Today / Yesterday headers and expanded them in place, and both were dropped (see **Successor mapping**).

`DateRangePurgeSheet` declares none — it is a Form of two pickers and a count, and what varies is the count,
not the arrangement.

| id | surface | file | kind | state | state source | view-model | data | direction | archive | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| records/empty | RecordsView | App/RecordsView.swift | screen | No rows; "Delete All Records…" disabled | `model.rows.isEmpty` | RecordsModel | Persistence · Event | read | pending | shipped |
| records/browse | RecordsView | App/RecordsView.swift | screen | Select and ⋯ menu in the toolbar | edit mode inactive | RecordsModel | Persistence · Event | read | pending | shipped |
| records/edit-mode | RecordsView | App/RecordsView.swift | screen | Selection circles; bottom bar Select All / Deselect All + "Delete (N)" | `editMode == .active` | RecordsModel | Persistence · Event | read-write | pending | shipped |
| records/edit-empty-selection | RecordsView | App/RecordsView.swift | screen | Delete disabled | edit mode with an empty selection | RecordsModel | Persistence · Event | read | pending | shipped |
| records/all-selected | RecordsView | App/RecordsView.swift | screen | Bottom bar reads "Deselect All" | `allSelected == true` | RecordsModel | Persistence · Event | read | pending | shipped |
| records/bulk-delete-confirm | RecordsView | App/RecordsView.swift | screen | Bulk-delete confirmation dialog | destructive action on a selection | RecordsModel | Persistence · Event | write | pending | shipped |
| records/delete-all-confirm | RecordsView | App/RecordsView.swift | screen | Delete-all confirmation dialog | ⋯ menu "Delete All Records…" | RecordsModel | Persistence · Event | write | pending | shipped |
| records/purge-sheet-open | RecordsView | App/RecordsView.swift | screen | `DateRangePurgeSheet` presented | ⋯ menu date-range action | RecordsModel | Persistence · Event | write | pending | shipped |
| records/swipe-delete | RecordsView | App/RecordsView.swift | screen | Swipe-to-delete on a single row | `.swipeActions` on a `RecordRow` | RecordsModel | Persistence · Event | write | pending | shipped |
| purge-range/defaulted | DateRangePurgeSheet | App/RecordsView.swift | sheet | From/To default to earliest record → now on appear | `.onAppear` seeding | RecordsModel | Persistence · Event | read | pending | shipped |
| purge-range/count-zero | DateRangePurgeSheet | App/RecordsView.swift | sheet | Delete disabled — no records in range | in-range count == 0 | RecordsModel | Persistence · Event | read | pending | shipped |
| purge-range/count-positive | DateRangePurgeSheet | App/RecordsView.swift | sheet | "Delete N records" enabled | in-range count > 0 | RecordsModel | Persistence · Event | read | pending | shipped |
| purge-range/singular | DateRangePurgeSheet | App/RecordsView.swift | sheet | Label reads "1 record" | in-range count == 1 | RecordsModel | Persistence · Event | read | pending | shipped |
| purge-range/confirm | DateRangePurgeSheet | App/RecordsView.swift | sheet | Destructive confirmation dialog | Delete tapped | RecordsModel | Persistence · Event | write | pending | shipped |
| row-meal/plain | MealRecordRow | App/RecordsView.swift | row | Corrected carbs, estimated mass, timestamp; navigates to the meal overview | `RecordRow.meal(DisplayMeal)` | RecordsModel | Persistence · MealRecord | read | pending | shipped |
| row-meal/corrected | MealRecordRow | App/RecordsView.swift | row | Trailing "corrected" capsule | `DisplayMeal` carries corrections | RecordsModel | Persistence · MealRecord | read | pending | shipped |
| row-insulin/bolus | InsulinRecordRow | App/RecordsView.swift | row | Teal syringe, units, timestamp; no navigation | `InsulinKind.bolus` | RecordsModel | Persistence · InsulinDose | read | pending | shipped |
| row-insulin/basal | InsulinRecordRow | App/RecordsView.swift | row | Purple syringe | `InsulinKind.basal` | RecordsModel | Persistence · InsulinDose | read | pending | shipped |
| row-glucose/reading | GlucoseRecordRow | App/RecordsView.swift | row | Value in mmol/L + timestamp; deletable by swipe or selection | `RecordRow.glucose(GlucoseRow)` | RecordsModel | Persistence · BslReading | read | pending | shipped |
| row-intake/entry | IntakeRecordRow | App/RecordsView.swift | row | Grams + "Carbs" type label + timestamp; swipe-deletable | `RecordRow.intake(IntakeRecord)` | RecordsModel | Persistence · IntakeEntry | read | pending | shipped |
| row-activity/with-duration | ActivityRecordRow | App/RecordsView.swift | row | Kind glyph, label, "N min" | `ActivityEvent` duration present | RecordsModel | Persistence · ActivityEvent | read | pending | shipped |
| row-activity/without-duration | ActivityRecordRow | App/RecordsView.swift | row | Nothing rendered where the duration would be — absent is not zero | `ActivityEvent` duration nil | RecordsModel | Persistence · ActivityEvent | read | pending | shipped |
| row-activity/kind-glyphs | ActivityRecordRow | App/RecordsView.swift | row | One glyph per kind: swim, waterpolo, cycle, run, walk, gym, other | `ActivityKind.allCases` | RecordsModel | Persistence · ActivityKind | read | pending | shipped |

## Trends

**Zones:**

- **`trends`** — `range-picker` · `chart` · `metric-chips` · `stat-cards` · `day-lists`. The computed
  properties of `App/TrendsView.swift` in body order: `rangePicker`, `chart`, `metricChips`, `statCards`, and
  the Day-only `dayMeals` / `dayInsulin` / `dayActivity` lists, grouped as one zone because they appear and
  disappear together with `TrendsRange.day`. `ChipFlow` is the layout inside `metric-chips`, not a zone —
  and it is the component an attempt branch silently deleted, which is a surface-delta question rather than a
  zone one.

`TrendsOptionsSheet` declares none: it is a Form of toggles whose states are catalogued row by row.

| id | surface | file | kind | state | state source | view-model | data | direction | archive | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| trends/range-day | TrendsView | App/TrendsView.swift | screen | Day range selected; the three day lists appear below the chart | `TrendsRange.day` | TrendsModel | Persistence · TrendsBucket | read | pending | shipped |
| trends/range-week | TrendsView | App/TrendsView.swift | screen | Week range selected | `TrendsRange.week` | TrendsModel | Persistence · TrendsBucket | read | pending | shipped |
| trends/range-month | TrendsView | App/TrendsView.swift | screen | Month range selected | `TrendsRange.month` | TrendsModel | Persistence · TrendsBucket | read | pending | shipped |
| trends/no-glucose | TrendsView | App/TrendsView.swift | screen | "no glucose data" caption overlaid top-trailing | glucose series empty | TrendsModel | Persistence · BslReading | read | pending | shipped |
| trends/chip-carbs | TrendsView | App/TrendsView.swift | screen | Carbs chip on/off; the chip fills with its series colour when on | carbs metric toggle | TrendsModel | Persistence · MealRecord, IntakeEntry | read | pending | shipped |
| trends/chip-glucose | TrendsView | App/TrendsView.swift | screen | Glucose chip on/off | glucose metric toggle | TrendsModel | Persistence · BslReading | read | pending | shipped |
| trends/chip-insulin | TrendsView | App/TrendsView.swift | screen | Insulin chip on/off | insulin metric toggle | TrendsModel | Persistence · InsulinDose | read | pending | shipped |
| trends/chip-activity | TrendsView | App/TrendsView.swift | screen | Activity chip on/off | activity metric toggle | TrendsModel | Persistence · ActivityEvent | read | pending | shipped |
| trends/chip-macros-disabled | TrendsView | App/TrendsView.swift | screen | "Protein · Fat" dashed chip, always inert | hard-coded disabled chip | TrendsModel | Macros · ClinicalMacros | none | pending | shipped |
| trends/target-band | TrendsView | App/TrendsView.swift | screen | Target band 3.9–10.0 mmol/L shown or hidden | target-band toggle | TrendsModel | Persistence · BslReading | read | pending | shipped |
| trends/y-scale-auto | TrendsView | App/TrendsView.swift | screen | Glucose y-scale derived from the data | scale mode auto | TrendsModel | Persistence · TrendsMath | read | pending | shipped |
| trends/y-scale-fixed | TrendsView | App/TrendsView.swift | screen | Glucose y-scale pinned to the configured maximum (8–25 mmol/L) | scale mode fixed | TrendsModel | Persistence · TrendsMath | read | pending | shipped |
| trends/activity-shaded | TrendsView | App/TrendsView.swift | screen | Activity with a duration renders as a shaded `RectangleMark` column | `ActivityMarker` with duration | TrendsModel | Persistence · ActivityEvent | read | pending | shipped |
| trends/activity-instant | TrendsView | App/TrendsView.swift | screen | Activity without a duration renders as a dashed `RuleMark` | `ActivityMarker` without duration | TrendsModel | Persistence · ActivityEvent | read | pending | shipped |
| trends/insulin-glyphs | TrendsView | App/TrendsView.swift | screen | Bolus circle, basal square, week/month aggregate diamond; unit count annotated above | `InsulinMarker` + `InsulinKind` + range | TrendsModel | Persistence · InsulinDose | read | pending | shipped |
| trends/stat-cards | TrendsView | App/TrendsView.swift | screen | Time-in-range and average glucose, with "—" when unavailable | `TrendsMath` returns nil | TrendsModel | Persistence · TrendsMath | read | pending | shipped |
| trends/day-meals | TrendsView | App/TrendsView.swift | screen | Day-only Meals list, populated or "no meals" | `TrendsRange.day` + meal set | TrendsModel | Persistence · MealRecord | read | pending | shipped |
| trends/day-insulin | TrendsView | App/TrendsView.swift | screen | Day-only Insulin list, populated or "no doses" | `TrendsRange.day` + dose set | TrendsModel | Persistence · InsulinDose | read | pending | shipped |
| trends/day-activity | TrendsView | App/TrendsView.swift | screen | Day-only Activity list, populated or "no activity" | `TrendsRange.day` + activity set | TrendsModel | Persistence · ActivityEvent | read | pending | shipped |
| trends/carb-bar-width | TrendsView | App/TrendsView.swift | screen | Bar width fixed at 6 pt on Day, automatic on Week/Month | `TrendsRange` | TrendsModel | Persistence · TrendsBucket | read | n/a | shipped |
| trends/options-open | TrendsView | App/TrendsView.swift | screen | `TrendsOptionsSheet` presented | options action | TrendsModel | — | none | pending | shipped |
| trends-options/scale-auto | TrendsOptionsSheet | App/TrendsOptionsSheet.swift | sheet | Scale Auto — the maximum stepper is hidden | scale mode auto | TrendsModel | — | read-write | pending | shipped |
| trends-options/scale-fixed | TrendsOptionsSheet | App/TrendsOptionsSheet.swift | sheet | Scale Fixed — "Max N mmol/L" stepper revealed, 8–25 | scale mode fixed | TrendsModel | — | read-write | pending | shipped |
| trends-options/metric-toggles | TrendsOptionsSheet | App/TrendsOptionsSheet.swift | sheet | Per-metric toggles with source captions, each on or off | metric toggle bindings | TrendsModel | Persistence · Event | read-write | pending | shipped |
| trends-options/target-band | TrendsOptionsSheet | App/TrendsOptionsSheet.swift | sheet | Target-band toggle | target-band binding | TrendsModel | — | read-write | pending | shipped |
| trends-options/macros-soon | TrendsOptionsSheet | App/TrendsOptionsSheet.swift | sheet | Disabled "Protein · Fat — soon" row | hard-coded disabled row | TrendsModel | Macros · ClinicalMacros | none | pending | shipped |
| chip-flow/single-line | ChipFlow | App/TrendsView.swift | layout | Every metric chip fits on one line | measured widths fit the proposal | TrendsModel | — | none | n/a | shipped |
| chip-flow/wrapped | ChipFlow | App/TrendsView.swift | layout | Chips wrap onto a second or later line rather than truncating to ellipsis | measured widths exceed the proposal | TrendsModel | — | none | n/a | shipped |

## Entry

**Zones:**

- **`intake`** — `enter-amount` · `preset-grid` · `recent-list`. `App/IntakeView.swift`'s
  `enterAmountButton`, `presetGrid` (adaptive quick-add tiles plus `addPresetButton`) and the Recent section.
- **`carb-entry`** — `amount-field` · `time-row` · `macro-disclosure` · `save-action`.
  `App/CarbEntrySheet.swift`: `carbField`, `timeRow`, `macroDisclosure`, and `saveButton` with
  `saveAsQuickAddButton` beneath it — both live in `save-action`, which is why `carb-entry/preset-subsheet`
  ("both save buttons latched dead") is one zone's state and not two.
- **`insulin-dose`** — `kind-picker` · `stepper` · `time-row` · `save-action`.
  `App/InsulinDoseSheet.swift`: `kindPicker`, `stepper`, `timeRow`, `saveButton`.
- **`activity`** — `kind-grid` · `duration-presets` · `time-row` · `save-action`.
  `App/ActivitySheet.swift`: `kindGrid`, `durationPresets`, `timeRow`, `saveButton`.
- **`preset-edit`** — `name-field` · `amount-field` · `macro-disclosure` · `save-action`.
  `App/QuickPresetEditSheet.swift`: `nameField`, `carbField`, `macroDisclosure`, `saveButton`.

The four entry sheets deliberately share the names they have in common — `time-row` and `save-action` across
all four, `macro-disclosure` and `amount-field` across `carb-entry` and `preset-edit`. They are the same
regions solving the same problem in more than one place, so an option for one is legible as an option for the
others, which is the whole point of declaring the vocabulary once rather than per wireframe.

| id | surface | file | kind | state | state source | view-model | data | direction | archive | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| intake/no-presets | IntakeView | App/IntakeView.swift | screen | Only the dashed add tile | `model.presets.isEmpty` | IntakeModel | Persistence · QuickPreset | read | pending | shipped |
| intake/presets | IntakeView | App/IntakeView.swift | screen | Adaptive quick-add grid plus the dashed add tile | `model.presets` non-empty | IntakeModel | Persistence · QuickPreset | read | pending | shipped |
| intake/preset-write-in-flight | IntakeView | App/IntakeView.swift | screen | Tile disabled at 0.4 opacity | `isSaving` on the preset tile (`.disabled(isSaving)`, `.opacity(isSaving ? 0.4 : 1)`) | IntakeModel | Persistence · IntakeEntry | write | pending | shipped |
| intake/quick-add-success | IntakeView | App/IntakeView.swift | screen | Success haptic; the entry appears in Recent | quick-add write completes | IntakeModel | Persistence · IntakeEntry | write | pending | shipped |
| intake/no-recent | IntakeView | App/IntakeView.swift | screen | Recent section omitted entirely | `model.entries.isEmpty` | IntakeModel | Persistence · IntakeEntry | read | pending | shipped |
| intake/recent | IntakeView | App/IntakeView.swift | screen | Recent entries listed | `model.entries` non-empty | IntakeModel | Persistence · IntakeEntry | read | pending | shipped |
| intake/row-with-macros | IntakeView | App/IntakeView.swift | screen | Entry row carries a macro summary line | `IntakeMacros` present | IntakeModel | Persistence · IntakeMacros | read | pending | shipped |
| intake/row-without-macros | IntakeView | App/IntakeView.swift | screen | No macro line — absent macros render nothing | `IntakeMacros` nil | IntakeModel | Persistence · IntakeMacros | read | pending | shipped |
| intake/swipe-delete | IntakeView | App/IntakeView.swift | screen | Swipe-to-delete on an entry row | `.swipeActions` | IntakeModel | Persistence · IntakeEntry | write | pending | shipped |
| intake/preset-context-menu | IntakeView | App/IntakeView.swift | screen | Preset context menu: Edit / Delete | long press on a preset tile | IntakeModel | Persistence · QuickPreset | write | pending | shipped |
| intake/sheet-new-entry | IntakeView | App/IntakeView.swift | screen | `CarbEntrySheet` in create mode | `IntakeSheet.newEntry` | IntakeModel | Persistence · IntakeEntry | write | pending | shipped |
| intake/sheet-edit-entry | IntakeView | App/IntakeView.swift | screen | `CarbEntrySheet` in edit mode | `IntakeSheet.editEntry(IntakeEntry)` | IntakeModel | Persistence · IntakeEntry | read-write | pending | shipped |
| intake/sheet-new-preset | IntakeView | App/IntakeView.swift | screen | `QuickPresetEditSheet` in create mode | `IntakeSheet.newPreset` | IntakeModel | Persistence · QuickPreset | write | pending | shipped |
| intake/sheet-edit-preset | IntakeView | App/IntakeView.swift | screen | `QuickPresetEditSheet` in edit mode | `IntakeSheet.editPreset(QuickPreset)` | IntakeModel | Persistence · QuickPreset | read-write | pending | shipped |
| carb-entry/create | CarbEntrySheet | App/CarbEntrySheet.swift | sheet | Title "Carbs"; Save-as-quick-add shown | create mode | CarbEntryModel | Persistence · IntakeEntry | write | pending | shipped |
| carb-entry/edit | CarbEntrySheet | App/CarbEntrySheet.swift | sheet | Title "Edit carbs"; Save-as-quick-add hidden | edit mode | CarbEntryModel | Persistence · IntakeEntry | read-write | pending | shipped |
| carb-entry/below-floor | CarbEntrySheet | App/CarbEntrySheet.swift | sheet | Save disabled, label reads plain "Save" | amount below the 1 g floor | CarbEntryModel | Persistence · IntakeEntry | none | pending | shipped |
| carb-entry/valid | CarbEntrySheet | App/CarbEntrySheet.swift | sheet | Label reads "Save N g" | amount at or above the floor | CarbEntryModel | Persistence · IntakeEntry | write | pending | shipped |
| carb-entry/macros-collapsed | CarbEntrySheet | App/CarbEntrySheet.swift | sheet | Macros disclosure collapsed | no macros on the entry | CarbEntryModel | Persistence · IntakeMacros | read | pending | shipped |
| carb-entry/macros-expanded | CarbEntrySheet | App/CarbEntrySheet.swift | sheet | Macros disclosure expanded — seeded open when macros exist | macros present | CarbEntryModel | Persistence · IntakeMacros | read-write | pending | shipped |
| carb-entry/back-dating | CarbEntrySheet | App/CarbEntrySheet.swift | sheet | Time row set to something other than now | time picker binding | CarbEntryModel | Persistence · IntakeEntry | write | pending | shipped |
| carb-entry/saving | CarbEntrySheet | App/CarbEntrySheet.swift | sheet | `MedataLoadingSymbol` inside the Save button | `model.isSaving` | CarbEntryModel | Persistence · IntakeEntry | write | pending | shipped |
| carb-entry/save-error | CarbEntrySheet | App/CarbEntrySheet.swift | sheet | Red footnote error line | `model.saveError != nil` | CarbEntryModel | Persistence · PersistenceError | read | pending | shipped |
| carb-entry/preset-subsheet | CarbEntrySheet | App/CarbEntrySheet.swift | sheet | Preset sub-sheet presented over it; both save buttons latched dead | preset sub-sheet presented | CarbEntryModel | Persistence · QuickPreset | write | pending | shipped |
| preset-edit/new | QuickPresetEditSheet | App/QuickPresetEditSheet.swift | sheet | Title "New quick-add" | create mode | — | Persistence · QuickPreset | write | pending | shipped |
| preset-edit/edit | QuickPresetEditSheet | App/QuickPresetEditSheet.swift | sheet | Title "Edit quick-add" | edit mode | — | Persistence · QuickPreset | read-write | pending | shipped |
| preset-edit/save-disabled | QuickPresetEditSheet | App/QuickPresetEditSheet.swift | sheet | Save disabled — blank name or carbs below the floor | validation fails | — | Persistence · QuickPreset | none | pending | shipped |
| preset-edit/saving | QuickPresetEditSheet | App/QuickPresetEditSheet.swift | sheet | Loading symbol in the Save button | `model.isSaving` | — | Persistence · QuickPreset | write | pending | shipped |
| preset-edit/save-error | QuickPresetEditSheet | App/QuickPresetEditSheet.swift | sheet | Red footnote error line | `model.saveError != nil` | — | Persistence · PersistenceError | read | pending | shipped |
| preset-edit/macros-collapsed | QuickPresetEditSheet | App/QuickPresetEditSheet.swift | sheet | Macros disclosure collapsed | no macros on the preset | — | Persistence · IntakeMacros | read | pending | shipped |
| preset-edit/macros-expanded | QuickPresetEditSheet | App/QuickPresetEditSheet.swift | sheet | Macros disclosure expanded | macros present | — | Persistence · IntakeMacros | read-write | pending | shipped |
| insulin-dose/default | InsulinDoseSheet | App/InsulinDoseSheet.swift | sheet | Opens at 10 U bolus, now | default seed | InsulinDoseModel | Persistence · InsulinDose | write | pending | shipped |
| insulin-dose/seeded | InsulinDoseSheet | App/InsulinDoseSheet.swift | sheet | Pre-seeded from an outstanding dose — same surface, no extra controls | `seedUnits` / `seedKind` non-nil | InsulinDoseModel | Persistence · DoseOccurrence, InsulinDose | read-write | pending | shipped |
| insulin-dose/bolus | InsulinDoseSheet | App/InsulinDoseSheet.swift | sheet | Kind picker on bolus | `InsulinKind.bolus` | InsulinDoseModel | Persistence · InsulinKind | write | pending | shipped |
| insulin-dose/basal | InsulinDoseSheet | App/InsulinDoseSheet.swift | sheet | Kind picker on basal; units preserved across the switch | `InsulinKind.basal` | InsulinDoseModel | Persistence · InsulinKind | write | pending | shipped |
| insulin-dose/step-held | InsulinDoseSheet | App/InsulinDoseSheet.swift | sheet | ± held: repeat schedule accelerating after about 2 s | `InsulinDoseModel.StepDirection` repeat | InsulinDoseModel | Persistence · InsulinDose | write | pending | shipped |
| insulin-dose/back-dating | InsulinDoseSheet | App/InsulinDoseSheet.swift | sheet | Time row set to something other than now | time picker binding | InsulinDoseModel | Persistence · InsulinDose | write | pending | shipped |
| insulin-dose/saving | InsulinDoseSheet | App/InsulinDoseSheet.swift | sheet | Loading symbol in the Save button | `model.isSaving` | InsulinDoseModel | Persistence · InsulinDose | write | pending | shipped |
| insulin-dose/save-error | InsulinDoseSheet | App/InsulinDoseSheet.swift | sheet | Red footnote error line | `model.saveError != nil` | InsulinDoseModel | Persistence · PersistenceError | read | pending | shipped |
| insulin-dose/detent | InsulinDoseSheet | App/InsulinDoseSheet.swift | sheet | Medium detent with a drag indicator, no close button | `.presentationDetents([.medium])` | InsulinDoseModel | — | none | n/a | shipped |
| activity/most-recent-kind | ActivitySheet | App/ActivitySheet.swift | sheet | Opens on the most recently used kind, tile filled `seriesActivity` | `model.selectedKind` seeded from history | ActivityModel | Persistence · ActivityKind | read | pending | shipped |
| activity/kind-grid | ActivitySheet | App/ActivitySheet.swift | sheet | Seven kind tiles always visible: swim, waterpolo, cycle, run, walk, gym, other | `ActivityKind.allCases` | ActivityModel | Persistence · ActivityKind | read | pending | shipped |
| activity/no-duration | ActivitySheet | App/ActivitySheet.swift | sheet | No duration selected; the Save label omits the duration | duration nil | ActivityModel | Persistence · ActivityEvent | write | pending | shipped |
| activity/duration-selected | ActivitySheet | App/ActivitySheet.swift | sheet | Preset chip inverted; Save label reads "… · N min" | `ActivityModel.durationPresets` selection | ActivityModel | Persistence · ActivityEvent | write | pending | shipped |
| activity/duration-cleared | ActivitySheet | App/ActivitySheet.swift | sheet | Preset re-tapped to clear — back to no duration | selection toggled off | ActivityModel | Persistence · ActivityEvent | write | pending | shipped |
| activity/back-dating | ActivitySheet | App/ActivitySheet.swift | sheet | Time row set to something other than now | time picker binding | ActivityModel | Persistence · ActivityEvent | write | pending | shipped |
| activity/saving | ActivitySheet | App/ActivitySheet.swift | sheet | Loading symbol in the Save button | `model.isSaving` | ActivityModel | Persistence · ActivityEvent | write | pending | shipped |
| activity/save-error | ActivitySheet | App/ActivitySheet.swift | sheet | Red footnote error line | `model.saveError != nil` | ActivityModel | Persistence · PersistenceError | read | pending | shipped |

## Settings

**Zones:**

- **`settings`** — `account` · `food-database` · `glucose-data` · `capture` · `insulin` · `dose-schedule` ·
  `export` · `developer` · `debug`. One zone per `Section` of `App/SettingsView.swift`, in body order. The
  section names are the zone names because a settings screen is its section order: an option here is a
  reordering or a merge, and both are sayable as zone choices. `debug` is the `#if DEBUG` section, which is
  why `settings/debug-absent` is that zone being empty rather than a different screen.
- **`dose-schedule-settings`** — `schedule-rows` · `reminder-plan`. `App/DoseScheduleSettingsSection.swift`:
  the per-schedule rows (time, enable, units, kind) and the plan controls beneath them (interval stepper,
  follow-up stepper, derived cutoff label, surface picker). It fills `settings`' `dose-schedule` zone.

The developer and glucose surfaces reached from here — `GlucoseConnectionsView`, `GlucoseImportView`,
`BenchmarkView`, `EstimationLogView`, `AboutView` and their rows and detail screens — declare none. They are
read surfaces whose content is the record they display; no design option is pending on any of them, and
declaring zones nobody will use is how a convention becomes noise.

| id | surface | file | kind | state | state source | view-model | data | direction | archive | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| settings/account-disabled | SettingsView | App/SettingsView.swift | screen | Account row permanently disabled | `.disabled(true)` | — | — | none | pending | shipped |
| settings/food-databases | SettingsView | App/SettingsView.swift | screen | Food database section listing CoFID and AFCD | static rows | — | Foods · FoodDatabase | read | pending | shipped |
| settings/capture-default-path | SettingsView | App/SettingsView.swift | screen | Default path picker (1-view / 2-view), resolving an unset key from device LiDAR capability | `SettingsKeys.captureMode` via `captureModeBinding` | — | CaptureKit · DepthMap | read-write | pending | shipped |
| settings/always-include-card | SettingsView | App/SettingsView.swift | screen | "Always include card" toggle | `SettingsKeys.alwaysIncludeCard` | — | CardDetection · card pose | read-write | pending | shipped |
| settings/insulin-defaults | SettingsView | App/SettingsView.swift | screen | Bolus and basal insulin product name fields | `SettingsKeys.insulinTypeBolusDefault` / `…BasalDefault` | — | Persistence · InsulinDose | read-write | pending | shipped |
| settings/export-idle | SettingsView | App/SettingsView.swift | screen | Export row shows a label with the share glyph | `isExporting == false` | — | Persistence · PersistenceStore (archive) | read | pending | shipped |
| settings/export-in-flight | SettingsView | App/SettingsView.swift | screen | `MedataLoadingSymbol` replaces the label; the button is disabled | `isExporting == true` | — | Persistence · PersistenceStore (archive) | read | pending | shipped |
| settings/export-failed | SettingsView | App/SettingsView.swift | screen | Red footnote line | `exportError != nil` | — | Persistence · PersistenceError | read | pending | shipped |
| settings/export-succeeded | SettingsView | App/SettingsView.swift | screen | `ShareSheet` presented over Settings | `archiveFile != nil` | — | Persistence · PersistenceStore (archive) | read | pending | shipped |
| settings/glucose-sources-open | SettingsView | App/SettingsView.swift | screen | `GlucoseConnectionsView` presented | `showsGlucoseSources == true` | GlucoseConnectionsModel | GlucoseIngestion · GlucoseConnectionState | read | pending | shipped |
| settings/glucose-import-open | SettingsView | App/SettingsView.swift | screen | `GlucoseImportView` presented | `showsGlucoseImport == true` | GlucoseImportModel | GlucoseGraph · Extraction | read | pending | shipped |
| settings/developer-links | SettingsView | App/SettingsView.swift | screen | Estimation log / Benchmark / About navigation links — present in Release too | unconditional section | — | Persistence · EstimationOutcome | read | pending | shipped |
| settings/debug-section | SettingsView | App/SettingsView.swift | screen | Seed demo glucose + Clear all data | `#if DEBUG` | — | Persistence · BslReading | write | pending | shipped |
| settings/debug-absent | SettingsView | App/SettingsView.swift | screen | Debug section absent in Release | `#if DEBUG` false | — | — | none | pending | shipped |
| settings/seeding | SettingsView | App/SettingsView.swift | screen | Loading symbol on the seed button | `isSeeding == true` | — | Persistence · BslReading | write | pending | shipped |
| settings/clearing | SettingsView | App/SettingsView.swift | screen | Loading symbol on the clear button | `isClearing == true` | — | Persistence · PersistenceStore | write | pending | shipped |
| settings/clear-confirm | SettingsView | App/SettingsView.swift | screen | Destructive confirmation dialog | `confirmsClear == true` | — | Persistence · PersistenceStore | write | pending | shipped |
| dose-schedule-settings/no-schedules | SettingsView.doseScheduleSection | App/DoseScheduleSettingsSection.swift | component | Only the Add row | `doseSchedule.schedules.isEmpty` | DoseScheduleModel | Persistence · ScheduledDose | read | pending | shipped |
| dose-schedule-settings/schedule-rows | SettingsView.doseScheduleSection | App/DoseScheduleSettingsSection.swift | component | Time picker, enable toggle, units stepper 1–60, kind segmented picker | `scheduleRow(_ schedule: ScheduledDose)` | DoseScheduleModel | Persistence · ScheduledDose, InsulinKind | read-write | pending | shipped |
| dose-schedule-settings/schedule-disabled | SettingsView.doseScheduleSection | App/DoseScheduleSettingsSection.swift | component | Row present but toggled off — distinct from deleted | `enabledBinding(for:)` false | DoseScheduleModel | Persistence · ScheduledDose | read-write | pending | shipped |
| dose-schedule-settings/swipe-delete | SettingsView.doseScheduleSection | App/DoseScheduleSettingsSection.swift | component | Swipe-to-delete on a schedule row | `.swipeActions` | DoseScheduleModel | Persistence · ScheduledDose | write | pending | shipped |
| dose-schedule-settings/interval-stepper | SettingsView.doseScheduleSection | App/DoseScheduleSettingsSection.swift | component | Reminder interval stepper, 5–240 min | `intervalBinding` over `ReminderPlan` | DoseScheduleModel | Persistence · ReminderPlan | read-write | pending | shipped |
| dose-schedule-settings/follow-up-stepper | SettingsView.doseScheduleSection | App/DoseScheduleSettingsSection.swift | component | Follow-up count stepper, 0–12 | `followUpBinding` over `ReminderPlan` | DoseScheduleModel | Persistence · ReminderPlan | read-write | pending | shipped |
| dose-schedule-settings/cutoff-label | SettingsView.doseScheduleSection | App/DoseScheduleSettingsSection.swift | component | Derived "Stops after" label: "—" / "N min" / "N h" / "N.N h" | `cutoffLabel` | DoseScheduleModel | Persistence · DoseScheduleMath | read | pending | shipped |
| dose-schedule-settings/surface-switch | SettingsView.doseScheduleSection | App/DoseScheduleSettingsSection.swift | component | Surface picker: Card vs Dose control — the developer-phase attempt switch | `DoseScheduleSettings.SurfaceStyle.banner` / `.doseRoute` | DoseScheduleModel | — | read-write | pending | shipped |
| about/static | AboutView | App/AboutView.swift | screen | Sole legal/attribution surface: data-source attributions, method paragraph, not-a-medical-device statement | single static state, exempt from the minimal-wording rule | — | Foods · FoodDatabase (attribution) | read | pending | shipped |
| glucose-connections/not-connected | GlucoseConnectionsView | App/GlucoseConnectionsView.swift | sheet | Source shows "Not connected" with a Connect button | `GlucoseConnectionState.notConnected` | GlucoseConnectionsModel | GlucoseIngestion · GlucoseConnectionState | read | pending | shipped |
| glucose-connections/connected | GlucoseConnectionsView | App/GlucoseConnectionsView.swift | sheet | "Connected", optional "Last reading", Disconnect | `GlucoseConnectionState.connected(lastReadingAt:)` | GlucoseConnectionsModel | GlucoseIngestion · GlucoseSample | read | pending | shipped |
| glucose-connections/failed | GlucoseConnectionsView | App/GlucoseConnectionsView.swift | sheet | "Failed" + red reason line; the credential form stays visible for in-place repair | `GlucoseConnectionState.failed(reason:lastSuccessAt:)` | GlucoseConnectionsModel | LibreLinkUpKit · LibreLinkUpError | read | pending | shipped |
| glucose-connections/busy | GlucoseConnectionsView | App/GlucoseConnectionsView.swift | sheet | Buttons disabled while a connect or disconnect is in flight | busy flag on the model | GlucoseConnectionsModel | GlucoseIngestion · IngestionCoordinator | read | pending | shipped |
| glucose-connections/llu-last-fetch | GlucoseConnectionsView | App/GlucoseConnectionsView.swift | sheet | LibreLinkUp connected, with a last-fetch timestamp row | `LibreLinkUpSharedState` last success | GlucoseConnectionsModel | LibreLinkUpKit · LibreLinkUpSession | read | pending | shipped |
| glucose-connections/llu-credentials-empty | GlucoseConnectionsView | App/GlucoseConnectionsView.swift | sheet | Email/password empty → Connect disabled | credential fields empty | GlucoseConnectionsModel | LibreLinkUpKit · LibreLinkUpCredentials | write | pending | shipped |
| glucose-connections/discrepancies | GlucoseConnectionsView | App/GlucoseConnectionsView.swift | sheet | Discrepancy count row, shown only when greater than zero | `model.discrepancyCounts[sourceID] > 0` | GlucoseConnectionsModel | Persistence · BslIngestSummary | read | pending | shipped |
| glucose-import/idle | GlucoseImportView | App/GlucoseImportView.swift | sheet | PhotosPicker plus the explanatory footer, no results | `results.isEmpty`, `isProcessing == false` | GlucoseImportModel | GlucoseGraph · Bitmap | read | pending | shipped |
| glucose-import/processing | GlucoseImportView | App/GlucoseImportView.swift | sheet | "Processing N of M…" with the loading symbol; picker disabled | `isProcessing == true` | GlucoseImportModel | GlucoseGraph · GlucoseGraphExtractor | read | pending | shipped |
| glucose-import/results | GlucoseImportView | App/GlucoseImportView.swift | sheet | One result row per imported screenshot | `results` non-empty | GlucoseImportModel | GlucoseGraph · Extraction | read | pending | shipped |
| row-import-result/stored | ResultRow | App/GlucoseImportView.swift | row | Green check, counts, agreeing/discrepant split | `ImageResult.Outcome.stored(BslIngestSummary)` | GlucoseImportModel | Persistence · BslIngestSummary | read | pending | shipped |
| row-import-result/skipped-duplicate | ResultRow | App/GlucoseImportView.swift | row | Grey u-turn, "Already imported — skipped" | `ImageResult.Outcome.skippedDuplicate` | GlucoseImportModel | Persistence · BslReading | read | pending | shipped |
| row-import-result/rejected | ResultRow | App/GlucoseImportView.swift | row | Red x plus the rejection reason | `ImageResult.Outcome.rejected(reason:)` | GlucoseImportModel | GlucoseGraph · RejectImage | read | pending | shipped |
| row-import-result/failed | ResultRow | App/GlucoseImportView.swift | row | Red x plus the failure message | `ImageResult.Outcome.failed(message:)` | GlucoseImportModel | GlucoseGraph · Bitmap.DecodeError | read | pending | shipped |
| row-import-result/warnings | ResultRow | App/GlucoseImportView.swift | row | Zero or more orange-triangle warning lines under the outcome | `ImageResult.warnings` non-empty | GlucoseImportModel | GlucoseGraph · Extraction | read | pending | shipped |
| benchmark/no-report | BenchmarkView | App/BenchmarkView.swift | screen | Report section absent | no report computed for the lineage | BenchmarkModel (in App/BenchmarkView.swift) | Benchmark · Report | read | pending | shipped |
| benchmark/report-valid | BenchmarkView | App/BenchmarkView.swift | screen | Report present and headline-valid | `Benchmark.Report` headline valid | BenchmarkModel (in App/BenchmarkView.swift) | Benchmark · Report | read | pending | shipped |
| benchmark/report-invalid | BenchmarkView | App/BenchmarkView.swift | screen | Warning naming N-below-floor and/or missing staples | headline invalid (`BenchmarkStaples`) | BenchmarkModel (in App/BenchmarkView.swift) | Benchmark · BenchmarkStaples | read | pending | shipped |
| benchmark/metrics-unavailable | BenchmarkView | App/BenchmarkView.swift | screen | "—" for MAE / MAPE / within ±10 g | metrics nil on `Report` | BenchmarkModel (in App/BenchmarkView.swift) | Benchmark · Report.MealRow | read | pending | shipped |
| benchmark/verdict | BenchmarkView | App/BenchmarkView.swift | screen | Verdict: better than / within noise of / worse than the SNAQ anchor / insufficient data | `Report.AnchorVerdict` via `verdictText(_:)` | BenchmarkModel (in App/BenchmarkView.swift) | Benchmark · Report.AnchorVerdict, BenchmarkAnchors | read | pending | shipped |
| benchmark/attempts-line | BenchmarkView | App/BenchmarkView.swift | screen | Attempts line, with and without an undecodable count | undecodable attempt count > 0 | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · EstimationOutcome | read | pending | shipped |
| benchmark/meals-empty | BenchmarkView | App/BenchmarkView.swift | screen | "No benchmark meals" | `BenchmarkMeal` set empty | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · BenchmarkMeal | read | pending | shipped |
| benchmark/meals-populated | BenchmarkView | App/BenchmarkView.swift | screen | One row per meal, with truth / items / fidelity / attempts | `BenchmarkMeal` set non-empty | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · BenchmarkMeal | read | pending | shipped |
| benchmark/editor-open | BenchmarkView | App/BenchmarkView.swift | screen | `BenchmarkMealEditorSheet` presented, new or edit | `MealEditorTarget` non-nil | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · BenchmarkMeal | write | pending | shipped |
| row-benchmark-meal/singular | BenchmarkMealRow | App/BenchmarkView.swift | row | Singular item and attempt counts | count == 1 | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · BenchmarkMeal | read | pending | shipped |
| row-benchmark-meal/plural | BenchmarkMealRow | App/BenchmarkView.swift | row | Plural item and attempt counts | count != 1 | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · BenchmarkMeal | read | pending | shipped |
| row-benchmark-meal/fidelity-weighed | BenchmarkMealRow | App/BenchmarkView.swift | row | Subtitle names weighed truth | `BenchmarkFidelity.weighed` | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · BenchmarkFidelity | read | pending | shipped |
| row-benchmark-meal/fidelity-package | BenchmarkMealRow | App/BenchmarkView.swift | row | Subtitle names package truth | `BenchmarkFidelity.package` | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · BenchmarkFidelity | read | pending | shipped |
| row-benchmark-meal/capture-launch | BenchmarkMealRow | App/BenchmarkView.swift | row | Tagged Capture launch button beside the edit tap target | `onCapture` with `benchmarkMealID` set | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · BenchmarkMeal | read | pending | shipped |
| benchmark-editor/new | BenchmarkMealEditorSheet | App/BenchmarkView.swift | sheet | Title "New meal", Save | create mode | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · BenchmarkMeal | write | pending | shipped |
| benchmark-editor/edit-no-attempts | BenchmarkMealEditorSheet | App/BenchmarkView.swift | sheet | Title "Edit meal", Save — the same id is reused | edit mode, attempt count 0 | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · BenchmarkMeal | read-write | pending | shipped |
| benchmark-editor/edit-with-attempts | BenchmarkMealEditorSheet | App/BenchmarkView.swift | sheet | "Has attempts — saves as a new meal" note, "Save new" button | edit mode, attempt count > 0 | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · EstimationOutcome | read-write | pending | shipped |
| benchmark-editor/cannot-save | BenchmarkMealEditorSheet | App/BenchmarkView.swift | sheet | Save disabled — blank name, no items, or an item under 1 g | `canSave == false` | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · BenchmarkMealItem | none | pending | shipped |
| benchmark-editor/saving | BenchmarkMealEditorSheet | App/BenchmarkView.swift | sheet | Save in flight | saving flag | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · BenchmarkMeal | write | pending | shipped |
| benchmark-editor/save-error | BenchmarkMealEditorSheet | App/BenchmarkView.swift | sheet | Error line: class unresolvable / grams out of range / generic | save error | BenchmarkModel (in App/BenchmarkView.swift) | Segmentation · ClassPalette | read | pending | shipped |
| benchmark-editor/swipe-delete-item | BenchmarkMealEditorSheet | App/BenchmarkView.swift | sheet | Swipe-to-delete on a palette-class item row | `.swipeActions` | BenchmarkModel (in App/BenchmarkView.swift) | Persistence · BenchmarkMealItem | write | pending | shipped |
| estimation-log/attempts-empty | EstimationLogView | App/EstimationLogView.swift | screen | "No attempts recorded" | outcome set empty | EstimationLogModel (in App/EstimationLogView.swift) | Persistence · EstimationOutcome | read | pending | shipped |
| estimation-log/attempts-populated | EstimationLogView | App/EstimationLogView.swift | screen | Attempts list populated | outcome set non-empty | EstimationLogModel (in App/EstimationLogView.swift) | Persistence · EstimationOutcome | read | pending | shipped |
| estimation-log/corrections-empty | EstimationLogView | App/EstimationLogView.swift | screen | "No corrections recorded" | correction set empty | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · correction record | read | pending | shipped |
| estimation-log/corrections-populated | EstimationLogView | App/EstimationLogView.swift | screen | Corrections list populated | correction set non-empty | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · correction record | read | pending | shipped |
| estimation-log/export-idle | EstimationLogView | App/EstimationLogView.swift | screen | Share glyph in the toolbar | export not in flight | EstimationLogModel (in App/EstimationLogView.swift) | Persistence · EstimationOutcome | read | pending | shipped |
| estimation-log/export-in-flight | EstimationLogView | App/EstimationLogView.swift | screen | Loading symbol; the menu is disabled | export in flight (`LogExport`) | EstimationLogModel (in App/EstimationLogView.swift) | Persistence · EstimationOutcome | read | pending | shipped |
| estimation-log/export-error | EstimationLogView | App/EstimationLogView.swift | screen | Red footnote line | export error | EstimationLogModel (in App/EstimationLogView.swift) | Persistence · PersistenceError | read | pending | shipped |
| estimation-log/export-share | EstimationLogView | App/EstimationLogView.swift | screen | `ShareSheet` presented with the JSON/JSONL file | `LogExportFile` non-nil | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · export envelope | read | pending | shipped |
| row-outcome/success | OutcomeRow | App/EstimationLogView.swift | row | Accent check, title "Success" | `EstimationOutcomeKind` success | EstimationLogModel (in App/EstimationLogView.swift) | Persistence · EstimationOutcome | read | pending | shipped |
| row-outcome/refused-decoded | OutcomeRow | App/EstimationLogView.swift | row | "domain: case" from the decoded `FailureEnvelope` | envelope decodes | EstimationLogModel (in App/EstimationLogView.swift) | Pipeline · EstimationFailure | read | pending | shipped |
| row-outcome/refused-undecodable | OutcomeRow | App/EstimationLogView.swift | row | Title falls back to "Refused" | envelope JSON undecodable | EstimationLogModel (in App/EstimationLogView.swift) | Pipeline · EstimationFailure | read | pending | shipped |
| row-outcome/benchmark-tagged | OutcomeRow | App/EstimationLogView.swift | row | Trailing "benchmark" capsule | `EstimationOutcome` carries a benchmark meal id | EstimationLogModel (in App/EstimationLogView.swift) | Persistence · BenchmarkMeal | read | pending | shipped |
| row-correction/rejected | CorrectionRow | App/EstimationLogView.swift | row | "X — rejected" | correction record: reject | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · correction record | read | pending | shipped |
| row-correction/not-in-database | CorrectionRow | App/EstimationLogView.swift | row | "X — not in database" | correction record: absent | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · correction record | read | pending | shipped |
| row-correction/relabel | CorrectionRow | App/EstimationLogView.swift | row | "X → Y" | correction record: relabel | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · correction record | read | pending | shipped |
| row-correction/relabel-amount | CorrectionRow | App/EstimationLogView.swift | row | "X → Y — amount" | correction record: relabel + amount | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · correction record | read | pending | shipped |
| row-correction/amount | CorrectionRow | App/EstimationLogView.swift | row | "X — amount" | correction record: amount only | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · correction record | read | pending | shipped |
| row-correction/picker-dismissed | CorrectionRow | App/EstimationLogView.swift | row | "X — picker dismissed" | correction record: picker dismissed | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · correction record | read | pending | shipped |
| row-correction/capture-abandoned | CorrectionRow | App/EstimationLogView.swift | row | "X — capture abandoned" | correction record: capture abandoned | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · correction record | read | pending | shipped |
| row-correction/unchanged | CorrectionRow | App/EstimationLogView.swift | row | "X — unchanged" | correction record: unchanged | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · correction record | read | pending | shipped |
| outcome-detail/with-failure | EstimationOutcomeDetailView | App/EstimationLogView.swift | screen | Fields plus a pretty-printed selectable failure JSON section | refused attempt | EstimationLogModel (in App/EstimationLogView.swift) | Pipeline · EstimationFailure | read | pending | shipped |
| outcome-detail/without-failure | EstimationOutcomeDetailView | App/EstimationLogView.swift | screen | No failure section | successful attempt | EstimationLogModel (in App/EstimationLogView.swift) | Persistence · EstimationOutcome | read | pending | shipped |
| outcome-detail/id-rows | EstimationOutcomeDetailView | App/EstimationLogView.swift | screen | Meal id and benchmark meal id rows, each present or absent | ids nil or non-nil | EstimationLogModel (in App/EstimationLogView.swift) | Persistence · MealRecord, BenchmarkMeal | read | pending | shipped |
| outcome-detail/raw-json | EstimationOutcomeDetailView | App/EstimationLogView.swift | screen | JSON that fails to parse renders raw | pretty-print throws | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · measurements JSON | read | pending | shipped |
| correction-detail/pretty | CorrectionRecordDetailView | App/EstimationLogView.swift | screen | Identity fields plus the pretty-printed protobuf-JSON blob | serialisation succeeds | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · correction record | read | pending | shipped |
| correction-detail/raw | CorrectionRecordDetailView | App/EstimationLogView.swift | screen | Raw fallback | serialisation fails | EstimationLogModel (in App/EstimationLogView.swift) | PortableContracts · correction record | read | pending | shipped |
| share-sheet/system | ShareSheet | App/ShareSheet.swift | representable | The system `UIActivityViewController` over the presenting surface — archive, estimation-log and corrections export | `UIViewControllerRepresentable`, one state | — | Persistence · PersistenceStore (archive) | read | pending | shipped |

## Shared chrome

**Zones:** none declared. A close button, a loading symbol and three brand-mark paths are elements that sit
inside other surfaces' zones. There is nothing to point at inside them that the state rows do not already
name.

| id | surface | file | kind | state | state source | view-model | data | direction | archive | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| close-cover/default | CloseCoverButton | App/MealRouting.swift | control | Toolbar xmark on Records / Graph / Settings / Intake — covers have no drag-to-dismiss | default styling | — | — | none | pending | shipped |
| close-cover/capture | CloseCoverButton | App/MealRouting.swift | control | 40 pt `captureChromeBG` circle with a white glyph | capture styling variant | — | — | none | pending | shipped |
| loading-symbol/loop | MedataLoadingSymbol | App/MedataLoadingSymbol.swift | component | Draw-in / erase-out forever — the indeterminate spinner | `MedataLoadingSymbol.Mode.loop` | — | — | none | pending | shipped |
| loading-symbol/once | MedataLoadingSymbol | App/MedataLoadingSymbol.swift | component | Draw in once and hold the finished mark | `MedataLoadingSymbol.Mode.once` | — | — | none | pending | shipped |
| loading-symbol/reduce-motion | MedataLoadingSymbol | App/MedataLoadingSymbol.swift | component | Finished mark, no animation | `\.accessibilityReduceMotion` | — | — | none | pending | shipped |
| loading-symbol/sizes | MedataLoadingSymbol | App/MedataLoadingSymbol.swift | component | 22 pt inline in buttons and rows, 64 pt default, 120 pt at launch | `size` parameter | — | — | none | pending | shipped |
| symbol-bowl/path | MedataSymbolGeometry.Bowl | App/MedataLoadingSymbol.swift | shape | The bowl arc of the brand mark | `MedataSymbolGeometry.Bowl` path maths | — | — | none | n/a | shipped |
| symbol-bar/path | MedataSymbolGeometry.Bar | App/MedataLoadingSymbol.swift | shape | One bar of the brand mark | `MedataSymbolGeometry.Bar` path maths | — | — | none | n/a | shipped |
| symbol-dot/path | MedataSymbolGeometry.Dot | App/MedataLoadingSymbol.swift | shape | The dot of the brand mark | `MedataSymbolGeometry.Dot` path maths | — | — | none | n/a | shipped |

## Notifications

**Zones:** none declared. A notification's layout belongs to the system: the app supplies a title, a body and
a set of actions, and cannot rearrange them. What can be decided is the copy and which actions exist, and
both are already carried by the state rows.

| id | surface | file | kind | state | state source | view-model | data | direction | archive | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| dose-notification/initial | (no struct — built by `DoseScheduleModel.reminderTitle` / `.reminderBody`, armed via `LocalReminderRequest`) | App/DoseScheduleModel.swift | notification | Title "<N U> <kind>", body "Due HH:MM" | first `UNCalendarNotificationTrigger` for the occurrence | DoseScheduleModel | Persistence · ScheduledDose, DoseOccurrence | read | pending | shipped |
| dose-notification/repeats | (no struct — same construction site) | App/DoseScheduleModel.swift | notification | Up to `followUpCount` repeats at `intervalMinutes` | `ReminderPlan` follow-ups | DoseScheduleModel | Persistence · ReminderPlan | read | pending | shipped |
| dose-notification/action-log | (no struct — action defined in `DoseNotificationCategory`) | App/DoseScheduleModel.swift | notification | "Log" action with no options: the app wakes in the background, nothing appears on screen | `DoseNotificationCategory.logNominal` (`"LOG_NOMINAL"`), `options: []` | DoseScheduleModel | Persistence · InsulinDose, DoseOccurrence | write | n/a | shipped |
| dose-notification/action-adjust | (no struct — action defined in `DoseNotificationCategory`) | App/DoseScheduleModel.swift | notification | "Adjust" action, foreground: routes to the pre-seeded insulin sheet | `DoseNotificationCategory.adjust` (`"ADJUST"`), `options: [.foreground]` | DoseScheduleModel | Persistence · DoseOccurrence | read | pending | shipped |
| dose-notification/default-action | (no struct — handled by `DoseNotificationDelegate`) | App/DoseNotificationDelegate.swift | notification | Tapping the banner behaves as Adjust | default action identifier | DoseScheduleModel | Persistence · DoseOccurrence | read | pending | shipped |
| dose-notification/stale-action | (no struct — handled by `DoseNotificationDelegate`) | App/DoseNotificationDelegate.swift | notification | Action on an already-closed occurrence writes nothing | occurrence no longer open | DoseScheduleModel | Persistence · OccurrenceOutcome | none | n/a | shipped |
| dose-notification/authorisation-refused | (no struct — `LocalReminderScheduler.authorisationStatus`) | App/LocalReminderScheduler.swift | notification | No notification is delivered; the home surface still works, because it reads the ledger | `UNAuthorizationStatus` denied | DoseScheduleModel | Persistence · DoseOccurrence | read | n/a | shipped |

## Widgets

**Zones:** none declared. The widget family **is** the layout — `accessoryCircular`, `accessoryRectangular`,
`accessoryInline`, `systemSmall` — and each family is already a state row. A zone list would duplicate the
family list without adding a way to point at anything.

| id | surface | file | kind | state | state source | view-model | data | direction | archive | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| widget-bundle/three-kinds | MeDataWidgetBundle | MeData/MeDataWidgets/MeDataWidgets.swift | bundle | The extension vends exactly three widget kinds: insulin, capture, glucose | `@main` `WidgetBundle` body | — | — | none | n/a | shipped |
| widget-dose/configuration | InsulinDoseWidget | MeData/MeDataWidgets/MeDataWidgets.swift | widget | Kind `ie.medata.widget.insulin`, display name "dose", deep link `medata://insulin/add`, families accessoryCircular / accessoryRectangular / systemSmall | `StaticConfiguration` + `LauncherProvider` | — | — | none | pending | shipped |
| widget-capture/configuration | CaptureWidget | MeData/MeDataWidgets/MeDataWidgets.swift | widget | Kind `ie.medata.widget.capture`, display name "Capture", deep link `medata://capture`, same three families | `StaticConfiguration` + `LauncherProvider` | — | — | none | pending | shipped |
| widget-glucose/configuration | GlucoseWidget | MeData/MeDataWidgets/GlucoseWidget.swift | widget | Kind `GlucoseSnapshotStore.widgetKind`, deep link `medata://graph`, families accessoryCircular / accessoryRectangular / accessoryInline / systemSmall | `StaticConfiguration` + `GlucoseProvider` | — | GlucoseWidgetShared · GlucoseSnapshot | read | pending | shipped |
| widget-glucose/timeline-refresh | GlucoseProvider | MeData/MeDataWidgets/GlucoseWidget.swift | widget | Next reload never sooner than `LibreLinkUpPolling.interval` — WidgetKit wakes come out of a daily budget | `GlucoseTimeline.nextBoundary` clamped | — | LibreLinkUpKit · LibreLinkUpPolling | read | n/a | shipped |
| launcher-view/circular | LauncherView | MeData/MeDataWidgets/MeDataWidgets.swift | component | Glyph only; the word lives in the accessibility label | `widgetFamily == .accessoryCircular` | — | — | none | pending | shipped |
| launcher-view/rectangular | LauncherView | MeData/MeDataWidgets/MeDataWidgets.swift | component | Glyph and label inline | `widgetFamily == .accessoryRectangular` | — | — | none | pending | shipped |
| launcher-view/small | LauncherView | MeData/MeDataWidgets/MeDataWidgets.swift | component | 40 pt glyph over the label | `widgetFamily == .systemSmall` (default branch) | — | — | none | pending | shipped |
| launcher-view/kind-dose | LauncherView | MeData/MeDataWidgets/MeDataWidgets.swift | component | syringe glyph, label "dose" | `symbol: "syringe"` | — | — | none | pending | shipped |
| launcher-view/kind-capture | LauncherView | MeData/MeDataWidgets/MeDataWidgets.swift | component | camera.fill glyph, label "Capture" | `symbol: "camera.fill"` | — | — | none | pending | shipped |
| glucose-widget-view/circular-fresh | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | 20 pt value, status token, 15 pt arrow | `.accessoryCircular` + `GlucoseRender.fresh(value:status:trend:)` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/circular-stale | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | Value alone at 0.5 opacity | `.accessoryCircular` + `GlucoseRender.stale(value:age:)` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/circular-last-reading | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | Clock glyph over the age, at 0.5 opacity | `.accessoryCircular` + `GlucoseRender.lastReading(age:)` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/circular-never | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | Em-dash at 0.5 opacity | `.accessoryCircular` + `GlucoseRender.neverRecorded` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/rectangular-fresh | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | Value + token + arrow on one baseline, live age beneath | `.accessoryRectangular` + `GlucoseRender.fresh` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/rectangular-stale | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | Value over a baked age string, 0.5 opacity | `.accessoryRectangular` + `GlucoseRender.stale` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/rectangular-last-reading | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | "Last reading" over the age, 0.5 opacity | `.accessoryRectangular` + `GlucoseRender.lastReading` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/rectangular-never | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | "No glucose reading", 0.5 opacity | `.accessoryRectangular` + `GlucoseRender.neverRecorded` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/inline-fresh | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | Single inline line: value, token, arrow | `.accessoryInline` + `GlucoseRender.fresh` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/inline-stale | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | Inline value with its age | `.accessoryInline` + `GlucoseRender.stale` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/inline-last-reading | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | Inline "Last reading" with its age | `.accessoryInline` + `GlucoseRender.lastReading` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/inline-never | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | Inline no-reading text | `.accessoryInline` + `GlucoseRender.neverRecorded` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/small-fresh | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | StandBy tile: large value, token, arrow, live age | `.systemSmall` + `GlucoseRender.fresh` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/small-stale | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | StandBy tile at 0.5 opacity with a baked age | `.systemSmall` + `GlucoseRender.stale` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/small-last-reading | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | StandBy tile showing only how long ago the last reading was | `.systemSmall` + `GlucoseRender.lastReading` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/small-never | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | StandBy tile with no reading — also the gallery placeholder | `.systemSmall` + `GlucoseRender.neverRecorded` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/status-lo | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | "LO" token beside the value | `GlucoseBandStatus.low` | — | GlucoseWidgetShared · GlucoseBandStatus | read | pending | shipped |
| glucose-widget-view/status-in-range | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | No token — in range | `GlucoseBandStatus` in range | — | GlucoseWidgetShared · GlucoseBandStatus | read | pending | shipped |
| glucose-widget-view/status-hi | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | "HI" token beside the value | `GlucoseBandStatus.high` | — | GlucoseWidgetShared · GlucoseBandStatus | read | pending | shipped |
| glucose-widget-view/trend-absent | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | No arrow — the snapshot carries no trend | `GlucoseTrend?` nil | — | GlucoseWidgetShared · GlucoseTrend | read | pending | shipped |
| glucose-widget-view/full-colour | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | Red/orange tint applied | `widgetRenderingMode == .fullColor` | — | GlucoseWidgetShared · GlucoseBandStatus | read | pending | shipped |
| glucose-widget-view/vibrant | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | Monochrome — tint suppressed, opacity carries staleness instead | `widgetRenderingMode == .vibrant` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |
| glucose-widget-view/gallery-placeholder | GlucoseWidgetView | MeData/MeDataWidgets/GlucoseWidget.swift | component | Gallery placeholder is `neverRecorded` — no fabricated specimen reading | `GlucoseProvider.placeholder(in:)` | — | GlucoseWidgetShared · GlucoseRender | read | pending | shipped |

---

## Exemptions

Rows below are deliberately **not** catalogued as surfaces. `tools/check_surfaces.sh` reads this section: a
type named here satisfies the "has a row or an explicit `exempt:` marker with a reason" rule. The grammar is
`exempt: <Name>` — backticks optional, several names comma-separated — with the reason in the same row; a
marker with no reason fails the check rather than excusing anything.

None of the 33 entries below conforms to one of the six protocols the check scans, so it reports `exempt=0`
today. They are written down anyway: without them, the next reader has to re-derive why each of these types
is not a surface.

| exempt | file | reason |
| --- | --- | --- |
| exempt: `TrendsChartPoint` | App/TrendsModel.swift | Plain `Identifiable` chart datum. Renders nothing on its own. |
| exempt: `InsulinEntry` | App/TrendsModel.swift | Plain datum. |
| exempt: `InsulinMarker` | App/TrendsModel.swift | Plain datum feeding a Swift Charts mark; the mark's states are catalogued under `trends/insulin-glyphs`. |
| exempt: `ActivityEntry` | App/TrendsModel.swift | Plain datum. |
| exempt: `ActivityMarker` | App/TrendsModel.swift | Plain datum; its two renderings are `trends/activity-shaded` and `trends/activity-instant`. |
| exempt: `MealEditorTarget` | App/BenchmarkView.swift | Sheet-identity wrapper; the sheet it drives is `benchmark-editor/*`. |
| exempt: `BenchmarkMealEditorSheet.EditorItem` | App/BenchmarkView.swift | Row datum inside the editor. |
| exempt: `ArchiveFile` | App/SettingsView.swift | `.sheet(item:)` identity wrapper for the export URL. |
| exempt: `OutstandingDose` | App/DoseScheduleModel.swift | Domain value the dose surfaces render; not itself renderable. |
| exempt: `ActiveRefusal` | App/ActiveRefusal.swift | Identity wrapper around an `EstimationFailure` presentation; the surface is `capture-error/*`. |
| exempt: `DisplayMeal` | App/MealHistoryModel.swift | View-model datum behind `row-meal/*`. |
| exempt: `PendingDoseAdjust` | App/DoseNotificationDelegate.swift | Routing payload for the ADJUST action. |
| exempt: `DoseNotificationDelegate.Payload` | App/DoseNotificationDelegate.swift | `userInfo` decoding shim. |
| exempt: `GlucoseImportModel.ImageResult` | App/GlucoseImportModel.swift | Datum behind `row-import-result/*`. |
| exempt: `LiveSampleObserver.Sample` | App/LiveSampleObserver.swift | Sensor sample value. |
| exempt: `ResultView.FoodRow` | App/ResultView.swift | Row datum; its states are `result/row-*`. |
| exempt: `MealOverviewView.PerClassRow` | App/MealOverviewView.swift | Row datum; its state is `meal-overview/per-class-rows`. |
| exempt: `MealReviewView.AccessorySignal` | App/MealReviewView.swift | Signal datum; its states are `meal-review/signal-*`. |
| exempt: `FoodCandidate`, `CorrectionFlags`, `ReviewFood` | App/MealReviewModel.swift | View-model data behind the review rows. |
| exempt: `GatingSnapshot` | App/GatingSnapshot.swift | The value carried by `CaptureState.ready` / `.capturing`; not renderable. |
| exempt: `PhotoKitSaver` | App/PhotoLibrarySaver.swift | Photo-library service; no UI. |
| exempt: `IntakeRecord`, `GlucoseRow` | App/MealRouting.swift | Row data behind `row-intake/*` and `row-glucose/*`. |
| exempt: `LocalReminderRequest` | App/LocalReminderScheduler.swift | Notification request value; the notification itself is `dose-notification/*`. |
| exempt: `RefusingPipeline`, `StallingPipeline` | App/App.swift | Harness pipeline stubs; their visible effect is `app-shell/refusing-pipeline` and `app-shell/stalling-pipeline`. |
| exempt: `DecodedMask` | App/MaskOverlayLoader.swift | Decoded artefact value behind `mask-overlay/*`. |
| exempt: `PreShutterSegmenter.TimestampedMask` | App/PreShutterSegmenter.swift | Pre-shutter segmentation value. |
| exempt: `ChipFlow.Line` | App/TrendsView.swift | Internal line accumulator of the `ChipFlow` layout. |
| exempt: `LogExportFile` | App/EstimationLogView.swift | `.sheet(item:)` identity wrapper for the export URL. |
| exempt: `EstimationLogView.FailureEnvelope` + `CodingKeys` | App/EstimationLogView.swift | Decoding shim behind `row-outcome/refused-decoded`. |
| exempt: `GlucoseEntry`, `GlucoseProvider` | MeData/MeDataWidgets/GlucoseWidget.swift | `TimelineEntry` / `TimelineProvider`; the provider's one visible behaviour is `widget-glucose/timeline-refresh`. |
| exempt: `LauncherEntry`, `LauncherProvider` | MeData/MeDataWidgets/MeDataWidgets.swift | Static `TimelineEntry` / `TimelineProvider` for the launcher widgets. |
| exempt: `GlucoseProvider.FetchOutcome` | MeData/MeDataWidgets/GlucoseWidget.swift | Fetch-result logging enum; never rendered. |
| exempt: all non-UI helper enums | App/*.swift | `ShutterButtonMetrics`, `MedataSymbolGeometry`, `ResultViewLayout`, `ResultFormat`, `PortionFormat`, `MealPhotoLoader`, `MaskOverlayDecoder`, `LiveSampleMath`, `LogExport`, `RowTime`, `CapturePathDecider`, `UITestSupport`, `PhotoLibrarySaveError`, `DoseScheduleSettings`, `SettingsKeys`, `InsulinDoseModel.StepDirection`, `PreShutterSegmenter.Source`, `LiveIndicatorBadgeElement`. Metrics, formatting and routing helpers with no rendering of their own; the states they select are catalogued on the surfaces that use them. |

---

## SvelteKit web-v0 (frozen)

These rows describe the SvelteKit web app that preceded the SwiftUI rewrite. It is not checked out on
`research`; it is preserved on the `main` branch, and every `file` below is a `main:` path you read with
`git show`. The rows are **historical record**. `status: web-v0` means the surface is frozen — not shipped,
not planned, and not a thing to build from without a decision that says so. They earn their place here for
two reasons: they are the second half of the "define the app as-is" baseline, and they are the only place the
capabilities the rewrite dropped are still written down. `archive` paths follow `archive/web-v0/<id>.png`
with the leading `web/` of the id elided, because the `web-v0/` directory already carries it; every one is
`pending` until the screens are captured. That capture is an expiring option: the SvelteKit toolchain on
`main` rots, and once it will not build these screens cannot be photographed at all.

**Zones:** none declared. Zones exist so that options for a surface can be pointed at and recombined, and no
options are being generated for a frozen app. Where a web surface is wanted as a design input, the zone list
belongs to the iOS surface that would carry it — take `logbook-list`'s date-group headers and expand-in-place
rows as a choice about `row-list` on `records`, not as a zone vocabulary for a Svelte component nobody will
build again.

Two structural facts about this app are worth carrying forward rather than losing. First, the UI↔data seam
was **actually clean here**: `git grep -l "lib/services\|lib/repositories\|lib/stores"` over the
Svelte files on `main` returns exactly five — `ToastContainer.svelte` and the four route files
(`+page.svelte`, `capture/+page.svelte`, `manual/+page.svelte`, `presets/+page.svelte`). Fifteen of the
sixteen components take data only through props, which is why so many rows below read `view-model: —` and
`direction: none`. Second, two capabilities are present in the source but **already dead on `main`**, and
should not be read as working features: `CameraCapture.svelte` captures an optional nutrition-label photo
into `result.labelImage`, but `capture/+page.svelte`'s `handleCapture(result: { foodImage; source })` never
destructures it, so the label is discarded; and `CameraCapture.svelte` imports `ImagePreview` and declares
`galleryPreviewBlob`, neither of which is ever rendered or assigned.

The capabilities with **no successor at all** in the current iOS app — spelt out row by row in the successor
mapping below — are: editing a meal after it is saved; gallery/file import in the meal path; several named
food items with individually typed carbs/protein/fat inside one meal; saving a captured meal as a preset;
Meals/Snacks categories on presets; a modify-before-saving step when applying a preset; transient
confirmation (toasts); and an on-screen marker that the app is running against a stubbed backend.

| id | surface | file | kind | state | state source | view-model | data | direction | archive | status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| web/document-shell/default | Document shell | main:src/app.html | model | default | static template | — | — | none | archive/web-v0/document-shell/default.png · pending | web-v0 |
| web/root-layout/default | Root layout | main:src/routes/+layout.svelte | screen | default | no branches | — | — | none | archive/web-v0/root-layout/default.png · pending | web-v0 |
| web/app-shell/default | AppShell | main:src/lib/components/AppShell.svelte | component | default | no branches | — | — | none | archive/web-v0/app-shell/default.png · pending | web-v0 |
| web/home/loading | Home | main:src/routes/+page.svelte | screen | loading | `loading === true` | meal-api · toast.svelte.ts | cosmos-meal-repository · Meal | read | archive/web-v0/home/loading.png · pending | web-v0 |
| web/home/error | Home | main:src/routes/+page.svelte | screen | error | `error !== null` | meal-api · toast.svelte.ts | cosmos-meal-repository · Meal | read | archive/web-v0/home/error.png · pending | web-v0 |
| web/home/loaded | Home | main:src/routes/+page.svelte | screen | loaded | `!loading && !error && meals.length > 0` | meal-api · toast.svelte.ts | cosmos-meal-repository · Meal | read | archive/web-v0/home/loaded.png · pending | web-v0 |
| web/home/empty | Home | main:src/routes/+page.svelte | screen | empty | `meals.length === 0` (delegated to LogbookList) | meal-api · toast.svelte.ts | cosmos-meal-repository · Meal | read | archive/web-v0/home/empty.png · pending | web-v0 |
| web/edit-meal-modal/image-and-confidence | Edit Meal modal | main:src/routes/+page.svelte | sheet | image + confidence | `editingMeal.imageUrl !== undefined && editingMeal.confidence !== undefined` | meal-api · toast.svelte.ts | cosmos-meal-repository · Meal · UpdateMealInput | read-write | archive/web-v0/edit-meal-modal/image-and-confidence.png · pending | web-v0 |
| web/edit-meal-modal/image-only | Edit Meal modal | main:src/routes/+page.svelte | sheet | image only | `imageUrl !== undefined` branch | meal-api · toast.svelte.ts | cosmos-meal-repository · Meal · UpdateMealInput | read-write | archive/web-v0/edit-meal-modal/image-only.png · pending | web-v0 |
| web/edit-meal-modal/confidence-only | Edit Meal modal | main:src/routes/+page.svelte | sheet | confidence only | `confidence !== undefined` branch | meal-api · toast.svelte.ts | cosmos-meal-repository · Meal · UpdateMealInput | read-write | archive/web-v0/edit-meal-modal/confidence-only.png · pending | web-v0 |
| web/edit-meal-modal/plain | Edit Meal modal | main:src/routes/+page.svelte | sheet | neither | `else` branch | meal-api · toast.svelte.ts | cosmos-meal-repository · Meal · UpdateMealInput | read-write | archive/web-v0/edit-meal-modal/plain.png · pending | web-v0 |
| web/delete-meal-confirm/singular | Delete Meal? | main:src/routes/+page.svelte | overlay | one item | `deleteConfirmMeal.items.length === 1` | meal-api · toast.svelte.ts | cosmos-meal-repository · Meal | write | archive/web-v0/delete-meal-confirm/singular.png · pending | web-v0 |
| web/delete-meal-confirm/plural | Delete Meal? | main:src/routes/+page.svelte | overlay | many items | `deleteConfirmMeal.items.length !== 1` | meal-api · toast.svelte.ts | cosmos-meal-repository · Meal | write | archive/web-v0/delete-meal-confirm/plural.png · pending | web-v0 |
| web/capture/status-loading | Capture flow | main:src/routes/capture/+page.svelte | screen | status skeleton | `statusLoading === true` | meal-api · toast.svelte.ts | /api/recognition/status | read | archive/web-v0/capture/status-loading.png · pending | web-v0 |
| web/capture/not-configured | Capture flow | main:src/routes/capture/+page.svelte | screen | recognition unconfigured | `!recognitionConfigured && !mockMode` | meal-api · toast.svelte.ts | /api/recognition/status | read | archive/web-v0/capture/not-configured.png · pending | web-v0 |
| web/capture/mock-mode | Capture flow | main:src/routes/capture/+page.svelte | screen | mock banner pinned | `mockMode === true` | meal-api · toast.svelte.ts | /api/recognition/status | read | archive/web-v0/capture/mock-mode.png · pending | web-v0 |
| web/capture/capture | Capture flow | main:src/routes/capture/+page.svelte | screen | capture | `flowState === 'capture'` | meal-api · toast.svelte.ts | — | none | archive/web-v0/capture/capture.png · pending | web-v0 |
| web/capture/preview | Capture flow | main:src/routes/capture/+page.svelte | screen | preview | `flowState === 'preview' && capturedImage` | meal-api · toast.svelte.ts | — | none | archive/web-v0/capture/preview.png · pending | web-v0 |
| web/capture/recognising | Capture flow | main:src/routes/capture/+page.svelte | screen | recognising | `flowState === 'recognising'` | meal-api · toast.svelte.ts | recognition · FoodAnalysisResult | read | archive/web-v0/capture/recognising.png · pending | web-v0 |
| web/capture/results | Capture flow | main:src/routes/capture/+page.svelte | screen | results | `flowState === 'results'` | meal-api · toast.svelte.ts | recognition · AnalysedFoodItem | read | archive/web-v0/capture/results.png · pending | web-v0 |
| web/capture/error | Capture flow | main:src/routes/capture/+page.svelte | screen | error | `flowState === 'error'` | meal-api · toast.svelte.ts | recognition · RecognitionErrorCode | none | archive/web-v0/capture/error.png · pending | web-v0 |
| web/capture/editing | Capture flow | main:src/routes/capture/+page.svelte | screen | editing | `flowState === 'editing'` | meal-api · toast.svelte.ts | meal · FoodItem | none | archive/web-v0/capture/editing.png · pending | web-v0 |
| web/capture/saving | Capture flow | main:src/routes/capture/+page.svelte | screen | saving | `isSaving === true` | meal-api · toast.svelte.ts | cosmos-meal-repository · CreateMealInput · blob-image-repository | write | archive/web-v0/capture/saving.png · pending | web-v0 |
| web/camera-capture/detecting | CameraCapture | main:src/lib/components/CameraCapture.svelte | screen | detecting camera | `!detectionComplete` | — | — | none | archive/web-v0/camera-capture/detecting.png · pending | web-v0 |
| web/camera-capture/camera-available | CameraCapture | main:src/lib/components/CameraCapture.svelte | screen | camera + gallery choice | `detectionComplete && hasCamera` | — | — | none | archive/web-v0/camera-capture/camera-available.png · pending | web-v0 |
| web/camera-capture/no-camera | CameraCapture | main:src/lib/components/CameraCapture.svelte | screen | gallery only | `detectionComplete && !hasCamera` | — | — | none | archive/web-v0/camera-capture/no-camera.png · pending | web-v0 |
| web/camera-capture/food-camera-active | CameraCapture | main:src/lib/components/CameraCapture.svelte | screen | food viewfinder | `isCameraActive && !showLabelOption` | — | — | none | archive/web-v0/camera-capture/food-camera-active.png · pending | web-v0 |
| web/camera-capture/label-prompt | CameraCapture | main:src/lib/components/CameraCapture.svelte | screen | label interstitial | `showLabelOption && !isCameraActive` | — | — | none | archive/web-v0/camera-capture/label-prompt.png · pending | web-v0 |
| web/camera-capture/label-camera-active | CameraCapture | main:src/lib/components/CameraCapture.svelte | screen | label viewfinder | `isCameraActive && showLabelOption` | — | — | none | archive/web-v0/camera-capture/label-camera-active.png · pending | web-v0 |
| web/camera-capture/error | CameraCapture | main:src/lib/components/CameraCapture.svelte | screen | error banner | `error !== null` (getUserMedia refusal or non-JPEG/PNG) | — | — | none | archive/web-v0/camera-capture/error.png · pending | web-v0 |
| web/image-preview/idle | ImagePreview | main:src/lib/components/ImagePreview.svelte | component | idle | `isProcessing === false` | — | — | none | archive/web-v0/image-preview/idle.png · pending | web-v0 |
| web/image-preview/processing | ImagePreview | main:src/lib/components/ImagePreview.svelte | component | processing | `isProcessing === true` | — | — | none | archive/web-v0/image-preview/processing.png · pending | web-v0 |
| web/recognition-result/high-confidence | FoodRecognitionResult | main:src/lib/components/FoodRecognitionResult.svelte | screen | high | `confidence >= 0.8` | — | recognition · AnalysedFoodItem | none | archive/web-v0/recognition-result/high-confidence.png · pending | web-v0 |
| web/recognition-result/moderate-confidence | FoodRecognitionResult | main:src/lib/components/FoodRecognitionResult.svelte | screen | moderate | `confidence >= 0.6 && < 0.8` | — | recognition · AnalysedFoodItem | none | archive/web-v0/recognition-result/moderate-confidence.png · pending | web-v0 |
| web/recognition-result/low-confidence | FoodRecognitionResult | main:src/lib/components/FoodRecognitionResult.svelte | screen | low | `confidence < 0.6` | — | recognition · AnalysedFoodItem | none | archive/web-v0/recognition-result/low-confidence.png · pending | web-v0 |
| web/recognition-result/zero-items | FoodRecognitionResult | main:src/lib/components/FoodRecognitionResult.svelte | screen | no items | `items.length === 0` | — | recognition · AnalysedFoodItem | none | archive/web-v0/recognition-result/zero-items.png · pending | web-v0 |
| web/recognition-error/timeout | AIErrorFallback | main:src/lib/components/AIErrorFallback.svelte | screen | timeout | `errorType === 'timeout'` (HTTP 504) | — | recognition · RecognitionErrorCode | none | archive/web-v0/recognition-error/timeout.png · pending | web-v0 |
| web/recognition-error/no-items | AIErrorFallback | main:src/lib/components/AIErrorFallback.svelte | screen | no items | `errorType === 'no_items'` (HTTP 422) | — | recognition · RecognitionErrorCode | none | archive/web-v0/recognition-error/no-items.png · pending | web-v0 |
| web/recognition-error/ai-failure | AIErrorFallback | main:src/lib/components/AIErrorFallback.svelte | screen | backend failure | `errorType === 'ai_failure'` (HTTP 502/503) | — | recognition · RecognitionErrorCode | none | archive/web-v0/recognition-error/ai-failure.png · pending | web-v0 |
| web/recognition-error/generic | AIErrorFallback | main:src/lib/components/AIErrorFallback.svelte | screen | generic | `errorType === 'generic'` | — | recognition · RecognitionErrorCode | none | archive/web-v0/recognition-error/generic.png · pending | web-v0 |
| web/recognition-error/retrying | AIErrorFallback | main:src/lib/components/AIErrorFallback.svelte | screen | retrying | `isRetrying === true` | — | recognition · RecognitionErrorCode | none | archive/web-v0/recognition-error/retrying.png · pending | web-v0 |
| web/food-item-card/with-confidence | FoodItemCard | main:src/lib/components/FoodItemCard.svelte | row | with confidence chip | `confidence !== undefined` | — | meal · FoodItem | none | archive/web-v0/food-item-card/with-confidence.png · pending | web-v0 |
| web/food-item-card/without-confidence | FoodItemCard | main:src/lib/components/FoodItemCard.svelte | row | no chip | `confidence === undefined` | — | meal · FoodItem | none | archive/web-v0/food-item-card/without-confidence.png · pending | web-v0 |
| web/food-item-card/empty-name | FoodItemCard | main:src/lib/components/FoodItemCard.svelte | row | empty name | `item.name === ''` (placeholder "Food name") | — | meal · FoodItem | none | archive/web-v0/food-item-card/empty-name.png · pending | web-v0 |
| web/meal-editor/with-image | MealEditor | main:src/lib/components/MealEditor.svelte | screen | with image | `imageUrl !== undefined` | — | meal · CreateMealInput | none | archive/web-v0/meal-editor/with-image.png · pending | web-v0 |
| web/meal-editor/without-image | MealEditor | main:src/lib/components/MealEditor.svelte | screen | no image | `imageUrl === undefined` | — | meal · CreateMealInput | none | archive/web-v0/meal-editor/without-image.png · pending | web-v0 |
| web/meal-editor/mock-mode | MealEditor | main:src/lib/components/MealEditor.svelte | screen | mock banner | `mockMode === true` | — | meal · CreateMealInput | none | archive/web-v0/meal-editor/mock-mode.png · pending | web-v0 |
| web/meal-editor/save-error | MealEditor | main:src/lib/components/MealEditor.svelte | screen | save error | `saveError !== null` | — | meal · CreateMealInput | none | archive/web-v0/meal-editor/save-error.png · pending | web-v0 |
| web/meal-editor/no-items | MealEditor | main:src/lib/components/MealEditor.svelte | screen | no items | `items.length === 0` (totals hidden, Save disabled) | — | meal · CreateMealInput | none | archive/web-v0/meal-editor/no-items.png · pending | web-v0 |
| web/meal-editor/all-names-blank | MealEditor | main:src/lib/components/MealEditor.svelte | screen | all names blank | `items.every(i => i.name.trim() === '')` | — | meal · CreateMealInput | none | archive/web-v0/meal-editor/all-names-blank.png · pending | web-v0 |
| web/meal-editor/has-items | MealEditor | main:src/lib/components/MealEditor.svelte | screen | has items | `hasItems === true` (totals panel shown) | — | meal · CreateMealInput | none | archive/web-v0/meal-editor/has-items.png · pending | web-v0 |
| web/meal-editor/preset-capable | MealEditor | main:src/lib/components/MealEditor.svelte | screen | preset button shown | `onSaveAsPreset !== undefined` | — | meal · CreatePresetInput | none | archive/web-v0/meal-editor/preset-capable.png · pending | web-v0 |
| web/save-as-preset-modal/category-meal | Save as Preset | main:src/lib/components/MealEditor.svelte | overlay | category meal | `presetCategory === 'meal'` | — | meal · CreatePresetInput | none | archive/web-v0/save-as-preset-modal/category-meal.png · pending | web-v0 |
| web/save-as-preset-modal/category-snack | Save as Preset | main:src/lib/components/MealEditor.svelte | overlay | category snack | `presetCategory === 'snack'` | — | meal · CreatePresetInput | none | archive/web-v0/save-as-preset-modal/category-snack.png · pending | web-v0 |
| web/save-as-preset-modal/name-empty | Save as Preset | main:src/lib/components/MealEditor.svelte | overlay | name empty | `!presetName.trim()` (Save disabled) | — | meal · CreatePresetInput | none | archive/web-v0/save-as-preset-modal/name-empty.png · pending | web-v0 |
| web/logbook-list/empty | LogbookList | main:src/lib/components/LogbookList.svelte | component | empty | `meals.length === 0` | — | meal · Meal | none | archive/web-v0/logbook-list/empty.png · pending | web-v0 |
| web/logbook-list/row-collapsed | LogbookList | main:src/lib/components/LogbookList.svelte | component | row collapsed | `!expandedMeals.has(meal.id)` | — | meal · Meal | none | archive/web-v0/logbook-list/row-collapsed.png · pending | web-v0 |
| web/logbook-list/row-expanded | LogbookList | main:src/lib/components/LogbookList.svelte | component | row expanded | `expandedMeals.has(meal.id)` (chevron rotated) | — | meal · Meal · FoodItem | none | archive/web-v0/logbook-list/row-expanded.png · pending | web-v0 |
| web/logbook-list/group-today | LogbookList | main:src/lib/components/LogbookList.svelte | component | header "Today" | `date.toDateString() === today.toDateString()` | — | meal · Meal | none | archive/web-v0/logbook-list/group-today.png · pending | web-v0 |
| web/logbook-list/group-yesterday | LogbookList | main:src/lib/components/LogbookList.svelte | component | header "Yesterday" | `date.toDateString() === yesterday.toDateString()` | — | meal · Meal | none | archive/web-v0/logbook-list/group-yesterday.png · pending | web-v0 |
| web/logbook-list/group-dated | LogbookList | main:src/lib/components/LogbookList.svelte | component | header "Mon 4 Aug" | `toLocaleDateString('en-IE', …)` fallback | — | meal · Meal | none | archive/web-v0/logbook-list/group-dated.png · pending | web-v0 |
| web/logbook-list/source-ai-image | LogbookList | main:src/lib/components/LogbookList.svelte | component | glyph 📷 | `source === 'ai_image'` | — | meal · MealDataSource | none | archive/web-v0/logbook-list/source-ai-image.png · pending | web-v0 |
| web/logbook-list/source-manual | LogbookList | main:src/lib/components/LogbookList.svelte | component | glyph ✏️ | `source === 'manual'` | — | meal · MealDataSource | none | archive/web-v0/logbook-list/source-manual.png · pending | web-v0 |
| web/logbook-list/source-preset | LogbookList | main:src/lib/components/LogbookList.svelte | component | glyph 📋 | `source === 'preset'` | — | meal · MealDataSource | none | archive/web-v0/logbook-list/source-preset.png · pending | web-v0 |
| web/meal-detail/with-image | MealDetail | main:src/lib/components/MealDetail.svelte | sheet | with image | `meal.imageUrl && !imageError` | — | meal · Meal · blob-image-repository | none | archive/web-v0/meal-detail/with-image.png · pending | web-v0 |
| web/meal-detail/image-unavailable | MealDetail | main:src/lib/components/MealDetail.svelte | sheet | image 404 | `meal.imageUrl && imageError` | — | meal · Meal · blob-image-repository | none | archive/web-v0/meal-detail/image-unavailable.png · pending | web-v0 |
| web/meal-detail/no-image | MealDetail | main:src/lib/components/MealDetail.svelte | sheet | no image | `meal.imageUrl === undefined` | — | meal · Meal | none | archive/web-v0/meal-detail/no-image.png · pending | web-v0 |
| web/meal-detail/with-confidence | MealDetail | main:src/lib/components/MealDetail.svelte | sheet | confidence line | `meal.confidence !== undefined` | — | meal · Meal | none | archive/web-v0/meal-detail/with-confidence.png · pending | web-v0 |
| web/meal-detail/without-confidence | MealDetail | main:src/lib/components/MealDetail.svelte | sheet | no confidence line | `meal.confidence === undefined` | — | meal · Meal | none | archive/web-v0/meal-detail/without-confidence.png · pending | web-v0 |
| web/manual-entry/entry | Manual entry | main:src/routes/manual/+page.svelte | screen | entry | `flowState === 'entry'` | meal-api · toast.svelte.ts | meal · FoodItem | none | archive/web-v0/manual-entry/entry.png · pending | web-v0 |
| web/manual-entry/review | Manual entry | main:src/routes/manual/+page.svelte | screen | review | `flowState === 'review'` | meal-api · toast.svelte.ts | meal · CreateMealInput | none | archive/web-v0/manual-entry/review.png · pending | web-v0 |
| web/manual-entry/saving | Manual entry | main:src/routes/manual/+page.svelte | screen | saving | `saving === true` | meal-api · toast.svelte.ts | cosmos-meal-repository · CreateMealInput | write | archive/web-v0/manual-entry/saving.png · pending | web-v0 |
| web/manual-entry-form/single-item | ManualEntryForm | main:src/lib/components/ManualEntryForm.svelte | screen | one item | `items.length === 1` (remove button hidden) | — | meal · FoodItem | none | archive/web-v0/manual-entry-form/single-item.png · pending | web-v0 |
| web/manual-entry-form/multiple-items | ManualEntryForm | main:src/lib/components/ManualEntryForm.svelte | screen | many items | `items.length > 1` | — | meal · FoodItem | none | archive/web-v0/manual-entry-form/multiple-items.png · pending | web-v0 |
| web/manual-entry-form/no-valid-names | ManualEntryForm | main:src/lib/components/ManualEntryForm.svelte | screen | no valid names | `!hasValidItems` (totals hidden, Review disabled) | — | meal · FoodItem | none | archive/web-v0/manual-entry-form/no-valid-names.png · pending | web-v0 |
| web/manual-entry-form/has-valid-names | ManualEntryForm | main:src/lib/components/ManualEntryForm.svelte | screen | has valid names | `hasValidItems === true` | — | meal · FoodItem | none | archive/web-v0/manual-entry-form/has-valid-names.png · pending | web-v0 |
| web/presets/loading | Presets | main:src/routes/presets/+page.svelte | screen | loading | `loading === true` | preset-api · toast.svelte.ts | cosmos-preset-repository · Preset | read | archive/web-v0/presets/loading.png · pending | web-v0 |
| web/presets/error | Presets | main:src/routes/presets/+page.svelte | screen | error | `error !== null` | preset-api · toast.svelte.ts | cosmos-preset-repository · Preset | read | archive/web-v0/presets/error.png · pending | web-v0 |
| web/presets/loaded | Presets | main:src/routes/presets/+page.svelte | screen | loaded | `!loading && !error && presets.length > 0` | preset-api · toast.svelte.ts | cosmos-preset-repository · Preset | read | archive/web-v0/presets/loaded.png · pending | web-v0 |
| web/presets/empty | Presets | main:src/routes/presets/+page.svelte | screen | empty | `presets.length === 0` (delegated to PresetList) | preset-api · toast.svelte.ts | cosmos-preset-repository · Preset | read | archive/web-v0/presets/empty.png · pending | web-v0 |
| web/preset-list/empty | PresetList | main:src/lib/components/PresetList.svelte | component | empty | `presets.length === 0` | — | meal · Preset | none | archive/web-v0/preset-list/empty.png · pending | web-v0 |
| web/preset-list/meals-only | PresetList | main:src/lib/components/PresetList.svelte | component | meals only | `groupedPresets.get('snack').length === 0` | — | meal · PresetCategory | none | archive/web-v0/preset-list/meals-only.png · pending | web-v0 |
| web/preset-list/snacks-only | PresetList | main:src/lib/components/PresetList.svelte | component | snacks only | `groupedPresets.get('meal').length === 0` | — | meal · PresetCategory | none | archive/web-v0/preset-list/snacks-only.png · pending | web-v0 |
| web/preset-list/both-groups | PresetList | main:src/lib/components/PresetList.svelte | component | both groups | both group arrays non-empty | — | meal · PresetCategory | none | archive/web-v0/preset-list/both-groups.png · pending | web-v0 |
| web/preset-card/meal | PresetCard | main:src/lib/components/PresetCard.svelte | row | category meal | `preset.category === 'meal'` | — | meal · Preset | none | archive/web-v0/preset-card/meal.png · pending | web-v0 |
| web/preset-card/snack | PresetCard | main:src/lib/components/PresetCard.svelte | row | category snack | `preset.category === 'snack'` | — | meal · Preset | none | archive/web-v0/preset-card/snack.png · pending | web-v0 |
| web/preset-card/long-name | PresetCard | main:src/lib/components/PresetCard.svelte | row | truncated name | name overflows (`truncate`) | — | meal · Preset | none | archive/web-v0/preset-card/long-name.png · pending | web-v0 |
| web/preset-card/focused | PresetCard | main:src/lib/components/PresetCard.svelte | row | keyboard focus | `focus:ring-2 ring-brand-accent` on `role="button"` | — | meal · Preset | none | archive/web-v0/preset-card/focused.png · pending | web-v0 |
| web/apply-preset-sheet/open | Apply Preset | main:src/routes/presets/+page.svelte | sheet | open | `applyingPreset !== null` | meal-api · preset-api · toast.svelte.ts | cosmos-meal-repository · CreateMealInput | write | archive/web-v0/apply-preset-sheet/open.png · pending | web-v0 |
| web/edit-preset-modal/category-meal | Edit Preset | main:src/routes/presets/+page.svelte | overlay | category meal | `editCategory === 'meal'` | preset-api · toast.svelte.ts | cosmos-preset-repository · UpdatePresetInput | read-write | archive/web-v0/edit-preset-modal/category-meal.png · pending | web-v0 |
| web/edit-preset-modal/category-snack | Edit Preset | main:src/routes/presets/+page.svelte | overlay | category snack | `editCategory === 'snack'` | preset-api · toast.svelte.ts | cosmos-preset-repository · UpdatePresetInput | read-write | archive/web-v0/edit-preset-modal/category-snack.png · pending | web-v0 |
| web/edit-preset-modal/name-blank | Edit Preset | main:src/routes/presets/+page.svelte | overlay | name blank | `!editName.trim()` (Save disabled) | preset-api · toast.svelte.ts | cosmos-preset-repository · UpdatePresetInput | read-write | archive/web-v0/edit-preset-modal/name-blank.png · pending | web-v0 |
| web/delete-preset-confirm/open | Delete Preset? | main:src/routes/presets/+page.svelte | overlay | open | `deleteConfirmPreset !== null` | preset-api · toast.svelte.ts | cosmos-preset-repository · Preset | write | archive/web-v0/delete-preset-confirm/open.png · pending | web-v0 |
| web/toast/success | Toast | main:src/lib/components/Toast.svelte | overlay | success | `type === 'success'` | toast.svelte.ts | toast · ToastMessage | none | archive/web-v0/toast/success.png · pending | web-v0 |
| web/toast/error | Toast | main:src/lib/components/Toast.svelte | overlay | error | `type === 'error'` | toast.svelte.ts | toast · ToastMessage | none | archive/web-v0/toast/error.png · pending | web-v0 |
| web/toast/info | Toast | main:src/lib/components/Toast.svelte | overlay | info | `type === 'info'` | toast.svelte.ts | toast · ToastMessage | none | archive/web-v0/toast/info.png · pending | web-v0 |
| web/toast/persistent | Toast | main:src/lib/components/Toast.svelte | overlay | no auto-dismiss | `duration === 0` | toast.svelte.ts | toast · ToastMessage | none | archive/web-v0/toast/persistent.png · pending | web-v0 |
| web/toast-container/none | ToastContainer | main:src/lib/components/ToastContainer.svelte | component | no toasts | `toastStore.toasts.length === 0` | toast.svelte.ts | toast · ToastMessage | read | archive/web-v0/toast-container/none.png · pending | web-v0 |
| web/toast-container/stacked | ToastContainer | main:src/lib/components/ToastContainer.svelte | component | stacked toasts | `toastStore.toasts.length > 1` (same fixed coordinates) | toast.svelte.ts | toast · ToastMessage | read | archive/web-v0/toast-container/stacked.png · pending | web-v0 |
| web/mock-mode-banner/shown | MockModeBanner | main:src/lib/components/MockModeBanner.svelte | control | shown | rendered by parent; copy is fixed | — | — | none | archive/web-v0/mock-mode-banner/shown.png · pending | web-v0 |
| web/manual-entry-cta/shown | ManualEntryCTA | main:src/lib/components/ManualEntryCTA.svelte | component | shown | rendered when recognition unconfigured; copy is fixed | — | — | none | archive/web-v0/manual-entry-cta/shown.png · pending | web-v0 |

### Successor mapping

Every web surface, and what took its place. `catalogue id` names the iOS surface in the catalogue above this
section; `/*` means the whole surface rather than one state, because most of these are surface-to-surface
replacements rather than state-to-state ones.

| web surface | iOS successor | catalogue id | note |
| --- | --- | --- | --- |
| Document shell (`main:src/app.html`) | none — dropped | — | The PWA manifest, `theme-color #63ff00` and `apple-mobile-web-app-capable` shell have no native analogue. Lost: install-to-home-screen and a URL anyone could open. |
| Root layout (`main:src/routes/+layout.svelte`) | `AppRoot` (`App/AppRoot.swift`) | `app-root/*` | Same job — one wrapper that hosts every screen and owns the presentation router. |
| AppShell (`main:src/lib/components/AppShell.svelte`) | `HomeView` header (`App/HomeView.swift`) | `home/*` | No persistent chrome in the iOS app: the "MeData" wordmark lives inside `HomeView` rather than above every route. |
| Home (`main:src/routes/+page.svelte`) | `HomeView` (`App/HomeView.swift`) | `home/*` | The web home was launcher **and** two-day logbook in one scroll. iOS splits it: `HomeView` launches, `RecordsView` holds history. Lost: recent meals visible on the launch screen. |
| Edit Meal modal (`main:src/routes/+page.svelte`) | none — dropped | — | Lost: editing a meal after it is saved. `App/MealOverviewView.swift` offers only `Menu { Button("Delete", role: .destructive) }`; correction happens before the save, in `MealReviewView`. |
| Delete Meal? (`main:src/routes/+page.svelte`) | `MealOverviewView` confirmation (`App/MealOverviewView.swift`) | `meal-overview/delete-confirm` | Same guard, native shape: `.confirmationDialog("Delete meal?", …)` with Delete/Cancel. |
| Capture flow (`main:src/routes/capture/+page.svelte`) | `CaptureFlowView` (`App/CaptureFlowView.swift`) | `capture-flow/*` | Six web flow states replaced by the `CaptureState` machine. The `statusLoading` and `not-configured` states cannot occur offline. |
| CameraCapture (`main:src/lib/components/CameraCapture.svelte`) | `CaptureFlowView` + `ARPreviewView` | `capture-flow/*` | Lost: the gallery/file fallback for meals — no `PhotosPicker` exists in the meal path (the only one in `App/` is `App/GlucoseImportView.swift`, for glucose screenshots). Also lost: the nutrition-label second photo leg, which on `main` is already dead (`handleCapture` never reads `result.labelImage`). |
| ImagePreview (`main:src/lib/components/ImagePreview.svelte`) | `CapturedFramesView` / `NadirThumbnailView` (`App/CaptureFlowView.swift`) | `capture-flow/captured-frames` | Frames are shown as thumbnails inside the flow. Lost: the explicit full-bleed Confirm/Retake gate on a single still. |
| FoodRecognitionResult (`main:src/lib/components/FoodRecognitionResult.svelte`) | `ResultView` (`App/ResultView.swift`) | `result/*` | Mechanism changed entirely — a remote model's per-item percentages became on-device estimation with `ConfidenceLevel` bands and `ConfidencePill`. Lost: an exact percentage per item. |
| AIErrorFallback (`main:src/lib/components/AIErrorFallback.svelte`) | `CaptureErrorOverlay` (`App/CaptureErrorOverlay.swift`) + `ActiveRefusal` (`App/ActiveRefusal.swift`) | `capture-error/*` | `timeout` and `ai_failure` are structurally impossible offline. iOS refusals are geometric (tracking, scale, coverage) rather than transport failures. |
| FoodItemCard (`main:src/lib/components/FoodItemCard.svelte`) | `MealReviewView` amount rows (`App/MealReviewView.swift`) | `meal-review/*` | Lost: typing carbs/protein/fat directly per named item. iOS derives macros from the bundled food database and edits the serving amount instead. |
| MealEditor (`main:src/lib/components/MealEditor.svelte`) | `MealReviewView` (`App/MealReviewView.swift`) | `meal-review/*` | Same role (review before commit), different content: mask overlays and per-food serving adjustment in place of a macro form. |
| Save as Preset (`main:src/lib/components/MealEditor.svelte`) | none — dropped | — | Lost: turning a captured meal into a reusable preset. iOS presets are created only from `IntakeView`'s add button, via `QuickPresetEditSheet`. |
| LogbookList (`main:src/lib/components/LogbookList.svelte`) | `RecordsView` + `MealRecordRow` (`App/RecordsView.swift`) | `records/*` | Lost: Today/Yesterday date-group headers and expand-in-place rows. `RecordsView` is a flat, multi-type list (meal, insulin, glucose, intake, activity) with swipe/multi-select deletion. |
| MealDetail (`main:src/lib/components/MealDetail.svelte`) | `MealOverviewView` (`App/MealOverviewView.swift`) | `meal-overview/*` | Carried over well, including the missing-image case: the photo-only fallback renders `overview.photoFallback` when the mask artefact or photo is unavailable. |
| Manual entry (`main:src/routes/manual/+page.svelte`) | `IntakeView` + `CarbEntrySheet` (`App/IntakeView.swift`, `App/CarbEntrySheet.swift`) | `intake/*` | Two-step entry → review collapsed into one sheet with a single confirm. |
| ManualEntryForm (`main:src/lib/components/ManualEntryForm.svelte`) | `CarbEntrySheet` (`App/CarbEntrySheet.swift`) | `carb-entry/*` | Protein and fat survive (`carb.protein`, `carb.fat`, plus fibre). Lost: several separately named food items inside one manual meal — the iOS sheet records one intake. |
| Presets page (`main:src/routes/presets/+page.svelte`) | `IntakeView` preset grid (`App/IntakeView.swift`) | `intake/preset-grid` | Presets stopped being their own route and became a grid on the intake screen. |
| PresetList (`main:src/lib/components/PresetList.svelte`) | `IntakeView` preset grid (`App/IntakeView.swift`) | `intake/preset-grid` | Lost: Meals/Snacks grouping. `QuickPreset` (`MedataCore/Sources/Persistence/PersistenceStore.swift`) carries `name`, `carbsG`, `macros`, `sortOrder` — there is no category field to group on. |
| PresetCard (`main:src/lib/components/PresetCard.svelte`) | `IntakeView` preset button (`App/IntakeView.swift`) | `intake/preset-grid` | Kept and improved: one tap writes the preset straight to the ledger; edit and delete moved into a context menu. |
| Apply Preset sheet (`main:src/routes/presets/+page.svelte`) | none — dropped | — | Lost: adjusting a preset's items before logging it. The iOS tap commits immediately — deliberate speed, but there is no "this time it was half a portion" path. |
| Edit Preset (`main:src/routes/presets/+page.svelte`) | `QuickPresetEditSheet` (`App/QuickPresetEditSheet.swift`) | `quick-preset-edit/edit` | Name survives; the Meal/Snack toggle does not (see PresetList). Gains a fibre field and a 1–999 g range check. |
| Delete Preset? (`main:src/routes/presets/+page.svelte`) | `IntakeView` context menu Delete (`App/IntakeView.swift`) | `intake/preset-grid` | Lost: the confirmation step — the iOS context-menu Delete acts immediately. |
| Toast (`main:src/lib/components/Toast.svelte`) | none — dropped | — | Lost: transient confirmation of a write. No `App/` file mentions a toast; a save's only feedback is the screen it returns to. |
| ToastContainer (`main:src/lib/components/ToastContainer.svelte`) | none — dropped | — | Follows Toast. Worth noting the bug it froze: stacked toasts render at identical fixed coordinates, so a second toast lands on top of the first. |
| MockModeBanner (`main:src/lib/components/MockModeBanner.svelte`) | none — dropped | — | Lost: an on-screen marker that you are looking at simulated output. `DEV_STUB_SEGMENTER` swaps the segmenter silently; the only signal is `event=launch … segmenterSource=…` in the device log. |
| ManualEntryCTA (`main:src/lib/components/ManualEntryCTA.svelte`) | none — dropped | — | Dropped correctly. Estimation is on-device and unconfigurable, so "recognition is not configured" cannot occur. |

---

## Coverage

Counted separately per half, because only the iOS half is ratcheted. `tools/check_surfaces.sh` reads the
whole file but checks the iOS numbers: a drop in `covered` fails the check, and a rise is the only permitted
movement. The web-v0 numbers are a frozen total — they change only if the freeze is found to have missed
something on `main`.

| measure | iOS | web-v0 | total |
| --- | --- | --- | --- |
| surfaces catalogued (distinct `<surface>` keys) | 67 | 28 | 95 |
| state rows | 418 | 101 | 519 |
| source files covered | 42 | 22 | 64 |
| surfaces declaring zones | 23, across 19 distinct lists — the five `row-*` record rows share one | 0 — frozen, no options pending | 23 |

### iOS detail

The numbers `tools/check_surfaces.sh` ratchets against.

| measure | count |
| --- | --- |
| surfaces catalogued (distinct `<surface>` keys) | 67 |
| state rows | 418 |
| files covered — `App/*.swift` | 40 of 65 |
| files covered — `MeData/MeDataWidgets/*.swift` | 2 of 2 |
| renderable types with a row (`View` / `Shape` / `Layout` / `UIViewRepresentable` / `UIViewControllerRepresentable` / `Widget` / `WidgetBundle` / `App`) | 63 of 63 — 61 under the six protocols `tools/check_surfaces.sh` scans, plus `MedataApp: App` and `MeDataWidgetBundle: WidgetBundle` |
| types with an explicit `exempt:` reason | 33 entries — none of them conforms to a scanned protocol, so the check reports `exempt=0` |
| surfaces with no struct at all (rows keyed on the construction site) | 7 — every `dose-notification/*` row |
| rows at `status: shipped` | 415 |
| rows at `status: retired` | 3 — `tilt-guide/state-only`, `live-badge/state-only`, `result/legacy-portion-note` |
| rows at `status: planned` | 0 |
| rows whose `archive` cell is `pending` | 378 |
| rows whose `archive` cell is `n/a` (nothing photographable in isolation, or retired) | 40 |
| archive PNGs captured (`design-system/archive/ios-v0/`) | 0 of 378 |

Closed-enum coverage — every case of each named enum appears as a state row:

| enum | file | cases | rows |
| --- | --- | --- | --- |
| `CaptureState` | App/CaptureState.swift | 8 (`permissionDenied` splits into 2 subjects → 9 visual states) | `capture/initialising`, `capture/permission-denied-camera`, `capture/permission-denied-motion`, `capture/tracking-lost`, `capture/ready-*`, `capture/capturing`, `capture/estimating`, `capture/showing-result`, `capture/refused` |
| `CaptureStage` | App/CaptureState.swift | 2 | `capture/ready-two-view-nadir`, `capture/ready-awaiting-oblique` |
| `CaptureRoute` | App/CaptureState.swift | 1 | `capture/showing-result` |
| `MealRoute` | App/CaptureState.swift | 2 | `meal-overview/*` (`.overview`), `result/*` (`.result`) |
| `PermissionSubject` | App/CaptureState.swift | 2 | `capture/permission-denied-camera`, `capture/permission-denied-motion` |
| `ShutterButtonState` | App/ShutterButton.swift | 3 | `shutter/ready`, `shutter/capturing`, `shutter/disabled` |
| `ConfidenceLevel` | App/ResultView.swift | 4 | `confidence-pill/high`, `/moderate`, `/low`, `/very-low` |
| `CalibrationBannerState` | App/ResultView.swift | 4 | `result/calibration-full`, `/softened`, `/suppressed`, `/none` |
| `PlateFraction` | App/ResultView.swift | 4 | `meal-review/plate-all`, `/plate-three-quarters`, `/plate-half`, `/plate-quarter` |
| `TiltGuideState` | App/TiltBubbleGuide.swift | 2 stages (`awaitingOblique` true/false) | `bubble-level/nadir`, `bubble-level/oblique` |
| `LiveIndicatorBadgeElement` | App/LiveIndicatorBadge.swift | 3 | `telemetry/tilt-readout`, `telemetry/lidar-with-distance`, `telemetry/non-lidar` |
| `AppRoot.ActiveSheet` | App/AppRoot.swift | 5 | `app-root/cover-capture`, `/cover-intake`, `/cover-records`, `/cover-graph`, `/cover-settings` |
| `AppRoot.DeepLinkTarget` | App/AppRoot.swift | 4 | `app-root/deeplink-insulin`, `/deeplink-activity`, `/deeplink-capture`, `/deeplink-graph` |
| `IntakeView.IntakeSheet` | App/IntakeView.swift | 4 | `intake/sheet-new-entry`, `/sheet-edit-entry`, `/sheet-new-preset`, `/sheet-edit-preset` |
| `DoseScheduleSettings.SurfaceStyle` | App/DoseScheduleSettings.swift | 2 | `home/dose-banner-attempt`, `home/dose-route-attempt` |
| `RecordRow` | App/MealRouting.swift | 5 | `row-meal/*`, `row-insulin/*`, `row-glucose/*`, `row-intake/*`, `row-activity/*` |
| `EstimationFailure` | MedataCore/Sources/Pipeline/EstimationFailure.swift | 16 cases → 12 chips | every `capture-error/*` row |
| `GlucoseRender` | MedataCore/Sources/GlucoseWidgetShared/GlucoseTimeline.swift | 4 x 4 families | every `glucose-widget-view/{circular,rectangular,inline,small}-*` row |
| `GlucoseConnectionState` | MedataCore/Sources/GlucoseIngestion/GlucoseSource.swift | 3 | `glucose-connections/not-connected`, `/connected`, `/failed` |
| `GlucoseImportModel.ImageResult.Outcome` | App/GlucoseImportModel.swift | 4 | `row-import-result/stored`, `/skipped-duplicate`, `/rejected`, `/failed` |
| `TrendsRange` | MedataCore/Sources/Persistence/TrendsMath.swift | 3 | `trends/range-day`, `/range-week`, `/range-month` |
| `ActivityKind` | MedataCore/Sources/Persistence/ActivityEvent.swift | 7 | `row-activity/kind-glyphs`, `activity/kind-grid` |
| `InsulinKind` | MedataCore/Sources/Persistence/PersistenceStore.swift | 2 | `row-insulin/bolus`, `row-insulin/basal`, `insulin-dose/bolus`, `insulin-dose/basal` |
| `BenchmarkFidelity` | MedataCore/Sources/Persistence/PersistenceStore.swift | 2 | `row-benchmark-meal/fidelity-weighed`, `/fidelity-package` |
| `MedataLoadingSymbol.Mode` | App/MedataLoadingSymbol.swift | 2 | `loading-symbol/loop`, `loading-symbol/once` |

### web-v0 detail

Frozen. Nothing here is ratcheted, and no number moves unless the freeze is corrected against `main`.

| measure | count |
| --- | --- |
| surfaces catalogued (distinct `<surface>` keys, all `web/`-prefixed) | 28 |
| state rows | 101 |
| files covered — `main:src/**` | 22 — 4 route files, 1 layout, 1 document template, 16 components |
| rows at `status: web-v0` | 101 — all of them |
| rows whose `archive` cell is `pending` | 101 |
| archive PNGs captured (`design-system/archive/web-v0/`) | 0 of 101 |
| successor-mapping entries (one per web surface) | 28 |
| web surfaces with no iOS successor at all | 8 |
