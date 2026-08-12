---
references:
    - specs/ui/glucose-lock-widget/requirements.md
    - specs/ui/glucose-lock-widget/design.md
    - specs/ui/glucose-lock-widget/decision_log.md
    - specs/ui/glucose-lock-widget/prerequisites.md
---
# Glucose Lock Screen Widget — Implementation Tasks

## Shared contract & pure logic (MedataCore)

- [x] 1. Add GlucoseWidgetShared SwiftPM target + library product <!-- id:7k39hjc -->
  - New Foundation-only target at MedataCore/Sources/GlucoseWidgetShared/ exposed as its own .library product (discrete, not umbrella) so the extension links exactly it and cannot pull GRDB (Decision 10). No WidgetKit import in this target — ever (Decision 12); Persistence depends on it, so a framework import here reaches Pipeline and HarnessCLI.
  - Add the Persistence -> GlucoseWidgetShared dependency edge (TrendsMath returns GlucoseTrend).
  - Config/wiring only — no preceding test.
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1)
  - References: Package.swift, specs/ui/glucose-lock-widget/design.md

- [x] 2. Write GlucoseWidgetShared tests (Red) <!-- id:7k39hjd -->
  - GlucoseSnapshot encode/decode round-trip identity; unknown-version blob -> .neverRecorded; corrupt/undecodable blob -> .neverRecorded.
  - GlucoseSnapshot.make sanity guard: non-finite or mmolL outside 1.0-35.0 -> .neverRecorded.
  - dump-package assertion: GlucoseWidgetShared has an empty dependency list (mirrors cgm-connect firewall test). Known limit: package edges only, so it cannot see an accidental import WidgetKit (Decision 12) — that stays a review concern.
  - Blocked-by: 7k39hjc (Add GlucoseWidgetShared SwiftPM target + library product)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [1.7](requirements.md#1.7), [2.7](requirements.md#2.7), [8.1](requirements.md#8.1)
  - References: MedataCore/Tests/GlucoseWidgetSharedTests/

- [x] 3. Implement GlucoseWidgetShared DTO, enums, store (Green) <!-- id:7k39hje -->
  - GlucoseSnapshot Codable (version, mmolL?, readingDate?, trend?, status?) + .neverRecorded + the sanity-guarded GlucoseSnapshot.make(mmolL:readingDate:trend:status:) builder (the publisher's only construction path).
  - GlucoseTrend (7 states, arrow glyph) and GlucoseBandStatus (low/inRange/high) enums.
  - appGroupID = group.rtob.MeData; widgetKind = ie.medata.widget.glucose (pinned here because the app's reloadTimelines(ofKind:) and the extension's StaticConfiguration(kind:) are in different targets and must match exactly; follows the existing ie.medata.widget.* launcher convention).
  - GlucoseSnapshotStore.read/write as a single JSON blob under one key in UserDefaults(suiteName:), nil-suite -> write no-op / read .neverRecorded.
  - Blocked-by: 7k39hjd (Write GlucoseWidgetShared tests Red)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [1.7](requirements.md#1.7), [2.7](requirements.md#2.7), [4.1](requirements.md#4.1), [8.1](requirements.md#8.1)
  - References: MedataCore/Sources/GlucoseWidgetShared/

- [x] 4. Write TrendsMath trend/rate/bandStatus tests (Red) <!-- id:7k39hjf -->
  - glucoseRate: exact threshold boundaries 0.056/0.111/0.166 (and negatives), half-open inclusivity; <2 readings and <10-min span -> nil; latest reading >15 min old -> nil; sign -> up/down direction.
  - bandStatus: 3.9 and 10.0 boundaries (low <3.9, in-range inclusive, high >10.0).
  - Blocked-by: 7k39hje (Implement GlucoseWidgetShared DTO, enums, store Green)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1)
  - References: MedataCore/Tests/PersistenceTests/

- [x] 5. Implement TrendsMath glucoseRate / trend / bandStatus (Green) <!-- id:7k39hjg -->
  - glucoseRate: least-squares slope (mmol/L per min) over readings within 15 min preceding now; nil unless >=2 readings AND earliest-latest span >=10 min.
  - trend: |rate| -> steady/slow/medium/fast band, sign -> direction, returning GlucoseTrend.
  - bandStatus: reuse targetLowMmolL / targetHighMmolL.
  - Blocked-by: 7k39hjf (Write TrendsMath trend/rate/bandStatus tests Red)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1)
  - References: MedataCore/Sources/Persistence/TrendsMath.swift

- [x] 6. Write GlucoseTimeline render/renderPoints/nextBoundary tests (Red) <!-- id:7k39hjh -->
  - render(snapshot, at:) crosses fresh -> stale -> lastReading at readingDate+15m and +30m; neverRecorded distinct from lastReading.
  - renderPoints(snapshot, from:) instants anchored to readingDate: reference, max(ref, readingDate+15m), max(ref, readingDate+30m); single point when already >30m stale or never-recorded.
  - nextBoundary(snapshot, after:) returns the next 15m/30m instant while the ladder can still advance, nil in the terminal lastReading / neverRecorded states.
  - age string: whole minutes <1h then whole hours; future readingDate clamps to age 0 (rendered fresh).
  - Blocked-by: 7k39hje (Implement GlucoseWidgetShared DTO, enums, store Green)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [8.1](requirements.md#8.1)
  - References: MedataCore/Tests/GlucoseWidgetSharedTests/

- [x] 7. Implement GlucoseRender + GlucoseTimeline (Green) <!-- id:7k39hji -->
  - GlucoseRender enum: fresh(value,status,trend?) / stale(value,age) / lastReading(age) / neverRecorded.
  - GlucoseTimeline.render + renderPoints + nextBoundary as tested. Foundation types only: renderPoints returns [(date: Date, render: GlucoseRender)] and nextBoundary returns Date? — NOT TimelineEntry / TimelineReloadPolicy, which are WidgetKit and belong in the extension (Decision 12). The widget maps nil -> .never, non-nil -> .after(_) in task 11.
  - Lives in GlucoseWidgetShared so it is MedataCore-testable and importable by the widget.
  - Blocked-by: 7k39hjh (Write GlucoseTimeline render/renderPoints/nextBoundary tests Red)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [6.2](requirements.md#6.2), [8.1](requirements.md#8.1)
  - References: MedataCore/Sources/GlucoseWidgetShared/

## App integration

- [x] 8. Implement GlucoseWidgetPublisher (app-lifetime actor) <!-- id:7k39hjj -->
  - actor (not @MainActor). Init order is subscribe -> prime -> consume: bind store.eventsDidChange to a stored property SYNCHRONOUSLY in init (the property is changeBroadcaster.subscribe(), no await needed, and AsyncStream has no replay), THEN spawn the process-lifetime Task which does the prime recompute+write (fixes cold-start never-recorded) and only then loops over the captured stream. Priming before subscribing would drop any tick landing during the async 24h read.
  - On each tick read last 24h bsl via store.events(in:type:.bsl) (Double? value + Date timestamp -> GlucoseReading, same compactMap idiom as App/TrendsModel.swift:117), build the snapshot via GlucoseSnapshot.make, and write + WidgetCenter.shared.reloadTimelines(ofKind: GlucoseSnapshotStore.widgetKind) ONLY when the snapshot differs (value/trend/status/timestamp).
  - No unit test — behaviour verified on device (Decision 11).
  - Blocked-by: 7k39hje (Implement GlucoseWidgetShared DTO, enums, store Green), 7k39hjg (Implement TrendsMath glucoseRate / trend / bandStatus Green)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)
  - References: App/GlucoseWidgetPublisher.swift

- [x] 9. Wire publisher into App.swift + add medata://graph deep link <!-- id:7k39hjk -->
  - Construct and retain GlucoseWidgetPublisher for the process lifetime in App.swift init, BEFORE the glucose.registerBackgroundRefresh()/glucose.start() pair so the subscription exists first. Note App.swift's DEBUG UITestSupport branch returns early above those calls — decide deliberately whether the publisher is constructed above the early return (harness launches then do a store read, against the "hermetic" comment) or below it (no widget publishing under UI test); below it is the default.
  - Deep link is THREE edits, not one: (a) add DeepLinkTarget.graphCover; (b) add ("graph","")/("graph","/") to handleDeepLink with the capture case's three branches (insulin sheet up -> defer; nothing presented -> present .graph; other cover up -> defer); (c) handle .graphCover in BOTH dismissal sites — the fullScreenCover onDismiss switch AND the .sheet(isPresented: $showInsulinSheet) onDismiss, which currently tests `pendingDeepLink == .captureCover` by equality. Skipping (c) silently drops a widget tap made while the dose sheet is open.
  - The medata scheme is already registered in MeData/Info.plist (CFBundleURLTypes) — confirmed, no plist change needed.
  - Blocked-by: 7k39hjj (Implement GlucoseWidgetPublisher app-lifetime actor)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2)
  - References: App/App.swift, App/AppRoot.swift, MeData/Info.plist

## Widget extension

- [x] 10. Add App Group entitlements + Xcode target wiring <!-- id:7k39hjl -->
  - Add App Group group.rtob.MeData to MeData.entitlements (currently HealthKit keys only); create MeDataWidgets.entitlements with the same group.
  - Set CODE_SIGN_ENTITLEMENTS for the widget target; add the GlucoseWidgetShared product to the widget target. The widget target today has NO packageProductDependencies and a deliberately empty Frameworks phase (docs/agent-notes/widget-extension.md) — this is a hand-edit of an objectVersion-77 pbxproj using PBXFileSystemSynchronizedRootGroup, so it needs a new XCSwiftPackageProductDependency plus the matching Frameworks build-file entry, not just a setting. The app target already reaches GlucoseWidgetShared transitively via MedataCore -> Pipeline -> Persistence; adding it explicitly is optional.
  - Config/wiring only — provisioning is human-gated (prerequisites.md).
  - Blocked-by: 7k39hjc (Add GlucoseWidgetShared SwiftPM target + library product)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.6](requirements.md#1.6)
  - References: MeData/MeData.entitlements, MeData/MeDataWidgets/MeDataWidgets.entitlements, MeData/MeData.xcodeproj/project.pbxproj

- [x] 11. Implement GlucoseWidget data-driven kind + views <!-- id:7k39hjm -->
  - New StaticConfiguration(kind: GlucoseSnapshotStore.widgetKind). Define GlucoseEntry: TimelineEntry HERE (the WidgetKit adapter, Decision 12) over GlucoseTimeline.renderPoints, and map nextBoundary -> .after(_) / nil -> .never.
  - TimelineProvider witnesses (placeholder / getSnapshot / getTimeline) MUST be marked nonisolated explicitly — the target builds with SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, see the existing LauncherProvider and docs/agent-notes/widget-extension.md.
  - Per-family views (accessoryCircular / accessoryRectangular / accessoryInline) + StandBy; non-colour status token as the sole signal, per-status Color only under @Environment(\.widgetRenderingMode)==.fullColor; reduced opacity for the stale state; containerBackground clear (match LauncherView); functional copy only.
  - widgetURL medata://graph; register GlucoseWidget in the MeDataWidgets WidgetBundle. UI — verified on device.
  - Blocked-by: 7k39hje (Implement GlucoseWidgetShared DTO, enums, store Green), 7k39hji (Implement GlucoseRender + GlucoseTimeline Green), 7k39hjl (Add App Group entitlements + Xcode target wiring)
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [2.7](requirements.md#2.7), [2.8](requirements.md#2.8), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [7.1](requirements.md#7.1), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: MeData/MeDataWidgets/GlucoseWidget.swift, MeData/MeDataWidgets/MeDataWidgets.swift

## Verification

- [x] 12. Update docs/agent-notes/widget-extension.md for the data-driven kind <!-- id:7k39hjp -->
  - The note's closing line ("No data display: no persistence imports, no App Group ... Keep it that way unless a data-showing widget is actually specced") is now false — a data-showing widget IS specced. Record the third kind ie.medata.widget.glucose, the App Group group.rtob.MeData, and the GlucoseWidgetShared product as the only package product the appex links (still no GRDB and no network in the extension).
  - Keep the existing objectVersion-77 pbxproj and signing gotchas; add whatever the task-10 wiring turned up (packageProductDependencies + Frameworks-phase entry on a filesystem-synchronized target; CODE_SIGN_ENTITLEMENTS).
  - Blocked-by: 7k39hjm (Implement GlucoseWidget data-driven kind + views)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1)
  - References: docs/agent-notes/widget-extension.md

- [x] 13. Verify: make test + spell green, build embeds the extension <!-- id:7k39hjn -->
  - make test — both XCTest and swift-testing totals green (new GlucoseWidgetShared + TrendsMath tests included); make spell clean.
  - make build-app embeds MeDataWidgets.appex with the App Group entitlement (first build may need -allowProvisioningUpdates).
  - Blocked-by: 7k39hjk (Wire publisher into App.swift + add medata://graph deep link), 7k39hjm (Implement GlucoseWidget data-driven kind + views)
  - Stream: 1
  - Requirements: [3.5](requirements.md#3.5), [5.4](requirements.md#5.4)
  - References: specs/ui/glucose-lock-widget/prerequisites.md

- [x] 14. Human-gated on-device verification (STOP) <!-- id:7k39hjo -->
  - NOT agent-executable. Per prerequisites.md: App Group provisions and the snapshot round-trips app->extension (watch for the non-nil private-store misprovisioning trap; the cfprefsd console warning is benign).
  - Widget appears as a distinct gallery kind; monochrome Lock Screen render shows the status token without colour; StandBy-day colour enhancement; staleness ladder as a reading ages; tap opens the Graph from both locked and unlocked.
  - 2026-08-13 developer verdict: gate closed — renders fine on portrait and Lock Screen, App Group round-trip works (widget shows live data). One defect observed: the widget often falls out of sync until the phone is unlocked or the app is opened/refreshed — recorded as the follow-up task below, not a blocker for this gate
  - 2026-08-13 correction: StandBy-day colour could NOT be checked — StandBy runs while the phone is docked/locked, which is exactly the window the sync defect keeps stale; that check moves to the follow-up task's verification
  - Blocked-by: 7k39hjn (Verify: make test + spell green, build embeds the extension)
  - Stream: 1
  - Requirements: [1.7](requirements.md#1.7), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2)
  - References: specs/ui/glucose-lock-widget/prerequisites.md

## Follow-ups

- [ ] 15. Tighten the trend derivation against the observed CGM cadence
  - Deferred from Decision 15. MVP accepted a laggier, less certain arrow in exchange for it existing at all (33.5 % -> 99.1 % availability); these are the two things knowingly left approximate
  - Re-derive the four rate thresholds (0.056 / 0.111 / 0.166 mmol/L per min) for a 30-minute regression baseline — they were chosen for a 15-minute one, so the band edges are currently approximate
  - Make the window adapt to the observed cadence instead of being pinned at 30 min: measure the recent median gap and size the window at about twice it, so a true 5-minute feed gets a short responsive baseline and a 15-minute feed still qualifies
  - Consider surfacing the arrow's confidence (e.g. withhold the fast bands when the baseline is long) rather than presenting a 30-minute average slope with the same authority as a 5-minute one
  - Evidence to re-run: pull Documents/meals.sqlite per docs/agent-notes/device-build-and-test.md and redo the gap-distribution + availability simulation recorded in Decision 15
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3)
  - References: decision_log.md

- [ ] 16. Widget falls out of sync while the app is suspended
  - Observed 2026-08-13 during the task 14 device pass: the widget often shows a stale reading until the phone is unlocked or the app is opened and refreshed
  - Expected from the current architecture, not a regression: GlucoseWidgetPublisher is app-process-bound — it writes the snapshot and calls reloadTimelines only on CGM ticks while the app process is alive, so a suspended/killed app means no new snapshots; terminal timeline states use .never policy and wait for the app's explicit reload (docs/agent-notes/widget-extension.md)
  - Candidate directions: HealthKit background delivery waking the app to republish; a BGAppRefresh fallback; or having getTimeline read fresh data itself so the widget refreshes on its own budget — each needs a Decision entry weighing background-execution limits
  - Requires design + decision-log work before implementation; keep the estimation path untouched (offline invariant is unaffected — this is all local)
  - Verification must include the StandBy-day colour check deferred from task 14 — it needs the widget updating while docked/locked, which only this fix makes possible
  - [ ] 16.1. Extract LibreLinkUpKit — client, keychain, shared poll-interval constant
    - New Foundation-only SwiftPM target + library product LibreLinkUpKit holding LibreLinkUpClient, LibreLinkUpKeychain, and the shared 5-minute poll-interval constant (cgm-connect Decision 13); GlucoseIngestion links it; no Persistence/GRDB dependency
    - EstimationFirewallTests stays green — no estimation target gains LibreLinkUpKit in its closure; make test green
  - [ ] 16.2. Move pure derivation to GlucoseWidgetShared — snapshot-from-readings, trend, snapToGrid
    - Snapshot-from-readings derivation and TrendsMath.trend move from Persistence, snapToGrid from GlucoseIngestion, into GlucoseWidgetShared (Foundation-only); Persistence/GlucoseIngestion keep thin wrappers so app-side callers do not change
    - Existing tests move with the code; both make test totals stay green
  - [ ] 16.3. Uniform 5-minute baseline in the app poll loop (Decision 13)
    - LibreLinkUpGlucoseSource adopts the LibreLinkUpKit constant as its baseline; Decision 12 adaptive machinery stays in code, now dormant (every branch yields 5 min) — it is the recorded rollback position
    - Update the Decision 12 tests to pin the dormancy and keep the 5-minute floor assertion (vendor ban evidence at ~3 min)
  - [ ] 16.4. Shared vendor rate gate in the App Group
    - One last-fetch timestamp key in the App Group suite; LibreLinkUpGlucoseSource records every successful fetch and skips while the gate is younger than the interval; gate is advisory — no cross-process atomicity, rare double fetch accepted (Req 6.3)
  - [ ] 16.5. Shared-state migration — flag/host/patientId to App Group, keychain to shared access group
    - glucose.source.librelinkup.connected + resolved host + patientId move from UserDefaults.standard to the App Group suite; credentials/session keychain items move to a shared keychain access group (new entitlement on BOTH targets — profiles re-mint on next device build)
    - One-time idempotent launch migration copies existing values and removes the old copies; no-op once migrated
  - [ ] 16.6. Extension-side fetch in getTimeline + timeline policy change
    - getTimeline: snapshot younger than interval -> render stored; else gate check -> fetch (~8 s timeout) -> snapToGrid + derive -> GlucoseSnapshotStore.write -> render; ANY failure falls back to stored snapshot (Req 6.4)
    - Widget never re-logins: 401 -> fallback, auth repair is the app's (design: auth is app-owned); extension reads credentials/session only
    - Policy while connected flag set: .after(min(next staleness boundary, last fetch + interval)) — never .never; without a connected flag today's behaviour stands (screenshot-only users: zero widget network)
  - [ ] 16.7. STOP — device pass: locked-phone sync + StandBy colour + vendor-signal watch
    - On device: leave the phone locked across several poll intervals — the widget advances without unlocking or opening the app; StandBy-day colour check (deferred from task 14)
    - Watch logs/Settings for any LLU rate-limit or ban signal (429, status 920, forced re-login churn) — any such signal triggers the Decision 13 rollback: restore the 15-minute baseline, adaptive machinery resumes
    - make test green (both totals), make spell clean
