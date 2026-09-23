# Requirements: fingerprick Glucose

## Introduction

MeData records glucose only from continuous sensors — LibreLinkUp, Apple Health, and screenshot import — all of it interstitial-fluid data carrying a lag and a bias against blood. This feature adds the blood measurement: readings from a Contour Next meter arriving through Apple Health, and a hand-entered reading for every other case, both outranking the sensor as the answer to "what is my glucose now" without displacing a single sensor row. A blood reading is the reference measurement, and each one records what the sensor said at that moment, so every fingerstick doubles as a measurement of the sensor itself. The governing constraint is interaction cost — a reading that takes more than a few seconds to record will not get recorded, and the record is the product.

## Non-Goals

- Connecting to the meter directly over Bluetooth — deferred to a later phase, gated on a protocol note the way `specs/data/cgm-direct` gates its Phase B.
- Calibrating, offsetting, or otherwise correcting the sensor trace from blood readings.
- Analysing or reporting sensor-versus-blood error. Each blood reading stamps its own paired delta ([Req 4.5](#4.5)) and the feature analyses none of it — no aggregation, no calibration, no correction of the trace.
- Any dosing calculation, correction suggestion, or insulin arithmetic consuming the reading.
- Alerting, alarming, or any interpretation of a value, including out-of-range notification.
- Editing a recorded reading's value in place — a wrong entry is deleted and re-entered.
- Writing readings back to Apple Health, or to any destination outside the event log.
- Meal-time tagging of readings (pre/post-prandial), ketone records, and control-solution records.
- mg/dL, unit conversion, or localisation of any kind — glucose is mmol/L, as `specs/data/event-log-schema` Req 2.2 fixes it.
- Migration or reclassification of glucose readings recorded before this feature.

## Requirements

### 1. Meter Readings Through Apple Health

**User Story:** As a user, I want a reading I took on my Contour meter to appear in MeData on its own, so that testing my blood costs me no app interaction at all.

**Acceptance Criteria:**

1. <a name="1.1"></a>WHEN a blood-glucose sample arrives from Apple Health whose originating writer is classified as a blood meter, the system SHALL record it as a `bsl` event carrying blood provenance.  
2. <a name="1.2"></a>IF an arriving sample's originating writer has no classification, THEN the system SHALL record it with sensor provenance, so that an unrecognised writer is never mistaken for a blood reading.  
3. <a name="1.3"></a>The system SHALL record a blood reading at the instant its originating device measured it, without snapping that instant to the 5-minute grid that sensor readings occupy.  
4. <a name="1.4"></a>WHEN Apple Health re-delivers a sample already recorded, the system SHALL NOT record a second event for it.  
5. <a name="1.5"></a>The system SHALL list, in Settings, every Apple Health writer that has contributed a glucose sample, and SHALL allow each to be classified as a blood meter or a sensor, taking effect on subsequently arriving samples.  

### 2. Hand-Entered Readings

**User Story:** As a user, I want to type a reading in a few seconds from wherever I am, so that a number I read off a screen still reaches the record.

**Acceptance Criteria:**

1. <a name="2.1"></a>The home page SHALL present a BSL control sharing the Dose control's row, and the system SHALL present a glucose-entry surface WHEN that control is tapped, and WHEN the `medata://glucose/add` deep link is opened, from any app state.  
2. <a name="2.2"></a>The system SHALL provide a lock- and home-screen widget that opens the glucose-entry surface, matching the existing dose and capture launcher widgets in behaviour and supported families.  
3. <a name="2.3"></a>The glucose-entry surface SHALL accept any value from 1.0 to 30.0 mmol/L to one decimal place, SHALL reach and record any value in that range within four interactions of the surface appearing, and SHALL dismiss itself on recording.  
4. <a name="2.4"></a>The system SHALL record the reading at the moment of saving, and SHALL allow that instant to be moved earlier by the same compact back-dating control the insulin, activity, and carb-entry sheets use, without that adjustment being a required step or counting against [2.3](#2.3)'s interaction budget.  
5. <a name="2.5"></a>A hand-entered reading SHALL carry blood provenance and SHALL be indistinguishable in behaviour from a meter reading on every surface and in every precedence decision.  
6. <a name="2.6"></a>The system SHALL retain, on each recorded reading, which route recorded it — Apple Health writer or hand entry — such that a reading's origin is recoverable without that origin altering its behaviour.  
7. <a name="2.7"></a>WHEN the latest-reading display on the home page is tapped, the system SHALL present the Graph surface — the reading is a route to its own history, not an entry point (redefines `specs/ui/home-router` [Req 4.8](../../ui/home-router/requirements.md#4.8)).  

### 3. Precedence of Blood Over Sensor

**User Story:** As a user, I want the blood reading to be the number the app shows me, so that the value I trusted enough to prick my finger for is the value I see.

**Acceptance Criteria:**

1. <a name="3.1"></a>WHERE a blood reading's instant falls within the hold window of the present moment, every surface reporting the current glucose value SHALL report that reading, even WHERE sensor readings more recent than it exist.  
2. <a name="3.2"></a>The hold window SHALL be 15 minutes unless changed, and SHALL be adjustable in Settings without reinstalling or rebuilding the app.  
3. <a name="3.3"></a>WHEN the hold window has elapsed since the most recent blood reading, those surfaces SHALL resume reporting the most recent reading of any provenance.  
4. <a name="3.4"></a>WHERE two or more blood readings fall within the window, the system SHALL report the one with the latest instant.  
5. <a name="3.5"></a>Every surface reporting the current glucose value SHALL name the reported reading's provenance alongside it.  
6. <a name="3.6"></a>The system SHALL measure a reported reading's age, and apply the existing staleness ladder to it, from that reading's own instant.  
7. <a name="3.7"></a>The home page, the lock-screen glucose widget, and any other current-value surface SHALL report the same reading as each other at the same moment, under the same hold window.  
8. <a name="3.8"></a>WHERE a current-value surface refreshes itself from a sensor source directly rather than from the recorded event log, that surface SHALL NOT replace a reported blood reading with a sensor reading before that blood reading's window has elapsed.  
9. <a name="3.9"></a>WHERE a reading's instant precedes the moment it is recorded by more than the hold window, the system SHALL record it without it becoming the reported current value.  

### 4. Sensor Data Preserved

**User Story:** As the data owner, I want every sensor reading kept exactly as recorded, so that the paired blood and sensor values remain available to measure my sensor against later.

**Acceptance Criteria:**

1. <a name="4.1"></a>Recording a blood reading SHALL NOT modify, supersede, hide, or delete any existing glucose event.  
2. <a name="4.2"></a>The Graph SHALL draw the sensor trace unbroken across the instant of a blood reading, and SHALL draw blood readings as markers distinct from that trace.  
3. <a name="4.3"></a>The Records timeline SHALL list every glucose reading of both provenances, each labelled with its own, in the existing most-recent-first order.  
4. <a name="4.4"></a>WHERE a blood reading and a sensor reading share an instant, both SHALL remain individually retrievable.  
5. <a name="4.5"></a>WHEN a blood reading is recorded and a sensor-provenance reading exists within the 15 minutes preceding the blood instant, the system SHALL record on the blood event that sensor reading's value and instant and the signed difference (blood minus sensor), without modifying the sensor event; WHEN none exists, the blood event SHALL carry no pairing.  

### 5. Trend Derivation

**User Story:** As a user, I want the trend arrow to keep meaning what it meant, so that one blood reading does not make a steady sensor trace look like a spike — and I still want a direction when fingersticks are the only data there is.

**Acceptance Criteria:**

1. <a name="5.1"></a>The system SHALL derive the trend indicator from readings of a single provenance — from sensor readings WHEN they satisfy the existing count-and-span rules within the trend window, otherwise from blood readings alone under the same rules — and SHALL NOT derive it from a mixed series, WHILE the reported current value may itself be a blood reading.  
2. <a name="5.2"></a>WHERE neither provenance alone satisfies the existing count-and-span rules, the system SHALL report no trend rather than deriving one from a mixed series.  

### 6. Correcting a Mistake

**User Story:** As a user, I want a mistyped reading gone, so that a fat-fingered entry does not sit in the record or on my Lock Screen.

**Acceptance Criteria:**

1. <a name="6.1"></a>A blood reading SHALL be deletable from the Records timeline by the same gestures and bulk actions as any other glucose reading.  
2. <a name="6.2"></a>WHEN a blood reading is deleted, every current-value surface SHALL report the reading it would have reported had that reading never been recorded.  

### 7. Existing Readings

**User Story:** As a developer, I want the readings already recorded to keep working, so that adding provenance costs no migration.

**Acceptance Criteria:**

1. <a name="7.1"></a>The system SHALL treat every glucose reading recorded before this feature as a sensor reading, without rewriting it.  
2. <a name="7.2"></a>The system SHALL continue to snap sensor readings to the 5-minute grid and merge them keep-first, so that sensor ingestion, screenshot import, and their duplicate handling behave as they do today.  
