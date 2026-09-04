# Requirements: cross-dataset-calibration

## Introduction

MeData fits a per-class bulk-correction factor (β_c) that rescales estimated food volume before macro calculation. The existing Nutrition5k calibration fit β for only one class, because Nutrition5k's mixed plates leave most classes below the identifiability bar. This feature broadens calibration by ingesting MetaFood3D — a public dataset of real single-food 3D captures with per-object mass — into the existing calibration harness, so carb-staple classes gain the single-food volume↔mass samples Nutrition5k cannot provide. β is fit from MeData's own volume estimator (not the dataset's ground-truth mesh) so it corrects the on-device geometric bias; cross-dataset samples are pooled with recorded provenance and a capture-skew guard; and classes that still fall short keep their existing pooled/unity fallback.

## Non-Goals

- **Other datasets.** ECUSTFD, NutritionVerse, SimpleFood45, FPB and any set beyond MetaFood3D are deferred (ECUSTFD is a candidate fast-follow once the multi-dataset abstraction proves out).
- **Self-captured gravimetric data.** No human meal-weighing; this feature is public-data only.
- **Device-LiDAR noise modelling.** β is fit on noise-free rendered depth and corrects geometric bias only; simulating iPhone-LiDAR noise/dropout to also capture sensor-induced bias is deferred (see Req 2.5, decision log Decision 8).
- **Accuracy-gated bake for single-source β.** A single-source β is not blocked from baking by the held-out accuracy anchor; it bakes on the statistical gates with a provenance flag (Req 8.3, decision log Decision 9). The anchor is reported, not enforced.
- **Taxonomy changes.** The feature does not merge or re-split palette classes (e.g. it does not collapse potato_boiled / potato_mashed / chips_fries) to force MetaFood3D coverage; the 35-channel palette and its ordering are fixed. *[Superseded by Decision 15 (2026-08-09): the live palette is v2 (36 channels, `cereal` appended); the fixed-taxonomy stance stands, but the fixed target is v2, not the 35-channel v1.]*
- **Segmenter production.** Training or exporting the Core ML segmenter remains owned by model-production; this feature does not depend on it.
- **On-device changes.** All work is offline harness + food-DB bake; no change to the iOS estimation path.

## Requirements

### 1. MetaFood3D ingestion into the existing fixture contract

**User Story:** As a calibration maintainer, I want MetaFood3D ingested into the same fixture format the harness already consumes, so that new samples flow through the existing calibrate path without reworking it.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL ingest MetaFood3D into the existing `.fixture` proto format consumed by `HarnessCLI calibrate`, without modifying that fixture contract.  
2. <a name="1.2"></a>The system SHALL NOT write MetaFood3D imagery or metadata into the repository; ingestion SHALL read only from a gitignored local data directory.  
3. <a name="1.3"></a>The system SHALL remap MetaFood3D food categories onto the 35-channel palette v1 via a versioned mapping artifact, preserving the load-bearing channel ordering; a category whose cooking method is ambiguous for a split class (e.g. potato_boiled vs potato_mashed) SHALL be excluded rather than guessed. *[Amended by Decision 15 (2026-08-09): the target is the palette **v2** content list (36 channels, `cereal` at solid index 24); β is keyed by class name throughout, so the mapping artifact locks palette content rather than channel ordering. The exclusion rule for ambiguous cooking-method categories is unchanged.]*  
4. <a name="1.4"></a>WHEN a MetaFood3D category has no palette mapping, the system SHALL exclude its objects and record the excluded count in the run summary.  
5. <a name="1.5"></a>The ingestion SHALL verify MetaFood3D's metric scale before emitting fixtures and SHALL abort on failure, using ground truth the dataset provides: a global unit-sanity gate on the object-size distribution (catching a millimetre/metre import error), and a per-object plausibility that the mesh bounding-box volume under a density band brackets the object's shipped gramme weight. A silent scale error is otherwise absorbed indistinguishably into β.  

### 2. β fit from the on-device estimator, against mass, with a volume-fit diagnostic

**User Story:** As a calibration maintainer, I want β fit against our own volume estimate and true mass, so that the correction transfers to real device captures and stays consistent with the Nutrition5k fit.

**Acceptance Criteria:**

1. <a name="2.1"></a>The system SHALL fit β for a MetaFood3D object from the volume produced by the same estimator path used for Nutrition5k and on-device capture; the estimator input SHALL be an overhead depth view rendered from the object's mesh, NOT the mesh's ground-truth volume.  
2. <a name="2.2"></a>The baked β SHALL be fit against per-object mass using the database density (ρ_DB), consistent with the Nutrition5k mass-fit, so the two datasets' β are poolable.  
3. <a name="2.3"></a>The system SHALL also compute, as a non-baked diagnostic, a volume-fit β from MetaFood3D's true mesh volume, to isolate the estimator's geometric bias from density effects and flag when the mass-fit β diverges from it.  
4. <a name="2.4"></a>The render SHALL use a fixed, recorded camera configuration — nadir pose, intrinsics, object-to-camera distance matched to the Nutrition5k/device capture geometry, depth units, resolution, and a synthetic support plane so the plane-fit path runs — such that β is reproducible and every object with a valid mesh yields one usable single-food sample.  
5. <a name="2.5"></a>The system SHALL record in lineage that β is fit on noise-free rendered depth; β corrects geometric bias and does NOT correct sensor-noise-induced bias (edge rectification, off-axis convexity, LiDAR dropout) present in real captures.  

### 3. Single-food path independent of the trained checkpoint

**User Story:** As a calibration maintainer, I want MetaFood3D's single-food samples usable before the segmenter checkpoint exists, so that carb staples can calibrate now.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL treat each MetaFood3D object as a single-class observation of its mapped palette class, requiring no segmenter output.  
2. <a name="3.2"></a>MetaFood3D calibration SHALL NOT be gated on the model-production checkpoint (Bucket C).  
3. <a name="3.3"></a>The system SHALL incorporate MetaFood3D single-food samples into the per-class β fit alongside Nutrition5k samples.  

### 4. Cross-dataset pooling with information-weighting and provenance

**User Story:** As a calibration maintainer, I want samples from multiple datasets pooled per class by how much information each carries, so that more classes clear the effective-sample bar without overstating precision.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN a class has qualifying samples from more than one dataset, the system SHALL pool them into a single per-class fit.  
2. <a name="4.2"></a>Lower-information observations (e.g. collinear Nutrition5k mixture-deconvolution rows relative to clean single-food rows) SHALL be down-weighted in the identifiability determination — the relative-SE (≤ 0.15) and conditioning gate — so that the effective-sample (≥ 30) and relative-SE gates together prevent a collinear pool from qualifying on raw count alone.  
3. <a name="4.3"></a>The system SHALL record, per baked β, the contributing datasets and each dataset's weighted sample contribution.  

### 5. Cross-dataset capture-skew guard

**User Story:** As a calibration maintainer, I want blended β rejected when the source datasets genuinely disagree, so that capture-rig differences do not bias a baked value — without firing on ordinary sampling noise.

**Acceptance Criteria:**

1. <a name="5.1"></a>The system SHALL compute a per-dataset β for each class that qualifies in more than one dataset, in addition to the pooled fit.  
2. <a name="5.2"></a>The system SHALL flag a class cross-dataset-inconsistent when the per-dataset β are not equivalent within a practical bound that accounts for each source's standard error, rather than a fixed relative constant.  
3. <a name="5.3"></a>A class flagged cross-dataset-inconsistent SHALL fall back to the existing pooled/unity β state rather than bake the pooled value.  

### 6. Provenance and single-source flag

**User Story:** As a calibration maintainer, I want each baked β to carry its data source and corroboration status, so that unverified single-source contributions can be identified later.

**Acceptance Criteria:**

1. <a name="6.1"></a>The system SHALL record, in calibration lineage, the source dataset(s) contributing to every baked β.  
2. <a name="6.2"></a>The system SHALL flag a class `single_source_uncorroborated` unless at least two datasets each yield an independently identifiable standalone β for it and those agree under the skew test (Req 5.2); a class present in two datasets but independently identifiable in only one SHALL still be flagged, as SHALL the carb staples calibrated from MetaFood3D alone.  

### 7. Nutrition5k baseline preserved

**User Story:** As a calibration maintainer, I want the existing Nutrition5k path unchanged, so that adding MetaFood3D is purely additive.

**Acceptance Criteria:**

1. <a name="7.1"></a>Running calibration without MetaFood3D at a fixed seed SHALL produce a calibrate artifact whose baseline-class β are identical to the current Nutrition5k-only bake, exercising the new pooling path with a single dataset.  
2. <a name="7.2"></a>The MetaFood3D contribution SHALL NOT alter the fixture contract, the existing calibrate-artifact fields, or the DB bake path in a way that breaks existing consumers.  

### 8. Honest coverage and preserved fallback

**User Story:** As a calibration maintainer, I want classes that still fall short to keep their current status and the bake policy stated plainly, so that coverage is never oversold.

**Acceptance Criteria:**

1. <a name="8.1"></a>A class that remains below the effective-sample or identifiability bar after pooling SHALL keep its existing uncalibrated_pooled or uncalibrated_unity status and β.  
2. <a name="8.2"></a>The system SHALL report, per class, the effective sample count and calibration status before and after adding MetaFood3D.  
3. <a name="8.3"></a>A β flagged `single_source_uncorroborated` (Req 6.2), including MetaFood3D-only carb staples, SHALL be baked when it clears the effective-sample and relative-SE gates, and the bake SHALL NOT be blocked by the held-out accuracy anchor (Req 10.2).  

### 9. Reproducibility from lineage

**User Story:** As a calibration maintainer, I want a bake reproducible from its lineage alone, so that a calibrated DB can be regenerated and audited.

**Acceptance Criteria:**

1. <a name="9.1"></a>The calibration lineage SHALL record the MetaFood3D mapping-artifact version, the dataset snapshot identifier, the RNG seed, the skew tolerance, and the render camera configuration, such that a bake is reproducible from lineage alone.  

### 10. Accuracy-delta and held-out anchor reporting

**User Story:** As a calibration maintainer, I want the accuracy change attributable to MetaFood3D reported, including an out-of-sample check, so that the coverage gain can be judged against the baseline.

**Acceptance Criteria:**

1. <a name="10.1"></a>The system SHALL report the change in carb MAPE/MAE, where measurable on the Nutrition5k eval pool, and the per-class β change attributable to adding MetaFood3D, against the Nutrition5k-only baseline; per-class accuracy deltas SHALL be reported only above a minimum eval-plate count, and staples absent from the eval pool SHALL be identified as having no in-harness accuracy validation.  
2. <a name="10.2"></a>The system SHALL compute and report a held-out MetaFood3D accuracy anchor — predicting per-object mass from (V_est × β × ρ_DB) on objects excluded from the fit — as an out-of-sample check on β, and SHALL cross-check the one overlapping calibrated Nutrition5k class (broccoli) where present. This anchor is reported, not a bake gate.  
</content>
