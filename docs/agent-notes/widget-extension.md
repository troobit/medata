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

No data display: no persistence imports, no App Group, `Timeline` policy
`.never`. Keep it that way unless a data-showing widget is actually specced —
an App Group + cache is a whole different animal (30 MB memory cap, no GRDB).

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
- Widget targets auto-link WidgetKit/SwiftUI; the Frameworks build phase is
  deliberately empty.
