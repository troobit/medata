# Nutrition5k app plumbing + banner (stream D)

Stream D of the nutrition5k-calibration spec (tasks 33–37): the on-device
plumbing that carries the baked calibration columns to the ResultView banner.

## Plumbing chain (no new lookups in the view layer)

`foods.beta_provenance`/`device_verified` → `GRDBFoodDatabase.rowToEntry` →
`FoodEntry.betaProvenance` (String, closed DB vocabulary) + `.deviceVerified` →
`Macros.compute` copies `deviceVerified` onto each `PerClassMacros` →
`PipelineBridges` → `PbPerClassMacros` → `ResultFormat.calibrationBanner`
reads `record.macros.perClass`. The old `record.perClassCalibration` field
still exists for persistence/migration but the banner no longer reads it.

- `FoodEntry.betaProvenance` is a **String**, not the `BetaProvenance` enum —
  that enum lives in `HarnessCore` (harness-only) and `Foods` cannot depend on
  it; the app makes no decisions on provenance.
- Both SELECT arms of the CoFID/AFCD UNION in `GRDBFoodDatabase.fetchEntry`
  must list new columns — adding to one arm gives a column-count mismatch.

## isLiquid is a palette property, not a DB column

The `foods` table has no `is_liquid` column. `Macros.compute` takes
`liquidClassIds: Set<String>` (defaulted `[]`) and Pipeline passes
`Set(palette.liquidClasses)`. Harness callers (`FixtureRunner`) omit it —
liquids never enter the β fit anyway.

## liquidOverEstimate (Req 8.2)

`MacroResult.liquidOverEstimate` is true when either (a) the caller threads
`liquidOverEstimate: true` from the `LiquidResolver` vessel path, or (b) any
computed per-class entry `isLiquid` — the depth-integrated path over-reads
(Req 7.3). LiquidResolver is NOT yet wired into Pipeline (liquid recognition
is the Req 7.7 deferred dependency), so at runtime the flag is currently
always false; the plumbing exists so ResultView needs no new lookups later.

## Banner semantics (ResultFormat.calibrationBanner)

Evaluated over solid classes only (`!isLiquid`):
- empty `perClass` → `.full` (conservative pre-existing rule, old records);
- no solid class but liquids present → `.none` (standalone drink — a stated
  rule, NOT the suppressed state by vacuous truth);
- any solid pooled/unity → `.full`; all calibrated + any unverified →
  `.softened`; all calibrated + all device-verified → `.suppressed`
  (unreachable this spec — `device_verified` bakes as 0; flag-injection
  tested only).
- The liquid flag renders additively and is suppressed (with the calibration
  banner) under the `dev_stub` placeholder chip — fake numbers can't carry a
  real over-estimate claim.

## Verification gotchas

- `MeData/Tests/*.swift` (incl. the new `CalibrationBannerTests`) are
  **orphaned** — the Xcode project has no unit-test target (see
  tilt-aim-guide.md). Gate = `xcodebuild build` + `swift test` baseline.
- `xcodebuild … build` currently fails at **CodeSign** on
  `MedataCore_Pipeline.bundle` ("bundle format unrecognized") — pre-existing
  on the branch, unrelated to code (the bundle contains only the committed
  `Resources/README.md` placeholder for the gitignored segmenter model).
  Verify compilation with `CODE_SIGNING_ALLOWED=NO`; on-device/simulator runs
  need this signing issue resolved first.
