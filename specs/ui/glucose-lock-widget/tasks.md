---
references:
    - specs/ui/glucose-lock-widget/requirements.md
    - specs/ui/glucose-lock-widget/design.md
    - specs/ui/glucose-lock-widget/decision_log.md
    - specs/ui/glucose-lock-widget/prerequisites.md
---
# Glucose Lock Screen Widget — Implementation Tasks

## Shared contract & pure logic (MedataCore)

- [ ] 1. Add GlucoseWidgetShared SwiftPM target + library product <!-- id:7k39hjc -->
  - New Foundation-only target at MedataCore/Sources/GlucoseWidgetShared/ exposed as its own .library product (discrete, not umbrella) so the extension links exactly it and cannot pull GRDB (Decision 10).
  - Add the Persistence -> GlucoseWidgetShared dependency edge (TrendsMath returns GlucoseTrend).
  - Config/wiring only — no preceding test.
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1)
  - References: Package.swift, specs/ui/glucose-lock-widget/design.md

- [ ] 2. Write GlucoseWidgetShared tests (Red) <!-- id:7k39hjd -->
  - GlucoseSnapshot encode/decode round-trip identity; unknown-version blob -> .neverRecorded; corrupt/undecodable blob -> .neverRecorded.
  - Snapshot builder sanity guard: non-finite or mmolL outside ~1.0-35.0 -> .neverRecorded.
  - dump-package assertion: GlucoseWidgetShared has an empty dependency list (mirrors cgm-connect firewall test).
  - Blocked-by: 7k39hjc (Add GlucoseWidgetShared SwiftPM target + library product)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [1.7](requirements.md#1.7), [2.7](requirements.md#2.7), [8.1](requirements.md#8.1)
  - References: MedataCore/Tests/GlucoseWidgetSharedTests/

- [ ] 3. Implement GlucoseWidgetShared DTO, enums, store (Green) <!-- id:7k39hje -->
  - GlucoseSnapshot Codable (version, mmolL?, readingDate?, trend?, status?) + .neverRecorded + sanity-guarded builder.
  - GlucoseTrend (7 states, arrow glyph) and GlucoseBandStatus (low/inRange/high) enums.
  - appGroupID = group.rtob.MeData; GlucoseSnapshotStore.read/write as a single JSON blob under one key in UserDefaults(suiteName:), nil-suite -> write no-op / read .neverRecorded.
  - Blocked-by: 7k39hjd (Write GlucoseWidgetShared tests Red)
  - Stream: 1
  - Requirements: [1.1](requirements.md#1.1), [1.5](requirements.md#1.5), [1.6](requirements.md#1.6), [1.7](requirements.md#1.7), [2.7](requirements.md#2.7), [4.1](requirements.md#4.1), [8.1](requirements.md#8.1)
  - References: MedataCore/Sources/GlucoseWidgetShared/

- [ ] 4. Write TrendsMath trend/rate/bandStatus tests (Red) <!-- id:7k39hjf -->
  - glucoseRate: exact threshold boundaries 0.056/0.111/0.166 (and negatives), half-open inclusivity; <2 readings and <10-min span -> nil; latest reading >15 min old -> nil; sign -> up/down direction.
  - bandStatus: 3.9 and 10.0 boundaries (low <3.9, in-range inclusive, high >10.0).
  - Blocked-by: 7k39hje (Implement GlucoseWidgetShared DTO, enums, store Green)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1)
  - References: MedataCore/Tests/PersistenceTests/

- [ ] 5. Implement TrendsMath glucoseRate / trend / bandStatus (Green) <!-- id:7k39hjg -->
  - glucoseRate: least-squares slope (mmol/L per min) over readings within 15 min preceding now; nil unless >=2 readings AND earliest-latest span >=10 min.
  - trend: |rate| -> steady/slow/medium/fast band, sign -> direction, returning GlucoseTrend.
  - bandStatus: reuse targetLowMmolL / targetHighMmolL.
  - Blocked-by: 7k39hjf (Write TrendsMath trend/rate/bandStatus tests Red)
  - Stream: 1
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5), [4.1](requirements.md#4.1)
  - References: MedataCore/Sources/Persistence/TrendsMath.swift

- [ ] 6. Write GlucoseTimeline render/entries tests (Red) <!-- id:7k39hjh -->
  - render(snapshot, at:) crosses fresh -> stale -> lastReading at readingDate+15m and +30m; neverRecorded distinct from lastReading.
  - entries(snapshot, from:) instants anchored to readingDate: reference, max(ref, readingDate+15m), max(ref, readingDate+30m); single entry when already >30m stale or never-recorded.
  - age string: whole minutes <1h then whole hours; future readingDate clamps to age 0 (rendered fresh).
  - Blocked-by: 7k39hje (Implement GlucoseWidgetShared DTO, enums, store Green)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [8.1](requirements.md#8.1)
  - References: MedataCore/Tests/GlucoseWidgetSharedTests/

- [ ] 7. Implement GlucoseRender + GlucoseTimeline (Green) <!-- id:7k39hji -->
  - GlucoseRender enum: fresh(value,status,trend?) / stale(value,age) / lastReading(age) / neverRecorded.
  - GlucoseTimeline.render + entries as tested; per-state reload policy exposed for the provider (.after next boundary for fresh/stale, .never for lastReading/neverRecorded).
  - Lives in GlucoseWidgetShared so it is MedataCore-testable and importable by the widget.
  - Blocked-by: 7k39hjh (Write GlucoseTimeline render/entries tests Red)
  - Stream: 1
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [6.2](requirements.md#6.2), [8.1](requirements.md#8.1)
  - References: MedataCore/Sources/GlucoseWidgetShared/

## App integration

- [ ] 8. Implement GlucoseWidgetPublisher (app-lifetime actor) <!-- id:7k39hjj -->
  - actor (not @MainActor): prime recompute+write at construction before subscribing (fixes cold-start never-recorded).
  - Process-lifetime Task consuming store.eventsDidChange; on each tick read last 24h bsl via store.events(in:type:.bsl), map to GlucoseReading, build snapshot, and write + WidgetCenter.shared.reloadTimelines(ofKind:) ONLY when the snapshot differs (value/trend/status/timestamp).
  - No unit test — behaviour verified on device (Decision 11).
  - Blocked-by: 7k39hje (Implement GlucoseWidgetShared DTO, enums, store Green), 7k39hjg (Implement TrendsMath glucoseRate / trend / bandStatus Green)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4), [6.1](requirements.md#6.1), [6.2](requirements.md#6.2)
  - References: App/GlucoseWidgetPublisher.swift

- [ ] 9. Wire publisher into App.swift + add medata://graph deep link <!-- id:7k39hjk -->
  - Construct and retain GlucoseWidgetPublisher for the process lifetime, with its stream subscription established before glucose sources start.
  - Add ("graph","")/("graph","/") case to AppRoot.handleDeepLink mirroring the capture dismiss-then-present sequencing onto .graph; confirm the medata scheme is already registered in Info.plist.
  - Blocked-by: 7k39hjj (Implement GlucoseWidgetPublisher app-lifetime actor)
  - Stream: 1
  - Requirements: [1.2](requirements.md#1.2), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2)
  - References: App/App.swift, App/AppRoot.swift, MeData/Info.plist

## Widget extension

- [ ] 10. Add App Group entitlements + Xcode target wiring <!-- id:7k39hjl -->
  - Add App Group group.rtob.MeData to MeData.entitlements; create MeDataWidgets.entitlements with the same group.
  - Set CODE_SIGN_ENTITLEMENTS for the widget target; link the GlucoseWidgetShared product into BOTH the app and widget targets.
  - Config/wiring only — provisioning is human-gated (prerequisites.md).
  - Blocked-by: 7k39hjc (Add GlucoseWidgetShared SwiftPM target + library product)
  - Stream: 2
  - Requirements: [1.1](requirements.md#1.1), [1.6](requirements.md#1.6)
  - References: MeData/MeData.entitlements, MeData/MeDataWidgets/MeDataWidgets.entitlements, MeData/MeData.xcodeproj/project.pbxproj

- [ ] 11. Implement GlucoseWidget data-driven kind + views <!-- id:7k39hjm -->
  - New StaticConfiguration with a distinct kind id; TimelineProvider reads GlucoseSnapshotStore and emits GlucoseTimeline.entries with the per-state reload policy.
  - Per-family views (accessoryCircular / accessoryRectangular / accessoryInline) + StandBy; non-colour status token as the sole signal, per-status Color only under @Environment(\.widgetRenderingMode)==.fullColor; reduced opacity for the stale state; containerBackground clear (match LauncherView); functional copy only.
  - widgetURL medata://graph; register GlucoseWidget in the MeDataWidgets WidgetBundle. UI — verified on device.
  - Blocked-by: 7k39hje (Implement GlucoseWidgetShared DTO, enums, store Green), 7k39hji (Implement GlucoseRender + GlucoseTimeline Green), 7k39hjl (Add App Group entitlements + Xcode target wiring)
  - Stream: 2
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6), [2.7](requirements.md#2.7), [2.8](requirements.md#2.8), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.4](requirements.md#4.4), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [7.1](requirements.md#7.1), [8.1](requirements.md#8.1), [8.2](requirements.md#8.2)
  - References: MeData/MeDataWidgets/GlucoseWidget.swift, MeData/MeDataWidgets/MeDataWidgets.swift

## Verification

- [ ] 12. Verify: make test + spell green, build embeds the extension <!-- id:7k39hjn -->
  - make test — both XCTest and swift-testing totals green (new GlucoseWidgetShared + TrendsMath tests included); make spell clean.
  - make build-app embeds MeDataWidgets.appex with the App Group entitlement (first build may need -allowProvisioningUpdates).
  - Blocked-by: 7k39hjk (Wire publisher into App.swift + add medata://graph deep link), 7k39hjm (Implement GlucoseWidget data-driven kind + views)
  - Stream: 1
  - Requirements: [3.5](requirements.md#3.5), [5.4](requirements.md#5.4)
  - References: specs/ui/glucose-lock-widget/prerequisites.md

- [ ] 13. Human-gated on-device verification (STOP) <!-- id:7k39hjo -->
  - NOT agent-executable. Per prerequisites.md: App Group provisions and the snapshot round-trips app->extension (watch for the non-nil private-store misprovisioning trap; the cfprefsd console warning is benign).
  - Widget appears as a distinct gallery kind; monochrome Lock Screen render shows the status token without colour; StandBy-day colour enhancement; staleness ladder as a reading ages; tap opens the Graph from both locked and unlocked.
  - Blocked-by: 7k39hjn (Verify: make test + spell green, build embeds the extension)
  - Stream: 1
  - Requirements: [1.7](requirements.md#1.7), [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [7.1](requirements.md#7.1), [7.2](requirements.md#7.2)
  - References: specs/ui/glucose-lock-widget/prerequisites.md
