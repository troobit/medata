# MeData MVP Requirements

**Version:** 1.2
**Last Updated:** 2026-02-03
**Status:** Approved

---

## Introduction

MeData is a personal health data repository for Type 1 diabetes management. The MVP focuses on **food macro capture via photography** - enabling the Owner to photograph meals, receive AI-powered macro estimates, review/adjust the results, and save meal records.

This document defines the MVP requirements in EARS (Easy Approach to Requirements Syntax) format. Requirements are organised by user story with testable acceptance criteria.

### Scope

**In Scope (MVP):**
- Food photo capture and AI macro estimation
- Manual macro entry (fallback and standalone)
- Meal record storage and retrieval
- Meal history logbook view
- Meal presets for frequently eaten foods
- Nutrition label scanning (Australian format)
- Edit saved meals after storage

**Out of Scope (MVP):**
- Insulin logging
- Blood sugar readings and CGM import
- Exercise and alcohol tracking
- Visualisation and graphs
- Dose suggestions and modelling
- User profile management
- Data export
- Offline support (online-only for MVP)
- Authentication (single-user application)
- Automated testing beyond mathematical validation

### Definitions

| Term | Definition |
|------|------------|
| **Owner** | The primary user - a person with T1 diabetes who has full authority over their data |
| **Macro** | Macronutrient - carbohydrates, protein, or fat measured in grams |
| **BSL** | Blood Sugar Level, measured in mmol/L |
| **Confidence Score** | A 0-1 value indicating AI certainty in a recognition result |
| **Preset** | A saved meal template that can be reused for quick logging |

---

## 1. Food Photo Capture

**User Story:** As the Owner, I want to photograph my meal and receive macro estimates, so that I can quickly log food without manual data entry.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL provide a camera capture interface that uses the device's rear-facing camera
2. <a name="1.2"></a>The system SHALL accept JPEG and PNG image formats for food recognition
3. <a name="1.3"></a>The system SHALL display a preview of the captured image before submitting for AI analysis
4. <a name="1.4"></a>The system SHALL allow the Owner to retake the photo if the preview is unsatisfactory
5. <a name="1.5"></a>The system SHALL be mobile-first and work on modern mobile browsers
6. <a name="1.6"></a>The system SHALL support uploading existing photos from the device gallery as an alternative to camera capture

---

## 2. AI Food Recognition

**User Story:** As the Owner, I want AI to identify foods in my photo and estimate their macros, so that I don't have to look up nutritional information manually.

**Acceptance Criteria:**

1. <a name="2.1"></a>The system SHALL send captured images to a configured AI provider for food recognition
2. <a name="2.2"></a>The system SHALL return an itemised list of recognised food items with individual macro estimates (carbs, protein, fat)
3. <a name="2.3"></a>The system SHALL display a confidence score (0-1) for each recognised food item
4. <a name="2.4"></a>The system SHALL display all recognition results regardless of confidence level
5. <a name="2.5"></a>The system SHALL calculate and display aggregate totals for all macros
6. <a name="2.6"></a>The system SHALL complete food recognition within 10 seconds under normal network conditions
7. <a name="2.7"></a>WHEN AI recognition fails, the system SHALL display an actionable error message and offer manual entry as a fallback
8. <a name="2.8"></a>The system SHALL support at least one AI provider (Claude, OpenAI, Gemini, or local model)
9. <a name="2.9"></a>IF multiple AI providers are configured, the system SHOULD attempt fallback providers when the primary fails
10. <a name="2.10"></a>WHEN AI recognition returns zero food items, the system SHALL display an error and offer to retry or proceed with manual entry

---

## 3. Manual Macro Entry

**User Story:** As the Owner, I want to manually enter food macros with minimal friction, so that I can log meals quickly when AI is unavailable.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL provide a minimal entry form with fields: name, carbs, protein, fat
2. <a name="3.2"></a>The system SHALL allow adding multiple food items to a single meal
3. <a name="3.3"></a>The system SHALL automatically calculate aggregate totals when items are added or modified
4. <a name="3.4"></a>The system SHALL validate that macro values are non-negative numbers
5. <a name="3.5"></a>The system SHALL allow manual entry without requiring a photo
6. <a name="3.6"></a>The system SHALL allow editing AI-recognised items before saving
7. <a name="3.7"></a>The system SHALL make carbs and fat fields immediately editable with large tap targets for quick adjustment

---

## 4. Meal Record Storage

**User Story:** As the Owner, I want my meal records saved permanently, so that I can build a history of my food intake over time.

**Acceptance Criteria:**

1. <a name="4.1"></a>The system SHALL persist meal records to the database with: timestamp, food items, total macros, source, and optional image URL
2. <a name="4.2"></a>The system SHALL record the data source for each meal (manual, ai_image, label_scan, preset)
3. <a name="4.3"></a>The system SHALL store the original image in blob storage when a photo is used
4. <a name="4.4"></a>The system SHALL default the meal timestamp to the current time
5. <a name="4.5"></a>The system SHALL allow the Owner to adjust the timestamp to backdate meals
6. <a name="4.6"></a>The system SHALL provide visual confirmation when a meal is successfully saved
7. <a name="4.7"></a>The system SHALL store timestamps in UTC with millisecond precision
8. <a name="4.8"></a>The system SHALL never delete meal records without explicit Owner action

---

## 5. Meal Review and Edit

**User Story:** As the Owner, I want to review and edit AI estimates before saving, so that I can correct any inaccuracies.

**Acceptance Criteria:**

1. <a name="5.1"></a>The system SHALL display AI recognition results in an editable format before saving
2. <a name="5.2"></a>The system SHALL allow inline editing of any food item's name, quantity, unit, or macro values
3. <a name="5.3"></a>The system SHALL allow removing individual food items from the meal
4. <a name="5.4"></a>The system SHALL allow adding new food items to the meal
5. <a name="5.5"></a>The system SHALL recalculate aggregate totals immediately when any item is modified
6. <a name="5.6"></a>The system SHALL preserve the original AI confidence scores for reference even after editing

---

## 6. Meal Presets

**User Story:** As the Owner, I want to save frequently eaten meals as presets, so that I can log them quickly without re-entering data.

**Acceptance Criteria:**

1. <a name="6.1"></a>The system SHALL allow saving any meal as a named preset (or use emoji only names)
2. <a name="6.2"></a>The system SHALL store preset data including: name, category (meal/snack), food items, and total macros
3. <a name="6.3"></a>The system SHALL allow applying a preset to create a new meal record in a single action
4. <a name="6.6"></a>The system SHALL allow editing preset details after creation
5. <a name="6.7"></a>The system SHALL allow deleting presets
6. <a name="6.8"></a>WHEN applying a preset, the system SHALL allow the Owner to modify the meal before saving

---

## 7. Nutrition Label Scanning

**User Story:** As the Owner, I want to scan nutrition labels on packaged foods, so that I can get accurate macro data without manual transcription.

**Acceptance Criteria:**

1. <a name="7.1"></a>The system SHALL accept photos of nutrition labels for parsing
2. <a name="7.2"></a>The system SHALL extract serving size, carbs, protein, and fat from Australian-format nutrition labels
3. <a name="7.4"></a>The system SHALL allow the Owner to then take a photo of this food item to estimate servings consumed.
4. <a name="7.5"></a>The system SHALL calculate total macros based on servings × per-serving values, or per 100g if servings are not provided.
5. <a name="7.6"></a>WHEN label parsing fails, the system SHALL offer manual entry as a fallback

---

## 8. Meal History and Logbook

**User Story:** As the Owner, I want to view my meal history in a logbook, so that I can review what I've eaten over time.

**Acceptance Criteria:**

1. <a name="8.1"></a>The system SHALL display saved meals in a chronological logbook view
2. <a name="8.2"></a>The system SHALL show meal timestamp, total macros, and food item count in the logbook list
3. <a name="8.3"></a>The system SHALL allow expanding a meal entry to view full details including individual food items
4. <a name="8.4"></a>The system SHALL allow editing saved meals after storage
5. <a name="8.5"></a>The system SHALL allow deleting saved meals from the logbook
6. <a name="8.6"></a>The system SHALL display the meal's associated photo (if any) in the detail view

---

## 9. User Interface

**User Story:** As the Owner, I want a mobile-friendly interface with minimal friction, so that logging meals doesn't feel like a chore.

**Acceptance Criteria:**

1. <a name="9.1"></a>The system SHALL be optimised for mobile devices with one-handed operation
2. <a name="9.2"></a>The system SHALL use touch-friendly tap targets of at least 44×44 pixels
3. <a name="9.3"></a>The system SHALL allow completing the primary flow (photo → review → save) in 3 or fewer distinct actions
4. <a name="9.4"></a>The system SHALL display a responsive layout that adapts to phone, tablet, and desktop viewports
5. <a name="9.5"></a>The system SHALL use Irish English spelling in all user-facing text
6. <a name="9.6"></a>The system SHALL NOT display cautionary warnings, disclaimers, or paternalistic messaging
7. <a name="9.7"></a>Error messages SHALL state what failed and suggest resolution without apologetic language

---

## 10. Data Integrity

**User Story:** As the Owner, I want my data to be reliably stored and never lost, so that I can trust the system with my health records.

**Acceptance Criteria:**

1. <a name="10.1"></a>The system SHALL include creation timestamp on all records
2. <a name="10.2"></a>The system SHALL include last-modified timestamp on all records
3. <a name="10.3"></a>The system SHALL store raw macro values in grams, not derived percentages
4. <a name="10.4"></a>The system SHALL store food names as user-provided strings, not opaque identifiers
5. <a name="10.5"></a>The system SHALL NOT impose artificial validation ranges on macro values
6. <a name="10.6"></a>The system SHALL display an error message when network requests fail (online-only MVP)

---

## 11. Security and Privacy

**User Story:** As the Owner, I want my health data and API keys secured, so that my personal information is protected.

**Acceptance Criteria:**

1. <a name="11.1"></a>The system SHALL load AI provider API keys from environment variables for deployment, with local storage fallback for development
2. <a name="11.2"></a>The system SHALL use secure best practice for image uploads to blob storage
3. <a name="11.3"></a>The system SHALL NOT log or persist API keys server-side
4. <a name="11.4"></a>The system SHALL NOT collect telemetry or analytics without explicit Owner consent
5. <a name="11.5"></a>Database credentials SHALL be server-side secrets, never exposed to the client
6. <a name="11.6"></a>The system SHALL be a single-user application with no authentication required

---

## Non-Functional Requirements

### Performance

1. <a name="NF.1"></a>The system SHALL load the initial page within 3 seconds on a 4G connection
2. <a name="NF.2"></a>The system SHALL complete AI food recognition within 10 seconds
3. <a name="NF.3"></a>The system SHALL save meal records within 2 seconds

### Compatibility

1. <a name="NF.4"></a>The system SHALL be mobile-first and function on modern mobile browsers
2. <a name="NF.5"></a>The system SHALL work as a Progressive Web App installable on mobile devices

### Constraints

1. <a name="NF.8"></a>The system SHALL require an internet connection (online-only for MVP)
2. <a name="NF.9"></a>The system SHALL support a single user without authentication

### Extensibility

1. <a name="NF.6"></a>The data model SHALL support adding new event types without schema migration
2. <a name="NF.7"></a>The system SHALL store events with flexible metadata to accommodate future data types

---

## Revision History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2026-02-03 | 1.0 | Claude | Initial requirements in EARS format based on specification.md |
| 2026-02-03 | 1.1 | Claude | Added meal history section, security constraints, design critic feedback |
| 2026-02-03 | 1.2 | Owner/Claude | Removed calories from input, simplified presets, frictionless input focus |
