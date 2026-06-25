# Requirements: Event Log Schema

## Introduction

MeData stores meals in a meal-centric SQLite schema — normalized columns plus a `record_json` BLOB, with `meal_classes`, `meal_artefacts`, and `corrections` side tables. This feature uplifts persistence to a Long-Form Event Log: one row per discrete physiological or behavioural event, with fixed `timestamp` / `event_type` / `value` columns and a flexible JSON `metadata` column, so future metrics can be added as new event types without schema changes. The app is pre-release with no production data, so the event log is introduced directly as the meal store; there is nothing to migrate. Scope is the data architecture only.

## Non-Goals

- Migration or backfill of existing data — there is none; the event log is introduced directly.
- Ingestion validation, or flagging of physiologically impossible values.
- Regression / ML models, decay functions, stateful sessionization, late-data detection.
- Lakehouse patterns: horizontal/vertical partitioning, small-file compaction, materialized projections, block-skipping statistics, schema-compatibility registry — deferred until justified by data volume.
- CGM or third-party health sync; ingesting any `event_type` other than `meal` in this phase.
- Localization or unit conversion of any kind.
- Folding `meal_artefacts` or `corrections` into the event log; they remain in their own tables, linked by the meal's id.

## Requirements

### 1. Long-Form Event Log Table

**User Story:** As a data scientist, I want an atomic long-form log of events, so that I can add new metrics without changing the schema.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL persist events in a single table where each row represents one discrete event with fixed columns for a unique id, a timestamp, an `event_type`, and a `value`, plus a `metadata` column holding JSON.  
2. <a name="1.2"></a>The system SHALL store the canonical scalar measurement for an event in the `value` column and all multi-dimensional or auxiliary data in the `metadata` column.  
3. <a name="1.3"></a>The system SHALL represent a new metric as a new `event_type` value without requiring a schema change.  
4. <a name="1.4"></a>The system SHALL store each timestamp as an absolute instant and SHALL return events ordered chronologically.  
5. <a name="1.5"></a>The system SHALL return only the events whose timestamp falls within a requested `[start, end]` range.  

### 2. Canonical Metric Units

**User Story:** As the system owner, I want one fixed unit per metric, so that stored values are unambiguous for the life of the app.

**Acceptance Criteria:**

1. <a name="2.1"></a>The system SHALL store every physiological value in metric units only.  
2. <a name="2.2"></a>The system SHALL store glucose values in mmol/L, mass in grams, and volume in cubic centimetres.  
3. <a name="2.3"></a>The system SHALL NOT store imperial units, and SHALL NOT perform unit or locale conversion on stored values.  

### 3. Meal Representation

**User Story:** As a developer, I want each meal stored as one event, so that meals stay atomic while their breakdown remains queryable.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL store each meal as a single event with `event_type` `"meal"`, `value` equal to the meal's total carbohydrate in grams, and that `value` SHALL be the uncorrected estimate (the same quantity the current `total_carbs_g` column holds).  
2. <a name="3.2"></a>The system SHALL store in the meal event's `metadata` the verbatim meal record (the protobuf-JSON currently held in `record_json`) together with the fields that exist only in SQL columns today (`palette_version`, and the `photo_asset_id` / `segmenter_source` overrides), such that the original `MealRecord` reconstructs from `metadata` with no loss.  
3. <a name="3.3"></a>The system SHALL use the meal's UUID as the event id so that `meal_artefacts` and `corrections` rows link to it.  

### 4. Event Log as Meal Store

**User Story:** As a developer, I want reads and writes to go through the event log, so that there is a single source of truth.

**Acceptance Criteria:**

1. <a name="4.1"></a>The system SHALL write each new meal to the event log as a `"meal"` event, and SHALL NOT write to a separate `meals` or `meal_classes` table.  
2. <a name="4.2"></a>The system SHALL read meals from the event log for all meal-listing and meal-detail paths.  
3. <a name="4.3"></a>WHEN a meal event is deleted, the system SHALL remove its linked `meal_artefacts` and `corrections` rows, preserving today's delete-cascade behaviour.  
4. <a name="4.4"></a>The system SHALL surface user corrections as a separate overlay read from the `corrections` table, leaving the meal event's `value` as the uncorrected estimate.  
5. <a name="4.5"></a>WHEN an event is written, the system SHALL emit a change notification so that subscribed UI updates as it does today.  
