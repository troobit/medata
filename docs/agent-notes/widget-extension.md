# MeDataWidgets extension

Widget extension target `MeDataWidgets`, sources at `MeData/MeDataWidgets/`
(`MeDataWidgets.swift` + `GlucoseWidget.swift` + Info.plist + entitlements).
THREE kinds in one `WidgetBundle`:

| Kind | File | Data | Tap |
|---|---|---|---|
| `ie.medata.widget.insulin` | `MeDataWidgets.swift` | none | `medata://insulin/add` |
| `ie.medata.widget.capture` | `MeDataWidgets.swift` | none | `medata://capture` |
| `ie.medata.widget.glucose` | `GlucoseWidget.swift` | App Group snapshot | `medata://graph` |

Lock-screen accessory widgets carry a SINGLE tap target — that is why dose and
capture are separate kinds, not two buttons in one widget, and why the glucose
kind's whole view is one `widgetURL`. Deep links are handled by
`App/AppRoot.swift handleDeepLink` (see `insulin-dose-ui.md`).

The two LAUNCHER kinds display no data: no persistence imports, `Timeline`
policy `.never`. Keep them that way — the App Group and the snapshot read
belong to the glucose kind alone. The 30 MB memory cap and the no-GRDB /
no-network rule bind every kind in the bundle, glucose included.

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
- The only linked package product is `GlucoseWidgetShared` (Foundation-only,
  zero deps). Wiring it into an objectVersion-77 pbxproj needs THREE objects,
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
is already stored. Reloads are scoped: `reloadTimelines(ofKind:)` with the
glucose kind, so glucose writes do not spend the shared WidgetKit reload budget
on the co-hosted launchers.

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

## Field-observed limitation (2026-08-13, task 14 device pass)

Task 14's device pass closed: App Group round-trips, portrait and Lock Screen
renders are fine. But the widget **often falls out of sync until the phone is
unlocked or the app is opened and refreshed**. This is the architecture above
behaving as built, not a bug in the render path: the publisher only runs while
the app process is alive, so nothing republishes the snapshot or reloads the
timeline while the app is suspended. Tracked as
`specs/ui/glucose-lock-widget/tasks.md` task 16 (candidates: HealthKit
background delivery, BGAppRefresh, or extension-side reads in `getTimeline`).
