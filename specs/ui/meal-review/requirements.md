# Requirements: Meal Review

## Introduction

After a capture, the estimate is currently spread across two screens: a read-only segmentation review that shows the photo and its detected foods but permits no editing, and a result screen that permits amount editing but never shows the photo's detected areas. The screen that tells you the model thinks something is bread is the one that lets you change nothing. This spec collapses the two into a single review surface where a detected food can be relabelled or rejected, amounts adjusted by serving or grams, and the meal recorded in one tap.

The purpose is a corpus. Prediction, result and correction are retained together so later models and a growing food database can be trained and evaluated against real captures; the interface exists to make corrections cheap enough that they happen. The estimate does not have to be right unaided — it has to reach a correct recorded figure faster than typing one in.

## Definitions

- **Detected food** — one entry in the estimate, keyed by class id. All pixels the segmenter assigned to that class form one detected food, however many separate areas they occupy on the photo. The segmenter is semantic, not instance-based; there is no per-blob identity in the stored data.
- **Interaction** — one discrete touch-down/touch-up on a control. A scroll, a keyboard character, and each repeat of a held stepper each count as one.
- **Review session** — the interval from the review surface appearing to it being dismissed by the primary action, retake, or delete. Backgrounding does not end it.

## Non-Goals

- Editing the shape of a detected area — no brush, lasso, magic wand, or expand/contract. Boundary error is absorbed by amount correction and retained as a scale factor ([9.6](#9.6)).
- Correcting one part of a detected food differently from another part of it, and merging or splitting detected areas. All three require per-instance identity the segmenter does not produce.
- Altering any stored density, β_c, or model weight — blocked by `estimation/pipeline` Req 14.3. Re-deriving a corrected food's carbohydrate from the existing bundled database is not such an alteration ([Decision 8](decision_log.md)).
- Remembering a correction and pre-applying it to a later capture of the same food.
- Correcting a meal from Records or Graph after the capture session has ended.
- Displaying confidence per detected food, in any form. Meal-level confidence remains the only confidence surface (`ui/design-handoff-00` Decision 16).
- Any change to the capture screen's chrome, or to the Graph's summary cards. Both are amendments to `ui/design-handoff-00`, tracked separately.
- Network access of any kind, including for food search.

## Requirements

### 1. <a name="1"></a>Single Review Surface

**User Story:** As someone who has just photographed a meal, I want one screen that shows what was detected and lets me fix it, so that I am not navigating between a screen that shows and a screen that edits.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN estimation completes successfully, THE SYSTEM SHALL present a single surface showing the captured photo with its detected areas marked, the meal carbohydrate total, and one editable row per detected food.  
2. <a name="1.2"></a>The system SHALL NOT require any interaction between estimation completing and that surface appearing.  
3. <a name="1.3"></a>The surface SHALL provide a retake action returning to the viewfinder, and a delete action, each discarding the recorded meal.  
4. <a name="1.4"></a>The surface SHALL show the meal-level confidence indication, the calibration state, and the very-low-confidence retake prompt, on the same terms as the result screen does today.  
5. <a name="1.5"></a>WHEN the estimate contains an unknown region or an unsupported liquid, THE SYSTEM SHALL say so in one line using an icon and text, not colour alone.  
6. <a name="1.6"></a>WHEN the photo asset is unavailable, THE SYSTEM SHALL show the rows and total without the photo; WHEN the mask artefact is unavailable, THE SYSTEM SHALL show the photo without detected-area marking. Neither SHALL error nor prevent recording.

### 2. <a name="2"></a>Detected Foods On The Photo

**User Story:** As someone reviewing an estimate, I want to see which parts of the photo the model assigned to each food, so that I can tell whether it understood the plate.

**Acceptance Criteria:**

1. <a name="2.1"></a>The system SHALL mark each detected food's areas on the photo without obscuring the pixels within them.  
2. <a name="2.2"></a>WHERE two detected foods occupy adjacent areas, THE SYSTEM SHALL render them as visually distinct from one another.  
3. <a name="2.3"></a>Each detected food SHALL be identified between photo and row by a means other than colour alone.  
4. <a name="2.4"></a>WHEN the user taps any marked area, THE SYSTEM SHALL select that food and its row; WHEN the user taps a row, THE SYSTEM SHALL select that food and all its marked areas.  
5. <a name="2.5"></a>WHEN a food is selected, THE SYSTEM SHALL de-emphasise the photo outside its areas such that the selected areas remain the highest-contrast content in the image.  
6. <a name="2.6"></a>Each detected food's marking SHALL be reachable by VoiceOver as one element whose label names the food and whose activation selects it.  
7. <a name="2.7"></a>Selecting a detected food SHALL NOT by itself present the relabel alternatives, and SHALL leave the photo unobscured so that the selected areas remain visible.  
8. <a name="2.8"></a>WHERE the mask marks an area for a class that carries no volume or macro entry, THE SYSTEM SHALL leave that area unmarked rather than marking an area with no corresponding row.

### 3. <a name="3"></a>Relabelling A Detected Food

**User Story:** As someone whose bread was identified as rice, I want to tell the app what the food actually is, so that the recorded figure is right and the mistake is on record.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHEN a detected food is selected AND the user activates its correction affordance, THE SYSTEM SHALL offer a shortlist of alternative foods without requiring a search, ordered by foods the user has recently chosen for a food of that kind.  
2. <a name="3.2"></a>The shortlist SHALL present at most five alternatives before further interaction is required, and SHALL NOT display a score, percentage, or confidence tier for any of them.  
3. <a name="3.3"></a>A correction record SHALL identify which ordering produced the shortlist it was chosen from, so that records made under different orderings remain distinguishable.  
4. <a name="3.4"></a>The system SHALL make every eligible food reachable from the ordered list in one interaction, without network access; WHERE the eligible set does not fit one screen, a means of narrowing it SHALL be offered.  
5. <a name="3.5"></a>WHEN the user chooses a different food, THE SYSTEM SHALL remove the β correction applied under the original class, apply the chosen food's own β_c, density and carbohydrate coefficient to the resulting volume, and update the row and the meal total.  
6. <a name="3.6"></a>WHERE the user has already set that food's amount, a subsequent relabel SHALL preserve the amount they set and derive carbohydrate from the chosen food's coefficient, rather than re-deriving the amount from volume.  
7. <a name="3.7"></a>WHERE the chosen food has no fitted β_c, THE SYSTEM SHALL derive its figure on the same terms the pipeline uses for an uncalibrated class, and the row SHALL carry the same calibration indication it would have carried had the segmenter chosen that food.  
8. <a name="3.8"></a>The system SHALL only offer as relabel targets those foods for which the bundled database provides a density and a carbohydrate coefficient.  
9. <a name="3.9"></a>The system SHALL NOT offer a relabel between a solid food and a liquid one.  
10. <a name="3.10"></a>WHERE a food has been relabelled, THE SYSTEM SHALL show what it was predicted as alongside what it was corrected to, on both the row and the selected marking.  
11. <a name="3.11"></a>A relabel SHALL be reversible within the review session, restoring the original food and its original carbohydrate contribution.

### 4. <a name="4"></a>Rejecting A Detected Food

**User Story:** As someone whose plate rim was counted as food, I want to strike an entry out entirely, so that it stops contributing carbohydrate.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN the user rejects a detected food, THE SYSTEM SHALL remove its carbohydrate contribution from the meal total and remove its row from the list.  
2. <a name="4.2"></a>The system SHALL keep a rejected food's areas marked in a distinct de-emphasised state, labelled with what it was predicted as.  
3. <a name="4.3"></a>A rejection SHALL be reversible within the review session.  
4. <a name="4.4"></a>WHEN every detected food has been rejected, THE SYSTEM SHALL show a total of zero and SHALL still permit the meal to be recorded.

### 5. <a name="5"></a>Unrecognised Foods

**User Story:** As someone eating a food the app has never heard of, I want to say so, so that it is recorded as a gap rather than forced into the nearest wrong class.

**Acceptance Criteria:**

1. <a name="5.1"></a>The ordered alternatives and the full eligible list SHALL each offer an action stating that the food is not in the database.  
2. <a name="5.2"></a>WHEN the user states that a food is not in the database, THE SYSTEM SHALL retain any search text entered alongside the original prediction, and SHALL leave the food's carbohydrate contribution in place and adjustable by amount.

### 6. <a name="6"></a>Adjusting Amounts

**User Story:** As someone who ate two thirds of what is in the photo, I want to correct the quantity per food or across the plate, so that the recorded figure matches what I ate.

**Acceptance Criteria:**

1. <a name="6.1"></a>Per-food amount adjustment by household serving with a gram fallback, its stepping behaviour, and the tap-to-reveal gram editor SHALL behave as specified by `serving-adjust` `prd.md` §iOS app items 1 and 3, unchanged.  
2. <a name="6.2"></a>The gram-stepper increment for a food with no serving definition SHALL remain as shipped by `serving-adjust`, unchanged.  
3. <a name="6.3"></a>The system SHALL offer a whole-meal scale control applied to every row, superseding the control specified by `serving-adjust` `prd.md` §iOS app item 2.  
4. <a name="6.4"></a>The scale SHALL apply to each row's currently derived amount — reflecting any relabel — rather than to the amount first estimated, and repeated scaling SHALL NOT compound.  
5. <a name="6.5"></a>The scale control SHALL offer stops representing fractions of the estimate at or below one, covering the leftovers case in one interaction; correcting an amount upward is reached through the per-food serving and gram controls, which SHALL NOT be capped at the volume measured from the photo.  
6. <a name="6.6"></a>The scale control SHALL be visible without scrolling when the surface first appears.  
7. <a name="6.7"></a>A gram entry SHALL be reachable alongside the serving and scale controls without first dismissing either.  
8. <a name="6.8"></a>An amount adjustment SHALL take effect on the displayed total without a separate confirmation step.  
9. <a name="6.9"></a>WHEN a relabel changes a food to one with no serving definition, or from one, THE SYSTEM SHALL carry the amount across in grams rather than resetting it.  
10. <a name="6.10"></a>The list order of rows SHALL NOT change as a consequence of a relabel, rejection, or amount adjustment made during the review session.

### 7. <a name="7"></a>Recording The Meal

**User Story:** As someone standing over a plate with a fork in my other hand, I want one tap to record the meal, so that logging costs less effort than guessing.

**Acceptance Criteria:**

1. <a name="7.1"></a>The surface SHALL provide one primary action that records the meal as displayed and dismisses, matching the interaction of the Intake surface's primary carb-entry action as specified by `data/manual-carb-intake` Req 3.2 — a single tap that writes with no further prompt or confirmation.  
2. <a name="7.2"></a>The primary action SHALL be available from the moment the surface appears, without prior interaction.  
3. <a name="7.3"></a>The primary action SHALL state the carbohydrate figure it will record, reflecting all corrections made.  
4. <a name="7.4"></a>The system SHALL NOT present a confirmation prompt, a satisfaction prompt, or any second action between the primary action and the meal being recorded, superseding the confirm pill specified by `serving-adjust` `prd.md` §iOS app item 4.  
5. <a name="7.5"></a>Recording an unmodified estimate SHALL take exactly one interaction from the surface appearing.  
6. <a name="7.6"></a>Scaling the whole meal and recording SHALL take no more than two interactions from the surface appearing.  
7. <a name="7.7"></a>On a three-food meal, adjusting one food by one serving step and recording SHALL take no more than six interactions from the surface appearing.  
8. <a name="7.8"></a>On a three-food meal, relabelling one food from the offered alternatives and recording SHALL take no more than six interactions from the surface appearing.

### 8. <a name="8"></a>Retaining The Original Estimate

**User Story:** As the developer improving the pipeline, I want every original prediction kept intact next to what the user said it should have been, so that a corrected meal can be re-derived once the pipeline changes.

**Acceptance Criteria:**

1. <a name="8.1"></a>The system SHALL retain each detected food's original predicted class, volume, mass and carbohydrate contribution unchanged after any correction, and SHALL NOT overwrite a stored prediction with a corrected value.  
2. <a name="8.2"></a>A recorded meal SHALL retain, for the life of the record, the inputs needed to re-derive its macros under a later food database or calibration without recapturing: the per-class volumes, the β applied to each, the palette version, and the database edition.  
3. <a name="8.3"></a>Re-running segmentation under a later model SHALL NOT be a retention obligation of the meal record; WHERE a capture bundle for the same capture survives, a correction record SHALL be joinable to it, and WHERE it does not, the correction record SHALL remain valid for macro re-derivation.  
4. <a name="8.4"></a>WHERE any process deletes stored data on age, THE SYSTEM SHALL exempt the capture artefacts of any meal carrying a correction record.  
5. <a name="8.5"></a>A failure to retain correction data SHALL NOT alter, delay, or prevent the meal being recorded.  
6. <a name="8.6"></a>Marking of corrected meals wherever shown SHALL behave as specified by `ui/design-handoff-00` Req 7.3, unchanged.  
7. <a name="8.7"></a>WHERE a food has been relabelled, every surface that names that food SHALL name the corrected food, not the predicted one.

### 9. <a name="9"></a>Correction Data For Later Review

**User Story:** As the developer diagnosing why an estimate was wrong, I want each correction retained with the prediction that provoked it, so that a failure is attributable rather than anecdotal.

**Acceptance Criteria:**

1. <a name="9.1"></a>The system SHALL retain one record per detected food per capture, holding both the values as predicted and the values as finally corrected, rather than one record per user action.  
2. <a name="9.2"></a>The predicted side of a record SHALL hold the class, volume, β applied, density, carbohydrate coefficient, mass and carbohydrate contribution as estimated, and SHALL NOT change thereafter.  
3. <a name="9.3"></a>The corrected side of a record SHALL hold the same fields as finally left by the user, and SHALL be updated in place by each subsequent change; intermediate values SHALL NOT be separately retained.  
4. <a name="9.4"></a>The system SHALL update a record at the moment a change is made, such that backgrounding or termination before the primary action does not lose it.  
5. <a name="9.5"></a>A record SHALL distinguish a food left unchanged, a food whose correction affordance was opened and dismissed without change, and a capture that was retaken or deleted.  
6. <a name="9.6"></a>WHERE a food's amount was corrected, THE SYSTEM SHALL retain the ratio of corrected mass to predicted mass.  
7. <a name="9.7"></a>WHERE a relabel was chosen from the offered alternatives, THE SYSTEM SHALL retain its position in that list; WHERE it was chosen from the full eligible list, THE SYSTEM SHALL retain that the alternatives did not contain it.  
8. <a name="9.8"></a>Each record SHALL identify the build and the segmenter that produced the prediction, such that records originating from a stub segmenter can be excluded from an export.  
9. <a name="9.9"></a>Correction records SHALL NOT be discarded on age, on record count, or by any sweep of stored data, and SHALL be retained in Release builds as well as Debug.  
10. <a name="9.10"></a>Correction records SHALL survive deletion or retake of the meal they refer to, remaining interpretable once the meal row and its artefacts are gone.  
11. <a name="9.11"></a>A record SHALL be interpretable as a training example without the app, without the food database at the edition that produced it, and without the capture's stored mask — the predicted and corrected densities and coefficients SHALL be carried in the record itself.  
12. <a name="9.12"></a>Each record SHALL carry the palette version and the class index locating the food in the capture's stored mask, so that pixel-level supervision can be recovered WHERE that mask still exists.  
13. <a name="9.13"></a>Correction records SHALL be browsable and exportable on-device without network access, and SHALL contain no capture imagery.

### 10. <a name="10"></a>Visual And Accessibility Conformance

**User Story:** As the developer, I want the review surface to read as part of this app, so that it does not look like a different product from the Intake screen.

**Acceptance Criteria:**

1. <a name="10.1"></a>The surface SHALL adopt the row grouping, spacing and single-prominent-primary-action layout of the Intake surface, while remaining on the capture palette.  
2. <a name="10.2"></a>The surface SHALL take its colour values from the design system tokens without introducing new inline values.  
3. <a name="10.3"></a>Text rendered over the photo SHALL meet a contrast ratio of at least 4.5:1 against the composited result at its worst case, not against an assumed background.  
4. <a name="10.4"></a>Every interactive control SHALL present a hit region of at least 44 × 44 pt.  
5. <a name="10.5"></a>WHEN Reduce Transparency is enabled, THE SYSTEM SHALL render any translucent chrome on the surface opaquely.  
6. <a name="10.6"></a>The meal carbohydrate total SHALL remain legible at Dynamic Type sizes up to AX5.  
7. <a name="10.7"></a>The surface SHALL carry no reassurance, disclaimer, or data-preservation copy, per `ui/design-handoff-00` Req 14.5.

## Supersession Register

This spec replaces the following. Per `PROCESS.md`, the superseded text is removed from the documents that hold it, not annotated in place; each removal is a task in `tasks.md`.

| Superseded | Replaced by | Note |
|---|---|---|
| `ui/design-handoff-00` Req 5.1, 5.3 | [1](#1), [2](#2), [3](#3) | Segmentation review becomes editable and is no longer a separate step. Req 5.2's banners are carried to [1.5](#1.5). |
| `ui/design-handoff-00` Req 7.1 | [3](#3), [4](#4) | Already partly stale: `serving-adjust` §iOS app item 5 retired `ManualCorrectionView` and the free-text note. This is cleanup of that debt plus the relabel addition. |
| `ui/design-handoff-00` `copy-inventory.md`, segmentation review relabel row | [3](#3) | The row records the relabel instruction as dropped. |
| `design-system/pages/segmentation-review.md` anti-pattern | [3](#3), [4](#4) | "Do NOT offer a relabel / per-class exclusion interaction." |
| `serving-adjust` `prd.md` §iOS app item 2 | [6.3](#6.3), [6.4](#6.4) | The scale control is retained; only its stop values are restated. |
| `serving-adjust` `prd.md` §iOS app item 4 | [7.4](#7.4), [9.1](#9.1), [9.3](#9.3) | The confirm pill and the edit-by-exception rule both go: corrections apply live, and unchanged foods are retained rather than written off. |
| `serving-adjust` `prd.md` non-goal "no new correction mechanism, event types, or schema changes" | [9](#9) | A correction schema carrying class identity, correction kind, palette version and lineage is required; extends `estimation/pipeline` Req 14.1 and must satisfy its Req 14.4 portability rule. |
| The `corrections` delete cascade (`GRDBPersistenceStore.swift:177`, `:542`) | [9.10](#9.10) | Applies to the correction records only. `corrections` keeps its cascade — it holds the meal's display value, and the per-food amounts its `note` field stood in for are now held directly by the correction record. |
| `PbUserCorrection` as amount-only | [8.7](#8.7) | It carries no corrected class, so every history surface would render a relabelled food under its predicted name. Extending it engages `estimation/pipeline` Req 14.4's portability rule. |
| `paletteVersion` as a SQL-only column, absent from `PbMealRecord` | [9.12](#9.12) | Without it in the portable record, an exported class index cannot be resolved outside the app. |

`ui/design-handoff-00` Decision 7 remains in force: correction is post-hoc, and no user-visible segmentation phase is introduced before the estimate completes. `serving-adjust` §iOS app items 1, 3 and 5 remain in force and are cited, not restated, by [6.1](#6.1).
