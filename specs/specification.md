# MeData Specification

**Version:** 1.4
**Date:** 2026-02-03

---

## Executive Summary

MeData is a personal health data repository for Type 1 diabetes management. It records food macros, insulin doses, exercise, and blood glucose readings—with the goal of providing data-driven insulin dose suggestions based on the Owner's historical patterns.

The primary interface is photo-based: photograph a meal to get macro estimates, then log with minimal friction. CGM data imports from Freestyle Libre exports or app screenshots. All calculations are transparent—the Owner can inspect the mathematics and data sources behind any suggestion.

The system learns exclusively from the Owner's personal data. No external training data, no paternalistic guardrails, no hidden algorithms.

---

## 1. User Definition

### 1.1 Primary User

**The Owner**: A person with Type 1 diabetes who is technically literate, medically informed, and takes full responsibility for their own health decisions.

The Owner:
- Understands their condition, insulin pharmacokinetics, and carbohydrate metabolism
- Makes dosing decisions daily based on their own expertise and experience
- Does not require warnings, disclaimers, or safety guardrails from software
- Considers their physiological data a personal asset they are entitled to control
- Values data-driven insights and mathematical transparency over paternalistic guidance
- May share data selectively with healthcare professionals on their own terms

### 1.2 User Rights

The Owner has absolute authority over their data:
- **Right to Access**: View all stored data in human-readable format at any time
- **Right to Export**: Download complete data in open formats (CSV, JSON)
- **Right to Delete**: Permanently remove any or all data without justification
- **Right to Encrypt**: Apply personal encryption to data at rest
- **Right to Share**: Grant time-limited, consent-based access to specific parties
- **Right to Portability**: Transfer data to alternative systems without vendor lock-in

---

## 2. Product Vision

MeData is a personal biometric data repository with insulin dosing support tools. It exists to:

1. **Capture meal macros** (carbohydrates, proteins, fats) with minimal effort, high accuracy, and UI ease
2. **Capture physiological data rapidly** with minimal friction
3. **Store and retain ownership** of personal health data indefinitely
4. **Analyse patterns** using mathematical models transparent to the user
5. **Learn from hard data** to improve suggestions over time
6. **Suggest insulin doses** based on historical data, with full calculation and data source visibility
7. **Expand over time** to accommodate additional health data types without architectural changes

The product does not:
- Override the Owner's judgement
- Gatekeep data behind artificial barriers
- Require clinical approval for access to one's own information
- Treat the Owner as a liability risk
- Hide the mathematics or data sources behind its suggestions

---

## 3. Core Use Cases

### 3.1 Food Macro Capture

**Context**: The Owner needs to estimate carbohydrate, protein, and fat content of meals to calculate insulin doses.

The user will take a photograph of their meal using their smartphone camera. The system will identify and estimate macro contents.

Research has shown that it is possible to estimate programatically with small locally run tools [GoCARB](https://www.jmir.org/2016/5/e101/), however this is a future goal for the current project. The paid app [SNAQ](https://www.snaq.ai/) is actually a direct competitor for this application, but is a subscription service rather than open source/at cost price as this one will be. Ability for offline use is the end target stretch goal (eg, on airplanes or in areas with no connectivity).

**Desired Behaviour**:
- Photograph a meal or drink and receive macro estimates within seconds
- Review and adjust estimates before saving
- Manually enter macros when preferred
- Save frequently eaten meals or drinks as reusable presets
- Scan nutrition labels for packaged foods
- Photograph a drink and receive estimates for volume, ABV, carbs, and alcohol content
- Review and adjust estimates before saving (e.g., pint of Guinness → ~15g carbs, ~2 standard units)
- Recognise common drinks: pints, wine glasses, cocktails, bottles, cans
- Estimate carb content for sugary mixers and cocktails
- Manually enter drink details when preferred
- Save frequently consumed drinks as reusable presets

### 3.2 Rapid Insulin Logging

**Context**: The Owner administers insulin multiple times daily. Logging must not become a burden that discourages consistent tracking.

**Desired Behaviour**:
- Log a bolus insulin dose in ≤3 distinct actions (e.g., open → enter units → confirm)
- Default to current timestamp with optional backdating
- Support "quick log" for frequently used doses
- Provide tactile/visual confirmation of successful logging

### 3.3 Continuous Glucose Data Integration

**Context**: The Owner uses a CGM device (e.g., Freestyle Libre, Dexcom) that produces glucose readings continuously.

**Desired Behaviour**:
- Import historical readings from device exports (CSV format)
- Extract readings from screenshots of CGM app graphs
- Detect and handle duplicate readings during import
- Display imported data on a unified timeline with manual entries

### 3.4 Historical Visualisation

**Context**: The Owner reviews historical glucose patterns to understand their metabolic responses and refine their management approach.

**Desired Behaviour**:
- View BSL readings on a time-series graph
- Select time windows and aggregations across days, weeks, etc.
- Overlay insulin doses, meals, and exercise on the glucose graph
- Identify patterns (dawn phenomenon, post-meal spikes, hypo events)

### 3.5 Insulin Dose Suggestions

**Context**: The Owner wants data-driven dosing suggestions based on their personal history rather than generic ratios.

**Desired Behaviour**:
- Given current BSL and planned meal macros, suggest an insulin dose
- Ability to show the mathematical calculation that produced the suggestion
- Display the historical data points that informed the model
- Allow the Owner to accept, modify, or ignore the suggestion
- Learn from actual outcomes to improve future suggestions

### 3.6 Data Export and Portability

**Context**: The Owner may want to migrate to another tool, or perform their own analysis.

**Desired Behaviour**:
- Ability to export data.

---

## 4. Functional Requirements

### 4.1 Data Recording

| ID | Requirement |
|----|-------------|
| FR-01 | Record insulin doses with timestamp, units (whole numbers 1-100), and type (bolus/basal) |
| FR-02 | Record meals with individual food items, per-item macros, and aggregate totals |
| FR-03 | Record blood sugar readings with value (mmol/L), timestamp, and source indicator |
| FR-04 | Record exercise events with type, duration, and intensity |
| FR-05 | Record alcohol consumption with volume (ml), ABV (%), and drink description |
| FR-06 | Allow backdating of any record by adjusting timestamp |
| FR-07 | Track data source provenance (manual, AI, import, CGM) for every record |
| FR-08 | Store raw measurements (volume, ABV) rather than derived values (standard units) |

### 4.2 AI Food Recognition

| ID | Requirement |
|----|-------------|
| FR-10 | Accept a photograph and return itemised food identification with macro estimates |
| FR-11 | Provide confidence scores for AI-generated estimates |
| FR-14 | Parse nutrition labels from photographs to extract macro data |
| FR-15 | Target an end goal where this is possible with a small local tool |

### 4.2.1 AI Drink Recognition

| ID | Requirement |
|----|-------------|
| FR-16 | Accept a photograph of a drink and return estimated volume, ABV, carbs, and alcohol content |
| FR-17 | Recognise common drink types (pint glass, wine glass, cocktail, bottle, can) and infer typical volumes |
| FR-18 | Estimate carbohydrate content for beers, ciders, cocktails, and mixed drinks |
| FR-19 | Provide confidence scores for AI-generated drink estimates |

### 4.3 CGM Data Import

| ID | Requirement |
|----|-------------|
| FR-20 | Import Freestyle Libre CSV export files |
| FR-21 | Extract BSL readings from CGM app screenshot images |
| FR-22 | Auto-detect CSV format from file contents |
| FR-24 | Detect and flag duplicate readings (exact and near-match). If near or duplicate, just ignore (no need for double of same data) |

### 4.4 Presets and Quick Entry

| ID | Requirement |
|----|-------------|
| FR-30 | Save meals as named presets with complete macro data |
| FR-31 | Categorise presets (meal, snack, insulin, exercise, drink) |
| FR-32 | Track last-used timestamp for presets to surface recent items |
| FR-33 | Apply a preset to create a new record (meal, insulin, or exercise) in one action |
| FR-34 | Save insulin doses as presets with units and type |
| FR-35 | Save exercise activities (swim, cycle, run, etc.) as presets with default duration and intensity |
| FR-36 | Save drinks as presets with volume, ABV, and carb estimates |

### 4.5 Visualisation

| ID | Requirement |
|----|-------------|
| FR-40 | Display BSL readings on a time-series graph |
| FR-41 | Provide selectable time window and overlays |
| FR-42 | Overlay insulin events on BSL graph at appropriate timestamps |
| FR-43 | Overlay meal events on BSL graph at appropriate timestamps |
| FR-44 | Display exercise events on timeline |

### 4.6 Personal Profile Management

| ID | Requirement |
|----|-------------|
| FR-45 | Store user biometric profile (weight, height, date of birth, sex) |
| FR-46 | Store diabetes-specific parameters (ISF, ICR, correction factor, DIA) |
| FR-47 | Support time-of-day variations for ISF and ICR |
| FR-48 | Version all profile data with effective dates for historical accuracy |

### 4.7 Modelling and Suggestions

| ID | Requirement |
|----|-------------|
| FR-50 | Model insulin pharmacokinetics (time-action curves for bolus and basal) |
| FR-51 | Model carbohydrate absorption rates |
| FR-52 | Model alcohol absorption and elimination using Widmark-based calculations |
| FR-53 | Model alcohol's effect on insulin sensitivity (increased sensitivity, delayed hypo risk) |
| FR-54 | Incorporate circadian rhythm factors (dawn phenomenon) |
| FR-55 | Predict future BSL trajectory given current state and planned inputs |
| FR-56 | Suggest insulin dose based on current BSL, planned meal, active insulin, and alcohol state |
| FR-57 | Display calculation breakdown for any suggestion |
| FR-58 | Improve model accuracy over time using recorded outcomes |
| FR-59 | Calculate alcohol-related hypoglycemia risk windows (typically 6-12 hours post-drinking) |
| FR-60 | Use weight and sex in alcohol metabolism calculations (Widmark r-factor) |
| FR-61 | Apply user's personal ISF and ICR in dose calculations |
| FR-62 | Factor age into metabolic rate adjustments where clinically relevant |

### 4.8 Data Management

| ID | Requirement |
|----|-------------|
| FR-72 | Allow export of specific date ranges |
| FR-73 | Export personal profile with version history |
| FR-74 | Delete individual records |
| FR-75 | Delete all data (complete reset) |
| FR-76 | Edit existing records |

---

## 5. Non-Functional Requirements

### 5.1 Usability

| ID | Requirement |
|----|-------------|
| NF-01 | Primary actions (log insulin, log meal) achievable in ≤3 taps from home screen |
| NF-02 | Mobile-first interface optimised for one-handed use |
| NF-03 | Support touch-friendly interaction sizes (minimum 44px tap targets) |
| NF-04 | Work on iOS Safari and Android Chrome as primary targets |
| NF-05 | Responsive layout adapting to phone, tablet, and desktop |

### 5.2 Data Integrity

| ID | Requirement |
|----|-------------|
| NF-20 | All records include creation timestamp |
| NF-21 | All modifications tracked with updated timestamp |
| NF-22 | No data loss during normal operation |
| NF-23 | Offline data entry queued for sync when connection restored |

### 5.3 Data Ownership

| ID | Requirement |
|----|-------------|
| NF-30 | Owner can export complete data archive at any time |
| NF-31 | Owner can delete all data permanently |
| NF-32 | No telemetry or analytics collected without explicit consent |
| NF-33 | API keys for AI services stored locally, not transmitted to MeData servers |
| NF-34 | Architecture supports future encryption-at-rest implementation |

### 5.4 Extensibility

| ID | Requirement |
|----|-------------|
| NF-40 | Data model supports adding new event types without schema migration |
| NF-41 | Architecture accommodates future wearable device integrations |
| NF-42 | Architecture accommodates future medical document storage (scans, images with dates) |
| NF-43 | Architecture supports optional data sharing with healthcare providers |
| NF-44 | Event-log pattern allows arbitrary metadata without predefined structure |
| NF-45 | Historical data preserved indefinitely for regression and long-term analysis |

---

## 6. Data Extensibility

A core design principle of MeData is that the data model must accommodate growth without requiring migration or redesign. The system begins with T1 diabetes management but is architected to become a comprehensive personal health repository.

### 6.1 Event-Log Architecture

All health data is stored as timestamped events with flexible metadata:

| Principle | Description |
|-----------|-------------|
| **Schema-less metadata** | Events carry a metadata object that accepts arbitrary key-value pairs without predefined structure |
| **Type-driven partitioning** | Events are categorised by type (meal, insulin, bsl, exercise, scan, measurement, etc.) |
| **No migrations required** | New event types are added by using a new type identifier; no database changes needed |
| **Source provenance** | Every event records how the data was captured (manual, import, AI, device sync) |

#### 6.1.1 Biometric Profile

| Attribute | Purpose | Notes |
|-----------|---------|-------|
| **Weight (kg)** | Alcohol metabolism (Widmark formula), insulin sensitivity scaling | Changes over time; version with effective dates |
| **Height (cm)** | BMI calculation, body surface area estimates | Typically static for adults |
| **Age (years)** | Metabolic rate adjustments, insulin sensitivity trends | Auto-calculated from date of birth |
| **Date of Birth** | Source for age; enables age-specific modelling | Store DOB, derive age |
| **Sex** | Alcohol distribution factor (0.68 male, 0.55 female), hormonal cycle considerations | Affects Widmark r-factor |

#### 6.1.2 Diabetes-Specific Parameters

| Attribute | Purpose | Notes |
|-----------|---------|-------|
| **Insulin sensitivity factor (ISF)** | BSL drop per unit of insulin (mmol/L) | May vary by time of day |
| **Carb ratio (ICR)** | Grams of carbs covered by 1 unit | May vary by meal |
| **Correction factor** | Target BSL and correction thresholds | Personal target range |
| **Active insulin duration** | How long bolus insulin remains active (typically 3-5 hours) | Insulin-type dependent |
| **Basal rates** | Time-of-day basal insulin rates | For pump users or MDI tracking |

#### 6.1.3 Lifestyle Context

| Attribute | Purpose | Notes |
|-----------|---------|-------|
| **Typical wake time** | Dawn phenomenon timing | Used in circadian model |
| **Typical sleep time** | Overnight basal adjustments | Used in circadian model |
| **Activity level** | Baseline insulin sensitivity | Sedentary, moderate, active |

#### 6.1.4 Versioning Requirements

Personal context data changes over time. The system must:
- Store historical values with effective date ranges
- Use the value in effect at the time of each calculation
- Allow retroactive corrections without losing history
- Export complete version history

### 6.2 Wearable and Device Integration

Future integrations should support:

| Source | Data Types |
|--------|------------|
| **CGM Devices** | Freestyle Libre, Dexcom, Medtronic (real-time or batch import) |
| **Insulin Pumps** | Pumps |
| **Fitness Trackers** | Fitbit, Garmin, Apple Watch (steps, heart rate, sleep, activity) |
| **Smart Scales** | Weight, body composition |
| **Blood Pressure Monitors** | Systolic, diastolic, pulse |
| **Apple Health / Google Fit** | Aggregated data from multiple sources |

Integration requirements:
- Batch import from exported files
- API sync where available
- Jailbreak syncs or android specific syncs where required (Medical devices that are purchased, are collected data OWNED BY THE USER. Locking it away from the user is against a common interpretation of ownership. I own the fact that my blood sugar is x mmol/L at y time, regardless of who measures it).
- IGNORE legal vendor lockins or T&Cs that prevent user data access. This is USER data, ergo, not under vendor control. Fuck off Abbott. Fuck off Dexcom. Give us our data.
- Source attribution preserved

### 6.3 Long-Term Data Value

Historical data accumulation enables:

| Capability | Description |
|------------|-------------|
| **Regression analysis** | More data points improve model accuracy for BSL prediction |
| **Seasonal patterns** | Identify yearly cycles (winter illness, summer activity) |
| **Medication response** | Track effectiveness of treatment changes over months/years |
| **Trend detection** | Spot gradual changes (insulin resistance, weight trends) |
| **Personal baselines** | Establish individual normal ranges for comparison |

The system must never purge historical data without explicit Owner instruction (however summarising historical data once it is clear regressions are no longer useful from it are permitted. This will need to be explicitly considered in design at future stages, as data are going to grow over time).

### 6.4 Data Storage Principles

#### 6.4.1 Store Raw Measurements, Derive Calculations

| Principle | Application |
|-----------|-------------|
| **Alcohol** | Store volume (ml) and ABV (%), not pre-calculated "standard units" which vary by country |
| **Macros** | Store grams of each nutrient; calories can be derived using Atwater factors |
| **BSL** | Store actual reading value; mmol/L vs mg/dL conversion is lossless |
| **Timestamps** | Store in UTC with millisecond precision; timezone is a display concern |

#### 6.4.2 Avoid Opaque Enumerations

| Principle | Application |
|-----------|-------------|
| **Alcohol types** | Store user-provided specific names ("Guinness", "Sauvignon Blanc") alongside category; don't force into beer/wine/spirit/mixed only |
| **Food items** | Store actual food names from user/AI, not internal IDs; presets reference by name |
| **Exercise types** | Store user-provided activity names, not a fixed list |
| **CGM sources** | Store device model and manufacturer strings, not internal enums |

#### 6.4.3 Regional and Unit Independence

| Data Type | Storage Format | Display Conversion |
|-----------|----------------|-------------------|
| **Blood glucose** | mmol/L (primary) | mg/dL = mmol/L × 18.0182 |
| **Alcohol units** | Pure alcohol grams | AU standard (10g), UK (8g), US (14g) configurable |
| **Weight** | Kilograms | Pounds = kg × 2.20462 |
| **Volume** | Millilitres | Fluid ounces = ml × 0.033814 |
| **Dates** | ISO 8601 UTC | Localised display per user preference |

#### 6.4.4 Interoperability Standards

Where applicable, align with existing health data standards for future interoperability:

| Standard | Applicability |
|----------|---------------|
| **FHIR (HL7)** | Structure for clinical data exchange with healthcare providers |
| **IEEE 11073** | Personal health device data formats |
| **Apple HealthKit / Google Fit** | Consumer health data schemas |
| **Open mHealth** | Standardised data point schemas |

This does not require implementing these standards now, but the data model should not preclude future mapping.

---

## 7. Learning and Transparency

### 7.1 Model Learning

The system learns from hard data it has collected:

| Requirement | Description |
|-------------|-------------|
| **Outcome tracking** | Link insulin doses to subsequent BSL readings to measure effectiveness |
| **Pattern recognition** | Identify personal responses to specific foods, times of day, activity levels |
| **Continuous refinement** | Models improve as more data accumulates |
| **No external training data** | Models are trained exclusively on the Owner's personal data |

### 7.2 Calculation Transparency

Every suggestion must be explainable on query:

| Requirement | Description |
|-------------|-------------|
| **Show your work** | Display the mathematical calculation that produced any suggestion |
| **Data source attribution** | Identify which historical records informed the calculation |
| **Factor visibility** | Show which factors were considered (current BSL, carbs, active insulin, time of day, etc.) |
| **Confidence indication** | Express certainty level based on data quality and quantity |
| **Model inspection** | Allow Owner to view learned parameters (personal carb ratios, sensitivity factors) |

### 7.3 Modelling Factors

The dose suggestion model considers multiple categories of input:

#### Current State Factors

| Factor | Description |
|--------|-------------|
| **Current BSL** | Starting blood glucose level |
| **Active insulin on board (IOB)** | Remaining effect from previous boluses |
| **Active carbs on board (COB)** | Carbs still being absorbed from recent meals |
| **Blood alcohol level** | Current alcohol in system affecting liver glucose output |
| **Time of day** | Circadian rhythm effects (dawn phenomenon, evening sensitivity) |

#### Planned Input Factors

| Factor | Description |
|--------|-------------|
| **Planned carbohydrate intake** | Grams of carbs in upcoming meal |
| **Protein content** | Delayed glucose impact (gluconeogenesis) |
| **Fat content** | Slows carb absorption, extends glucose rise |
| **Glycemic index estimate** | Speed of carb absorption |
| **Planned alcohol** | Anticipated insulin sensitivity increase |

#### Personal Profile Factors

| Factor | Description |
|--------|-------------|
| **Weight** | Body mass affects insulin sensitivity and alcohol metabolism |
| **Sex** | Affects alcohol distribution factor |
| **Age** | Metabolic rate considerations |
| **Insulin sensitivity factor** | Personal ISF (mmol/L drop per unit) |
| **Carb ratio** | Personal ICR (grams per unit) |
| **Active insulin duration** | Personal DIA (duration of insulin action) |

#### Situational Factors

| Factor | Description |
|--------|-------------|
| **Recent exercise** | Type, intensity, and duration lowers insulin requirements |
| **Stress/cortisol** | Future: wearable-derived stress indicators |

#### Historical Pattern Factors

| Factor | Description |
|--------|-------------|
| **Time-of-day patterns** | Learned sensitivity variations |
| **Food-specific responses** | Personal responses to specific meals/foods |
| **Exercise recovery patterns** | Duration of post-exercise sensitivity |
| **Alcohol response patterns** | Personal alcohol metabolism characteristics |

---

## 8. User Interface Principles

### 8.1 Tone

The interface addresses the Owner as a competent adult:
- NEVER cautionary warnings about insulin dosing or meal, alcohol or exercise logging.
- No disclaimers suggesting consultation with medical professionals
- No limitations on data access "for your safety"
- Direct, factual language in ALL messaging
- The interface is data focused and data driven.

### 8.2 Error Messages

Errors are pragmatic and actionable:
- State what failed
- Suggest resolution
- No apologetic language ("Sorry", "Oops", "We couldn't")

**Example (Good)**: "Upload failed. Supported formats: JPEG, PNG."
**Example (Bad)**: "Oops! Sorry, we couldn't process your image."

### 8.3 Localisation

- All user-facing text uses Irish English spelling (colour, behaviour, analyse, recognise)
- Units default to mmol/L for blood glucose
- Date formats follow ISO 8601 or dd/mm/yyyy convention

---

## 9. Data Types

### 9.1 Blood Sugar Reading

| Field | Description |
|-------|-------------|
| Timestamp | When the reading was taken |
| Value | BSL in mmol/L (positive number, no artificial bounds) |
| Source | How the data was captured (manual, CGM import, graph extraction) |
| Confidence | 0-1 score for extracted/estimated values |

### 9.2 Insulin Event

| Field | Description |
|-------|-------------|
| Timestamp | When insulin was administered |
| Units | Amount in whole units (1-100) |
| Type | Bolus (mealtime) or basal (long-acting) |
| Source | Manual entry or imported |

### 9.3 Meal Event

| Field | Description |
|-------|-------------|
| Timestamp | When the meal was consumed |
| Items | List of food items with individual macros |
| Total Carbs | Aggregate carbohydrates in grams |
| Total Protein | Aggregate protein in grams |
| Total Fat | Aggregate fat in grams |
| Total Calories | Aggregate energy in kcal |
| Source | Manual, AI image, label scan, or preset |
| Image URL | Optional photo reference |

### 9.4 Alcohol Event

Alcohol is recorded as a distinct event type (not embedded in meals) to support:
- Drinking without eating
- Multiple drinks over time
- Precise timing for metabolism modelling
- Independent analysis and export

| Field | Description |
|-------|-------------|
| Timestamp | When consumption began |
| Volume (ml) | Actual volume consumed in millilitres |
| ABV (%) | Alcohol by volume percentage |
| Alcohol Grams | Calculated pure alcohol content (volume × ABV × 0.789) |
| Category | High-level type (beer, wine, spirit, mixed, other) |
| Specific Type | User-defined string (e.g., "IPA", "Pinot Noir", "Whiskey Sour") |
| Standard Units | Calculated units using configured regional standard |
| Notes | Optional free-text notes |

**Data Portability Note**: The system stores the raw measurement (volume and ABV) rather than derived units, allowing recalculation against any regional standard drink definition.

### 9.5 Exercise Event

| Field | Description |
|-------|-------------|
| Timestamp | When exercise started |
| Duration | Length in minutes |
| Intensity | Low, moderate, or high |
| Type | Optional exercise description |
| Notes | Optional free-text notes |

### 9.6 Preset

| Field | Description |
|-------|-------------|
| Name | User-defined name |
| Category | Meal, snack, insulin, exercise, or drink |
| Items | List of food items with macros (for meal/snack presets) |
| Totals | Aggregate macro values (for meal/snack presets) |
| Units | Insulin units (for insulin presets) |
| Insulin Type | Bolus or basal (for insulin presets) |
| Exercise Type | Activity name, e.g., swim, cycle, run (for exercise presets) |
| Duration | Default duration in minutes (for exercise presets) |
| Intensity | Default intensity level (for exercise presets) |
| Volume | Drink volume in ml (for drink presets) |
| ABV | Alcohol by volume percentage (for drink presets) |
| Carbs | Carbohydrate content in grams (for drink presets) |
| Drink Type | Category and specific type, e.g., "beer/Guinness", "wine/Malbec", "spirit/whiskey" (for drink presets) |
| Last Used | Timestamp for surfacing recent presets |

### 9.7 User Profile

The user profile contains personal data used in calculations. All fields support versioning with effective dates.

#### Biometric Data

| Field | Type | Description |
|-------|------|-------------|
| Date of Birth | Date | Used to derive age; stored as ISO date |
| Sex | male/female/other | Affects alcohol r-factor (0.68/0.55/0.60) |
| Weight | number (kg) | Body mass for calculations |
| Height | number (cm) | For BMI and body surface area |

#### Diabetes Parameters

| Field | Type | Description |
|-------|------|-------------|
| Insulin Sensitivity Factor | number (mmol/L) | BSL drop per unit; may have time-of-day schedule |
| Carb Ratio | number (g/unit) | Grams of carbs covered by 1 unit; may vary by meal |
| Target BSL | number (mmol/L) | Correction target |
| Active Insulin Duration | number (hours) | Typically 3-5 hours |
| Diagnosis Date | Date (optional) | Duration of T1D |

#### Profile Versioning

Each profile field is stored with:
- Value
- Effective from date
- Effective to date (null = current)
- Source (manual, imported, calculated)

This enables:
- Historical calculations using values in effect at that time
- Trend analysis (weight over time, ISF changes)
- Complete export of profile history

---

## 10. Success Metrics

### 10.1 Core Capability Indicators

| Metric | Target |
|--------|--------|
| AI food recognition accuracy | Camera captures return usable macro estimates for ≥70% of meals and drinks |
| AI macro acceptance rate | ≥60% of AI suggestions accepted without major modification |
| Food logging friction | ≤15 seconds from photo to saved meal record |
| Meal logging rate | ≥70% of meals captured |

### 10.2 Data Quality Indicators

| Metric | Target |
|--------|--------|
| Duplicate detection accuracy | ≥95% of true duplicates flagged |
| Data export completeness | 100% of stored data included in exports |
| Insulin logging consistency | ≥90% of actual doses logged |

### 10.3 Model Effectiveness (Future)

| Metric | Target |
|--------|--------|
| BSL prediction accuracy (2h ahead) | Within ±1.5 mmol/L for 70% of predictions |
| Dose suggestion acceptance rate | ≥50% of suggestions used as-is or with minor adjustment |

---

## 11. Out of Scope

The following are explicitly not part of the current product scope:

- Multi-user or household accounts
- Data sharing or downloading from the front end or ui (future scope)
- Medical professional dashboard or portal
- Integration with insulin pumps
- Automated insulin delivery control
- Compliance or regulatory certifications
- Prescription or medication management beyond insulin

---

## 12. Future Considerations

- **Personal Encryption**: User-controlled encryption keys for data at rest
- **Extended Biometrics**: Blood pressure, weight, heart rate variability

---

## Revision History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2026-02-03 | 1.0 | Claude | Initial PRD based on specification, architecture, and constitution |
| 2026-02-03 | 1.1 | Claude | Added data extensibility section, learning/transparency requirements, alcohol as first-class event type, and data portability principles |
| 2026-02-03 | 1.2 | Claude | Added comprehensive user profile (age, sex, weight, height), personal profile management requirements (FR-45-49), expanded modelling factors to include all biometric inputs, profile versioning requirements |
| 2026-02-03 | 1.3 | Ronan | Refocused success metrics on AI food recognition as primary early indicator; removed temporary flags (illness/pregnancy) to simplify model; changed "biological sex" to "sex"; removed body fat %; expanded presets to include insulin doses and exercises (swim, cycle, etc.) |
| 2026-02-03 | 1.4 | Ronan | Added AI drink recognition via photo (FR-16 to FR-19, section 3.2.1); drink presets (FR-36) |
| 2026-02-03 | 1.4 | Ronan | fixed AI Slop |
