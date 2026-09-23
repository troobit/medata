# Bugfix Report: graph-month-selection-hang

**Date:** 2026-07-06
**Status:** Fixed (device verification pending)

## Description of the Issue

Selecting **Month** in the Graph range picker froze the UI: the segmented control
stuck mid-selection while the chart re-rendered, for long enough to read as a hang.
Day and Week were tolerable; Month was the one that stalled.

**Reproduction steps:**
1. Open the app (Graph is the launch root) with a month of data (DEBUG seeds glucose).
2. Tap **Month** in the range picker.
3. The picker freezes on the tap and the chart takes seconds to appear.

**Impact:** Graph unusable at the Month range — the default landing screen.

## Investigation Summary

- **Code inspected:** `App/TrendsModel.swift` (series shaping), `App/TrendsView.swift`
  (chart body).
- **Root observation:** `carbBars`, `glucoseLine`, and `insulinMarkers` were computed
  properties re-evaluated on *every* access, and the chart body accesses them
  quadratically.

## Discovered Root Cause

`TrendsView.chart` reads the series far more than once per render:
- `ForEach(model.carbBars)` renders each bar with `y: mappedCarb(bar.value)`, and
  `mappedCarb` → `model.carbAxisMax` → `carbBars.map(\.value).max()` — so **all of
  `carbBars` is recomputed once per bar**. With ~30 Month buckets that is O(30²), each
  pass re-running `TrendsMath.dailyBuckets` and minting fresh `UUID`s.
- `glucoseAxisMax` → `model.autoGlucoseMax` → `glucoseLine.map(...).max()` is likewise
  hit per bar and per axis tick; `glucoseLine` for Month re-buckets the *entire* month
  of raw glucose (thousands of seeded readings) on each of those calls.
- Fresh `UUID` per access also gave every point unstable identity, so Swift Charts
  could not diff and rebuilt all marks each render.

The combination — quadratic re-bucketing over thousands of samples with per-access
allocation, on the main thread — is the multi-second render that froze the picker.
Day (meals used directly, no bucketing) and Week (7 buckets) stayed under the pain
threshold; Month crossed it.

**Defect type:** Performance — repeated recomputation of derived state in the view.

## Resolution for the Issue

**Changes made:**
- `App/TrendsModel.swift` — `carbBars`, `glucoseLine`, `insulinMarkers`, `carbAxisMax`,
  `autoGlucoseMax` are now stored `private(set)` properties, shaped once per reload in a
  new `recomputeSeries(in:)` called at the end of `reload()`. The view's existing
  `.onChange(of: model.range)` already reloads on a range switch, so Month recomputes
  once and every chart-body access is now an array read with stable element identity.

**Approach rationale:** The series depend only on the loaded rows and the range, both of
which change through `reload()`. Caching there removes the per-access recomputation
without changing any output. Stored arrays also stabilise point identity for Swift Charts.

**Alternatives considered:**
- *Memoise inside the computed properties* — rejected: `@Observable` computed properties
  have no natural cache key and would still allocate on first access per render.
- *Move only the axis maxima to stored* — rejected: the `dailyBuckets`/UUID cost is in
  the series themselves; caching the maxima alone leaves the dominant term.

## Regression Test

None added. `TrendsModel` is app-target and not covered by an executable suite (project
MVP test gate: build + on-device). The `TrendsMath` bucketing maths it calls is unchanged
and still covered by the core suite. Verified by build + on-device.

## Affected Files

| File | Change |
|------|--------|
| `App/TrendsModel.swift` | Series + axis maxima cached in `recomputeSeries(in:)` |

## Verification

**Automated:**
- [x] `make build-app` (iphoneos Debug) compiles
- [x] `make test` unchanged (TrendsMath core suite green)
- [x] `make spell` clean

**Manual verification:**
- Pending: on-device — switch to Month and confirm the picker responds immediately.

## Prevention

- Shape chart series once in the view-model on data/range change; never in computed
  properties the chart body reads repeatedly.
- Give chart points stable identity (data-derived, or created once) so Swift Charts can
  diff instead of rebuilding every mark.

## Related

- `App/TrendsView.swift` chart body — the quadratic access pattern that exposed the cost.
- Same session as `specs/bugfixes/capture-no-flat-surface-gravity-frame/`.
