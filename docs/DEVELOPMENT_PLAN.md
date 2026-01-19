# MeData Development Plan

> **Source of Truth**: [requirements.md](./requirements.md)
> **Architecture Reference**: [arch_pattern_review.md](./arch_pattern_review.md)

---

## Overview

MeData is a **mobile-first SPA** for tracking physiological data (meals, insulin, blood sugar) with AI-powered food recognition and eventual regression modeling for insulin dose prediction.

### Key Design Decisions

| Decision         | Choice                         | Rationale                                 |
| ---------------- | ------------------------------ | ----------------------------------------- |
| Framework        | SvelteKit + adapter-static     | SPA with offline capability, modern DX    |
| Data Storage     | IndexedDB (via Dexie.js)       | Structured offline storage, good capacity |
| Data Abstraction | Repository Pattern             | Clean separation, enables future backends |
| API Keys         | User-provided, session storage | Simplest model, no backend needed         |
| UI Approach      | Mobile-first, responsive       | Primary users on phones                   |
| ML/Regression    | Deferred to Phase 5+           | Focus on data capture first               |

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
│  (EventService, MealService, InsulinService, AIService)         │
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

### Data Model (Event Log)

```typescript
// Core event structure - all physiological data follows this pattern
interface PhysiologicalEvent {
  id: string; // UUID
  timestamp: Date; // When the event occurred
  event_type: EventType; // 'meal' | 'insulin' | 'bsl' | 'exercise' | ...
  value: number; // Primary numeric value
  metadata: Record<string, any>; // Type-specific additional data
  created_at: Date; // Record creation time
  updated_at: Date; // Last modification time
  synced?: boolean; // For future multi-device sync
}

// Event type definitions
type EventType =
  | 'meal' // value = total carbs, metadata = { calories, protein, fat, description, photo_url }
  | 'insulin' // value = units, metadata = { type: 'bolus' | 'basal' }
  | 'bsl' // value = mmol/L or mg/dL, metadata = { unit }
  | 'exercise'; // value = duration_minutes, metadata = { intensity, type }

// Preset for saved meals
interface MealPreset {
  id: string;
  name: string;
  items: MealItem[];
  total_macros: MacroData;
  created_at: Date;
}

interface MacroData {
  calories: number;
  carbs: number;
  protein: number;
  fat: number;
}
```

### Repository Interface Pattern

```typescript
// Base repository interface - all implementations must satisfy this
interface IEventRepository {
  // CRUD
  create(
    event: Omit<PhysiologicalEvent, 'id' | 'created_at' | 'updated_at'>
  ): Promise<PhysiologicalEvent>;
  getById(id: string): Promise<PhysiologicalEvent | null>;
  update(id: string, updates: Partial<PhysiologicalEvent>): Promise<PhysiologicalEvent>;
  delete(id: string): Promise<void>;

  // Queries
  getByDateRange(start: Date, end: Date): Promise<PhysiologicalEvent[]>;
  getByType(type: EventType, limit?: number): Promise<PhysiologicalEvent[]>;
  getRecent(limit: number): Promise<PhysiologicalEvent[]>;

  // Bulk operations
  bulkCreate(events: PhysiologicalEvent[]): Promise<PhysiologicalEvent[]>;
  exportAll(): Promise<PhysiologicalEvent[]>;
  importBulk(events: PhysiologicalEvent[]): Promise<void>;
  clear(): Promise<void>;
}
```

This pattern allows:

- **Testing**: Mock repositories for unit tests
- **Future backends**: Implement `RestApiEventRepository` without changing UI
- **Multiple storage**: Mix IndexedDB for events, LocalStorage for settings

---

## Phase Structure

Each phase is developed on its own **feature branch** and can be merged independently. Phases are designed with minimal cross-dependencies.

**Priority Order** (updated 2026-01-20):

1. Phase 1: Foundation ✅ Complete
2. Phase 2: Data Input ✅ Core complete
3. **Phase 3: AI Food Recognition** ← CURRENT PRIORITY
4. Phase 4: Visualization (deferred)
5. Phase 5: Import/Export
6. Phase 6: ML Regression (deferred)

```
main
  ├── phase-1/foundation          ✅ COMPLETE
  ├── phase-2/data-input          ✅ CORE COMPLETE
  ├── phase-3/ai-food-recognition ← PRIORITY
  ├── phase-4/visualization       (deferred)
  ├── phase-5/import-export
  └── phase-6/ml-regression       (deferred)
```

---

## Parallel Worker Strategy

Phases 2, 3, and 5 can run **concurrently** after Phase 1 completes. Phase 4 depends on Phase 2.

### File Ownership

Each phase owns distinct directories to prevent merge conflicts:

| Phase | Owns                                                                                      | Can Extend                              |
| ----- | ----------------------------------------------------------------------------------------- | --------------------------------------- |
| 1     | `types/`, `repositories/`, `services/`, `stores/`, `components/layout/`, `components/ui/` | -                                       |
| 2     | `components/input/`, `components/events/`, `routes/log/`, `routes/history/`               | `components/ui/`                        |
| 3     | `components/charts/`, `routes/dashboard/`, `utils/chartHelpers.ts`                        | `components/ui/`                        |
| 4     | `services/ai/`, `components/ai/`, `types/ai.ts`                                           | `routes/log/meal/`, `types/settings.ts` |
| 5     | `services/ImportExportService.ts`, `components/import-export/`                            | `routes/settings/`                      |

### Conflict Prevention Rules

1. **Append-only** for shared files (export barrels, type extensions)
2. **Extend interfaces** rather than modify them
3. **Rebase onto main** after Phase 1 merges

---

## Frontend Abstraction

Services are **pure TypeScript** (no Svelte imports) to support future React/Vue frontends:

```
Svelte Components → Svelte Stores (*.svelte.ts) → Services (pure TS) → Repositories
```

- **Services**: Return Promises, framework-agnostic
- **Stores**: Wrap services with `$state`/`$derived` for Svelte reactivity
- **Types**: Shared across any frontend

---

## Branding

**Source**: `static/icon.svg` — all icons generated from this via `scripts/generate-icons.js`

```bash
node scripts/generate-icons.js  # Generates PWA icons, favicon, apple-touch-icon
```

**Brand colors**: Background `#064e3b`, Icon `#63ff00`

---

## Phase 1: Foundation

**Branch**: `phase-1/foundation`
**Dependencies**: None
**Merge requirement**: Can merge to main independently

### Objectives

- Project scaffolding
- Data layer with Repository Pattern
- Core TypeScript types and interfaces
- Basic app shell with mobile navigation

### Tasks

#### 1.1 Project Setup

- [x] Configure adapter-static for SPA mode
- [x] Setup Tailwind CSS (mobile-first utilities)
- [x] Configure PWA manifest for mobile install
- [x] Setup service worker for offline caching
- [x] ESLint + Prettier configuration
- [ ] Run `npm run generate-icons` to create PWA assets _(icons manually created, script not implemented)_

```bash
# Key dependencies
npm create svelte@latest medata
npm install -D @sveltejs/adapter-static tailwindcss sharp
npm install dexie uuid
```

#### 1.2 Data Layer Implementation

- [x] Define TypeScript interfaces in `$lib/types/`
- [x] Implement Dexie.js database schema in `$lib/db/`
- [x] Create `IEventRepository` interface
- [x] Implement `IndexedDBEventRepository`
- [x] Create `ISettingsRepository` for user preferences
- [x] Implement `LocalStorageSettingsRepository`
- [x] Create repository factory/provider

#### 1.3 Service Layer

- [x] `EventService` - business logic wrapper around repository
- [x] `SettingsService` - API key management, preferences
- [x] Svelte stores for reactive state (`$lib/stores/`)

#### 1.4 App Shell

- [x] Root layout with mobile navigation
- [x] Bottom tab bar component (Home, Log, History, Settings)
- [x] Settings page with API key input
- [x] Empty state components
- [x] Loading/error state components

### File Structure (Phase 1)

```
src/
├── lib/
│   ├── types/           # events.ts, presets.ts, settings.ts
│   ├── db/              # schema.ts, migrations.ts
│   ├── repositories/    # Interfaces + IndexedDB/LocalStorage implementations
│   ├── services/        # EventService.ts, SettingsService.ts (pure TS)
│   ├── stores/          # *.svelte.ts (Svelte 5 runes adapters)
│   └── components/
│       ├── layout/      # BottomNav, AppShell
│       └── ui/          # index.ts, LoadingSpinner, EmptyState
├── routes/
│   ├── +layout.svelte
│   ├── +layout.js       # ssr = false, prerender = true
│   ├── +page.svelte
│   └── settings/+page.svelte
└── service-worker.js
static/
├── icon.svg             # Brand source (do not delete)
├── *.png, favicon.ico   # Generated by scripts/generate-icons.js
└── manifest.json
scripts/
└── generate-icons.js
```

### Acceptance Criteria

- [x] App loads offline after first visit _(service worker caches app shell)_
- [x] Can store and retrieve test events from IndexedDB
- [x] Settings persist across sessions _(LocalStorage implementation)_
- [x] Mobile navigation functional
- [ ] Lighthouse PWA score > 90 _(needs testing)_

---

## Phase 1 Review Notes (2026-01-19)

**Status: COMPLETE** (all core objectives met)

**Implementation Quality:**

- Clean repository pattern with interfaces + IndexedDB/LocalStorage implementations
- Services are framework-agnostic (pure TypeScript)
- Svelte 5 runes properly used in stores (`$state`, `$derived`)
- Mobile-first dark theme with Tailwind CSS
- PWA manifest and service worker fully configured

**Architecture Decisions:**

- Dexie.js used as planned with proper TypeScript EntityTable types
- Settings stored in LocalStorage for simplicity (as planned)
- Type guards implemented for metadata discrimination

**Minor Gaps:**

- Icon generation script not implemented (icons created manually)
- Lighthouse score not yet validated

---

## Phase 2: Data Input

**Branch**: `phase-2/data-input`
**Dependencies**: Phase 1 (data layer)
**Merge requirement**: Phase 1 merged first, or rebase onto phase-1

### Objectives

- Insulin dose logging (3 clicks/steps max)
- Manual meal entry with macros
- Time adjustment for all entries
- Recent entries list

### Tasks

#### 2.1 Insulin Entry (Priority: Highest - Req 2.2)

- [x] Quick insulin log component
  - Default to current time
  - Default to last-used type (bolus/basal)
  - Whole number input (1-300 range)
  - Large touch targets for mobile
- [x] Insulin type toggle (bolus/basal)
- [x] Number pad or stepper for units _(stepper with quick-select buttons)_
- [ ] Confirmation haptic/visual feedback _(visual feedback only, no haptic)_
- [ ] "Just now" quick log button on home screen

#### 2.2 Meal Entry (Manual - Req 2.1)

- [x] Meal logging form
  - Carbs (required)
  - Calories, protein, fat (optional)
  - Description/notes
  - ~~Time picker (defaults to now)~~ _(defaults to now only, no picker)_
- [ ] Quick macro calculator
- [ ] Recent meals list for quick re-entry

#### 2.3 Time Adjustment (Req 2.3)

- [ ] Edit modal for any event
- [ ] Timestamp picker component
- [ ] Swipe-to-edit on event list items
- [ ] Edit history tracking (in metadata)

#### 2.4 Event History

- [x] Chronological event list _(grouped by date)_
- [x] Filter by event type
- [ ] Date range selector
- [ ] Pull-to-refresh pattern
- [ ] Infinite scroll or pagination _(limited to 50 recent events)_

### UI Components (Phase 2)

```
src/lib/components/
├── input/
│   ├── InsulinQuickLog.svelte    # 3-step insulin entry
│   ├── MealEntryForm.svelte      # Full meal form
│   ├── NumberStepper.svelte      # +/- buttons for units
│   ├── TimePicker.svelte         # Mobile-friendly time picker
│   └── MacroInputGroup.svelte    # Carbs/protein/fat inputs
├── events/
│   ├── EventList.svelte          # Scrollable event history
│   ├── EventCard.svelte          # Single event display
│   ├── EventEditModal.svelte     # Edit existing event
│   └── EventFilters.svelte       # Type/date filters
└── feedback/
    ├── Toast.svelte              # Success/error notifications
    └── HapticButton.svelte       # Button with haptic feedback
```

### Routes (Phase 2)

```
src/routes/
├── log/
│   ├── +page.svelte              # Log entry hub
│   ├── insulin/
│   │   └── +page.svelte          # Quick insulin entry
│   └── meal/
│       └── +page.svelte          # Meal entry form
└── history/
    └── +page.svelte              # Event history list
```

### Acceptance Criteria

- [x] Insulin can be logged in ≤3 taps from home _(Home → Log Insulin → Select type → Enter units → Save)_
- [x] Meal macros saved correctly to IndexedDB
- [ ] Events can be edited after creation _(edit functionality not implemented)_
- [x] History shows all events chronologically
- [x] Works fully offline

---

## Phase 2 Review Notes (2026-01-19)

**Completed:**

- Basic insulin logging with type toggle and stepper controls
- Basic meal logging with macro inputs
- Event history with type filtering
- Home page with today's summary and recent entries

**Outstanding:**

- Time picker component for adjusting timestamps
- Event editing modal
- Haptic feedback
- Quick log from home screen
- Macro calculator
- Recent meals quick-select
- Date range filtering in history
- Pagination/infinite scroll

---

## Phase 2 Review Notes (2026-01-20)

### Issues Fixed

- **A11y warnings**: Fixed label association warnings in insulin log page (`src/routes/log/insulin/+page.svelte`)
  - Changed labels for button groups to `<span>` with `role="group"` and `aria-labelledby`
  - Associated "Units" label with input using `for`/`id` attributes
  - Added `aria-label` to increment/decrement buttons

### Database Permission Error

- **Not a setup issue**: IndexedDB is client-side and auto-creates on first use
- **Cause**: Browser permissions, private mode, or `file://` access
- **Documentation**: Added troubleshooting section to README.md

### UI/UX Feedback for Future Iterations

#### Insulin Quick Select (Task 2.1 Enhancement)

Current implementation uses fixed values `[2, 4, 6, 8, 10, 12]`. Should be changed to:

- Show recent doses filtered by insulin type (bolus/basal)
- Add +5/-5 adjustment buttons relative to current value
- Store last used doses per type in settings

#### Meal Entry UI Consistency (Task 2.2 Enhancement)

Current meal entry form is visually different from insulin entry. Should:

- Use same stepper UI pattern as insulin for carb input
- Add +5/-5 adjustment buttons for macro values
- Include photo capture option in main meal UI (not separate route)
- Add customizable icon-based shortcuts (burger, pint, etc.)
- Quick presets based on recent/saved meals

---

## Phase 3: Visualization

**Branch**: `phase-3/visualization`
**Dependencies**: Phase 1 (data layer), benefits from Phase 2 data
**Merge requirement**: Phase 1 required; Phase 2 optional but recommended

### Objectives

- BSL trend charts
- Meal/insulin timeline overlay
- Daily/weekly summary views
- Best-in-class mobile charting

### Tasks

#### 3.1 Charting Library Selection

Evaluate and select charting library:

| Library                | Pros                        | Cons                |
| ---------------------- | --------------------------- | ------------------- |
| **Chart.js**           | Simple, well-known          | Less customizable   |
| **Apache ECharts**     | Powerful, mobile-optimized  | Larger bundle       |
| **Lightweight Charts** | Trading-style, performant   | Limited chart types |
| **LayerCake**          | Svelte-native, composable   | More manual work    |
| **Pancake**            | Svelte-native, SSR-friendly | Less maintained     |

**Recommendation**: LayerCake or ECharts depending on complexity needs.

#### 3.2 BSL Trend Chart

- [ ] Time-series line chart for BSL readings
- [ ] Configurable time range (day/week/month)
- [ ] Touch-friendly zoom/pan
- [ ] Reference lines for target ranges
- [ ] Color coding (in-range, high, low)

#### 3.3 Event Timeline Overlay

- [ ] Meal events as markers on BSL chart
- [ ] Insulin doses as vertical lines/markers
- [ ] Tap marker to see event details
- [ ] Legend with toggle visibility

#### 3.4 Summary Dashboard

- [ ] Daily carb/insulin totals
- [ ] Average BSL with trend indicator
- [ ] Time-in-range percentage
- [ ] Weekly comparison cards

### File Structure (Phase 3)

```
src/lib/
├── components/
│   └── charts/
│       ├── BSLTrendChart.svelte
│       ├── TimelineOverlay.svelte
│       ├── DailySummaryCard.svelte
│       ├── WeeklySummary.svelte
│       └── ChartControls.svelte   # Zoom, pan, time range
└── utils/
    └── chartHelpers.ts            # Data transformation for charts
```

### Acceptance Criteria

- [ ] BSL chart renders smoothly with 1000+ data points
- [ ] Charts responsive on mobile (touch gestures work)
- [ ] Meal/insulin markers visible on timeline
- [ ] Summary statistics calculate correctly
- [ ] Charts work offline with cached data

---

## Phase 3: AI Food Recognition (PRIORITY)

**Branch**: `phase-3/ai-food-recognition`
**Dependencies**: Phase 1 (settings for API keys), Phase 2 (meal entry)
**Merge requirement**: Phase 1 required; Phase 2 recommended
**Priority**: HIGH - Core differentiating feature

> **Research Reference**: [GoCARB System (JMIR 2016)](https://www.jmir.org/2016/5/e101/) - Mobile phone-based carbohydrate estimation achieving 26.9% mean absolute error vs 34.3% for self-report, with 85.1% food recognition accuracy.

### Objectives

- Photo-based meal recognition (Req 4.1, 4.2)
- Visual annotation of recognized food (Req 4.3)
- Nutrition label scanning (Req 4.4)
- **Cloud-first architecture**: Vision APIs with iterative learning from user corrections
- User corrections stored to improve prompts and track accuracy over time

### Architecture: Cloud Vision API with Iterative Learning

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
                    │                   │
                    └─────────┬─────────┘
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Macro Estimation Engine                       │
│  • Volume estimation (reference object or learned scales)        │
│  • USDA FNDDS nutritional database lookup                       │
│  • Confidence scoring and uncertainty bounds                    │
│  • Prompt enhancement from correction history                   │
└─────────────────────────────────────────────────────────────────┘
```

### Research-Backed Approach

Based on [GoCARB](https://www.jmir.org/2016/5/e101/) and recent advances in [mobile food recognition](https://link.springer.com/article/10.1007/s11042-021-11329-6):

1. **Reference Object Estimation**: GoCARB uses reference card for volume/portion estimation
2. **Cloud Vision APIs**: Modern LLM vision APIs (GPT-4V, Gemini, Claude) exceed standalone model accuracy
3. **Iterative Improvement**: User corrections stored to enhance future prompts and accuracy tracking
4. **Nutritional Mapping**: Link recognized items to USDA FNDDS database for macro lookup

### Tasks

#### 3.1 Cloud AI Service Layer (Quick Start)

- [ ] `IFoodRecognitionService` interface
- [ ] Cloud provider implementations:
  - [ ] OpenAI Vision API (GPT-4V)
  - [ ] Google Gemini Pro Vision
  - [ ] Anthropic Claude (Vision)
  - [ ] Ollama with LLaVA (self-hosted, privacy-first)
- [ ] API key validation and secure storage
- [ ] Rate limiting / error handling
- [ ] Provider fallback chain
- [ ] Structured prompt engineering for consistent macro output

```typescript
interface IFoodRecognitionService {
  recognizeFood(image: Blob, options?: RecognitionOptions): Promise<FoodRecognitionResult>;
  parseNutritionLabel(image: Blob): Promise<NutritionLabelResult>;
  isConfigured(): boolean;
  getProvider(): MLProvider;
}

interface FoodRecognitionResult {
  items: RecognizedFoodItem[];
  totalMacros: MacroData;
  confidence: number;
  boundingBoxes?: BoundingBox[]; // For visual annotation
  rawResponse?: string; // For debugging/improvement
}

interface RecognizedFoodItem {
  name: string;
  quantity: string; // "1 cup", "150g", etc.
  macros: MacroData;
  confidence: number;
  boundingBox?: BoundingBox;
  usdaFoodCode?: string; // Link to FNDDS
}

interface RecognitionOptions {
  includeAnnotations?: boolean;
  referenceObjectSize?: number; // Known size in mm for scale
  preferredUnits?: 'metric' | 'imperial';
}
```

#### 3.2 Iterative Learning Pipeline

- [ ] **Correction Storage**: Save user edits for accuracy tracking
  ```typescript
  interface CorrectionRecord {
    imageHash: string; // Deduplicated reference
    originalPrediction: FoodRecognitionResult;
    userCorrection: MacroData;
    timestamp: Date;
    feedbackType: 'macro_edit' | 'item_add' | 'item_remove' | 'quantity_change';
  }
  ```
- [ ] **Prompt Enhancement**: Use correction history to improve prompts
  - [ ] Track common user adjustments per food type
  - [ ] Include correction patterns in system prompts
  - [ ] "You previously overestimated carbs for pasta by 20%"
- [ ] **Accuracy Tracking**:
  - [ ] Track prediction accuracy over time
  - [ ] Surface "uncertain" predictions for explicit user review
  - [ ] Dashboard showing AI accuracy trends

#### 3.3 Camera Integration

- [ ] Camera capture component (mobile-optimized)
  - [ ] `getUserMedia` with rear camera preference
  - [ ] Flash/torch control
  - [ ] Focus tap-to-focus
- [ ] Reference object detection (optional)
  - [ ] Credit card size reference (85.6mm × 53.98mm)
  - [ ] Coin detection for scale
- [ ] Image preprocessing:
  - [ ] Resize to model input dimensions
  - [ ] EXIF orientation handling
  - [ ] Compression for cloud upload (WebP, quality 80)
- [ ] Gallery selection fallback

#### 3.4 Food Recognition UX Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Capture   │ ──► │  Analyzing  │ ──► │   Review    │ ──► │    Save     │
│   Photo     │     │  (Loading)  │     │   Results   │     │   + Learn   │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
      │                   │                   │                   │
      │                   │                   │                   │
      ▼                   ▼                   ▼                   ▼
 • Take photo        • Cloud API call    • Show items +      • Save event
 • Add reference     • Progress bar        bounding boxes    • Store image
   object (opt)      • Provider status   • Edit macros         hash
 • Retake option                         • Add/remove items  • Log correction
                                         • Confidence          if edited
                                           indicators
```

- [ ] Capture/select photo
- [ ] Show loading state with progress
- [ ] Display recognized items with confidence scores
- [ ] Visual annotation with bounding boxes
- [ ] Allow user to adjust/confirm macros (per-item and total)
- [ ] Save meal with photo reference and correction data

#### 3.5 Nutrition Label Scanner

- [ ] Dedicated "scan label" mode
- [ ] OCR extraction via cloud vision API
- [ ] Extract: serving size, calories, carbs, protein, fat, fiber
- [ ] User inputs number of servings
- [ ] Calculate totals
- [ ] Support Australian nutrition panel format

#### 3.6 Visual Annotation (Req 4.3)

- [ ] Overlay bounding boxes on recognized food
- [ ] Color-coded by macro density (high carb = green, high fat = yellow, etc.)
- [ ] Tap region to see/edit item details
- [ ] Canvas-based rendering for performance

### File Structure (Phase 3)

```
src/lib/
├── services/
│   └── ai/
│       ├── IFoodRecognitionService.ts
│       ├── OpenAIFoodService.ts
│       ├── GeminiFoodService.ts
│       ├── ClaudeFoodService.ts
│       ├── OllamaFoodService.ts
│       ├── FoodServiceFactory.ts
│       └── prompts/
│           └── foodRecognition.ts    # Structured prompts
├── components/
│   └── ai/
│       ├── CameraCapture.svelte
│       ├── PhotoPreview.svelte
│       ├── RecognitionLoading.svelte
│       ├── FoodRecognitionResult.svelte
│       ├── AnnotatedFoodImage.svelte
│       ├── FoodItemEditor.svelte
│       ├── NutritionLabelScanner.svelte
│       └── MacroConfirmation.svelte
├── data/
│   └── usda-fndds.ts               # Nutritional database subset
└── utils/
    └── imageProcessing.ts          # Compression, conversion, EXIF
```

### Routes (Phase 3)

```
src/routes/
└── log/
    └── meal/
        ├── +page.svelte            # Enhanced with photo capture
        ├── photo/
        │   └── +page.svelte        # Dedicated photo recognition flow
        └── label/
            └── +page.svelte        # Nutrition label scanning
```

### Acceptance Criteria

- [ ] User can configure API key in settings ✅ (already implemented)
- [ ] Photo capture works on iOS Safari and Android Chrome
- [ ] Cloud AI returns macro estimates within 10 seconds
- [ ] User can adjust AI estimates before saving
- [ ] User corrections are stored for iterative improvement
- [ ] Correction history used to enhance prompts over time
- [ ] Nutrition label parsing extracts key values
- [ ] Visual bounding boxes displayed on recognized items
- [ ] Graceful fallback to manual entry when API unavailable

### Research References

- [GoCARB: Carbohydrate Estimation by Mobile Phone (JMIR 2016)](https://www.jmir.org/2016/5/e101/)
- [Comprehensive Survey of Image-Based Food Recognition (Healthcare 2021)](https://pmc.ncbi.nlm.nih.gov/articles/PMC8700885/)
- [Smartphone-based Food Recognition with Multiple CNN Models (MTA 2021)](https://link.springer.com/article/10.1007/s11042-021-11329-6)
- [Applying Image-Based Food-Recognition Systems (Advances in Nutrition 2023)](<https://advances.nutrition.org/article/S2161-8313(23)00093-5/fulltext>)
- [AI-based Digital Image Dietary Assessment (Annals of Medicine 2023)](https://www.tandfonline.com/doi/full/10.1080/07853890.2023.2273497)

---

## Phase 4: Visualization (DEFERRED)

> **Note**: Visualization is lower priority than AI food recognition. Implement after Phase 3.

**Branch**: `phase-4/visualization`
**Dependencies**: Phase 1 (data layer), benefits from Phase 2 data
**Merge requirement**: Phase 1 required; Phase 2 optional but recommended

_See original Phase 3 content below for visualization tasks._

---

## Phase 5: Import/Export

**Branch**: `phase-5/import-export`
**Dependencies**: Phase 1 (data layer)
**Merge requirement**: Phase 1 required

### Objectives

- CSV upload/download (Req 3.1, 3.2)
- BSL time-series import (Req 3.3)
- Backup and restore functionality
- Meal presets (Req 6.2)

### Tasks

#### 5.1 Export Functionality

- [ ] Export all data as JSON backup
- [ ] Export filtered data as CSV
- [ ] Date range selection for export
- [ ] Download trigger (mobile-friendly)

#### 5.2 Import Functionality

- [ ] JSON backup restore
- [ ] CSV import with column mapping
- [ ] Duplicate detection
- [ ] Import preview before commit
- [ ] Progress indicator for large imports

#### 5.3 BSL Time-Series Import (Req 3.3)

- [ ] Support common CGM export formats
- [ ] Libre CSV format
- [ ] Dexcom CSV format
- [ ] Time zone handling
- [ ] Merge with existing data

#### 5.4 Graph Image Interpolation (Req 3.3.1)

- [ ] Upload graph image
- [ ] AI-powered curve extraction
- [ ] User-defined axis ranges
- [ ] Convert to time-series data points
- [ ] Preview before import

#### 5.5 Meal Presets (Req 6.2)

- [ ] Save current meal as preset
- [ ] Preset library management
- [ ] Quick-apply preset to new meal
- [ ] Edit/delete presets

### File Structure (Phase 5)

```
src/lib/
├── services/
│   ├── ImportExportService.ts
│   ├── CSVParser.ts
│   └── PresetService.ts
├── components/
│   └── import-export/
│       ├── ExportPanel.svelte
│       ├── ImportWizard.svelte
│       ├── CSVColumnMapper.svelte
│       ├── ImportPreview.svelte
│       ├── GraphImageImport.svelte
│       └── PresetManager.svelte
└── utils/
    ├── csvHelpers.ts
    └── dateNormalization.ts
```

### Routes (Phase 5)

```
src/routes/
├── settings/
│   ├── export/
│   │   └── +page.svelte
│   ├── import/
│   │   └── +page.svelte
│   └── presets/
│       └── +page.svelte
```

### Acceptance Criteria

- [ ] Full backup can be exported and re-imported
- [ ] CSV import handles common date formats
- [ ] BSL data from Libre/Dexcom imports correctly
- [ ] Presets save and apply correctly
- [ ] No data loss on import/export cycle

---

## Phase 6: ML & Regression (Deferred)

**Branch**: `phase-6/ml-regression`
**Dependencies**: Phases 1-5 (needs sufficient data)
**Status**: Deferred until core features stable

### Objectives (Future)

- Insulin dose prediction (Req 5.1)
- Decay function modeling (Req 5.3)
- Time-of-day effects (Req 5.4)
- Continuous improvement with data (Req 5.5)

### Research Areas

- [ ] Evaluate client-side ML (TensorFlow.js, ONNX Runtime)
- [ ] Define minimum data requirements for training
- [ ] Decay function mathematical models
- [ ] Time-series regression approaches

### Potential Architecture

```
┌─────────────────────────────────────────┐
│           ML Service Layer              │
│  (Runs in Web Worker for performance)   │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│         Feature Engineering             │
│  - 5-min interval resampling            │
│  - Decay function application           │
│  - Time-of-day encoding                 │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│         Regression Model                │
│  - Linear regression (baseline)         │
│  - Gradient boosting (advanced)         │
│  - Personal model per user              │
└─────────────────────────────────────────┘
```

---

## Cross-Cutting Concerns

### Offline-First Strategy

```javascript
// Service Worker caching strategy
const CACHE_STRATEGIES = {
  static: 'cache-first', // App shell, JS, CSS
  api: 'network-first', // AI API calls (when online)
  data: 'stale-while-revalidate' // Not applicable for IndexedDB
};
```

- All data stored in IndexedDB (always available offline)
- Service worker caches app shell
- AI features gracefully degrade when offline
- Sync indicator when back online (future)

### Mobile-First Design Principles

1. **Touch targets**: Minimum 44x44px
2. **Bottom navigation**: Thumb-reachable actions
3. **Swipe gestures**: Edit, delete, navigate
4. **Large text**: Readable without zooming
5. **Dark mode**: Respect system preference
6. **Haptic feedback**: Confirm important actions

### Error Handling Strategy

```typescript
// Centralized error handling
class AppError extends Error {
  constructor(
    message: string,
    public code: ErrorCode,
    public recoverable: boolean = true
  ) {
    super(message);
  }
}

enum ErrorCode {
  STORAGE_FULL = 'STORAGE_FULL',
  AI_UNAVAILABLE = 'AI_UNAVAILABLE',
  INVALID_DATA = 'INVALID_DATA',
  NETWORK_ERROR = 'NETWORK_ERROR'
}
```

### Testing Strategy

| Layer        | Testing Approach                     |
| ------------ | ------------------------------------ |
| Repositories | Unit tests with mock IndexedDB       |
| Services     | Unit tests with mock repositories    |
| Components   | Component tests with Testing Library |
| E2E          | Playwright for critical flows        |

_Note: Testing frameworks are out of scope per requirements, but structure supports future addition._

---

## Git Workflow

### Branch Strategy

```bash
# Create phase branch from main
git checkout main
git checkout -b phase-1/foundation

# Work on phase
git commit -m "feat: add event repository interface"

# When phase complete, create PR to main
# Review and merge

# Next phase branches from main (includes previous phases)
git checkout main
git pull
git checkout -b phase-2/data-input
```

### Independent Mergeability

Phases are designed so that:

- **Phase 1** can merge alone (foundation)
- **Phase 3** can merge before Phase 2 (visualization works with test data)
- **Phase 4** can merge before Phase 3 (AI works without charts)
- **Phase 5** can merge independently (import/export is standalone)

### Commit Convention

```
feat: add new feature
fix: bug fix
refactor: code change that neither fixes bug nor adds feature
docs: documentation only
style: formatting, no code change
test: adding tests
chore: maintenance tasks
```

---

## Tech Stack Summary

| Category         | Technology              | Version |
| ---------------- | ----------------------- | ------- |
| Framework        | SvelteKit               | 2.x     |
| Language         | TypeScript              | 5.x     |
| Styling          | Tailwind CSS            | 3.x     |
| Database         | Dexie.js (IndexedDB)    | 4.x     |
| Charting         | TBD (LayerCake/ECharts) | -       |
| PWA              | Workbox                 | 7.x     |
| Build            | Vite                    | 5.x     |
| Asset Generation | Sharp                   | 0.33.x  |

---

## Appendix: Data Model Research

### Event Log Paradigm Analysis

The requirements specify an event-log structure. This aligns with:

1. **Immutability**: Events are facts that occurred; editing creates new events
2. **Extensibility**: New `event_type` values without schema changes
3. **Time-series friendly**: Natural fit for BSL data and regression
4. **Audit trail**: Full history for medical/personal records

### IndexedDB vs Alternatives

| Storage       | Capacity  | Structure  | Offline    | Decision                  |
| ------------- | --------- | ---------- | ---------- | ------------------------- |
| LocalStorage  | 5-10MB    | Key-value  | Yes        | Too small                 |
| IndexedDB     | 50MB+     | Structured | Yes        | **Selected**              |
| SQLite (WASM) | Unlimited | Relational | Yes        | Overkill for v1           |
| PouchDB       | 50MB+     | Document   | Yes + Sync | Good, but adds dependency |

**Decision**: Dexie.js wrapping IndexedDB provides:

- Clean Promise-based API
- TypeScript support
- Migration handling
- Good performance for our data volume

### Repository Pattern Benefits

1. **Testability**: Mock repositories for unit tests
2. **Portability**: Swap IndexedDB for REST API without UI changes
3. **Single Responsibility**: UI doesn't know about storage details
4. **Future-proofing**: Multi-user/sync can be added at repository level

### AI Service Abstraction

User-provided API keys means:

- Keys stored in sessionStorage (not persisted) or localStorage (user choice)
- No backend proxy needed
- User controls their API costs
- Graceful degradation when keys not configured

---

## Getting Started (Phase 1)

```bash
# Clone and install
git clone <repo>
cd medata
npm install

# Start development
npm run dev

# Build for production
npm run build

# Preview production build
npm run preview
```

---

## Phase 2 Review Notes (2026-01-20 - Comprehensive Review)

### Code Quality Assessment

**Svelte 5 Paradigm Usage**: ✅ Excellent

- Proper use of `$state`, `$derived`, `$derived.by()`, `$effect`, `$props()` throughout
- Snippets correctly used for component composition (`children`, `action`, `icon`)
- `@render` directive used correctly for snippet rendering
- Type-safe Props interfaces defined for all components
- Stores use reactive getters pattern correctly

**Responsive Design Patterns**: ✅ Good

- Mobile-first approach with `min-h-dvh`, `pb-safe` for safe area insets
- Touch-friendly targets (min-h-[44px] on interactive elements)
- Responsive grid layouts (`grid-cols-2`, `grid-cols-3`, `grid-cols-6`)
- Bottom navigation fixed with backdrop blur
- Flexible layouts using `flex-1`, `flex-col`

**Aesthetic & UI Consistency**: ✅ Good

- Consistent dark theme (`gray-950` background, `gray-800` cards)
- Coherent color palette (blue for insulin, green for meals, yellow for BSL, purple for alcohol)
- Brand accent color (`#63ff00`) used consistently
- Rounded corners (`rounded-lg`, `rounded-xl`) applied uniformly
- Consistent spacing (`gap-2`, `gap-3`, `gap-4`, `mb-4`, `mb-6`, `mb-8`)
- Icon components are consistent and well-structured

**Architecture Quality**: ✅ Excellent

- Clean separation: UI → Stores → Services → Repositories
- Services are framework-agnostic (pure TypeScript)
- Repository pattern properly implemented with interfaces
- Type guards for metadata discrimination
- IndexedDB via Dexie.js properly configured

### Minor Issues Found

1. **Prettier formatting** - 9 files had formatting issues (now fixed via `npm run format`)
2. **Missing haptic feedback** - Not implemented (browser API support limited)
3. **No event editing** - Events cannot be edited after creation

### Current Feature Status

| Feature              | Status         | Notes                                      |
| -------------------- | -------------- | ------------------------------------------ |
| Insulin logging      | ✅ Complete    | Type toggle, stepper, recent doses         |
| Meal logging         | ✅ Complete    | Presets, macros, alcohol, photo capture UI |
| History view         | ✅ Complete    | Filtering, grouping by date                |
| Home dashboard       | ✅ Complete    | Today's summary, quick actions             |
| Settings             | ✅ Complete    | ML provider config, defaults               |
| Service worker       | ✅ Complete    | Offline caching                            |
| PWA manifest         | ✅ Complete    | Installable                                |
| Event editing        | ❌ Not started |                                            |
| Time picker          | ❌ Not started |                                            |
| BSL logging page     | ❌ Not started | Route exists in nav but no page            |
| AI food recognition  | ❌ Not started | Settings ready, service not implemented    |
| Data export/import   | ❌ Not started |                                            |
| Charts/visualization | ❌ Not started |                                            |

### Accessibility Notes

- Proper `aria-labelledby` and `role="group"` for button groups
- Labels associated with inputs via `for`/`id`
- `aria-label` on icon-only buttons
- `aria-current="page"` on active nav items
- `aria-hidden="true"` on decorative SVGs

---

## Suggested Next Steps (Priority Order)

### Immediate Priority: AI Food Recognition (Phase 3)

1. **IFoodRecognitionService Interface**
   - Define TypeScript interfaces for food recognition
   - Create service factory for provider selection
   - Structured prompt templates for consistent output

2. **Cloud Provider Implementation (Start with one)**
   - OpenAI Vision API (GPT-4V) - best accuracy
   - OR Gemini Pro Vision - good free tier
   - OR Ollama + LLaVA - privacy-first, self-hosted
   - API key already stored in settings

3. **Camera Capture Component**
   - `getUserMedia` with rear camera
   - Image preview and retake
   - Compression for upload (WebP)
   - EXIF orientation handling

4. **Food Recognition Flow**
   - Photo capture → Cloud API → Review results → Save
   - Display recognized items with confidence
   - Allow macro edits before saving
   - Store corrections for iterative learning

5. **Iterative Learning Pipeline**
   - Save original prediction + user corrections
   - Track accuracy over time
   - Use correction history to enhance prompts

6. **Nutrition Label Scanner**
   - OCR via cloud vision API
   - Australian nutrition panel support
   - Serving size calculations

### Lower Priority: Phase 2 Completion

7. **BSL Logging Page** (`/log/bsl/+page.svelte`)
   - Stepper-style input
   - mmol/L and mg/dL units

8. **Event Editing**
   - Edit modal for existing events
   - Time picker component

### Deferred: Visualization (Phase 4)

9. **Charting** (after AI recognition working)
   - BSL trend charts
   - Meal/insulin timeline overlay
   - Weekly summaries

### Research Tasks

- [ ] Research USDA FNDDS API or static dataset for nutritional lookup
- [ ] Test cloud vision APIs with sample food images
- [ ] Design prompt templates for consistent macro extraction
- [ ] Evaluate reference object detection for portion estimation

---

_Last updated: 2026-01-20_
_Reviewed after commit 29731a8 - UI updates and logo input_
_Priority update: AI Food Recognition now Phase 3 (priority), Visualization deferred to Phase 4_
_Research reference: [GoCARB JMIR 2016](https://www.jmir.org/2016/5/e101/) for cloud-only architecture with iterative learning_

## Svelte 5 Compliance Verification (2026-01-20)

All components verified with MCP Svelte autofixer:

| Component               | Status | Notes                                          |
| ----------------------- | ------ | ---------------------------------------------- |
| AppShell.svelte         | ✅     | No issues                                      |
| PageTransition.svelte   | ✅     | $effect for navigation tracking is intentional |
| BottomNav.svelte        | ✅     | Removed redundant onMount (now uses $effect)   |
| Button.svelte           | ✅     | No issues                                      |
| EmptyState.svelte       | ✅     | No issues                                      |
| LoadingSpinner.svelte   | ✅     | No issues                                      |

**Svelte 5 Patterns Used Correctly:**
- `$state` for reactive state
- `$derived` and `$derived.by()` for computed values
- `$effect` for side effects
- `$props()` with TypeScript interfaces
- Snippets with `@render` directive
- No legacy Svelte 4 patterns (`export let`, `$:`, `on:` directives)

**Build & Lint Status:** All checks pass (0 errors, 0 warnings)

**Ready for Phase 3:** AI Food Recognition implementation
