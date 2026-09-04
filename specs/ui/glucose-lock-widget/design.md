# Design: Glucose Lock Screen Widget

## Overview

A data-driven glucose readout added as a new widget kind in the existing `MeDataWidgets` extension. The app publishes a small versioned snapshot of the latest `bsl` reading to a shared App Group whenever glucose events change; the widget renders solely from that snapshot across the Lock Screen accessory families and StandBy. Trend and staleness are pure functions with unit tests; the widget process holds no database and no heavy dependency, but does carry the narrow LibreLinkUp client so it can refresh itself while the app is suspended (Decision 16).

## Architecture

### New and changed pieces

| Piece | Location | Role |
|---|---|---|
| `GlucoseWidgetShared` (new SwiftPM target + its own library product, Foundation-only) | `MedataCore/Sources/GlucoseWidgetShared/` | Snapshot DTO, `GlucoseTrend`/`GlucoseBandStatus` enums, App Group id, widget kind id, `GlucoseSnapshotStore` read/write, and the pure `GlucoseRender`/`GlucoseTimeline` staleness maths. A **discrete linkable product** so the extension links exactly this and cannot pull GRDB via an umbrella product; no third-party deps and **no WidgetKit import** (Decision 12). |
| `TrendsMath.trend(...)` | `MedataCore/Sources/Persistence/TrendsMath.swift` | Pure trend derivation returning `GlucoseTrend` (Persistence gains a dep on `GlucoseWidgetShared`). |
| `GlucoseWidgetPublisher` | `App/GlucoseWidgetPublisher.swift` (new) | App-lifetime service: on `eventsDidChange`, recompute + write the snapshot, reload the widget on change. |
| `GlucoseWidget` + provider/entry/views | `MeData/MeDataWidgets/GlucoseWidget.swift` (new file in the existing target) | The data-driven widget kind; reads the snapshot only. Owns the WidgetKit-conforming `GlucoseEntry` and the `TimelineReloadPolicy` mapping (Decision 12). |
| App Group entitlement | `MeData/MeData.entitlements` + new `MeData/MeDataWidgets/MeDataWidgets.entitlements` | Shared container between the two targets. |
| `medata://graph` route | `App/AppRoot.swift` `handleDeepLink` | Tap target → Graph cover. |

### Why a shared UserDefaults blob, not a file

The snapshot is a single Codable value stored as one JSON `Data` blob under one key in `UserDefaults(suiteName: appGroupID)`. A single key holds one value written atomically at the plist level, so a concurrent reader sees the old or the new blob, never a spliced one (Req 1.5) — and this sidesteps the App Group file-write gotcha in the Swift rules (`containerURL` can be non-nil while the sandbox blocks a file write). **Atomicity is not freshness**: each process caches its own CFPreferences snapshot via `cfprefsd`, so a value the app writes is not instantly visible in the widget process. The ordering here is safe — the widget reads in a freshly-launched `getTimeline` triggered by the app's reload, by which point `cfprefsd` has synced — but nothing depends on an immediate cross-process read-back.

**Misprovisioning is not detectable via a nil suite.** `UserDefaults(suiteName:)` returns `nil` only for an invalid or own-bundle name; a *missing or mis-provisioned App Group entitlement* still yields a non-nil instance backed by a private (non-shared) store. The app then writes where the widget cannot see, the widget reads its own empty store, and the user-visible result is the never-recorded placeholder (Req 1.7) — the intended safe outcome, but reached without the nil guard firing. The real safeguard is the device round-trip verification (prerequisites), not the nil check. The nil guard remains for the genuinely-nil case: write no-ops (Req 1.6), read returns never-recorded.

### Data flow

```
bsl write (screenshot import / CGM ingest) ─▶ store.eventsDidChange tick
   └▶ GlucoseWidgetPublisher: read last 24h bsl (store.events) ─▶ TrendsMath.trend + band status
        └▶ build GlucoseSnapshot ─▶ if differs from stored: GlucoseSnapshotStore.write
             ├▶ written (reading is newer) ─▶ WidgetCenter.shared.reloadTimelines(ofKind: glucoseKind)
             └▶ dropped (reading is older — the widget already published a newer one) ─▶ no reload

Lock Screen render:
   GlucoseWidget provider ─▶ GlucoseSnapshotStore.read ─▶ timeline entries anchored to readingDate ─▶ view

Extension-side refresh (app suspended; Decision 16):
   getTimeline wake ─▶ snapshot ≥ pollInterval old AND shared rate gate open?
      └▶ LibreLinkUpKit fetch (shared keychain session) ─▶ pure snapshot derivation ─▶ GlucoseSnapshotStore.write ─▶ render fresh entries (or, if the write is dropped as not newer, render the stored snapshot)
      └▶ gate closed or fetch failed ─▶ render stored snapshot (staleness ladder)
```

**Publisher lifecycle and isolation.** `GlucoseWidgetPublisher` is an `actor` (not `@MainActor` — the 24h store read must not hop to the main thread) that owns a long-lived `Task` consuming `store.eventsDidChange`. It is constructed once at app launch in `App.swift` and retained for the process lifetime. The ordering is **subscribe, then prime, then consume**, and it matters in that order:

1. **Capture the stream synchronously in `init`.** `eventsDidChange` is `changeBroadcaster.subscribe()` — reading the property registers the continuation immediately, with no `await`. Binding it to a stored property inside the actor's (non-async) `init` is therefore the only step that can be ordered against `App.swift`'s synchronous init, and it is what makes "subscribed before glucose sources start" an actual guarantee rather than a hope: `AsyncStream` has no replay, so a tick emitted before the subscription exists is lost outright.
2. **Prime write inside the spawned `Task`.** An `actor` init cannot `await`, and `store.events(in:type:)` is `async throws`, so the prime recompute+write necessarily runs in the `Task` `init` kicks off — after step 1. It exists so a user with existing `bsl` history sees their reading immediately rather than never-recorded until the next event (Req 1.4/8.1 distinction).
3. **Then `for await` the captured stream.** Because the stream was captured in step 1, any tick that lands *during* the prime read is buffered by the `AsyncStream`, not dropped — which is exactly why the prime write must not precede the subscription.

It reacts to the post-commit `eventsDidChange` notification and never blocks a write path. Background HealthKit `enableBackgroundDelivery` wakes run in the **app** process and write `bsl` through the same `ingestLiveBsl` path that emits `eventsDidChange` (cgm-connect design), so the retained `Task` observes them; the compare-read-write-reload is bounded work (≤288 rows) that completes within the wake. Background reloads are nonetheless best-effort under the WidgetKit reload budget (below) — the staleness ladder (Req 5) is the safety net when a reload is throttled, so a missed update degrades to a dimmed/last-reading state rather than a wrong one. `reloadTimelines(ofKind:)` targets only the glucose kind, so glucose writes never spend reload budget on the co-hosted static launcher widgets (Decision 11).

### Display-horizon read (no new store API)

The publisher reads `store.events(in: (now − 24h)...now, type: EventType.bsl)`. The most-recent row is the snapshot reading (any age up to 24h drives the dimmed / last-reading states); the trailing-15-minute subset feeds the trend. Empty window → never-recorded snapshot (Req 1.4). Bounded at ≤288 rows/day, so no full-history scan and no `mostRecentEvent` accessor is added. A reading older than 24h is treated as never-recorded — beyond any glance-useful horizon.

### Extension-side refresh (Req 6.2–6.4, Decision 16)

The field defect this solves: the publisher above only runs while the app process is alive, so a locked phone shows a stale widget until the next unlock or app open — which also made the StandBy-day render impossible to verify. The fix lets `getTimeline` refresh the snapshot itself when the app has gone quiet. It raises the freshness ceiling from "next unlock" to "next WidgetKit wake" — it does **not** make the widget real-time: WidgetKit wakes are budgeted and best-effort, and the staleness ladder remains the degradation path. The shared vendor poll interval is **5 minutes** (one constant in `LibreLinkUpKit`, adopted by the app's `pollInterval` and the gate alike) — cgm-connect Decision 13's call: it matches the cadence LLU actually serves (the measured 5-minute gaps in the field data) and stays above the ~3-minute rate with known ban evidence, but is untested against the vendor's tolerance. The recorded rollback is a 15-minute baseline with the adaptive tightening re-armed; a ban costs the data stream entirely.

**Trigger and gate.** In `getTimeline`: if the stored snapshot's reading is younger than the poll interval, render as today — no fetch. Otherwise consult the shared rate gate, one timestamp under a key in the App Group suite written after every successful vendor fetch by either process. Gate younger than the poll interval → render stored (another fetch happened recently); otherwise fetch with a short timeout (~8 s, `getTimeline` must return promptly), derive, write the snapshot, render. Failure of any step falls back to the stored snapshot — never a blank or an error state (Req 6.4). The gate is also adopted by `LibreLinkUpGlucoseSource` on the app side, on every path but one: `connect(sink:)` passes `ignoringRateGate: true`, because that call exists to validate the stored credentials and a user who has just typed a password must get a connection state within seconds rather than silence until the gate reopens (Req 6.3). Every scheduled path — the poll loop, `catchUp()`, the background fetch — is gated, and a gate-skip is not an error: the connection state is untouched and the readings arrive on the next poll, because the graph endpoint returns history rather than only what is new. **The gate is advisory, not atomic**: check-then-fetch on a UserDefaults timestamp has no cross-process compare-and-set, and `cfprefsd` visibility lags — an app poll and a widget wake landing together can both pass. The accepted outcome is a rare double fetch; the steady-state combined rate targets one fetch per interval (Req 6.3), and the ban evidence concerns sustained fast polling, not occasional overlap.

**Auth is app-owned.** The widget never re-logins. It reads the shared session token; on a 401 (expired or invalidated session) it falls back to the stored snapshot and leaves auth repair to the app's next poll or foreground catch-up. This removes the two-process re-login race on the shared session item outright — the extension is a read-only consumer of credentials and session alike.

**Fetch and derivation.** The LLU graph endpoint already returns `graphData` plus the latest measurement — enough history for the 30-minute trend window (Decision 15). The extension converts via the existing `mgPerDl` init and derives the snapshot with the same pure helpers the app uses. That requires the pure snapshot-from-readings derivation (and `TrendsMath.trend`) to move from `Persistence` into `GlucoseWidgetShared` — Foundation-only, already the home of the render maths; `Persistence` keeps thin wrappers so app-side callers do not change. `snapToGrid` (the 5-minute-mark snapping currently internal to `GlucoseIngestion`) moves with them and the extension applies it before deriving, so both surfaces preprocess identically and the arrow cannot differ across app and widget for the same data. Insufficient series → arrow withheld, exactly the existing Req 3 behaviour.

**Packaging.** `LibreLinkUpClient` + `LibreLinkUpKeychain` extract from `GlucoseIngestion` into a new Foundation-only target/product `LibreLinkUpKit`, linked by `GlucoseIngestion` and the widget extension. This keeps GRDB/Persistence out of the appex (the Decision 12 constraint stands) and leaves the estimation-firewall untouched — no estimation target gains any new dependency.

*(As implemented: `LibreLinkUpKit` carries one package dependency, `GlucoseWidgetShared` — the shared connection state and the vendor rate gate live in the App Group suite, and the group id is pinned there. Since `GlucoseWidgetShared` is itself Foundation-only with an empty dependency list, the appex link closure is still Foundation + system frameworks and the Decision 12 constraint is unaffected; the alternative was passing the suite in at every call site or spelling the group id twice. `LibreLinkUpClient` also stops one step earlier than this section implies: it maps a graph response to a vendor-unit `LibreLinkUpReading`, and the `GlucoseSample` conversion stays in `GlucoseIngestion`, which is what keeps the source abstraction out of the vendor module.)*

**Shared state migration.** Three things the extension needs currently live app-private and move to shared storage: the LLU connected flag + resolved host + patientId (from `UserDefaults.standard` to the App Group suite), and the keychain `credentials`/`session` items (into a shared keychain access group — a new entitlement on both targets; profiles re-mint on the next device build). The items are already `kSecAttrAccessibleAfterFirstUnlock`, so a locked-phone fetch works any time after the first unlock since boot — before that first unlock the widget renders the stored snapshot, an accepted edge. Existing installs get a one-time launch migration: any of these keys still in `UserDefaults.standard` (or the app-private keychain) are copied to the shared locations and the old copies removed — idempotent, a no-op once migrated.

**Timeline policy change.** While the shared connected flag is set, the provider never returns `.never`: the policy is `.after(min(next staleness boundary, last fetch + poll interval))`, so WidgetKit keeps scheduling wakes and terminal states can self-heal without the app. With no connection configured, today's `.never` behaviour stands — a screenshot-import-only user gets no network activity from the widget, ever.

**Divergence note (Req 6.4).** A widget-side fetch can make the shared snapshot briefly newer than the app's database; the DB catches up on the app's next poll/foreground catch-up, which fetches the same readings from the same endpoint. The snapshot is a display contract, not a store — nothing reads it back into persistence.

## Components and Interfaces

### `GlucoseWidgetShared` (Foundation only)

```swift
public enum GlucoseTrend: String, Codable, Sendable {
    case fallingFast, falling, fallingSlow, steady, risingSlow, rising, risingFast
    public var arrow: String { /* ↓↓ ↓ ↘ → ↗ ↑ ↑↑ */ }
}

public enum GlucoseBandStatus: String, Codable, Sendable { case low, inRange, high }

public struct GlucoseSnapshot: Codable, Sendable, Equatable {
    public static let schemaVersion = 1
    public let version: Int          // == schemaVersion when written
    public let mmolL: Double?         // nil ⇒ never-recorded
    public let readingDate: Date?     // nil ⇒ never-recorded
    public let trend: GlucoseTrend?   // nil ⇒ no trend (Req 3.3/3.4)
    public let status: GlucoseBandStatus?
    public static let neverRecorded = GlucoseSnapshot(version: schemaVersion, mmolL: nil, readingDate: nil, trend: nil, status: nil)

    // The only construction path the publisher uses. Applies the value sanity
    // guard below: a non-finite or implausible mmolL yields .neverRecorded
    // (Req 2.7) rather than a snapshot carrying a fabricated decimal.
    public static func make(mmolL: Double, readingDate: Date,
                            trend: GlucoseTrend?, status: GlucoseBandStatus) -> GlucoseSnapshot
}

public enum GlucoseSnapshotStore {
    public static let appGroupID = "group.rtob.MeData"
    // Must match the extension's StaticConfiguration(kind:) exactly — the app
    // passes it to reloadTimelines(ofKind:) and the widget declares it, in two
    // separate targets, so it is pinned here rather than typed twice. Follows
    // the existing launcher convention (ie.medata.widget.insulin/.capture —
    // docs/agent-notes/widget-extension.md).
    public static let widgetKind = "ie.medata.widget.glucose"
    @discardableResult
    public static func write(_ s: GlucoseSnapshot) -> Bool  // stored? no-op if suite nil, encode fails (Req 1.6), or the reading is not newer than the stored one (Req 1.8)
    public static func read() -> GlucoseSnapshot        // .neverRecorded if suite nil / missing / undecodable / version ≠ schemaVersion (Req 1.7)
}
```

**Ordering guard (Req 1.8, Decision 19).** With Decision 16 there are two writers — the app, publishing what the database holds, and the widget, publishing what it fetched while the app was suspended — so "has the snapshot changed?" stopped being a sufficient test: change is symmetric and time is not. `write` therefore drops a candidate whose `readingDate` is not strictly newer than the stored one. The guard lives in the store, not in either writer, so both paths and any future third writer are covered by construction; `readingDate` is the ordering key because it is the only clock the two processes already agree on, and both already carry it. The write returns whether it landed: the app skips its `reloadTimelines` when it did not, and the widget renders the stored snapshot rather than the derivation it just tried to publish. A candidate carrying *no* reading is the never-recorded state (Req 1.4), not an older reading, and is still written — otherwise emptying the `bsl` history could never clear the tile. Like the vendor rate gate (Req 6.3) the guard is advisory: read-then-write across two processes has no compare-and-set, so it closes the observed regression rather than a genuine simultaneous race.

`status` is derivable from `mmolL`, but it is baked into the snapshot so the widget never re-derives band logic — one source of truth in `TrendsMath`. `Persistence` depends on `GlucoseWidgetShared` only for the two leaf enums (`TrendsMath` returns `GlucoseTrend`); the `GlucoseSnapshotStore` UserDefaults layer is called only by the app and the widget, never on the estimation path. The dependency edge is one-way and `GlucoseWidgetShared` has no path to `GlucoseIngestion`, so the cgm-connect estimation firewall is unaffected.

**Value sanity guard (Req 2.7).** No source in the codebase emits an out-of-range HI/LO sentinel — `bsl` values are plain mmol/L `Double`s from CGM ingest and Libre OCR, and the `value` column has no encoding for one — so there is no sentinel to render. `GlucoseSnapshot.make` maps a non-finite or implausible-range `mmolL` (outside 1.0–35.0) to `.neverRecorded` rather than rendering a fabricated decimal, so a future sentinel-emitting source cannot silently display a fake number. Should such a source ever land, showing the sentinel *as* a sentinel is a new requirement, not a tweak to this guard.

### Trend maths (pure, MedataCore-tested)

```swift
enum GlucoseTrendMath {   // GlucoseWidgetShared
    // Slope of a least-squares fit over readings within `window` before `now`,
    // in mmol/L per minute; nil unless ≥2 readings AND span ≥ minSpan.
    static func glucoseRate(_ readings: [GlucoseReading], now: Date,
                            window: TimeInterval = 30*60, minSpan: TimeInterval = 10*60) -> Double?
    static func trend(_ readings: [GlucoseReading], now: Date) -> GlucoseTrend?   // rate → band map
    static func bandStatus(_ mmolL: Double) -> GlucoseBandStatus                  // targetLow/HighMmolL
}
```

(Superseded wording: this block previously declared these as `extension TrendsMath` in `Persistence`,
with a 15-minute window. The window went to 30 minutes in Decision 15; the whole block moved to
`GlucoseWidgetShared` in Decision 16, because the widget derives its own trend after a fetch and
cannot import `Persistence`. `TrendsMath` keeps same-named forwards, and `GlucoseReading` moved with
the maths — `Persistence` re-exports the name as a typealias, so app-side call sites are unchanged
except for one added `import GlucoseWidgetShared` where the type's *members* are touched.)

Threshold map (decision_log Decision 4), by `|rate|`, sign choosing direction: `<0.056` steady · `0.056–0.111` slow · `0.111–0.166` medium · `≥0.166` fast. Half-open bands; boundary values are exact test points. "Reusable by the graph" (Req 3.5) means the in-app Graph screen (`TrendsView`/`TrendsModel`), not the `GlucoseGraph` SwiftPM target (which is the Libre OCR module). `bandStatus` runs on the raw `mmolL`, while the widget shows the value to 1 dp, so a raw 3.87 displays "3.9" yet carries the low token — the raw-value band is the intended authority at the boundary; the token, not the rounded number, is the status signal.

### Timeline maths (pure, in `GlucoseWidgetShared`) and its WidgetKit adapter (Req 5.4, Decision 12)

`TimelineEntry` and `TimelineReloadPolicy` are **WidgetKit** types, and `GlucoseWidgetShared` is Foundation-only and sits under `Persistence` in the graph — importing WidgetKit there would drag a UI framework through `Pipeline` into the macOS `HarnessCLI`, and the `dump-package` assertion could not catch it (system frameworks never appear in the package graph). So the split is: **all the maths is shared and testable; only the protocol conformance lives in the widget target.**

Shared, Foundation-only, unit-tested in `GlucoseWidgetSharedTests`:

```swift
// The render state at one instant.
public enum GlucoseRender: Equatable, Sendable {
    case fresh(value: String, status: GlucoseBandStatus, trend: GlucoseTrend?)   // ≤15m
    case stale(value: String, age: String)                                       // >15m ≤30m, de-emphasised, no status/arrow
    case lastReading(age: String)                                                // >30m, no value
    case neverRecorded
}

public enum GlucoseTimeline {
    // One second, per Decision 13: the bands are inclusive (age ≤15m is fresh), so
    // the first instant the ladder has actually advanced is one second past the
    // boundary. An entry ON the boundary would render fresh and freeze the ladder
    // a step behind for its whole life.
    public static let transitionOffset: TimeInterval = 1

    // Render instants anchored to readingDate (the staleness boundaries are ages of
    // the reading, NOT of `reference`): reference, max(reference, readingDate+15m+1s),
    // max(reference, readingDate+30m+1s) — deduped/ordered. If the reading is already >30m
    // stale (or never-recorded) at `reference`, a single point is returned.
    // (Superseded wording: this list previously read readingDate+15m / +30m exactly —
    // see Decision 13 for why that could not advance past the fresh state.)
    public static func renderPoints(_ snapshot: GlucoseSnapshot, from reference: Date)
        -> [(date: Date, render: GlucoseRender)]
    public static func render(_ snapshot: GlucoseSnapshot, at date: Date) -> GlucoseRender
    // The instant the ladder next advances, or nil in a terminal state
    // (lastReading / neverRecorded) — the widget maps nil to `.never`.
    public static func nextBoundary(_ snapshot: GlucoseSnapshot, after reference: Date) -> Date?
}
```

In the widget target only (`GlucoseWidget.swift`), a thin adapter:

```swift
struct GlucoseEntry: TimelineEntry {
    let date: Date
    let render: GlucoseRender
    let readingDate: Date?   // Decision 14 — see below
}

// renderPoints → [GlucoseEntry]; nextBoundary → policy:
//   non-nil ⇒ .after(boundary)   nil ⇒ .never
```

(Superseded wording: this snippet previously declared `GlucoseEntry` as `{ date, render }`
only. `GlucoseRender.fresh` carries no age string — deliberately, since a fresh entry has no
transition instant to anchor one to and lives up to 15 minutes — so the two-field entry left
`accessoryRectangular` unable to show the Req 2.4 age at full prominence. `readingDate` rides
along for that one label, rendered with `Text(_, style: .relative)` so it ticks without extra
entries. `GlucoseWidgetShared` is unchanged; see Decision 14.)

Reload policy by terminal state: `fresh`/`stale` timelines use `.after(next boundary)` so the ladder advances even without a new write; `lastReading` and `neverRecorded` use `.never` (a now-in-the-past `.after` would trigger a pointless reload-asap, and the "Xh ago" label need not tick between data writes) — the next app/background write reloads them explicitly.

**The booked date is a request, not a schedule (Req 6.5, Decision 18).** Three hours of tethered logs found none of the observed reloads attributable to the booked date: 14 of 18 fired as `com.apple.chrono` `reason: stale`, each preceded by "Widget is visible and effectively stale". The reload clock is WidgetKit's own visibility-gated staleness evaluation, keyed on `GlucoseTimeline.staleAge`, and it ran at roughly 20 minutes against a booked 5. So the policy above still says what the widget *wants*; the cadence it *gets* is the platform's, and the resulting routine stale render is the accepted window of Req 6.5, not a defect to design around. Two rules follow and are do-not-revert: `staleAge` stays at 15 minutes (it is the trigger as well as the threshold, so raising it postpones the reload by what it buys), and the Decision 17 one-interval wake floor stays (an earlier booking cannot produce an earlier wake when the booking is not honoured at all — only budget spend).

**Provider isolation gotcha.** The widget target builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so every `TimelineProvider` witness (`placeholder`, `getSnapshot`, `getTimeline`) must be marked `nonisolated` explicitly or the conformance does not compile — see the existing `LauncherProvider` and `docs/agent-notes/widget-extension.md`.

`age` string (Req 5.5): whole minutes `"\(m)m"` for the first hour, whole hours `"\(h)h"` beyond; `max(0, ...)` clamps a future `readingDate` (clock skew) to age 0 → treated as fresh.

### Widget views and status channel (Req 4.2, Decision 7)

Status is a **non-colour** channel that survives the Lock Screen's monochrome vibrant rendering:
- Low / high → a short leading token or SF Symbol (e.g. `arrow.down.to.line` / `arrow.up.to.line`, or "LO"/"HI" text tokens — functional, not a disclaimer); in-range → no token. The token is the sole status signal.
- Staleness de-emphasis (Req 5.2) uses `.opacity(...)`, which survives monochrome; colour does not carry meaning.
- Per-status `Color` is applied only under the full-colour StandBy day render (`@Environment(\.widgetRenderingMode) == .fullColor`) as an enhancement layered on the token (Req 4.3).

**Arrow weight** (device pass, 2026-08-05). The arrow renders at the VALUE's font in `accessoryRectangular` and `systemSmall`, and at 15 pt in `accessoryCircular` — not at the status token's caption size, which is where it started. On the Lock Screen a caption-sized arrow read as a footnote to the number rather than as the second thing the eye lands on, and direction is the one thing the value alone cannot convey. The token stays small deliberately: it is a qualifier on the value, whereas the arrow is data in its own right. `accessoryCircular` is the exception because its ~40 pt disc cannot fit a full-size arrow beside a token.

Per family (Req 2.3–2.5): `accessoryCircular` = value + status token + arrow (its only staleness cue is the opacity, since there is no room for age text — stated in Req 2.3/5.2); `accessoryRectangular` = value + token + arrow + age; `accessoryInline` = value + arrow glyph on one line, always monochrome. `systemSmall` = the same content as `accessoryRectangular` at the larger type its tile affords; it exists to reach StandBy, whose widget panel draws from the Home Screen pool and never shows accessory families (Req 2.2, Decision 3 as amended). All use `.containerBackground(for: .widget) { Color.clear }` (matches the existing `LauncherView`). Widget gallery/display copy is functional only (Req 2.1/8.2).

### Deep link (Req 7)

`.widgetURL(URL(string: "medata://graph"))` on the widget. On a locked device iOS defers the open until unlock, then `onOpenURL` fires and the Graph cover presents (Req 7.2) — no extra work.

App side, this is **three** edits to `AppRoot`, not one — `pendingDeepLink` is consumed in two separate `onDismiss` closures and the existing `.sheet` one tests for `.captureCover` by equality, so a graph tap arriving while the insulin dose sheet is up would otherwise be set and then silently discarded:

1. `DeepLinkTarget` gains a third case, `graphCover`.
2. `handleDeepLink` gains the route, mirroring the capture case's three branches (insulin sheet up → defer behind its dismissal; nothing presented → present directly; another cover up → defer behind its dismissal):

```swift
case ("graph", ""), ("graph", "/"):
    if showInsulinSheet {
        pendingDeepLink = .graphCover
        showInsulinSheet = false
    } else if activeSheet == nil {
        activeSheet = .graph
    } else if activeSheet != .graph {
        pendingDeepLink = .graphCover
        activeSheet = nil
    }
```

3. **Both** dismissal handlers learn the new case: the `fullScreenCover` `onDismiss` switch gains a `.graphCover` arm, and the `.sheet(isPresented: $showInsulinSheet)` `onDismiss` — currently `if pendingDeepLink == .captureCover { … }` — must handle `.graphCover` too. Missing this second site is the failure mode: tap the widget with the dose sheet open and nothing happens.

## Data Models

Only `GlucoseSnapshot` (above). No event-log schema change — `bsl` events are read through the existing `events(in:type:)`; nothing new is persisted to the store.

## Error Handling

| Failure | Behaviour | Req |
|---|---|---|
| App Group suite genuinely nil (invalid name) | `write` no-op, prior snapshot untouched; app does not crash | 1.6 |
| App Group entitlement missing/mis-provisioned (non-nil private store) | App writes a store the widget can't see; widget reads empty → never-recorded. Caught only by device round-trip verify, not the nil guard | 1.7 |
| Snapshot missing / undecodable / version mismatch | `read` returns `.neverRecorded`; widget shows never-recorded | 1.7, 8.1 |
| `mmolL` non-finite or outside 1.0–35.0 | `GlucoseSnapshot.make` emits `.neverRecorded` (no fabricated decimal) | 2.7 |
| Torn read during write | Single-key blob ⇒ reader sees old-or-new, never partial | 1.5 |
| Fewer than 2 in-window readings, or span < 10m, or latest older than the 30m window (Decision 15) | `trend == nil`, no arrow | 3.3, 3.4 |
| `readingDate` in the future (clock skew) | age clamps to 0, rendered fresh | 5.5 |
| No bsl in 24h | never-recorded snapshot | 1.4, 8.1 |
| Candidate snapshot's reading not newer than the stored one (app catch-up behind the widget's own fetch) | `write` drops it and returns false; app skips the reload, widget renders the stored snapshot | 1.8 |
| Reload cadence longer than the 15-minute freshness threshold | Stale treatment for part of most cycles; accepted, not corrected | 5.2, 6.5 |

## Testing Strategy

Per the project gate (MedataCore logic tests green; no app-UI test target; device looks-right is human-gated). New automated tests, all pure:

- **`GlucoseTrendMath.trend` / `glucoseRate`** (GlucoseWidgetSharedTests — moved there with the implementation in Decision 16; previously `TrendsMath` in PersistenceTests): each threshold boundary (0.056, 0.111, 0.166 and negatives — half-open inclusivity), the `<2 readings` and `<10m span` guards, `latest` older than the window ⇒ nil, and sign→direction. Boundary values are exact, so example-based tests suffice; no PBT needed.
- **`bandStatus`**: 3.9 and 10.0 boundaries (low/in-range/high inclusive at the band edges).
- **`GlucoseSnapshot` round-trip** (new `GlucoseWidgetSharedTests`): encode/decode identity; a blob with an unknown `version` decodes to `.neverRecorded`; a corrupt blob → `.neverRecorded`; non-finite / out-of-range `mmolL` builds to `.neverRecorded`.
- **Ordering guard** (same suite, Req 1.8): a write carrying an older or equal-dated reading is dropped and the stored snapshot survives; a newer one replaces it; `.neverRecorded` still clears a stored reading. Pure comparison on data both writers already carry, so it is testable on the package side even though one of the two writers is the extension.
- **Dependency-graph assertion** (in `GlucoseWidgetSharedTests`, mirroring the cgm-connect firewall approach): `swift package dump-package` shows `GlucoseWidgetShared` has an empty dependency list, so the extension link closure cannot acquire GRDB/Persistence. Note the limit of this check — it sees only *package* edges, so it cannot detect an accidental `import WidgetKit`; that boundary (Decision 12) is held by review and by the module compiling for the macOS test host.
- **`GlucoseTimeline.render`/`renderPoints`/`nextBoundary`**: given a snapshot at `T`, `render` returns fresh / stale / lastReading / neverRecorded across the 15- and 30-minute boundaries; `renderPoints` emits the three boundary points in order; `nextBoundary` returns the 15m/30m instant when the ladder can still advance and nil in the terminal states; age-string formatting incl. the future-timestamp clamp. All Foundation-only — the WidgetKit adapter in the extension is too thin to test and is covered by the device pass.

Human-gated device verification (prerequisites.md): App Group provisions and the snapshot round-trips app→extension; the widget appears in the Lock Screen gallery as a distinct kind; renders correctly in monochrome (status token visible without colour) and in StandBy day (colour enhancement); staleness ladder observed as a reading ages; tap opens the Graph from locked and unlocked; `make build-app` embeds the extension with the new entitlement (first build may need `-allowProvisioningUpdates` to mint the App Group profile, per the launcher-widget task history).

## Requirement traceability

| Req | Design element |
|---|---|
| 1.1–1.8 | `GlucoseSnapshot` (versioned schema), `GlucoseSnapshotStore` (atomic single-key blob, nil-suite/decode fallbacks, 1.8 `readingDate` ordering guard shared by both writers), `GlucoseWidgetPublisher` |
| 2.1–2.8 | `GlucoseWidget` kind (`GlucoseSnapshotStore.widgetKind`) + per-family views; functional copy; mmol/L 1-dp; 2.7 value sanity guard in `GlucoseSnapshot.make`; locked-render intent |
| 3.1–3.5 | `TrendsMath.glucoseRate`/`trend` (now-anchored, regression, guards) |
| 4.1–4.4 | `bandStatus`; non-colour status token; StandBy-day colour enhancement; suppressed when stale/absent |
| 5.1–5.5 | `GlucoseTimeline.render`/`renderPoints`/`nextBoundary` + the widget's `GlucoseEntry` adapter; opacity de-emphasis; last-reading vs never-recorded; age format + skew clamp |
| 6.1–6.5 | Publisher `reloadTimelines(ofKind:)` on change; subscribe-then-prime init ordering; extension-side fetch under the shared rate gate; per-state reload policy, bounded by the measured staleness-driven cadence (6.5) |
| 7.1–7.2 | `medata://graph` route (`DeepLinkTarget.graphCover` + both `onDismiss` sites) + `widgetURL`; locked-open defers to unlock |
| 8.1–8.2 | `.neverRecorded` render distinct from last-reading; functional placeholder copy |
