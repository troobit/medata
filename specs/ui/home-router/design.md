# Design: Home Router

## Overview

Re-root the SwiftUI shell on a new `HomeView` router, demote `TrendsView` (Graph) from launch root to a routed cover, and replace the meal-only `DataView` with a `RecordsView` unified timeline. All presentation, deep-link, and AR-session coordination stays in `AppRoot`; only its root content and cover vocabulary change.

## Architecture

### Shell re-root (Req 1, 2.1)

`AppRoot` (`App/AppRoot.swift`) remains the presentation coordinator — it already owns `activeSheet`, `showInsulinSheet`, `pendingDeepLink`, the deep-link handler, and the `onChange(of: activeSheet)` AR-session trigger. Only its root content changes: `body` renders `HomeView` instead of `TrendsView` (currently `AppRoot.swift:63`). Keeping the coordinator in `AppRoot` means the deep-link and AR-session logic (§below) move under the new root unchanged, rather than being re-implemented in `HomeView`.

`HomeView` (new, `App/HomeView.swift`) is the root content: six controls, no presentation state of its own. It triggers routes through closures/bindings injected by `AppRoot` (the same wiring pattern `AppRoot` uses today to inject `onOpen*` into `TrendsView`, `App.swift`/`AppRoot.swift:64-78`). Capture is the primary action — accent-prominent, matching the established primary-capture treatment (`.buttonStyle(.borderedProminent).tint(.medataAccent)`, currently `TrendsView.swift:118-121`); the `ShutterButton` is capture-surface chrome and is not reused here.

### Latest-glucose header (Req 4)

`HomeView` carries exactly one piece of data above the route controls: the most recent `bsl` reading. Three pieces:

- **`GlucoseSnapshotSource`** (`MedataCore/Sources/Persistence/GlucoseSnapshotSource.swift`, new) — the read-and-derive step lifted verbatim out of `GlucoseWidgetPublisher.currentSnapshot`: the 24-hour `displayHorizon`, the one-hour `futureSkewAllowance` upper bound (the fix from `glucose-widget-lagged-a-reading-behind`), and `readings → GlucoseSnapshot` via `TrendsMath.trend`/`bandStatus`. Both the publisher and the home model call it, which is what makes Req 4.7 structural rather than a convention. The publisher keeps its write/reload side effects and its `futureReading` log line.
- **`HomeGlucoseModel`** (`App/HomeGlucoseModel.swift`, new) — `@Observable @MainActor`; holds one `GlucoseSnapshot`, reloads on every `store.eventsDidChange` tick (the `RecordsModel`/`MealHistoryModel` mechanism, Req 4.6). It reads the **store**, not `GlucoseSnapshotStore` (the App Group defaults the widget reads): the header must be correct on a build whose App Group is not yet provisioned — `glucose-lock-widget` task 14 is still open — and the app already has the rows to hand (Req 4.7).
- **`HomeView.glucoseHeader`** — a `TimelineView(.periodic(by: 60))` so the age label advances while the page is open (Req 4.6) without the model re-querying; the snapshot itself only changes when a row lands.

Ownership: the model is `@State` on `AppRoot`, not on `HomeView`. `HomeView` is rebuilt on every cover present/dismiss, so a `@State` inside it would tear down and re-subscribe on each one.

Freshness handling reuses `GlucoseTimeline.staleAge` rather than a second threshold, but **not** `GlucoseTimeline.render`: that ladder's third rung withholds the number past 30 minutes, which is right for a context-free lock-screen glance and wrong for the surface whose stated job is "show me my most recent reading" (Req 4.2, Decision 15). Home shows the value at any age with the age beside it; past `staleAge` it withholds the two *derived* signals — trend arrow and band colour — because those describe a rate and a position that are no longer current (Req 4.4).

### Cover vocabulary (`ActiveSheet`)

`ActiveSheet` (`AppRoot.swift:55-61`) changes from `capture, data, settings` to:

| Case | Surface | Presentation | Note |
|---|---|---|---|
| `capture` | `CaptureFlowView` | `fullScreenCover` | unchanged |
| `intake` | `IntakeView()` (Track C) | `fullScreenCover` | new route; content owned by `manual-carb-intake` (§Intake seam) |
| `records` | `RecordsView` | `fullScreenCover` | replaces `data` |
| `graph` | `TrendsView` | `fullScreenCover` | Graph is now a route, not the root |
| `settings` | `SettingsView` | `fullScreenCover` | unchanged |

Dose is **not** an `ActiveSheet` case: it stays the existing insulin dose-entry `.sheet(isPresented: $showInsulinSheet)`, because Req 1.6 requires `medata://insulin/add` and the Dose control to open the *same* sheet, and a `.sheet` coexists with the mutually-exclusive cover `item:`. Its presentation relocates from `TrendsView` to `AppRoot` (see removal audit).

Each cover carries the existing `CloseCoverButton` (Decision 19 pattern) in `topBarLeading` (Req 1.4). `TrendsView` and `RecordsView` gain one; `CaptureFlowView`/`SettingsView` already have one. The Dose `.sheet` — the one non-cover surface from home — satisfies Req 1.4 through its native drag-to-dismiss (covers have none, which is why they carry `CloseCoverButton`; sheets do); no `CloseCoverButton` is added to it.

### AR session (Req 1.5) — unchanged mechanism

`AppRoot.onChange(of: activeSheet)` (`AppRoot.swift:110-117`) already calls `captureModel.capturePresented()` when the new value is `.capture` and `captureModel.captureDismissed()` otherwise (arm/release within 200 ms, `CaptureFlowModel.swift:394-441`). This is keyed on `activeSheet == .capture`, which is unaffected by the new root — the session is still armed only while the Capture cover is presented, now anchored under `HomeView`. `scenePhaseChanged` background release (`App.swift:100-102`) is untouched.

### Deep links (Req 1.6) — logic preserved, presentation relocated

`handleDeepLink` (`AppRoot.swift:128-151`) and the `pendingDeepLink`/`DeepLinkTarget` deferral (`AppRoot.swift:29,33-36`, `.fullScreenCover(onDismiss:)` at `80-91`) stay in `AppRoot` unchanged: `medata://capture` → `.capture`, `medata://insulin/add` → `showInsulinSheet`, deferring behind a conflicting surface. The only move: the insulin `.sheet` and its `onInsulinSheetDismiss` handler (which presents a pending `.captureCover` after the dose sheet dismisses, currently passed into `TrendsView` at `AppRoot.swift:66-74`) attach directly to `AppRoot`, since Graph is no longer the root that hosts them.

### Graph demotion — removal/parity audit (Req 2)

Every current `TrendsView` (`App/TrendsView.swift`) entry point and its wiring:

| Element (site) | Action | Req |
|---|---|---|
| `graph.data` toolbar button (`:84-90`) | remove | 2.3 |
| `graph.settings` toolbar button (`:91-97`) | remove | 2.3 |
| `graph.insulin` toolbar button → `showInsulinSheet` (`:98-106`) | remove | 2.3 |
| `graph.capture` toolbar button (`:116-124`) | remove | 2.3 |
| `trends.options` toolbar button (`:107-115`) | **keep** — chart options, not a navigation entry point | 2.2 |
| `onOpenData`/`onOpenSettings`/`onOpenCapture` + `showInsulinSheet` binding injection | remove from `TrendsView`; `AppRoot` drives these from `HomeView` | 2.3 |
| `onInsulinSheetDismiss` closure + insulin `.sheet(isPresented:onDismiss:)` (`:131-133`) | relocate to `AppRoot` | 1.6 |
| `.onChange(of: showInsulinSheet)` options-collapse (`:137-139`) | remove — dead once the sheet leaves `TrendsView` | 1.6 |
| `TrendsOptionsSheet` presentation (`:130`) | keep — chart options | 2.2 |
| `dayMeals` inline list → `NavigationLink(MealRoute.overview)` (`:354-384`) | **keep** — meal tap-through retained (Decision 11) *(destination redefined to `MealRoute.result` by Decision 16)* | 2.2 |
| `dayInsulin` inline list `.onDelete` → `model.deleteDose` (`:404-435`) | remove the `.onDelete`; list stays read-only | 2.4 |
| the chart, ranges, series | keep unchanged | 2.2 |

Graph carries no *direct* delete affordance after this (the only one was the day-insulin swipe). Meal rows still tap through to the meal-detail surface, which has its own delete — retained per Decision 11; Graph itself provides no deletion UI (Decision 11). *(Redefined in place by Decision 16. Superseded wording: "Meal rows still tap through to `MealOverviewView`, which has its own delete" — the destination is now `ResultView`, whose delete the surface already carries.)*

### Records replaces Data (Req 3)

`RecordsView` (new, `App/RecordsView.swift`) supersedes `DataView`. `.data` → `.records`; `DataView.swift` is removed. Two symbols currently in `DataView.swift` are used by other surfaces and must survive its removal — **relocate to a shared file** (`App/MealRouting.swift`):

| Symbol (current site) | Used by | Action |
|---|---|---|
| `mealRouteDestination(_:store:path:)` (`DataView.swift:188-223`) | `RecordsView`, `TrendsView` (meal nav) | move to `MealRouting.swift` |
| `CloseCoverButton` (`DataView.swift:233-243`) | `RecordsView`, `TrendsView`, `SettingsView`, `CaptureFlowView` | move to `MealRouting.swift` |

`RecordsView` owns a `NavigationStack(path: [MealRoute])` (as `DataView` did) so meal rows navigate to the single meal-detail surface (`ResultView`) via the shared destination builder; insulin and glucose rows do not navigate (Req 3.3). *(Redefined in place by Decision 16. Superseded wording: "meal rows navigate to `MealOverviewView` via the shared destination builder" — the overview page and its push to a separate full-result screen are deleted.)*

### Meal detail — one surface (Req [3.3](requirements.md#3.3), Decision 16) *(Added by Decision 16.)*

`ResultView` (`App/ResultView.swift`) is the meal-detail destination for both the Records list and the Graph day list; `App/MealOverviewView.swift` is deleted (with its `project.pbxproj` entries). What the overview carried lands on named `ResultView` surfaces:

- **Capture-metadata line** — the overview's `metadataLine` (capture path as `1-view · LiDAR` / `2-view`, middle dot, `MedataFormat.dateTimeString(record.createdAt)`) joins `ResultView`'s summary card beside the existing mass total and `CoFID + AFCD` provenance — the card is already the surface's metadata register.
- **Delete with confirmation** — `ResultView`'s pinned action-row `Menu` (`result.menu`: Save as quick-add, Delete) keeps its items; the overview's `.confirmationDialog("Delete meal?")` attaches to its Delete item, replacing the immediate delete `mealRouteDestination` wires today — with the summary hop gone, the dialog is the one step between tap and cascade.
- **Mask-overlaid photo** — `ResultView` already loads the photo in a `.task` via `MealPhotoLoader.loadImage(assetID:)`; the overview's `MaskOverlayLoader(store:mealId:paletteVersion:)` ZStack layer joins that photo surface. The loader renders nothing when the mask artefact is missing, so the photo-fallback behaviour is unchanged.
- **Dose readout** — already present: `ResultView` renders the dose readout line (`RecordedSuggestion.line`, `result.doseSuggestion`) beneath the hero total. On this surface it follows `specs/data/insulin-dosing` [Req 6.10](../../data/insulin-dosing/requirements.md#6.10), recomputing the suggestion live for the meal's own instant ([Req 6.11](../../data/insulin-dosing/requirements.md#6.11)) and opening its tap-through working the same way ([Req 6.12](../../data/insulin-dosing/requirements.md#6.12)); the mechanics belong to that spec. *(Redefined in place by `specs/data/insulin-dosing` Decision 18. Superseded wording: "renders the recorded suggestion line" / "opens its tap-through working reconstructed from the recorded row" — the `dose_suggestions` store is removed; every surface recomputes. The `RecordedSuggestion` type name survives in code.)*

`MealRoute` (`App/CaptureState.swift`) collapses to the single `.result(MealRecord)` case: `.overview` and the DEBUG-only `.review` case (with its `MealReviewView` destination and Retake-means-delete wiring) are deleted, so `mealRouteDestination` (`App/MealRouting.swift`) reduces to the one `.result` branch. Meal-row links in `RecordsView` and in `TrendsView`'s day list carry `MealRoute.result(record)`.

### Records data flow (Req 3.1, 3.6, 3.7)

`RecordsModel` (new, `App/RecordsModel.swift`) builds a merged, most-recent-first `[RecordRow]` and reloads on the store's `eventsDidChange` `AsyncStream` (`PersistenceStore.swift:181-187`), the same live-refresh mechanism `MealHistoryModel` (`MealHistoryModel.swift:50-60`) and `TrendsModel` (`TrendsModel.swift:71-80`) already use — so deletes/adds anywhere reflect without manual refresh, and the Graph reflects a Records delete through its own subscription.

Sources, all already persisted (no schema change). `RecordsModel` maps each **directly**, keeping the source identifier for the tie-break; it does **not** reuse `TrendsModel`'s plotting decoders (they drop `Event.id`, and `TrendsModel` is perf-sensitive — `graph-month-selection-hang`):

- **meals** — `store.allMeals()` (`PersistenceStore.swift:157`) composed with `store.corrections(for:)` per meal into the corrected total. `RecordRow.meal` carries a `DisplayMeal` (not a raw `MealRecord`), reusing the existing corrections overlay in `DisplayMeal`/`MealHistoryModel` (`MealHistoryModel.swift:8-28,76-96`) — `MealRecord.macros.totalCarbsG` is the *original* estimate, so the corrected total (Req 3.2) must come from that overlay, not the record. `RecordsModel` reuses `MealHistoryModel`'s composition (Records replaces the Data screen it backed, Decision 6).
- **insulin** — `.insulin` `Event`s via `insulinEntry(from:)` (`TrendsModel.swift:142-151`); `InsulinEntry.id` (UUID) is the tie-break key.
- **glucose** — `.bsl` `Event`s mapped in-place to `(id: Event.id, timestamp, mmolL)`. `GlucoseReading` (`TrendsMath.swift:10-18`) carries no `id`, so `RecordRow.glucose` keeps the source `Event.id` for row identity and the tie-break rather than the id-less plotting struct.

`events(in:type:)` is range-bounded (`PersistenceStore.swift:174`) — there is no range-free events accessor (only `allMeals()` is unbounded). For the all-time timeline (Decision 8) `RecordsModel` passes a sentinel `Date.distantPast...Date.distantFuture`; stated so it is not silently narrowed back into windowing.

Sort: `timestamp` descending, ties broken by the source `id` (UUID for meals/insulin, `Event.id` for glucose) so ordering is total and repeatable (Req 3.1).

Reload cost (within Decision 8's accepted trade-off): each `eventsDidChange` tick rebuilds the whole merged array — a per-meal `corrections(for:)` query plus a full re-fetch/merge/sort over the unbounded glucose volume. Accepted, but flagged given `TrendsModel`'s prior hang; if it bites, the windowing Decision 8 deferred is the lever.

Delete: swipe-to-delete on meal and insulin rows → `store.deleteMeal(id:)` (cascades corrections + artefacts, `GRDBPersistenceStore.swift:168-186`) and `store.deleteInsulinEvent(id:)` (`:431+`); no confirmation dialog (Decision 8). Glucose rows expose no delete (Req 3.5). Empty state: an empty list, no copy (Req 3.8, developer-phase no-disclaimer rule).

### Intake seam — parallel-safe with `manual-carb-intake` (Req 1.2, Dependency)

The design assumes `manual-carb-intake`'s intake surface already exists (parallel development, Decision 12) and is structured so the two streams edit disjoint lines:

- `ActiveSheet.intake` presents `IntakeView()` by name; `IntakeView` is owned and implemented by `manual-carb-intake` in its own file. Home-router adds only the enum case and the one-line cover branch that constructs it — Track C never edits that switch, only `IntakeView`'s own file. If Track C lands after this, the case is inert until `IntakeView` compiles; if before, it wires straight through.
- `RecordRow` (below) is an open enum: `manual-carb-intake` adds a single `.intake(IntakeRecord)` case plus one merge source in `RecordsModel` additively, without reworking existing cases — the manual intake records become deletable in Records (satisfying that spec's deferral of edit/delete to this surface) with a minimal, conflict-light diff. `IntakeRecord` and its subtype taxonomy (`carb`, `alcohol`, …) are **owned by `manual-carb-intake`**; it is one `RecordRow` case carrying the category internally (a discriminated union), so new intake subtypes never touch home-router's `RecordRow` switches. Home-router renders an intake row from `IntakeRecord`'s own display value + type label, staying agnostic to the category set. Note: intake records are not in this spec's Req 3.1 (meals/insulin/glucose); the `.intake` case is the forward seam Track C fills.

## Components and Interfaces

```swift
// App/HomeView.swift — launch-root router (Req 1.2, 1.3). No presentation state.
struct HomeView: View {
    let glucose: HomeGlucoseModel   // the latest-reading header (Req 4)
    let onCapture: () -> Void   // primary
    let onIntake:  () -> Void
    let onDose:    () -> Void   // sets showInsulinSheet in AppRoot
    let onRecords: () -> Void
    let onGraph:   () -> Void
    let onSettings:() -> Void
}

// App/HomeGlucoseModel.swift — the home header's one value (Req 4).
@Observable @MainActor final class HomeGlucoseModel {
    private(set) var snapshot: GlucoseSnapshot   // .neverRecorded until the first load
    func start() async      // reload(), then subscribe to store.eventsDidChange
    func cancel()
    func reload() async     // GlucoseSnapshotSource.current(store:now:)
}

// MedataCore/Sources/Persistence/GlucoseSnapshotSource.swift — shared derivation (Req 4.7).
public enum GlucoseSnapshotSource {
    public static let displayHorizon: TimeInterval        // 24 h
    public static let futureSkewAllowance: TimeInterval   // 1 h, the window's upper bound
    public static func current(store: any PersistenceStore, now: Date) async -> GlucoseSnapshot
    public static func snapshot(from readings: [GlucoseReading], now: Date) -> GlucoseSnapshot
}

// App/RecordsModel.swift — merged, live, most-recent-first.
@Observable final class RecordsModel {
    private(set) var rows: [RecordRow]
    func start()           // subscribe to store.eventsDidChange, then reload()
    func reload()          // fetch meals+insulin+glucose, merge, sort desc + id tie-break
    func delete(_ row: RecordRow)   // meal/insulin only; glucose no-op-absent
}

// App/MealRouting.swift — the unified row view-model + relocated shared symbols.
enum RecordRow: Identifiable {          // open for manual-carb-intake's .intake(IntakeRecord)
    case meal(DisplayMeal)              // corrected total folded in (Req 3.2), not raw MealRecord
    case insulin(InsulinEntry)          // .id is UUID
    case glucose(GlucoseRow)            // (id: Event.id, timestamp, mmolL) — GlucoseReading has no id
    var timestamp: Date { ... }         // sort key
    var id: String { ... }              // stable tie-break: source UUID / Event.id
}
// also moved here from DataView.swift: mealRouteDestination(_:store:path:), CloseCoverButton
```

`RecordsView` renders `RecordsModel.rows` in a `List` inside a `NavigationStack(path:)`; a meal row is a `NavigationLink(value: MealRoute.result(record))` *(Decision 16; superseded value: `MealRoute.overview(record)`)*, insulin/glucose rows are plain; `.swipeActions`/`.onDelete` on meal+insulin rows call `model.delete`. Row rendering distinguishes type and shows the key value + timestamp (Req 3.2): carbs (current total incl. corrections) for meals, units + bolus/basal for insulin, mmol/L for glucose.

## Data Models

No persistence or schema change — all three record types are already stored (`EventType.meal/.insulin/.bsl`). `RecordRow` is a view-model only. Glucose has no dedicated persisted model (generic `Event` rows mapped to `GlucoseReading`); that mapping is reused, not added.

## Error Handling

No new failure modes. Deep-link deferral, delete cascades, and the empty state are covered above; each reuses an existing path.

## Testing Strategy

Per the MVP test gate (build + looks-right on device; no committed app-target suite runs — `docs/agent-notes/ui-capture-flow.md`). Keep the MedataCore math tests green (`make test`); add no app-target test scaffolding (project `testing-mvp-minimal` convention).

- **PBT candidate, not built:** the Records merge/sort has a genuine invariant — total, deterministic order under equal timestamps (Req 3.1). It lives in the App-layer `RecordsModel`, which no harness executes, so it is verified on device rather than by a committed property test. Recorded here as the one place a property test *would* apply if the app target gained a runnable suite.
- **On-device verification checklist:** launch → HomeView root, no tab bar (1.1); all six controls route, Capture most prominent (1.2, 1.3); each surface closes back to home (1.4); AR session armed only during Capture (1.5); `medata://capture` and `medata://insulin/add` route, deferring behind an open surface (1.6); Graph shows no entry-point controls and no delete (2.3, 2.4); Records merges all three types most-recent-first (3.1), a meal row in Records or the Graph day list lands directly on `ResultView` with metadata line, delete confirmation, overlaid photo, and dose readout present (3.3, Decision 16), delete on meal/insulin reflects live in Records + Graph (3.6), add elsewhere reflects live (3.7), glucose not deletable (3.5), empty Records has no copy (3.8).
