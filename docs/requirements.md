# Requirements for MeData

These are the core system requirements and source of truth for the MeData project. The application is **web-first** with **offline-first** capability (works without internet, syncs later) or browser-based local storage (localStorage/IndexedDB), depending on the design pattern used.

**Tech Stack**: Svelte UI, best-in-class graphing libraries.

---

## 1. Data Architecture

1.1. **Event-Log Paradigm**: Use a long-form event log structure where each row represents a single physiological or behavioral event. Fixed columns: `timestamp`, `event_type`, `value`. Flexible column: `metadata` (JSON) for secondary attributes (fats, proteins, descriptions).

1.2. **Extensibility**: The data model must be extensible. New metrics (e.g., heart rate, exercise) are added as new `event_type` entries rather than new columns. Food items and macros should be groupable and saveable as presets.

1.3. **Multi-User Ready**: While initially single-user, the data structure must allow for multi-user support in future.

---

## 2. Data Input

2.1. **Meal Entry**: Users can record meals as a point in time. Support for:
   - Photo-based entry (AI estimates macros)
   - Manual macro input
   - Preset meals (saved groupings of food items)

2.2. **Insulin Dose Entry**: Light-touch input within 3 clicks/steps:
   - Defaults to current time
   - Defaults to preferred or last-used type (bolus or basal)
   - Whole number units only (no decimals)
   - Range: 1–300 units (realistic max ~30)

2.3. **Time Adjustment**: Users can adjust timestamps on any record and edit macro values after entry.

---

## 3. Data Import/Export

3.1. **Ingestion Methods**: Backend can asynchronously load data from multiple sources:
   - Image uploads (processed by AI)
   - CSV uploads
   - Direct API integration (future)

3.2. **Backup & Restore**: Users can upload/download their data for backup or to import prior records.

3.3. **BSL Time-Series Upload**: Support upload of blood sugar level (BSL) time-series data for regression analysis.

3.3.1 **Graph interpolation**: Support upload of images of graph data, (a line across a chart) to input estimate time series data in differing formats (may need to use similar process to food macro data method)

---

## 4. Image Processing

4.1. **Food Recognition**: AI model identifies food items from photos and estimates volume/weight.

4.2. **Macro Estimation Accuracy**: AI macro estimation must be within **5% accuracy** of test data (collected from online datasets or academic research).

4.3. **Visual Annotation**: Tag food items on images (shading or bounding boxes) to show the estimation work.

4.4. **Nutrition Label Scanning**: Support photos of Australian-standard nutrition information panels. User inputs weight or servings; system extracts macro data.

---

## 5. Regression & Modeling

5.1. **Target Variable**: The regression target is **insulin dose prediction**.

5.2. **Time-Series Analysis**: Use BSL data combined with meal and insulin events, and capacity to include future metrics like exercise records (intensity, duration, or direct wearable fitness data) to build regression models.

5.3. **Decay Functions**: Model the biological half-life and compounding effects of:
   - Insulin absorption over time
   - Carbohydrate/fat breakdown and absorption rates

5.4. **Time-of-Day Effects**: Model how absorption and insulin sensitivity vary by time of day.

5.5. **Continuous Improvement**: More recorded data leads to more accurate regression predictions.

---

## 6. User Interface

6.1. **Light-Touch Design**: Prioritize minimal clicks/taps for common actions (especially insulin logging).

6.2. **Presets**: Allow users to save meal presets to avoid repeated photo uploads.

6.3. **Graphs & Visualization**: Use best-in-class graphing libraries for displaying BSL trends, meal impacts, and regression insights.

---

## 7. Integration

7.1. **AI Model Integration**: Photos are sent to an AI model (Gemini, OpenAI, Claude, etc.) for food quantification.

7.2. **API Key Configuration**: API keys can be provided either:
   - In-app (stored as session variable for local-first mode)
   - As environment variables (for cloud deployment, e.g., Azure Container Apps)

---

## 8. Authentication

8.1. **Phase 1 (Development)**: Single user, no authentication required.

8.2. **Phase 2 (Future)**: Implement 1:1 certificate, YubiKey, or FIDO authentication for secure access and potential data encryption/decryption.

---

## 9. Architecture Patterns

These patterns are recommended based on the data architecture review:

9.1. **Ingestion Strategy**: Use Incremental Loader or Change Data Capture (CDC) for continuous/sporadic data ingestion without full dataset reloads.

9.2. **Storage Layout**:
   - **Horizontal Partitioning**: Partition by timestamp (daily or weekly) for data skipping and query optimization.
   - **Vertical Partitioning**: Separate core columns (`timestamp`, `event_type`, `value`) from metadata JSON to reduce I/O for standard queries.

9.3. **Indexing & Retrieval**:
   - **Sorter Pattern**: Sort by timestamp within partitions.
   - **Bucket Pattern**: Colocate records by time-window hash for efficient 5-minute interval resampling.

9.4. **Stateful Sessionizer**: For decay function calculations, maintain state across intervals to accurately compute biological half-life effects across partitions.

9.5. **Failure Mitigations**:
   - **Late Data Detector**: Handle late-arriving events to maintain chronological integrity for regression.
   - **Compactor Pattern**: Consolidate small files from incremental ingestion to avoid file-listing overhead.
   - **Schema Compatibility Enforcer**: Validate new `event_type` entries to prevent breaking existing regression scripts.

---

## Out of Scope

1. **Multiple user management** (data structure supports future implementation)
2. **Medical advice or alerts**
3. **Backups, data security, or networking infrastructure**
4. **Testing, or building out testing frameworks**