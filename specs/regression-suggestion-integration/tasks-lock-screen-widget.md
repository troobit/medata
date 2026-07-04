---
references:
    - prd.md
---
# Insulin dose inflow (medreg integration) — Lock screen widget

## Widget extension

- [ ] 1. Add WidgetKit extension target (MeDataWidgets) to MeData.xcodeproj: new directory, embed in app, signing consistent with rtob.MeData — PRD Widget 1

- [ ] 2. Static launcher accessory widgets (accessoryCircular + accessoryRectangular) as TWO kinds: dose widget (syringe glyph, "Log dose", opens medata://insulin/add) and capture widget (camera glyph, "Capture", opens medata://capture); single static Timeline (.never), no persistence imports, no App Group — PRD Widget 1, 2

- [ ] 3. systemSmall home-screen family for both widget kinds with the same deep links — PRD Widget 3 (SHOULD)

- [ ] 4. Build verification: make build-app passes with the extension embedded; both widgets appear in lock-screen gallery (device check noted for user)
