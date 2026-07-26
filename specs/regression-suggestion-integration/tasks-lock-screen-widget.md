---
references:
    - specs/regression-suggestion-integration/prd.md
---
# Insulin dose inflow (medreg integration) — Lock screen widget

## Widget extension

- [x] 1. Add WidgetKit extension target (MeDataWidgets) to MeData.xcodeproj: new directory, embed in app, signing consistent with rtob.MeData — PRD Widget 1

- [x] 2. Static launcher accessory widgets (accessoryCircular + accessoryRectangular) as TWO kinds: dose widget (syringe glyph, "Log dose", opens medata://insulin/add) and capture widget (camera glyph, "Capture", opens medata://capture); single static Timeline (.never), no persistence imports, no App Group — PRD Widget 1, 2

- [x] 3. systemSmall home-screen family for both widget kinds with the same deep links — PRD Widget 3 (SHOULD)

- [x] 4. Build verification: make build-app passes with the extension embedded; both widgets appear in lock-screen gallery (device check noted for user)
  - make build-app passes (DEVICE_UDID=00008140-00015C4C02E0801C); MeDataWidgets.appex embedded in MeData.app/PlugIns with NSExtensionPointIdentifier com.apple.widgetkit-extension
  - bundle id rtob.MeData.MeDataWidgets
  - version 1.0 matching app; both deep-link URLs and widget kinds verified in the built binary (Debug code lives in MeDataWidgets.debug.dylib — Xcode 26 blank-executor stub). First build needed xcodebuild -allowProvisioningUpdates once to mint the team profile for the new bundle id. On-device lock-screen gallery + tap check pending (user).
