---
references:
    - prd.md
---
# Insulin dose inflow (medreg integration) — Lock screen widget

## Widget extension

- [ ] 1. Add WidgetKit extension target (MeDataWidgets) to MeData.xcodeproj: new directory, embed in app, signing consistent with rtob.MeData — PRD Widget 1

- [ ] 2. Static launcher accessory widgets (accessoryCircular + accessoryRectangular): syringe glyph + short label, single static Timeline (.never), no persistence imports, no App Group; tap opens medata://insulin/add — PRD Widget 1, 2

- [ ] 3. systemSmall home-screen family with same deep link — PRD Widget 3 (SHOULD)

- [ ] 4. Build verification: make build-app passes with the extension embedded; widget appears in lock-screen gallery (device check noted for user)
