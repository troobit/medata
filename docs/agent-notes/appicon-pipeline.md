# AppIcon asset pipeline

## How it works
`tools/appicon/generate.sh` rasterises the brand vector master
`static/icon.svg` (stroke colour `#63ff00`) into the iOS AppIcon PNG set and
writes a matching `Contents.json` into
`MeData/MeData/Assets.xcassets/AppIcon.appiconset/`.

It is a one-off build-tooling step (UI spec task 25, Decision 7): run the script
and commit the generated PNGs alongside it. There is no code-time dependency on
the script — Xcode just consumes the committed PNGs.

## Sizes and slot mapping
Eight unique pixel sizes cover all iPhone slots plus the marketing icon:
`40, 58, 60, 80, 87, 120, 180, 1024`. `icon-120.png` is referenced by two
slots (40pt@3x and 60pt@2x), so there are 9 `Contents.json` entries for 8 files.

## Rasteriser
Prefers `rsvg-convert`; falls back to `sips` (ships with macOS). On this machine
only `sips` is present, so that path is what runs. `sips` reads SVG fine on
recent macOS.

## Gotcha — alpha channel on the 1024 marketing icon
`icon.svg` has `fill="none"`, so every PNG (including `icon-1024.png`) is RGBA
with transparency. Xcode displays it fine, but App Store Connect upload
validation rejects a 1024 marketing icon that has an alpha channel. If/when
submitting, flatten `icon-1024.png` onto an opaque background first. No
background colour was chosen here because that is a design decision outside the
task's scope.
