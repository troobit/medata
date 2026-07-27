# Decision Log: Glucose Lock Screen Widget

## Decision 1: New `ui` spec rather than extending regression-suggestion-integration

**Date**: 2026-07-27
**Status**: accepted

### Context

The Lock Screen already carries two widgets from `specs/regression-suggestion-integration` (the `MeDataWidgets` extension): static launchers for "Log dose" and "Capture" that only deep-link into the app. The new request is a data-driven glucose readout with a trend arrow. `regression-suggestion-integration` is a done PRD-lane spec whose widgets deliberately carry no data and no App Group.

### Decision

Author a new `ui`-domain spec at `specs/ui/glucose-lock-widget/`. Reuse the existing `MeDataWidgets` extension target by adding a new widget kind to it, but keep requirements, design, and decisions in this spec.

### Rationale

A data-driven readout is a distinct capability — it needs a new App Group, a process-crossing snapshot cache, trend maths, staleness/colour states, and a timeline refresh policy — none of which the launcher widgets have. Reopening a completed PRD spec to bolt this on would blur its scope. Reusing the extension target avoids a second widget-extension process and duplicate signing.

### Alternatives Considered

- **Extend regression-suggestion-integration**: Add the glucose widget into that done spec — Rejected: it is complete and its widgets are launcher-only; a data bridge is out of its scope.
- **New widget extension target**: A second `.appex` for glucose — Rejected: unnecessary process/signing overhead; WidgetKit hosts multiple kinds from one bundle.

### Consequences

**Positive:**
- Clear scope boundary; the data-bridge and trend maths live with the feature that needs them.
- One widget extension continues to host all kinds.

**Negative:**
- The `MeDataWidgets` target now spans two specs; both must be considered when touching it.

---

## Decision 2: WidgetKit accessory widget, not a Live Activity

**Date**: 2026-07-27
**Status**: accepted

### Context

The user framed the surface around "live-events". For an always-present Lock Screen glucose readout, the two candidate mechanisms are a WidgetKit accessory widget and an ActivityKit Live Activity.

### Decision

Deliver a WidgetKit accessory widget only. A Live Activity is an explicit non-goal for this feature.

### Rationale

A Live Activity is ephemeral: it must be explicitly started and self-expires (8h default, 12h hard cap), so it cannot be the persistent glucose tile. An accessory widget is always present, needs no lifecycle management, and updates via timeline reload when the app writes a new reading — the right fit for a glance surface.

### Alternatives Considered

- **Live Activity primary**: Lead with ActivityKit — Rejected: cannot stay resident; wrong tool for an always-on tile.
- **Widget + Live Activity now**: Ship both — Rejected for this cycle: doubles scope; a time-boxed "watch now" session can layer on later if wanted.

### Consequences

**Positive:**
- Always-present, zero-lifecycle surface; no expiry handling.

**Negative:**
- Update latency is bounded by the app/background-refresh write cadence, not push — mitigated by the staleness treatment (Req 5).

---

## Decision 3: Placements — Lock Screen accessory families + StandBy, no Home Screen small

**Date**: 2026-07-27
**Status**: accepted

### Context

WidgetKit offers accessory families (`accessoryCircular`, `accessoryRectangular`, `accessoryInline`) plus Home Screen system families. The existing launcher widgets also expose `systemSmall`.

### Decision

Support `accessoryCircular`, `accessoryRectangular`, `accessoryInline`, and StandBy. Do not offer a Home Screen `systemSmall` glucose widget.

### Rationale

The reference surface (the FreeStyle LibreLink screenshot) and the "minimise interaction / glance" goal are Lock Screen concerns. StandBy reuses the accessory rendering for near-free. A Home Screen tile is a different placement with no stated need.

### Alternatives Considered

- **Add systemSmall**: Mirror the launcher widgets — Rejected: no requirement; expands rendering/layout surface without demand.

### Consequences

**Positive:** Focused rendering surface; StandBy comes along cheaply.
**Negative:** No at-a-glance glucose on the Home Screen; revisit if requested.

---

## Decision 4: Trend derived from recent readings, not a source-specific arrow

**Date**: 2026-07-27
**Status**: accepted

### Context

LibreLinkUp's payload carries a native `TrendArrow`, but it is dropped at ingest and does not persist. HealthKit and screenshot imports carry no trend field. The widget needs a trend arrow across all sources.

### Decision

Derive the trend from `bsl` readings within the most recent 15 minutes as a rate of change, in the shared `TrendsMath` module, mapped to seven arrow states by fixed thresholds. Do not plumb any source-specific trend value.

### Rationale

A derived trend is uniform across HealthKit, LibreLinkUp, and screenshots, keeps the widget source-agnostic, and gives the graph a reusable helper. Persisting a source-specific arrow would be undefined for two of three sources and would add an ingest-path change this feature is meant to avoid.

**Rate method (pinned so `TrendsMath` is testable):** the rate is the slope of a least-squares linear regression over all `bsl` readings whose timestamps fall within the 15 minutes preceding *now* (device time), in mmol/L per minute. Anchoring to now (not to the latest reading) keeps trend and staleness on the same clock. A trend is reported only when ≥2 readings fall in the window **and** the earliest and latest span ≥10 minutes — this guards against two near-simultaneous readings amplifying into a spurious fast arrow.

Threshold mapping by signed rate `r` (mmol/L per minute), non-overlapping half-open bands on `|r|`, sign choosing direction (Dexcom convention, adjustable in code):

| Band | State | Arrow |
|---|---|---|
| `\|r\| < 0.056` | steady | → |
| `0.056 ≤ \|r\| < 0.111` | slow | ↗ / ↘ |
| `0.111 ≤ \|r\| < 0.166` | medium | ↑ / ↓ |
| `\|r\| ≥ 0.166` | fast | ↑↑ / ↓↓ |

Positive `r` → up arrow, negative → down. Boundaries are testable exact values (0.056, 0.111, 0.166).

### Alternatives Considered

- **Plumb LibreLinkUp `TrendArrow`**: Persist the source arrow where present, derive otherwise — Rejected: source-specific, undefined for HealthKit/screenshots, requires an ingest-path change.
- **Two-point rate (latest vs earliest in window)**: Simpler — Rejected: sensitive to a single noisy endpoint; regression over the 5-minute-grid points is steadier.
- **Window anchored to the latest reading**: Rejected: diverges from staleness (which is now-relative), so a lagging reading would report a trend the staleness rule already calls stale.

### Consequences

**Positive:** One computation for all sources; reusable by the graph; testable in MedataCore with exact boundary and min-span cases.
**Negative:** Needs ≥2 recent readings spanning ≥10 min; sparse screenshot-only data yields no arrow (Req 3.3) — accepted as correct behaviour.

---

## Decision 5: Staleness thresholds — dim after 15 min, hide value after 30 min

**Date**: 2026-07-27
**Status**: accepted — the *thresholds* stand; the colour wording below is superseded by Decision 7

**Note:** this entry was written before the WidgetKit rendering review and describes the
status signal as a colour ("status colour", "colour suppressed"). Decision 7 established
that the Lock Screen always renders accessory widgets in monochrome vibrant mode, so status
is carried by a non-colour token instead. Read every "colour" below as "status indicator";
the 15/30-minute thresholds and the dim-then-hide ladder are unaffected.

### Context

The widget is only as fresh as the last app/background-refresh write; between writes the displayed reading ages. CGM cadence is 5 minutes. A stale value must not read as authoritative.

### Decision

Full prominence + status colour when the reading is ≤15 minutes old; dimmed (colour suppressed, value + age still shown) when >15 and ≤30 minutes; replace the value with a no-recent-reading placeholder when >30 minutes.

### Rationale

Fifteen minutes is roughly three missed CGM cycles — past that, the reading is drifting and should stop looking live. Thirty minutes is stale enough that a precise number misleads more than a placeholder. The user chose the stricter of the offered policies.

### Alternatives Considered

- **Dim >20 / hide >60**: Looser horizon — Rejected by the user in favour of tighter control.
- **Never dim, always show age**: Rejected: a hours-old value looks as authoritative as a live one.

### Consequences

**Positive:** Stale data is visually distinct; no misleading precision past 30 min.
**Negative:** During real CGM gaps the value hides sooner; the timeline must schedule entries at both age boundaries (Req 5.4).

---

## Decision 6: Tap opens the Graph view via a `medata://` deep link

**Date**: 2026-07-27
**Status**: accepted

### Context

The app already handles `medata://` deep links (`AppRoot` handleDeepLink) for the launcher widgets. The glucose tile needs a single tap target consistent with "minimise interaction".

### Decision

Tapping the widget opens the app to the Graph view via a `medata://` deep link, reusing the existing handler.

### Rationale

The graph is the natural "see more" destination for a glucose glance, and the deep-link infrastructure already exists. One tap target keeps the accessory widget simple.

### Alternatives Considered

- **Open app to Home**: Rejected: extra navigation to reach the trend.
- **No tap target**: Rejected: wastes the obvious see-more affordance.

### Consequences

**Positive:** One tap to the full trend; reuses existing routing.
**Negative:** Adds one new `medata://` route to define and handle.

---

## Decision 7: Status is a non-colour channel; colour is a StandBy-day-only enhancement

**Date**: 2026-07-27
**Status**: accepted

### Context

The initial requirement encoded low / in-range / high as a colour treatment, matching the FreeStyle LibreLink reference (red LOW banner). WidgetKit review (Apple WWDC22/23 material, corroborated) established that Lock Screen accessory widgets **always render in vibrant mode**: the system desaturates content to monochrome and re-tints it to the wallpaper. `accessoryInline` is always monochrome. Only StandBy *day* mode renders in full colour; StandBy night is vibrant. So per-status hue is invisible on the primary surface (the Lock Screen) for every user, and colour-only encoding is a colour-blind failure regardless.

### Decision

Distinguish low / in-range / high with a channel that survives monochrome vibrant rendering — a functional glyph or short status token — as the sole status signal. Per-status colour is permitted only as an enhancement where the system renders full colour (StandBy day), layered on top of the non-colour channel.

### Rationale

The Req 4 user story ("notice an out-of-range level without reading the number") only holds if the signal survives the Lock Screen's monochrome rendering. A glyph/token also passes colour-blind accessibility. Functional status text is not disclaimer/reassurance copy, so it complies with the developer-phase rule. Opacity (used for the dimmed staleness state, Decision 5) also survives vibrant rendering, so the two visual cues remain distinct in monochrome.

### Alternatives Considered

- **Colour per status (original)**: Red/amber/green — Rejected: invisible on the Lock Screen; colour-blind failure.
- **`accented` render mode with three tints**: Rejected: `accented` applies the user's single chosen tint, so it cannot encode three semantic states by hue.

### Consequences

**Positive:** Status readable on the primary surface and in monochrome; colour-blind safe; no disclaimer copy.
**Negative:** A glyph/token costs layout space in the already-tight circular and inline families — design must budget it against the value and arrow.

---

## Decision 8: Distinguish >30-min-stale from never-recorded; add a snapshot schema version

**Date**: 2026-07-27
**Status**: accepted

### Context

Requirements review found the >30-minute stale state and the never-connected state collapsing into one identical placeholder, discarding "last reading, 41 min ago" — the exact signal that tells a CGM sensor gap from an unconfigured app. Separately, the app and the widget extension can run mismatched builds, and a snapshot has no version, atomicity, or widget-side decode-failure contract, so a format change or torn read had undefined behaviour.

### Decision

Keep the locked "hide the number past 30 minutes" (Decision 5) but still show the reading's relative age as a "last reading · Xh ago" label, visually distinct from a never-recorded placeholder. Give the snapshot a schema version field, write it atomically, and define the widget to fall back to the never-recorded state when the snapshot is missing, undecodable, or carries an unrecognised version.

### Rationale

Showing age-without-value preserves the staleness signal the whole feature is built on while honouring the locked decision to hide a misleadingly-precise stale number. A version field plus atomic write plus a defined decode-failure fallback makes the app↔extension contract testable and immune to cross-build drift and torn reads — the standard App Group snapshot discipline.

### Alternatives Considered

- **Single placeholder for both states (original)**: Rejected: loses the sensor-gap-vs-unconfigured distinction.
- **Show the stale number past 30 min**: Rejected: contradicts the locked Decision 5 and shows misleading precision.
- **Unversioned snapshot**: Rejected: a format change between app and extension builds would silently misdecode.

### Consequences

**Positive:** Users can tell "sensor dropped out" from "never set up"; the snapshot contract survives mismatched builds and concurrent reads.
**Negative:** One more state to render and test; the snapshot writer must handle versioning and atomic replace.

---

## Decision 9: Timeline staleness modelled as a pure entry-generation function

**Date**: 2026-07-27
**Status**: accepted — refined by Decision 12 (the pure function emits render states, not WidgetKit `TimelineEntry` values)

### Context

The staleness transitions (full → de-emphasised at 15 min → last-reading at 30 min) happen with the passage of time, not on new data. The original requirement asserted the timeline "SHALL schedule entries at the boundaries", which is OS-scheduler behaviour that cannot be unit-tested.

### Decision

Model the transitions as a pure function of (snapshot, reference time) that emits timeline entries at the 15- and 30-minute age boundaries carrying the pre-computed rendered state, and unit-test that function. The observable staleness outcomes (Req 5.1–5.3) remain the requirement; the OS scheduler is not asserted against.

### Rationale

Pre-baking the state transitions into the timeline is WidgetKit's intended pattern and mirrors the discipline already applied to trend derivation (a pure `TrendsMath` function). It makes the behaviour testable without depending on the opaque reload budget.

### Alternatives Considered

- **Assert scheduler behaviour (original)**: Rejected: not unit-testable; delivery timing is system-controlled.
- **Rely on data-write reloads only**: Rejected: staleness would not advance during a gap between writes, which is exactly when it matters.

### Consequences

**Positive:** Staleness transitions are deterministic and unit-tested; correct WidgetKit usage.
**Negative:** The provider must compute future-dated entries, slightly more logic than a single-entry timeline.

---

## Decision 10: Shared snapshot code in one Foundation-only linkable product

**Date**: 2026-07-27
**Status**: accepted

### Context

The snapshot DTO and its `GlucoseTrend`/`GlucoseBandStatus` enums must be readable by both the app and the widget extension. The widget cannot import `Persistence` (it drags in GRDB, blowing the ~30 MB extension budget), and `PortableContracts` carries a SwiftProtobuf dependency. `TrendsMath` (in `Persistence`) must return `GlucoseTrend`.

### Decision

Create one new SwiftPM target `GlucoseWidgetShared` (Foundation only, zero third-party deps) exposed as its own library product, holding the DTO, the two enums, the App Group id, and `GlucoseSnapshotStore`. The extension links exactly that product; `Persistence` depends on it for the enums.

### Rationale

A single tiny Foundation-only target is the least-ceremony way to share the contract without coupling the widget to GRDB. Making it a discrete product (not an umbrella) means the extension link list references only it, so GRDB cannot ride in transitively. The dependency edge `Persistence → GlucoseWidgetShared` is one-way and the module has no path to `GlucoseIngestion`, so the cgm-connect estimation firewall is unaffected; a `dump-package` assertion pins the module's empty dependency list.

### Alternatives Considered

- **Split enums and the UserDefaults store into two targets**: so estimation targets link only leaf enums, not App-Group I/O — Rejected: extra target for negligible gain; the I/O code is inert unless called and never runs on the estimation path.
- **Reuse `PortableContracts`**: Rejected: pulls SwiftProtobuf into the widget needlessly.
- **Put the enums in `Persistence`**: Rejected: the widget can't import `Persistence` (GRDB), so the DTO's enums can't live there.

### Consequences

**Positive:** Widget stays light; one contract source; firewall intact.
**Negative:** Estimation binaries transitively link a (tiny, Foundation-only) display DTO — accepted and documented.

---

## Decision 11: Snapshot publisher — actor, prime write, kind-scoped reload, best-effort background

**Date**: 2026-07-27
**Status**: accepted

### Context

WidgetKit review established: `reloadAllTimelines()` would burn the shared reload budget on the co-hosted static launcher widgets; the CGM 5-minute cadence (~288 writes/day) far exceeds any reload budget; an app-lifetime observer must own a real `Task` (not a SwiftUI `.task`) to catch HealthKit background-delivery ticks; and a reaction-only publisher shows never-recorded on first launch until the next event.

### Decision

`GlucoseWidgetPublisher` is an `actor` that (1) does a prime recompute+write at construction before subscribing, (2) owns a process-lifetime `Task` consuming `store.eventsDidChange`, established before glucose sources start, and (3) writes then calls `WidgetCenter.shared.reloadTimelines(ofKind:)` for the glucose kind only. Background reloads are best-effort under the reload budget; the staleness ladder (Decision 5/9) is the degradation path.

### Rationale

An `actor` keeps the 24h store read off the main thread and serialises the compare-read-then-write. The prime write fixes the cold-start never-recorded bug. Kind-scoped reload avoids spending budget on widgets whose content never changes. Tying freshness to the write cadence with a graceful staleness ladder is the only workable model given the budget — chasing per-reading reloads would fail silently.

### Alternatives Considered

- **`@MainActor` publisher (like `TrendsModel`)**: Rejected: hops the 24h read to the main thread on every CGM tick.
- **`reloadAllTimelines()`**: Rejected: reloads the launcher widgets needlessly.
- **Couple the write to the CGM `BGTask` completion**: Considered — Rejected for now: adds coupling to `GlucoseConnectionsModel`; the shared `eventsDidChange` path already fires on the background ingest write, and the staleness ladder covers a dropped background reload.

### Consequences

**Positive:** Correct cold start; budget-efficient; thread-correct; degrades gracefully.
**Negative:** Background updates are not guaranteed real-time — accepted (Req 6.2); a dropped background reload shows a dimmed/last-reading state until the next foreground or permitted reload.

---

## Decision 12: WidgetKit types stay in the extension; the shared module exposes pure render points

**Date**: 2026-07-27
**Status**: accepted

### Context

Decision 10 established `GlucoseWidgetShared` as a Foundation-only target with zero
dependencies, linked by the widget extension and depended on by `Persistence`. The first
draft of the design then placed the whole timeline layer in that module — including
`struct GlucoseEntry: TimelineEntry` and a `TimelineReloadPolicy` — so that the staleness
transitions (Decision 9) would be unit-testable in MedataCore.

Both of those are WidgetKit types. Putting them in `GlucoseWidgetShared` would force an
`import WidgetKit` into a module that `Persistence` depends on, so WidgetKit would ride
transitively into `Pipeline` and on into the macOS `HarnessCLI` executable — a UI framework
in the estimation and harness link closures, for no benefit. The `dump-package` assertion
guarding that module cannot detect this: it enumerates *package* dependency edges, and
system frameworks never appear there.

### Decision

Keep every unit-testable value in `GlucoseWidgetShared` and Foundation-only: `GlucoseRender`,
`GlucoseTimeline.render`, `GlucoseTimeline.renderPoints` (returning
`[(date: Date, render: GlucoseRender)]`), and `GlucoseTimeline.nextBoundary` (returning
`Date?`). The widget extension owns the WidgetKit surface: a `GlucoseEntry: TimelineEntry`
wrapper over `(date, render)`, and the `Date?` → `.after(_)` / `.never` reload-policy mapping.

### Rationale

The split puts the module boundary where the testability argument actually needs it. Every
branch of the staleness ladder is a pure function of `(snapshot, reference date)` and stays
in `make test`; what moves to the extension is a struct declaration and a two-case mapping,
which have no logic to test and are covered by the on-device pass anyway. `Date?` is the
honest shared vocabulary for "when does this next change" — `TimelineReloadPolicy` is
WidgetKit's encoding of that same fact, and encoding it twice is what created the problem.

### Alternatives Considered

- **Import WidgetKit into `GlucoseWidgetShared`**: Simplest edit — Rejected: falsifies
  Decision 10's central claim, drags WidgetKit into `Persistence` → `Pipeline` → `HarnessCLI`,
  and the existing package-graph assertion cannot catch the regression.
- **Split off a third target for the timeline maths**: A `GlucoseWidgetTimeline` module the
  extension links alongside — Rejected: same objection Decision 10 already made to splitting
  the enums out; an extra target for one enum and three functions that share the DTO anyway.
- **Move the staleness maths into the extension entirely**: Rejected: it is the logic
  Decision 9 exists to make unit-testable, and the app target has no test surface.

### Consequences

**Positive:**
- Decision 10's Foundation-only guarantee is true as written.
- The full staleness ladder stays inside `make test`; no WidgetKit in the estimation or
  harness link closures.

**Negative:**
- One extra hop in the extension (`renderPoints` → `[GlucoseEntry]`, `nextBoundary` → policy)
  that would not exist if the module could speak WidgetKit directly.
- The boundary is held by review, not by an executable assertion — the `dump-package` test
  is blind to framework imports, so this is called out explicitly in the design's testing
  strategy.

### Impact

`GlucoseWidgetShared` API surface (design "Components and Interfaces"), tasks 7 and 11.
