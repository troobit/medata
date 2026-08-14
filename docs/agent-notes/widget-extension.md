# MeDataWidgets extension

Widget extension target `MeDataWidgets`, sources at `MeData/MeDataWidgets/`
(`MeDataWidgets.swift` + `GlucoseWidget.swift` + Info.plist + entitlements).
THREE kinds in one `WidgetBundle`:

| Kind | File | Data | Tap |
|---|---|---|---|
| `ie.medata.widget.insulin` | `MeDataWidgets.swift` | none | `medata://insulin/add` |
| `ie.medata.widget.capture` | `MeDataWidgets.swift` | none | `medata://capture` |
| `ie.medata.widget.glucose` | `GlucoseWidget.swift` | App Group snapshot, plus its own LibreLinkUp fetch when the app is suspended (Decision 16) | `medata://graph` |

Lock-screen accessory widgets carry a SINGLE tap target — that is why dose and
capture are separate kinds, not two buttons in one widget, and why the glucose
kind's whole view is one `widgetURL`. Deep links are handled by
`App/AppRoot.swift handleDeepLink` (see `insulin-dose-ui.md`).

The two LAUNCHER kinds display no data: no persistence imports, `Timeline`
policy `.never`, no network. Keep them that way — the App Group, the snapshot
read and the vendor fetch belong to the glucose kind alone. The 30 MB memory cap
and the no-GRDB rule bind every kind in the bundle; the no-network rule binds
the launchers only, since Decision 16 (see the last section).

Families differ by kind: the launchers support `accessoryCircular`,
`accessoryRectangular` and `systemSmall`; glucose supports those three plus
`accessoryInline`.

Glucose carries `systemSmall` **only to reach StandBy**. StandBy's widget panel
is populated from the Home Screen pool — `systemSmall` is auto-promoted into it
and accessory families never appear there — and `supportedFamilies` cannot
discriminate by placement, so the Home Screen listing is an unavoidable side
effect, not a wanted placement. Decision 3 originally rejected `systemSmall`
while requiring StandBy, which is unbuildable; it was amended on 2026-08-03
after task-14 device verification found the widget absent from StandBy. Do not
"tidy up" the family back out without also dropping the StandBy requirement.

## pbxproj setup (hand-edited, objectVersion 77)

- Sources attach via a `PBXFileSystemSynchronizedRootGroup` (path
  `MeDataWidgets`, relative to the project dir `MeData/`) listed in the
  target's `fileSystemSynchronizedGroups` — NO per-file PBXBuildFile entries.
  Files dropped into the folder are picked up automatically.
- `Info.plist` inside the synced folder is excluded from build phases via a
  `PBXFileSystemSynchronizedBuildFileExceptionSet` (`membershipExceptions`).
  It carries only `NSExtension → NSExtensionPointIdentifier =
  com.apple.widgetkit-extension`; the rest merges from
  `GENERATE_INFOPLIST_FILE = YES` + `INFOPLIST_FILE = MeDataWidgets/Info.plist`.
- App target embeds the appex via a `PBXCopyFilesBuildPhase`
  ("Embed Foundation Extensions", `dstSubfolderSpec = 13`) plus a
  `PBXTargetDependency`/`PBXContainerItemProxy` pair.
- Widget build settings mirror the app: team `6G974YC4Z2`, automatic signing,
  `IPHONEOS_DEPLOYMENT_TARGET = 26.5`, `MARKETING_VERSION = 1.0` (appex
  CFBundleShortVersionString MUST match the app's), `SKIP_INSTALL = YES`,
  bundle id `rtob.MeData.MeDataWidgets`, plus
  `@executable_path/../../Frameworks` in runpaths.

## Gotchas

- **First build fails signing**: the wildcard team profile did not include the
  device for the new bundle id. One `xcodebuild … -allowProvisioningUpdates
  build` mints the profile; plain `make build-app` works from then on.
- **Debug appex binary looks empty**: Xcode 26 Debug builds emit a
  "blank executor" stub as the appex main executable; the real code (and any
  strings you grep for) is in `MeDataWidgets.appex/MeDataWidgets.debug.dylib`.
- `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` means `TimelineProvider` witness
  methods must be marked `nonisolated` explicitly.
- Widget targets auto-link WidgetKit/SwiftUI; the Frameworks build phase held
  nothing until `GlucoseWidgetShared` was added (below). Do not add the
  `MedataCore` umbrella product — it would drag GRDB into the extension.

## App Group + GlucoseWidgetShared

- App Group `group.rtob.MeData` is declared in BOTH
  `MeData/MeData.entitlements` and `MeData/MeDataWidgets/MeDataWidgets.entitlements`;
  the widget target sets
  `CODE_SIGN_ENTITLEMENTS = MeDataWidgets/MeDataWidgets.entitlements` in Debug
  and Release. The entitlements file sits inside the synchronized folder, so it
  is listed in `membershipExceptions` beside `Info.plist` to keep it out of the
  build phases — `CODE_SIGN_ENTITLEMENTS` is a path setting, not a membership.
- The linked package products are `GlucoseWidgetShared` (Foundation-only, zero
  deps) and, since Decision 16, `LibreLinkUpKit` (Foundation-only, depends on
  GlucoseWidgetShared alone). Wiring one into an objectVersion-77 pbxproj needs THREE objects,
  not a build setting: an `XCSwiftPackageProductDependency`, a `PBXBuildFile`
  with `productRef` pointing at it, and that build file listed in the widget's
  `PBXFrameworksBuildPhase` — plus the dependency in the target's
  `packageProductDependencies`.
- **Adding the App Group breaks signing until the profiles are re-minted.**
  A device/generic-iOS build fails with `Provisioning profile … doesn't include
  the App Groups capability` for both `rtob.MeData` and the wildcard widget
  profile. Fix is one `xcodebuild … -allowProvisioningUpdates build` (or the
  Xcode capability toggle) — same dance as the original widget bundle id. A
  simulator build with `CODE_SIGNING_ALLOWED=NO` compiles and links fine and is
  the way to verify the pbxproj wiring without touching provisioning.
- **Verifying the wiring without provisioning** (what task 13 checks): build with
  `-destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO`, then confirm
  (a) `MeData.app/PlugIns/MeDataWidgets.appex` exists,
  (b) `…/MeDataWidgets.build/Objects-normal/arm64/MeDataWidgets.LinkFileList`
  lists `GlucoseWidgetShared.o` and nothing else beyond the two target objects,
  (c) `strings …/MeDataWidgets.debug.dylib | grep ie.medata.widget` shows all
  three kinds and `otool -L` on it shows no GRDB. Grep the `.debug.dylib`, not
  the 72 KB stub executable. What this CANNOT prove is that the App Group
  entitlement survives signing — that needs the device build (task 14).

## Glucose kind data flow

App side is `App/GlucoseWidgetPublisher.swift`, an `actor` (deliberately not
`@MainActor` — it runs on every CGM tick) held for the process lifetime by
`App.swift`. It reads the trailing 24 h of `bsl` rows, builds a
`GlucoseSnapshot`, and writes + reloads ONLY when the value differs from what
is already stored AND carries a newer reading. Reloads are scoped:
`reloadTimelines(ofKind:)` with the glucose kind, so glucose writes do not spend
the shared WidgetKit reload budget on the co-hosted launchers.

- **The store is monotonic in `readingDate`** (Decision 19, Req 1.8). The
  ordering test lives in `GlucoseSnapshotStore.write`, not in either writer,
  because there are two of them — put it on the app side only and the widget's
  own fetches escape it, and so would a third writer. `write` returns whether
  the snapshot landed: the app skips its reload when it did not
  (`event=publish.dropped reason=notNewer`), and the widget renders the stored
  snapshot instead of its own derivation (`outcome=notNewer`). Strictly newer,
  so an equal-dated recompute is a no-op rather than two writers alternating
  derivations of one reading. A candidate with a nil `readingDate` is the
  never-recorded state and is still written — block that and emptying the `bsl`
  history could never clear the tile.

- The contract is one `Codable` blob under one key in
  `UserDefaults(suiteName: "group.rtob.MeData")` — plist-level atomicity, so a
  concurrent reader sees the old blob or the new one, never a splice. Both
  sides go through `GlucoseSnapshotStore` (`widgetKind`, `write`, `read`); the
  kind string is pinned there because app and extension are separate targets
  and the two literals must match exactly.
- **A nil suite is not a misprovisioning detector.**
  `UserDefaults(suiteName:)` returns nil only for an invalid or own-bundle
  name. A missing App Group entitlement still yields a non-nil PRIVATE store,
  so the app writes where the widget cannot see and the widget shows
  never-recorded. Only the on-device round trip catches it (see
  `specs/ui/glucose-lock-widget/prerequisites.md`). The
  `CFPrefsPlistSource … detaching from cfprefsd` console warning is expected
  with App Group suites and is not a failure.
- Atomicity is not freshness: each process caches its own CFPreferences view,
  so nothing may depend on an immediate cross-process read-back. The ordering
  works because the widget reads inside a `getTimeline` that the app's reload
  triggered.
- All staleness/render logic is pure and lives in `GlucoseTimeline` /
  `TrendsMath` inside the package; `GlucoseWidget.swift` is only the WidgetKit
  adapter plus per-family views. Keep new display rules on the package side
  where they are testable — the appex has no executable test target.
- One exception the pure ladder cannot express: a FRESH entry spans up to 15
  minutes of wall time, so its age is rendered with `Text(_, style: .relative)`
  from a `readingDate` carried on the entry, rather than a baked string that
  would read "0m" for most of that window.
- The timeline policy is `.after(nextBoundary)` while a staleness transition is
  still ahead, and `.never` once the state is terminal (last-reading /
  never-recorded) — a terminal state cannot advance on its own and waits for
  the app's explicit reload.

## Field-observed limitation (2026-08-13, task 14 device pass) — and the fix

Task 14's device pass closed: App Group round-trips, portrait and Lock Screen
renders are fine. But the widget **often fell out of sync until the phone was
unlocked or the app was opened and refreshed**. This was the architecture above
behaving as built, not a bug in the render path: the publisher only runs while
the app process is alive, so nothing republished the snapshot or reloaded the
timeline while the app was suspended.

Task 16 / Decision 16 fixes it by letting `getTimeline` fetch for itself. The
widget is therefore **no longer network-free** — the "no network" rule in the
table above now binds the two LAUNCHER kinds only. What still binds every kind:
the 30 MB memory cap and no GRDB.

- `GlucoseProvider.refreshedSnapshot` is the whole path, and every branch of it
  falls back to the stored snapshot — a failed, gated or unconfigured fetch
  renders exactly what it would have rendered before. There is no error state.
- Four conditions must all hold before a request goes out: the shared connected
  flag is set, the stored reading is at least `LibreLinkUpPolling.interval` old,
  the shared `LibreLinkUpRateGate` is open, and a usable session + patient id are
  readable. A screenshot-import-only user fails the first and never transmits.
- **The widget never logs in.** It reads the session from the shared keychain
  group; a 401 falls back and leaves auth repair to the app. Do not "improve"
  this into a re-login — two processes repairing one session item is the race
  Decision 16 avoided by construction.
- Readings are snapped and rounded through `GlucoseGrid` before
  `GlucoseDerivation.snapshot` — the same helpers the ingest path uses. Deriving
  from raw vendor instants here would make the arrow differ between the widget
  and the app for identical data.
- Timeline policy changed with it: with a connection configured the provider
  never returns `.never` (a widget that can refresh itself must keep being
  woken, and the last-reading state is where a wake helps most). It books
  whichever comes first — the next staleness boundary or the moment the rate
  gate reopens — **floored at one poll interval from now** (Decision 17).
  Never lower that floor: the ladder transitions ship as timeline entries, so a
  wake exists only to fetch, and a fetch inside the interval is refused by the
  gate. A sooner wake spends the daily reload budget on nothing, and that budget
  is what the locked-phone window runs on. Without a connection, the old
  `.never`-when-terminal rule stands.
- `LibreLinkUpRateGate.recordFetch` is called **before** the request goes out,
  on both the widget and app sides (Decision 17). It records requests, not
  successes — that is what gives a failing fetch its one-interval backoff. Move
  it back after the response and a 401 loop books "reload as soon as possible"
  on every wake until the budget is gone.
- `getTimeline` logs one `event=widget.timeline` line per wake with
  `outcome=` (the branch of `refreshedSnapshot`), the stored and rendered
  reading ages, and the booked wake delay — subsystem `ie.medata.app`, category
  `GlucoseWidget`, so `make logs-device` interleaves it with the app's
  publishes. No such line during a locked stretch means WidgetKit never woke the
  extension, which is a budget observation and not a code defect.
- The shared snapshot can now briefly lead the database. That is intended: the
  snapshot is a display contract, nothing reads it back into persistence, and
  the app ingests the same readings on its next poll. What makes leading *safe*
  rather than merely tolerated is the ordering guard in
  `GlucoseSnapshotStore.write` (Decision 19, above): the app's catch-up cannot
  publish the database's older reading over the widget's newer one.

The extension links **two** package products now — `GlucoseWidgetShared` and
`LibreLinkUpKit` — each needing the same three pbxproj objects described above.
Both targets also carry a `keychain-access-groups` entitlement
(`$(AppIdentifierPrefix)rtob.MeData.shared`), which must stay in step with
`LibreLinkUpKeychain.accessGroup`; that constant spells the team prefix out, so
`codesign -d --entitlements -` on the appex is the check that they match.

## What actually schedules a reload (2026-08-13, task 16.7, 3 h tethered)

**The `.after(date)` policy is advisory. It is not what wakes this widget.**
Measured over three hours with the app suspended for most of it: nine extension
wakes, every one booking `nextWakeSeconds=300`, none arriving at 300 s. Gaps were
20.1, 20.7, 20.1, 20.1, 22.2, 20.1, 20.1 minutes (the one 15.0 gap was the app's
own `publish.reloadRequested`, not a WidgetKit wake).

`com.apple.chrono` records the trigger for each reload. Over the window:
**14 × `Reload widget for reason: stale`, 4 × `environmentMismatch`, 0 from the
booked date**, each staleness reload preceded by `Widget is visible and
effectively stale, reloading content.` So the cadence is WidgetKit's own
staleness evaluation, gated on visibility — keyed on `GlucoseTimeline.staleAge`,
not on anything the provider books.

Consequences, all recorded as Decision 18:

- **`staleAge` (15 min) < cadence (~20 min), so the widget routinely renders
  stale for several minutes of each cycle.** Working as designed, not a bug.
- **Do not raise `staleAge` to close that gap.** It is the reload trigger, so
  raising it postpones the refresh by the same amount it buys, and the widget
  spends that time rendering stale data relabelled as fresh.
- **Do not lower the Decision 17 wake floor.** If the booked date is not honoured
  at all, an earlier one cannot produce an earlier wake — only budget spend.
- The ~20 min figure is one device, one window, with the widget periodically
  visible; "visible" is part of the trigger, so a locked-and-untouched stretch is
  what would separate system cadence from how often the phone was woken. The
  *trigger* observation does not depend on the number.

Read the wake lines as: `storedAgeSeconds` is how stale the App Group snapshot
was when the extension ran, `renderedAgeSeconds` is what shipped after
`refreshedSnapshot`. Eight of nine wakes rendered 0–2.2 min old against stored
ages of 19–24 min — **Decision 16's self-fetch is carrying the entire locked
window**. The one stale render (29.8 min, `outcome=refreshed`) was a real
45-minute vendor gap, nothing fresher to fetch.

### Negative ages are normal

`renderedAgeSeconds` goes negative (observed -1.1, -0.9, -0.2, -0.1 min, with
`event=publish.futureReading skewSeconds=` 13 and 1). The vendor stamps readings
on the next 5-minute boundary, so a reading can arrive dated slightly ahead. The
ladder handles it — `age <= staleAge` is true for negatives, so it renders fresh.
But the fresh branch renders age with `Text(_, style: .relative)` (Decision 14),
which on a future date reads as a countdown. Not yet checked on-screen.

### Prime could publish backwards (fixed in task 16.9, Decision 19)

Seen at launch: `trigger=prime was=…10:55:00Z now=…09:55:00Z lagSeconds=4670` —
the app republished an hour-old reading over the newer one the widget had
fetched while the app was suspended, because prime reads the database and the
widget's fetches never write back to it. The next tick corrected it 274 ms later.
The publisher gated on *value differs*, which is a change test; with two writers
it needs an ordering test on `readingDate`.

Fixed by making `GlucoseSnapshotStore.write` itself monotonic (see the data-flow
section above), so both writers — and any third one added later — are covered
without either of them opting in. **Not verified on device**: the fix landed
without a device pass, so the field confirmation is a missing
`event=publish.dropped reason=notNewer` line at a launch that would previously
have logged a backwards `publish.reloadRequested`.

## StandBy colour (2026-08-13, task 16.7 device pass)

Portrait StandBy, **high** band: orange renders. That is the result that matters,
because the open question was whether `renderingMode` reports `.fullColor` in
StandBy at all — the `guard renderingMode == .fullColor else { return .primary }`
in `tint(_:)` is the only thing that can suppress the whole colour channel, and
`high` proved it resolves.

- **In-range renders white by design.** `tint(.inRange)` is `.primary` and
  `token(.inRange)` is `nil` — an absent token *is* the in-range state (Req 4.3,
  Decision 7). White is the correct render, not an unstyled one.
- **Low was not observed on-device and is accepted on construction.** `.low`
  is a case in the same `switch` in the same function, behind the same
  `renderingMode` guard the high pass already exercised; the only difference from
  the verified branch is the `Color` literal (`.red` vs `.orange`). There is no
  separate code path left to fail.
