# Bugfix Report: App-side Palette Drift After the v2 Promotion

**Date:** 2026-07-26
**Status:** Fixed

## Description of the Issue

The palette-v2 promotion (myfoodrepo-bridge, model `ab812dc3aa9d`) flipped
`PipelineFactory`'s defaults to `ClassPalette.v2Standard` (36 channels: cereal
appended at solid index 24, liquids shifted +1, background 32→33,
unknown_food 33→34) but left six App-target sites on v1:

1. `App/App.swift` — `PreShutterSegmenter(palette: .v1Standard)`: the live
   arming predicate reads v2 model output with v1 indices (cereal missed as
   food; sentinel indices misread).
2. `App/App.swift` — `CaptureFlowModel(paletteVersion: "v1")`: every new meal
   record and capture bundle persisted `paletteVersion=v1` while carrying
   v2-space class data (confirmed in today's device fixtures — 36-channel
   probs stamped `palette_version: v1`).
3. `App/MaskOverlayLoader.swift` — decoder hardcoded `v1Standard` for the
   background-skip index: v2 masks would paint background (33) as a class
   colour and skip wine (32).
4. `App/MealOverviewView.swift` — swatch colours resolved class names via
   `v1Standard` (cereal/liquids land on wrong wheel positions for v2 meals),
   and its `MaskOverlayLoader` call omitted the record's palette version.
5. `App/SegmentationReviewView.swift` — unknown/unsupported banners read v1
   sentinel indices against v2 masks.
6. `App/BenchmarkView.swift` — pickable truth classes omitted cereal.

**Reproduction steps:**
1. Pull any post-promotion capture bundle: `palette_version: v1` with
   36-channel probs.
2. Capture a meal with visible background and open Segmentation review: the
   background region tints; sentinel banners misfire.

**Impact:** wrong provenance on every v2-era meal/fixture (breaks the future
v1→v2 `PaletteMigrator` path), broken mask overlays and sentinel banners for
v2 meals, cereal invisible to the pre-shutter arming predicate.

## Investigation Summary

- **Symptoms examined:** `palette_version: v1` stamps on today's fixtures
  (found while diagnosing unrecognised-food-estimated-as-residual-sliver).
- **Code inspected:** every `v1Standard` / `paletteVersion` reference in
  `App/` plus `PipelineFactory`, `ClassColourTable` (id-indexed, no change
  needed — matches the promotion note).
- **Hypotheses tested:** whether display sites should pin the CURRENT palette
  or the record's own — record's own wins (v1-era meals must keep v1 index
  semantics; the `paletteVersion` SQL column exists exactly for this).

## Discovered Root Cause

The promotion changed the palette where the model is built
(`PipelineFactory`) but the App target duplicates the palette choice in six
places with no single seam, and `ClassPalette.version`'s label cannot detect
drift (class-palette note) — nothing failed at build or runtime.

**Defect type:** Incomplete change / duplicated configuration.

**Why it occurred:** no resolver existed from the persisted `paletteVersion`
label to a palette value, so each site hardcoded `v1Standard`.

**Contributing factors:** the promotion verified `ClassColourTable`
(genuinely palette-size-independent) and inferred the App side was covered.

## Resolution for the Issue

**Changes made:**
- `MedataCore/Sources/Segmentation/ClassPalette.swift` — new
  `standard(for version:)` resolver (v2 for "v2", v1 fallback otherwise).
- `App/App.swift` — pre-shutter palette → `.v2Standard`; persisted
  `paletteVersion` → `"v2"`.
- `App/MaskOverlayLoader.swift` — decoder resolves the palette from its
  `paletteVersion` parameter.
- `App/MealOverviewView.swift` — swatches + loader use
  `record.paletteVersion`.
- `App/SegmentationReviewView.swift` — sentinel indices from
  `record.paletteVersion`.
- `App/BenchmarkView.swift` — pickable classes from `v2Standard` (cereal
  included).

**Approach rationale:** display code keys off the record's own stored
version (historical meals stay correct); live-capture code pins the current
palette in exactly two places (pre-shutter + persisted label), both now next
to comments tying them to `PipelineFactory`.

**Alternatives considered:**
- **Thread the palette object through every view** — rejected: wider diff
  for the same effect; the label + resolver is the established persistence
  contract (`paletteVersion` column).
- **Make `PipelineFactory` expose a `currentPaletteVersion`** — deferred:
  App.swift's two literals sit beside the factory call; a constant seam can
  come with the next palette bump.

## Regression Test

**Test file:** `MedataCore/Tests/SegmentationTests/SegmentationModuleTests.swift`
**Test name:** `testStandardForVersionResolvesLabelToPalette`

**What it verifies:** the label→palette resolution including the v1 fallback
for unrecognised labels.

**Run command:** `make test`

## Affected Files

| File | Change |
|------|--------|
| `MedataCore/Sources/Segmentation/ClassPalette.swift` | `standard(for:)` resolver |
| `App/App.swift` | v2 pre-shutter palette + "v2" persisted label |
| `App/MaskOverlayLoader.swift` | palette from paletteVersion param |
| `App/MealOverviewView.swift` | per-record palette for swatches + loader |
| `App/SegmentationReviewView.swift` | per-record sentinel indices |
| `App/BenchmarkView.swift` | v2 pickable classes |
| `MedataCore/Tests/SegmentationTests/SegmentationModuleTests.swift` | resolver test |

## Verification

**Automated:**
- [x] Regression test passes
- [x] Full test suite passes (`make test`, both totals)
- [x] `make spell` passes

**Manual verification:**
- App builds for device; deployed with the records-deletion work and checked
  on device.

## Prevention

**Recommendations to avoid similar bugs:**
- Any future palette bump must grep the App target for palette literals; the
  two remaining intentional pins (`App.swift`) carry comments naming this
  bugfix.
- The class-palette note's warning stands: the version label cannot detect
  drift — content checks (class-list comparison) are the guard.

## Related

- `docs/agent-notes/model-production.md` — palette-v2 promotion entry.
- `docs/agent-notes/class-palette.md` — predicate contract + drift warning.
- `specs/bugfixes/unrecognised-food-estimated-as-residual-sliver/` — the
  investigation that surfaced the wrong fixture stamps.
