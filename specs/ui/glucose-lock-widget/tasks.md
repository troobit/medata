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

- [ ] 15. Tighten the trend derivation against the observed CGM cadence <!-- id:7k39hjr -->
  - Deferred from Decision 15. MVP accepted a laggier, less certain arrow in exchange for it existing at all (33.5 % -> 99.1 % availability); these are the two things knowingly left approximate
  - Re-derive the four rate thresholds (0.056 / 0.111 / 0.166 mmol/L per min) for a 30-minute regression baseline — they were chosen for a 15-minute one, so the band edges are currently approximate
  - Make the window adapt to the observed cadence instead of being pinned at 30 min: measure the recent median gap and size the window at about twice it, so a true 5-minute feed gets a short responsive baseline and a 15-minute feed still qualifies
  - Consider surfacing the arrow's confidence (e.g. withhold the fast bands when the baseline is long) rather than presenting a 30-minute average slope with the same authority as a 5-minute one
  - Evidence to re-run: pull Documents/meals.sqlite per docs/agent-notes/device-build-and-test.md and redo the gap-distribution + availability simulation recorded in Decision 15
  - Blocked-by: 7k39hjq (Widget falls out of sync while the app is suspended)
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3)
  - References: decision_log.md

- [-] 16. Widget falls out of sync while the app is suspended <!-- id:7k39hjq -->
  - Observed 2026-08-13 during the task 14 device pass: the widget often shows a stale reading until the phone is unlocked or the app is opened and refreshed
  - Expected from the current architecture, not a regression: GlucoseWidgetPublisher is app-process-bound — it writes the snapshot and calls reloadTimelines only on CGM ticks while the app process is alive, so a suspended/killed app means no new snapshots; terminal timeline states use .never policy and wait for the app's explicit reload (docs/agent-notes/widget-extension.md)
  - Candidate directions: HealthKit background delivery waking the app to republish; a BGAppRefresh fallback; or having getTimeline read fresh data itself so the widget refreshes on its own budget — each needs a Decision entry weighing background-execution limits
  - Requires design + decision-log work before implementation; keep the estimation path untouched (offline invariant is unaffected — this is all local)
  - Verification must include the StandBy-day colour check deferred from task 14 — it needs the widget updating while docked/locked, which only this fix makes possible
  - [x] 16.1. Extract LibreLinkUpKit — client, keychain, shared poll-interval constant
    - New Foundation-only SwiftPM target + library product LibreLinkUpKit holding LibreLinkUpClient, LibreLinkUpKeychain, and the shared 5-minute poll-interval constant (cgm-connect Decision 13); GlucoseIngestion links it; no Persistence/GRDB dependency
    - EstimationFirewallTests stays green — no estimation target gains LibreLinkUpKit in its closure; make test green
  - [x] 16.2. Move pure derivation to GlucoseWidgetShared — snapshot-from-readings, trend, snapToGrid
    - Snapshot-from-readings derivation and TrendsMath.trend move from Persistence, snapToGrid from GlucoseIngestion, into GlucoseWidgetShared (Foundation-only); Persistence/GlucoseIngestion keep thin wrappers so app-side callers do not change
    - Existing tests move with the code; both make test totals stay green
  - [x] 16.3. Uniform 5-minute baseline in the app poll loop (Decision 13)
    - LibreLinkUpGlucoseSource adopts the LibreLinkUpKit constant as its baseline; Decision 12 adaptive machinery stays in code, now dormant (every branch yields 5 min) — it is the recorded rollback position
    - Update the Decision 12 tests to pin the dormancy and keep the 5-minute floor assertion (vendor ban evidence at ~3 min)
  - [x] 16.4. Shared vendor rate gate in the App Group
    - One last-fetch timestamp key in the App Group suite; LibreLinkUpGlucoseSource records every successful fetch and skips while the gate is younger than the interval; gate is advisory — no cross-process atomicity, rare double fetch accepted (Req 6.3)
  - [x] 16.5. Shared-state migration — flag/host/patientId to App Group, keychain to shared access group
    - glucose.source.librelinkup.connected + resolved host + patientId move from UserDefaults.standard to the App Group suite; credentials/session keychain items move to a shared keychain access group (new entitlement on BOTH targets — profiles re-mint on next device build)
    - One-time idempotent launch migration copies existing values and removes the old copies; no-op once migrated
  - [x] 16.6. Extension-side fetch in getTimeline + timeline policy change
    - getTimeline: snapshot younger than interval -> render stored; else gate check -> fetch (~8 s timeout) -> snapToGrid + derive -> GlucoseSnapshotStore.write -> render; ANY failure falls back to stored snapshot (Req 6.4)
    - Widget never re-logins: 401 -> fallback, auth repair is the app's (design: auth is app-owned); extension reads credentials/session only
    - Policy while connected flag set: .after(min(next staleness boundary, last fetch + interval)) — never .never; without a connected flag today's behaviour stands (screenshot-only users: zero widget network)
  - [x] 16.7. STOP — device pass: locked-phone sync + StandBy colour + vendor-signal watch
    - On device: leave the phone locked across several poll intervals — the widget advances without unlocking or opening the app at WidgetKit's own cadence, measured at ~20 minutes against the 5 minutes every timeline asks for, so the displayed reading is up to ~22 minutes old at worst. That bound is the criterion: it is WidgetKit's wake budget, not anything in the fetch path, and it is accepted as a documented gap rather than chased (developer call, 2026-08-14). Decision 18 carries the reasoning; task 16.10 states it in requirements; StandBy-day colour check (deferred from task 14)
    - Watch logs/Settings for any LLU rate-limit or ban signal (429, status 920, forced re-login churn) — any such signal triggers the Decision 13 rollback: restore the 15-minute baseline, adaptive machinery resumes
    - make test green (both totals), make spell clean
    - 2026-08-13 attempt 1: the widget rendered 16.0 with the high status in full colour, but at an age of 9m49s while the app was suspended, and refreshed only once the app was opened (opening the Libre app did not help). 9m49s sits inside Req 5.1's fresh band, so the ladder is not at fault — the clause that failed is Req 6.2's self-fetch
    - Attempt 1 was undiagnosable: the extension carried no logging, so which of getTimeline's four guards ran — or whether WidgetKit woke it at all — could not be told apart. Instrumented with one event=widget.timeline line per wake, at .notice level because .info never survives a device log collect
    - BULLET 1 PASSES (2026-08-13 23:05 to 2026-08-14 00:05, build 8e6c651-20260813-173737, phone locked, app suspended): three wakes in the window, all outcome=refreshed — the widget fetched for itself with no unlock and no app open, which is what Decision 16 was built for
    - But not at the requested cadence. Wakes landed 23:17:32, 23:37:54, 23:58:00 — gaps of 20m22s and 20m06s against a nextWakeSeconds=300 request on every one of them, so WidgetKit granted about a quarter of what the timeline asked for. storedAgeSeconds at each wake was 752, 1374, 1380: the snapshot had aged 12 to 23 minutes before a wake arrived. renderedAgeSeconds after the fetch was 152, 174 and -119, so the tile lands at roughly 2-3 minutes old and then ages until the next wake — worst-case displayed age about 22 minutes
    - Consequence for this task's own wording: `advances without unlocking` is met and should be recorded as met. A `never older than one poll interval` reading of the same bullet is NOT achievable — the measured ceiling is WidgetKit's wake budget, not anything in the fetch path. Reword the criterion to the measured bound rather than chasing it
    - BULLET 3 CLEAN so far: no 429, no status 920, no re-login churn, and no error or fault from subsystem ie.medata.app anywhere in the collected window. The Decision 13 rollback is not triggered
    - BULLET 2 CLOSES: StandBy-day colour renders. Portrait StandBy at the high band shows orange, which is the result the check existed for — the only thing that can suppress the whole colour channel is `guard renderingMode == .fullColor` in `tint(_:)`, and high resolving proves it reports full colour on that surface. In-range rendering white is correct, not unstyled (`tint(.inRange)` is `.primary`, `token(.inRange)` is nil — an absent token IS in-range, Req 4.3/Decision 7). Low was not observed on-device and is accepted on construction: same switch, same function, same guard the high pass exercised, differing only in the Color literal. Recorded in docs/agent-notes/widget-extension.md
    - The negative check was already met at task 14, whose closed gate covers `monochrome Lock Screen render shows the status token without colour` — Lock Screen accessory widgets are always vibrant, so the HI token seen there carries status with the colour channel unavailable. Req 4.3's `colour is an enhancement, never the sole signal` therefore holds on both surfaces
    - Surface identification, if it is ever in doubt again: tap the tile. Only this kind deep-links to `medata://graph` (Req 7.1), so the Graph opening identifies both the widget and the surface it was tapped on — cheaper than reasoning about which pool a tile came from
    - make test 2026-08-13: XCTest 573 executed / 3 skipped / 0 failures; swift-testing 411 tests / 1 failure — EndToEndCalibrateBakeTests fails in generate.py on PEP 604 `str | None` because PATH-resolved python3 on this machine is Apple's 3.9.6. Environmental, in the food-db bake path, untouched by this work, but it did block this task's `both totals green` criterion as written
    - make test 2026-08-14 GREEN, both totals: XCTest 573 executed / 3 skipped / 0 failures; swift-testing 411 tests in 48 suites, all passed. The only change was interpreter selection — the test shells out through `/usr/bin/env python3` (EndToEndCalibrateBakeTests.swift, deliberately PATH-resolved so the bake runs on the repo's tooling python), and this machine has Homebrew 3.14.6 at /opt/homebrew/bin behind Apple's 3.9.6 at /usr/bin. Running `PATH=/opt/homebrew/bin:$PATH make test` passes. Nothing in the tree changed; if the criterion is to hold without the prefix, the machine's PATH order is the thing to fix, not the test. make spell clean
    - NEW DEFECT observed at 00:04:55, since filed as task 16.9 / Decision 19: the app publisher can move the shared snapshot BACKWARDS. Two ticks 123 ms apart logged was=14:00:00Z now=13:50:00Z (lagSeconds=895) and then was=13:50:00Z now=14:05:00Z — the widget's own fetch had written 14:00:00Z, the app recomputed 13:50:00Z from the database, which had not yet ingested that reading, and overwrote it. GlucoseWidgetPublisher writes when the snapshot DIFFERS, not when it is NEWER, so a suspended-app catch-up can regress the tile by a poll interval. Decision 16 anticipated the snapshot leading the database but not the publisher rolling it back
  - [x] 16.8. Widget wake backoff — the shared gate counts requests sent (Decision 17)
    - Found by inspection during the 16.7 pass, not by the pass itself: LibreLinkUpRateGate.recordFetch ran only after a good response, so a failed vendor request left the gate stamp old, nextWake computed a reopen instant already in the past, and the one-second floor turned it into `reload as soon as possible` — the extension asked WidgetKit to re-run immediately for as long as the failure lasted, spending the daily reload budget the locked-phone window depends on
    - Decision 17: record the request before it is sent (both the widget and LibreLinkUpGlucoseSource, so one rule covers both processes), and floor the widget's next wake at one poll interval instead of one second — every staleness transition already ships as a timeline entry, so a wake exists only to fetch and a fetch inside the interval is refused by the gate
    - Req 6.3 redefined in place (records each request sent, not each successful fetch); docs/agent-notes/widget-extension.md carries the floor and the recording order as do-not-revert notes
    - No new test scaffolding (MVP test gate); the rate gate had no tests before this either. Verified by build + the 16.7 device pass
  - [ ] 16.9. Monotonic publish guard — drop a publish carrying an older readingDate (Decision 19)
  - [ ] 16.10. State the accepted stale window in requirements — staleAge 15m vs ~20m reload cadence (Decision 18)
