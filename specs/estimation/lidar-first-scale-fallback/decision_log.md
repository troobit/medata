# Decision Log: LiDAR-First Scale Fallback

## Decision 1: Card-solve failure falls back to LiDAR scale when depth is present

**Date**: 2026-06-23
**Status**: accepted

### Context

`Pipeline.estimate` Stage C throws `EstimationFailure.cardTooOblique` / `.degenerateCardPose` whenever `CardPoseSolver.solve` fails, aborting the entire estimate even when the nadir frame carries LiDAR depth. The support-plane fitter (`LiDARSupportPlaneFitter`) and the metric-scale resolver (`MetricScaleResolver`) both already support a LiDAR-only path, and design §6.4 documents LiDAR-only scale as a first-class outcome. The pipeline simply never reaches them because Stage C throws first. The roadmap (`nextup.md` open Decision 2) requires LiDAR-first scale with the card as the non-LiDAR fallback.

### Decision

When `CardPoseSolver.solve` throws `cardTooOblique` or `degenerateCardPose` and `nadir.depth != nil`, set `cardPose = nil` and continue (LiDAR supplies scale and support plane). When LiDAR depth is absent, retain the current throw.

### Rationale

LiDAR depth, when present, independently yields both the support plane and metric scale; a failed card read provides no additional information in that case, so aborting discards a recoverable estimate. The change is localised to the Stage C catch arms and needs no change to the resolver, fitter, or `EstimationFailure` enum, because the LiDAR-only branches already exist and are unit-tested.

### Alternatives Considered

- **Change `MetricScaleResolver` instead**: Rejected — the resolver already handles `cardScaleMmPerPx == nil` correctly; the gap is upstream in Stage C, not in the resolver.
- **Always continue past a card-solve failure (even without LiDAR)**: Rejected — without LiDAR the card is the only scale source, so a failed card read genuinely has no scale and must refuse (`noScaleAvailable` would otherwise be the result anyway, with a less specific message).

### Consequences

**Positive:**
- A mis-read or oblique card no longer blocks an otherwise-valid LiDAR estimate (the common case on LiDAR devices).
- Pipeline behaviour now matches the documented §6.4 resolver intent.

**Negative:**
- Card-only (non-LiDAR) devices see no change; a card-solve failure there still refuses.
- The `cardScaleAvailable == false` outcome cannot be asserted end-to-end in a unit test on synthetic fixtures (Volume throws downstream); it is verified indirectly via the resolver's existing LiDAR-only tests.

---

## Decision 2: Generic (unexpected) card-solve errors remain fail-closed

**Date**: 2026-06-23
**Status**: accepted

### Context

Stage C's card-solve `do/catch` has a generic `catch` arm that maps any error other than the two known `CardPoseError` cases to `EstimationFailure.degenerateCardPose`. Decision 1 introduces a LiDAR fallback for the two known cases; the question is whether the generic arm should also fall back.

### Decision

Only `cardTooOblique` and `degenerateCardPose` fall back to LiDAR. The generic `catch` arm keeps throwing `degenerateCardPose` regardless of LiDAR depth.

### Rationale

An unexpected error from `CardPoseSolver.solve` (a future `CardPoseError` case, or a programming error) is not a known, benign "card unreadable" condition. Silently falling back to LiDAR would mask it and make regressions invisible on device trails. Fail-closed keeps unknown failures surfaced.

### Alternatives Considered

- **Fail-open (generic arm also falls back when depth present)**: Rejected — hides genuinely unexpected failures behind a successful-looking LiDAR estimate, which is harder to diagnose than an explicit refusal.

### Consequences

**Positive:**
- Unknown card-solve failures stay visible as refusals rather than being absorbed.

**Negative:**
- A hypothetical future "benign" card error not yet enumerated would refuse rather than fall back until it is explicitly added to the known-cases set.

---
