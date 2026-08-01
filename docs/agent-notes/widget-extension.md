# MeDataWidgets extension (launcher widgets)

Widget extension target `MeDataWidgets`, sources at `MeData/MeDataWidgets/`
(one Swift file + Info.plist). Two STATIC launcher widget kinds in one
`WidgetBundle` — `ie.medata.widget.insulin` ("Log dose", syringe, opens
`medata://insulin/add`) and `ie.medata.widget.capture` ("Capture", camera,
opens `medata://capture`). Families: `accessoryCircular`,
`accessoryRectangular` (lock screen), `systemSmall` (home screen). Lock-screen
accessory widgets carry a SINGLE tap target — that is why dose and capture are
separate kinds, not two buttons in one widget. Deep links are handled by
`App/AppRoot.swift handleDeepLink` (see `insulin-dose-ui.md`).

The two LAUNCHER kinds display no data: no persistence imports, `Timeline`
policy `.never`. Keep them that way. A third, data-driven kind
(`specs/ui/glucose-lock-widget`) now lives in the same extension and brings the
App Group + snapshot cache — see "App Group + GlucoseWidgetShared" below. The
30 MB memory cap and the no-GRDB rule still bind every kind in the bundle.

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
