# MeData Development Plan

> **Source of Truth**: [requirements.md](./requirements.md)
> **Last Updated**: 2026-01-20
> **Current Branch**: `dev-0` (integration staging)

---

## Overview

MeData is a **mobile-first SPA** for tracking physiological data (meals, insulin, blood sugar) with AI-powered food recognition and eventual regression modeling for insulin dose prediction.

### Key Design Decisions

| Decision         | Choice                      | Rationale                                 |
| ---------------- | --------------------------- | ----------------------------------------- |
| Framework        | SvelteKit + adapter-vercel  | SPA with offline capability, modern DX    |
| Data Storage     | IndexedDB (via Dexie.js)    | Structured offline storage, good capacity |
| Data Abstraction | Repository Pattern          | Clean separation, enables future backends |
| API Keys         | User-provided, localStorage | Simplest model, no backend needed         |
| UI Approach      | Mobile-first, responsive    | Primary users on phones                   |

---

## Architecture

### Data Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                        Svelte UI Layer                          │
│  (Components, Pages, Stores)                                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Service Layer                              │
│  (EventService, SettingsService, + Workstream Services)         │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                   Repository Layer (Interfaces)                 │
│  IEventRepository, ISettingsRepository, IPresetRepository       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                 Repository Implementations                      │
│  IndexedDBEventRepository, LocalStorageSettingsRepository       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Storage Layer                              │
│  IndexedDB (Dexie.js)  │  LocalStorage  │  Future: REST API     │
└─────────────────────────────────────────────────────────────────┘
```

---

## Parallel Workstream Architecture

The project is structured into **4 independent workstreams** that can be developed concurrently by different team members. Each workstream has:

- Its own feature branch
- Dedicated file ownership (no overlapping files)
- Independent merge capability
- Shared interfaces for integration

```
main (stable releases)
  │
  └── dev-0 (integration staging)
        │
        ├── dev-1 ← CGM graph image capture
        ├── dev-2 ← AI-powered food recognition
        ├── dev-3 ← Local food volume estimation
        └── dev-4 ← BSL data import
```

### Integration Strategy

1. **Feature branches** merge into `dev-0` for integration testing
2. **dev-0** merges into `main` for stable releases
3. All workstreams share common interfaces defined in `src/lib/types/`
4. Integration tests run on `dev-0` before main merge

---

## Shared Infrastructure (Phase 0)

**Status**: ✅ COMPLETE (Phase 1 & 2 baseline)

Before workstreams begin, the following shared infrastructure must be in place:

### Completed Foundation

- [x] Project scaffolding (SvelteKit, TypeScript, Tailwind)
- [x] Data layer with Repository Pattern
- [x] Core TypeScript types and interfaces
- [x] Basic app shell with mobile navigation
- [x] Settings page with API key management
- [x] Event logging (insulin, meal basics)
- [x] History view with filtering
- [x] PWA manifest and service worker

### Shared Types & Interfaces

All workstreams use these common interfaces:

```typescript
// src/lib/types/events.ts - SHARED (do not modify without coordination)
interface PhysiologicalEvent {
  id: string;
  timestamp: Date;
  eventType: 'meal' | 'insulin' | 'bsl' | 'exercise';
  value: number;
  metadata: Record<string, any>;
  createdAt: Date;
  updatedAt: Date;
  synced?: boolean;
}

// Meal metadata structure (extended by workstreams A & C)
interface MealMetadata {
  calories?: number;
  protein?: number;
  fat?: number;
  carbs?: number; // Stored in value field
  description?: string;
  photoUrl?: string;
  items?: MealItem[];
  source?: 'manual' | 'ai' | 'local-estimation'; // NEW: Identifies data source
  confidence?: number; // NEW: Estimation confidence 0-1
  corrections?: CorrectionRecord[]; // NEW: User correction history
}

// BSL metadata structure (used by workstreams B & D)
interface BSLMetadata {
  unit: 'mmol/L' | 'mg/dL';
  source?: 'manual' | 'cgm-image' | 'csv-import' | 'api'; // NEW
  device?: string; // NEW: e.g., "Freestyle Libre 3"
}
```

---

## Workstream A: AI-Powered Food Recognition

**Branch**: `dev-1`
**Owner**: TBD
**Dependencies**: Phase 0 complete
**Priority**: HIGH - Core differentiating feature

### Objectives

- Photo-based meal recognition using cloud Vision APIs
- User correction capture for iterative learning
- Nutrition label scanning (OCR)
- Visual annotation with bounding boxes

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Food Recognition Pipeline                    │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
┌───────────────────────────┐ ┌───────────────────────────┐
│      Cloud Vision API     │ │     User Corrections      │
│      (Primary)            │ │     (Iterative Learning)  │
├───────────────────────────┤ ├───────────────────────────┤
│ • OpenAI Vision (GPT-4V)  │ │ • Store original image    │
│ • Google Gemini Pro       │ │ • Store AI predictions    │
│ • Anthropic Claude        │ │ • Capture user edits      │
│ • Ollama + LLaVA (local)  │ │ • Build correction history│
└───────────────────────────┘ └───────────────────────────┘
```

### File Ownership

```
src/lib/
├── services/
│   └── ai/                          # OWNED BY WORKSTREAM A
│       ├── IFoodRecognitionService.ts
│       ├── OpenAIFoodService.ts
│       ├── GeminiFoodService.ts
│       ├── ClaudeFoodService.ts
│       ├── OllamaFoodService.ts
│       ├── FoodServiceFactory.ts
│       └── prompts/
│           └── foodRecognition.ts
├── components/
│   └── ai/                          # OWNED BY WORKSTREAM A
│       ├── CameraCapture.svelte
│       ├── PhotoPreview.svelte
│       ├── RecognitionLoading.svelte
│       ├── FoodRecognitionResult.svelte
│       ├── AnnotatedFoodImage.svelte
│       ├── FoodItemEditor.svelte
│       ├── NutritionLabelScanner.svelte
│       └── MacroConfirmation.svelte
├── types/
│   └── ai.ts                        # OWNED BY WORKSTREAM A
└── utils/
    └── imageProcessing.ts           # OWNED BY WORKSTREAM A
```

### Routes

```
src/routes/
└── log/
    └── meal/
        ├── photo/                   # OWNED BY WORKSTREAM A
        │   └── +page.svelte         # AI photo recognition flow
        └── label/                   # OWNED BY WORKSTREAM A
            └── +page.svelte         # Nutrition label scanning
```

### Tasks

#### A.1 Cloud AI Service Layer

- [ ] Define `IFoodRecognitionService` interface
- [ ] Implement OpenAI Vision provider (GPT-4V)
- [ ] Implement Gemini Pro Vision provider
- [ ] Implement Claude Vision provider
- [ ] Implement Ollama/LLaVA provider (self-hosted)
- [ ] Create provider factory with fallback chain
- [ ] Structured prompt engineering for consistent output

#### A.2 Camera & Image Processing

- [ ] Camera capture component (`getUserMedia`)
- [ ] Image compression (WebP, quality 80)
- [ ] EXIF orientation handling
- [ ] Gallery selection fallback

#### A.3 Recognition UX Flow

- [ ] Photo capture screen
- [ ] Loading state with progress
- [ ] Results display with bounding boxes
- [ ] Per-item macro editing
- [ ] Confidence indicators
- [ ] Save with source attribution

#### A.4 Iterative Learning Pipeline

- [ ] Store original predictions
- [ ] Capture user corrections
- [ ] Track accuracy over time
- [ ] Prompt enhancement from history

#### A.5 Nutrition Label Scanner

- [ ] OCR via cloud vision API
- [ ] Australian nutrition panel format
- [ ] Serving size calculations

### Acceptance Criteria

- [ ] Photo capture works on iOS Safari and Android Chrome
- [ ] Cloud AI returns macro estimates within 10 seconds
- [ ] User can adjust AI estimates before saving
- [ ] User corrections stored with `source: 'ai'`
- [ ] Graceful fallback to manual entry when API unavailable

---

## Workstream B: CGM Graph Image Capture

**Branch**: `dev-2`
**Owner**: TBD
**Dependencies**: Phase 0 complete
**Priority**: HIGH - Enables BSL data without manual entry

### Objectives

- Capture screenshots from Freestyle Libre, Dexcom, and similar CGM apps
- Extract BSL time-series data from graph images
- ML-assisted curve extraction (initially), moving to local algorithms
- Handle standard CGM graph formats efficiently

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                   CGM Graph Processing Pipeline                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
┌───────────────────────────┐ ┌───────────────────────────┐
│   Image Preprocessing     │ │    Curve Extraction       │
├───────────────────────────┤ ├───────────────────────────┤
│ • Graph region detection  │ │ • ML-assisted (Phase 1)   │
│ • Axis label OCR          │ │ • Template matching       │
│ • Grid line detection     │ │ • Local algorithms (Goal) │
│ • Color filtering         │ │ • Edge detection          │
└───────────────────────────┘ └───────────────────────────┘
                    │                   │
                    └─────────┬─────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Time-Series Generation                        │
│  • Map pixels to BSL values using detected axis ranges          │
│  • Generate 5-minute interval data points                        │
│  • Validate against expected CGM ranges                          │
└─────────────────────────────────────────────────────────────────┘
```

### CGM App Formats

| App             | Graph Style           | Time Range       | Y-Axis       |
| --------------- | --------------------- | ---------------- | ------------ |
| Freestyle Libre | Yellow line, white bg | 8h, 12h, 24h     | 2-15 mmol/L  |
| Dexcom G6/G7    | Blue line, dark bg    | 3h, 6h, 12h, 24h | 40-400 mg/dL |
| Medtronic       | Blue gradient         | Variable         | Variable     |

### File Ownership

```
src/lib/
├── services/
│   └── cgm/                         # OWNED BY WORKSTREAM B
│       ├── ICGMImageService.ts
│       ├── CGMImageProcessor.ts
│       ├── LibreGraphParser.ts
│       ├── DexcomGraphParser.ts
│       ├── CurveExtractor.ts
│       └── AxisDetector.ts
├── components/
│   └── cgm/                         # OWNED BY WORKSTREAM B
│       ├── CGMImageCapture.svelte
│       ├── GraphRegionSelector.svelte
│       ├── AxisRangeInput.svelte
│       ├── ExtractionPreview.svelte
│       └── TimeSeriesConfirm.svelte
├── types/
│   └── cgm.ts                       # OWNED BY WORKSTREAM B
└── utils/
    └── curveExtraction.ts           # OWNED BY WORKSTREAM B
```

### Routes

```
src/routes/
└── import/
    └── cgm/                         # OWNED BY WORKSTREAM B
        └── +page.svelte             # CGM graph image import
```

### Tasks

#### B.1 Image Preprocessing

- [ ] Graph region auto-detection
- [ ] Manual region selection fallback
- [ ] Axis label OCR (time and BSL ranges)
- [ ] Grid line detection for calibration

#### B.2 Curve Extraction - ML Phase

- [ ] Cloud vision API for initial extraction
- [ ] Prompt engineering for CGM graphs
- [ ] Structured output (time-series JSON)

#### B.3 Curve Extraction - Local Algorithms

- [ ] Color-based line detection (filter by CGM line color)
- [ ] Edge detection for curve tracing
- [ ] Template matching for known CGM formats
- [ ] Canvas-based pixel analysis

#### B.4 Time-Series Generation

- [ ] Pixel-to-value mapping
- [ ] 5-minute interval resampling
- [ ] Outlier detection and smoothing
- [ ] Range validation (2-25 mmol/L / 36-450 mg/dL)

#### B.5 User Confirmation Flow

- [ ] Overlay extracted curve on original image
- [ ] Allow manual point adjustment
- [ ] Show generated time-series preview
- [ ] Batch import into event log

### Acceptance Criteria

- [ ] Libre graph screenshots extract ≥90% of data points correctly
- [ ] Dexcom graph screenshots supported
- [ ] User can adjust axis ranges if auto-detection fails
- [ ] Extracted data imports as BSL events with `source: 'cgm-image'`
- [ ] Local extraction works without API (Phase 2 goal)

---

## Workstream C: Local Food Volume Estimation

**Branch**: `dev-3`
**Owner**: TBD
**Dependencies**: Phase 0 complete
**Priority**: MEDIUM - Privacy-first alternative to cloud AI

### Objectives

- Non-AI food volume estimation using reference objects
- Browser/device-local processing (no cloud calls)
- Reference card method (credit card = 85.6mm × 53.98mm)
- Iterative estimation engine that improves over time

### Research References

- [GoCARB System](https://www.jmir.org/2016/5/e101/): Uses reference card for volume estimation, achieved 26.9% MAE
- 3D reconstruction from single image with known reference size
- Depth estimation using monocular cues

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                 Local Volume Estimation Pipeline                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                    ┌─────────┴─────────┐
                    ▼                   ▼
┌───────────────────────────┐ ┌───────────────────────────┐
│   Reference Detection     │ │    Volume Estimation      │
├───────────────────────────┤ ├───────────────────────────┤
│ • Card edge detection     │ │ • Pixel-to-mm scaling     │
│ • Perspective correction  │ │ • Food region segmentation│
│ • Scale factor calc       │ │ • Height estimation       │
│ • Coin detection (alt)    │ │ • Volume calculation      │
└───────────────────────────┘ └───────────────────────────┘
                    │                   │
                    └─────────┬─────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Macro Lookup & Estimation                     │
│  • Food type selection (user-assisted)                          │
│  • USDA FNDDS density lookup                                    │
│  • Volume → weight → macros conversion                          │
│  • User correction feedback loop                                │
└─────────────────────────────────────────────────────────────────┘
```

### File Ownership

```
src/lib/
├── services/
│   └── local-estimation/            # OWNED BY WORKSTREAM C
│       ├── IVolumeEstimationService.ts
│       ├── ReferenceDetector.ts
│       ├── VolumeCalculator.ts
│       ├── FoodDensityLookup.ts
│       └── EstimationEngine.ts
├── components/
│   └── local-estimation/            # OWNED BY WORKSTREAM C
│       ├── ReferenceCardGuide.svelte
│       ├── FoodRegionSelector.svelte
│       ├── VolumePreview.svelte
│       ├── FoodTypeSelector.svelte
│       └── EstimationResult.svelte
├── data/
│   └── food-density.ts              # OWNED BY WORKSTREAM C (USDA subset)
├── types/
│   └── local-estimation.ts          # OWNED BY WORKSTREAM C
└── utils/
    └── volumeCalculation.ts         # OWNED BY WORKSTREAM C
```

### Routes

```
src/routes/
└── log/
    └── meal/
        └── estimate/                # OWNED BY WORKSTREAM C
            └── +page.svelte         # Local volume estimation flow
```

### Tasks

#### C.1 Reference Object Detection

- [ ] Credit card edge detection (Canvas API)
- [ ] Perspective correction (homography)
- [ ] Scale factor calculation (pixels/mm)
- [ ] Alternative: coin detection (known diameters)
- [ ] Guide overlay for card placement

#### C.2 Food Region Segmentation

- [ ] User-assisted region selection (tap/draw)
- [ ] Color-based foreground extraction
- [ ] Boundary refinement
- [ ] Multiple food regions support

#### C.3 Volume Estimation

- [ ] 2D area calculation from segmentation
- [ ] Height estimation heuristics
- [ ] Shape templates (bowl, plate, pile)
- [ ] Volume calculation with uncertainty bounds

#### C.4 Macro Lookup

- [ ] USDA FNDDS food density dataset (subset)
- [ ] Food type selector with search
- [ ] Volume → weight → macros conversion
- [ ] Confidence scoring

#### C.5 Estimation Engine Improvement

- [ ] Store estimations with user corrections
- [ ] Track estimation accuracy per food type
- [ ] Calibration factors learned from corrections
- [ ] Export/import calibration data

### Acceptance Criteria

- [ ] Reference card detected in >80% of well-lit photos
- [ ] Volume estimation within 30% of actual (initially)
- [ ] Works entirely in-browser (no network calls)
- [ ] User corrections improve future estimates
- [ ] Saved with `source: 'local-estimation'`

---

## Workstream D: BSL Data Import

**Branch**: `dev-4`
**Owner**: TBD
**Dependencies**: Phase 0 complete
**Priority**: HIGH - Essential for regression modeling

### Objectives

- CSV import from Freestyle Libre, Dexcom exports
- Manual BSL entry (finger prick, more accurate than CGM)
- Historical data bulk import
- Time zone handling and duplicate detection

### Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    BSL Data Import Pipeline                      │
└─────────────────────────────────────────────────────────────────┘
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│   CSV Import    │ │  Manual Entry   │ │  API Import     │
├─────────────────┤ ├─────────────────┤ ├─────────────────┤
│ • Libre CSV     │ │ • Single reading│ │ • Future: Direct│
│ • Dexcom CSV    │ │ • Finger prick  │ │   CGM API       │
│ • Generic CSV   │ │ • Lab results   │ │                 │
└─────────────────┘ └─────────────────┘ └─────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Data Normalization                            │
│  • Timestamp parsing (multiple formats)                          │
│  • Unit conversion (mmol/L ↔ mg/dL)                             │
│  • Duplicate detection                                           │
│  • Time zone handling                                            │
└─────────────────────────────────────────────────────────────────┘
```

### File Ownership

```
src/lib/
├── services/
│   └── import/                      # OWNED BY WORKSTREAM D
│       ├── IImportService.ts
│       ├── CSVParser.ts
│       ├── LibreCSVParser.ts
│       ├── DexcomCSVParser.ts
│       ├── GenericCSVParser.ts
│       └── DuplicateDetector.ts
├── components/
│   └── import/                      # OWNED BY WORKSTREAM D
│       ├── CSVUpload.svelte
│       ├── ColumnMapper.svelte
│       ├── ImportPreview.svelte
│       ├── DuplicateResolver.svelte
│       └── ImportProgress.svelte
├── components/
│   └── bsl/                         # OWNED BY WORKSTREAM D
│       ├── BSLQuickLog.svelte
│       └── BSLHistoryInput.svelte
├── types/
│   └── import.ts                    # OWNED BY WORKSTREAM D
└── utils/
    ├── csvHelpers.ts                # OWNED BY WORKSTREAM D
    └── dateNormalization.ts         # OWNED BY WORKSTREAM D
```

### Routes

```
src/routes/
├── log/
│   └── bsl/                         # OWNED BY WORKSTREAM D
│       └── +page.svelte             # Manual BSL entry
└── import/
    └── bsl/                         # OWNED BY WORKSTREAM D
        └── +page.svelte             # CSV import wizard
```

### CSV Format Support

**Freestyle Libre Export**:

```csv
Device,Serial Number,Device Timestamp,Record Type,Historic Glucose mmol/L,...
FreeStyle Libre 3,ABC123,01-15-2026 08:30,0,5.6,...
```

**Dexcom Export**:

```csv
Index,Timestamp (YYYY-MM-DDThh:mm:ss),Event Type,Event Subtype,Glucose Value (mg/dL),...
1,2026-01-15T08:30:00,EGV,,112,...
```

### Tasks

#### D.1 Manual BSL Entry Page

- [ ] BSL logging page (`/log/bsl`)
- [ ] Stepper-style input (like insulin)
- [ ] Unit toggle (mmol/L ↔ mg/dL)
- [ ] Source indicator (CGM vs finger prick)
- [ ] Historical timestamp entry

#### D.2 CSV Parser Framework

- [ ] Generic CSV parsing with column detection
- [ ] Libre CSV format parser
- [ ] Dexcom CSV format parser
- [ ] Auto-detect format from file header

#### D.3 Import Wizard UI

- [ ] File upload component
- [ ] Format detection and confirmation
- [ ] Column mapping for generic CSV
- [ ] Import preview with sample rows
- [ ] Progress indicator for large files

#### D.4 Data Normalization

- [ ] Multiple timestamp format parsing
- [ ] Unit conversion (mg/dL × 0.0555 = mmol/L)
- [ ] Time zone handling
- [ ] Outlier flagging (values outside 2-30 mmol/L)

#### D.5 Duplicate Detection

- [ ] Exact match detection (same timestamp + value)
- [ ] Near-duplicate detection (within 5 min window)
- [ ] Merge strategies (keep newer, keep both, skip)
- [ ] User confirmation for conflicts

#### D.6 Export Functionality

- [ ] JSON backup export
- [ ] CSV export with date range
- [ ] Include source metadata

### Acceptance Criteria

- [ ] Libre CSV imports correctly (tested with sample data)
- [ ] Dexcom CSV imports correctly (tested with sample data)
- [ ] Manual BSL entry in ≤3 taps
- [ ] Duplicates detected and handled gracefully
- [ ] Imported data has `source: 'csv-import'` metadata
- [ ] Finger prick entries marked as higher accuracy

---

## Integration Points

### Shared Meal Entry Page

The `/log/meal/+page.svelte` page serves as the entry point, with options:

- **Manual entry** (existing)
- **AI Photo** → Workstream A route
- **Estimate** → Workstream C route

```svelte
<!-- Integration in /log/meal/+page.svelte -->
<div class="grid grid-cols-3 gap-2">
  <a href="/log/meal/photo">📷 AI Photo</a>
  <a href="/log/meal/estimate">📐 Estimate</a>
  <button>✏️ Manual</button>
</div>
```

### Shared BSL Entry Points

BSL data can come from multiple sources:

- **Manual** → Workstream D `/log/bsl`
- **CSV Import** → Workstream D `/import/bsl`
- **Graph Image** → Workstream B `/import/cgm`

### Event Metadata Source Tracking

All workstreams must set the `source` field in event metadata:

| Workstream | Source Value         | Description                    |
| ---------- | -------------------- | ------------------------------ |
| Manual     | `'manual'`           | User typed values              |
| A          | `'ai'`               | Cloud AI recognition           |
| B          | `'cgm-image'`        | Extracted from graph image     |
| C          | `'local-estimation'` | Local volume estimation        |
| D          | `'csv-import'`       | Imported from CSV file         |
| D          | `'api'`              | Future: direct API integration |

---

## Git Workflow & Merge Strategy

### Branch Naming Convention

```
dev-0              # Integration staging branch
dev-1              # Workstream A: AI-Powered Food Recognition
dev-2              # Workstream B: CGM Graph Image Capture
dev-3              # Workstream C: Local Food Volume Estimation
dev-4              # Workstream D: BSL Data Import
dev-n              # Additional workstreams as needed
```

### Development Flow

```bash
# Start new workstream (from dev-0)
git checkout dev-0
git pull origin dev-0
git checkout -b dev-1

# Work on features
git commit -m "feat(food-ai): add OpenAI vision service"

# Keep in sync with dev-0
git fetch origin
git rebase origin/dev-0

# Create PR to dev-0 (not main)
gh pr create --base dev-0 --title "feat: AI food recognition"
```

### Merge Order

Workstreams can merge in any order since they own distinct files:

1. PR from `dev-n` → `dev-0` (integration testing)
2. After integration tests pass on `dev-0`:
3. PR from `dev-0` → `main` (stable release)

### Conflict Prevention Rules

1. **File ownership is strict** - only modify files in your workstream's directories
2. **Extend shared types** - add optional fields, don't modify existing
3. **Use barrel exports** - `index.ts` files should only add, not remove
4. **Coordinate type changes** - if you need to modify shared types, discuss first

### Integration Testing on dev-0

Before merging to main:

- [ ] All workstream features work independently
- [ ] Manual + AI + Estimate meal entry all work
- [ ] BSL from manual + CSV + graph image all import correctly
- [ ] Event history shows source correctly
- [ ] No console errors in production build

---

## File Ownership Matrix

| Directory/File                         | Owner        | Can Extend By      |
| -------------------------------------- | ------------ | ------------------ |
| `src/lib/types/events.ts`              | Shared       | All (add optional) |
| `src/lib/types/settings.ts`            | Shared       | All (add optional) |
| `src/lib/types/ai.ts`                  | Workstream A | -                  |
| `src/lib/types/cgm.ts`                 | Workstream B | -                  |
| `src/lib/types/local-estimation.ts`    | Workstream C | -                  |
| `src/lib/types/import.ts`              | Workstream D | -                  |
| `src/lib/services/ai/`                 | Workstream A | -                  |
| `src/lib/services/cgm/`                | Workstream B | -                  |
| `src/lib/services/local-estimation/`   | Workstream C | -                  |
| `src/lib/services/import/`             | Workstream D | -                  |
| `src/lib/components/ai/`               | Workstream A | -                  |
| `src/lib/components/cgm/`              | Workstream B | -                  |
| `src/lib/components/local-estimation/` | Workstream C | -                  |
| `src/lib/components/import/`           | Workstream D | -                  |
| `src/lib/components/bsl/`              | Workstream D | -                  |
| `src/routes/log/meal/photo/`           | Workstream A | -                  |
| `src/routes/log/meal/label/`           | Workstream A | -                  |
| `src/routes/log/meal/estimate/`        | Workstream C | -                  |
| `src/routes/log/bsl/`                  | Workstream D | -                  |
| `src/routes/import/cgm/`               | Workstream B | -                  |
| `src/routes/import/bsl/`               | Workstream D | -                  |

---

## Testing Strategy

| Layer       | Approach                            | Owner   |
| ----------- | ----------------------------------- | ------- |
| Unit tests  | Vitest for services and utilities   | Each WS |
| Component   | Svelte Testing Library              | Each WS |
| Integration | Playwright on dev-0                 | Shared  |
| E2E         | Critical flows (meal, BSL, history) | Shared  |

_Note: Testing frameworks are out of scope per requirements, but file structure supports future addition._

---

## Success Metrics

### Workstream A (AI Food)

- Photo recognition accuracy vs user corrections (track over time)
- API response time < 10 seconds
- User correction rate (lower = better AI)

### Workstream B (CGM Capture)

- Graph extraction accuracy (vs manual verification)
- Percentage of graphs successfully processed
- Time to extract vs manual entry

### Workstream C (Local Estimation)

- Volume estimation accuracy (user-corrected vs original)
- Reference card detection success rate
- Estimation improvement over time (learning)

### Workstream D (BSL Import)

- CSV import success rate
- Duplicate detection accuracy
- Manual entry speed (taps to complete)

---

## Appendix: Research References

### Food Recognition

- [GoCARB: Carbohydrate Estimation by Mobile Phone (JMIR 2016)](https://www.jmir.org/2016/5/e101/)
- [Comprehensive Survey of Image-Based Food Recognition (Healthcare 2021)](https://pmc.ncbi.nlm.nih.gov/articles/PMC8700885/)

### Volume Estimation

- Reference card method: Credit card = 85.6mm × 53.98mm (ISO/IEC 7810)
- GoCARB achieved 26.9% MAE using reference card for scale

### CGM Data Formats

- [Freestyle Libre CSV Export Format](https://www.freestylelibre.com/)
- [Dexcom Clarity Export Format](https://clarity.dexcom.com/)

---

_Last updated: 2026-01-20_
_Architecture: 4 parallel workstreams with independent merge capability_
