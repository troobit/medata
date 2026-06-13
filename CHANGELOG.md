# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- **Persistence schema** — replaced the meal-centric `meals` + `meal_classes` tables with a single long-form `events` table. Each meal is one row with `event_type='meal'`, `value=total_carbs_g`, and the verbatim `PbMealRecord` protobuf-JSON in a generic `metadata` column. New `events(in:type:)` and `corrections(for:)` read methods, `EventType.meal` constant for the event-type vocabulary, and the change-notification stream renamed `mealsDidChange` → `eventsDidChange` (now also fires after `updatePhotoAssetID`). Schema version bumps to "3"; no migration (pre-release, no production data). See [specs/event-log-schema](specs/event-log-schema/).
- Cleaned up changelog to match first version (ignoring history of pre-release UI exploration).
