# MeData Development Plan

> **Source of Truth**: [requirements.md](./requirements.md)
> **Architecture Reference**: [arch_pattern_review.md](./arch_pattern_review.md)

---

## Overview

MeData is a **mobile-first SPA** for tracking physiological data (meals, insulin, blood sugar) with AI-powered food recognition and eventual regression modeling for insulin dose prediction.

### Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Framework | SvelteKit + adapter-static | SPA with offline capability, modern DX |
| Data Storage | IndexedDB (via Dexie.js) | Structured offline storage, good capacity |
| Data Abstraction | Repository Pattern | Clean separation, enables future backends |
| API Keys | User-provided, session storage | Simplest model, no backend needed |
| UI Approach | Mobile-first, responsive | Primary users on phones |
| ML/Regression | Deferred to Phase 5+ | Focus on data capture first |

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
│                 Repository Implementations                       │
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
  id: string;                    // UUID
  timestamp: Date;               // When the event occurred
  event_type: EventType;         // 'meal' | 'insulin' | 'bsl' | 'exercise' | ...
  value: number;                 // Primary numeric value
  metadata: Record<string, any>; // Type-specific additional data
  created_at: Date;              // Record creation time
  updated_at: Date;              // Last modification time
  synced?: boolean;              // For future multi-device sync
}

// Event type definitions
type EventType =
  | 'meal'      // value = total carbs, metadata = { calories, protein, fat, description, photo_url }
  | 'insulin'   // value = units, metadata = { type: 'bolus' | 'basal' }
  | 'bsl'       // value = mmol/L or mg/dL, metadata = { unit }
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
  create(event: Omit<PhysiologicalEvent, 'id' | 'created_at' | 'updated_at'>): Promise<PhysiologicalEvent>;
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

```
main
  ├── phase-1/foundation
  ├── phase-2/data-input
  ├── phase-3/visualization
  ├── phase-4/ai-integration
  ├── phase-5/import-export
  └── phase-6/ml-regression (deferred)
```

---

## Phase 1: Foundation

**Branch**: `phase-1/foundation`
**Dependencies**: None
**Merge requirement**: Can merge to main independently

### Objectives
- Project scaffolding with SvelteKit
- Data layer with Repository Pattern
- Core TypeScript types and interfaces
- Basic app shell with mobile navigation

### Tasks

#### 1.1 Project Setup
- [ ] Initialize SvelteKit project with TypeScript
- [ ] Configure adapter-static for SPA mode
- [ ] Setup Tailwind CSS (mobile-first utilities)
- [ ] Configure PWA manifest for mobile install
- [ ] Setup service worker for offline caching
- [ ] ESLint + Prettier configuration

```bash
# Key dependencies
npm create svelte@latest medata
npm install -D @sveltejs/adapter-static tailwindcss
npm install dexie uuid
```

#### 1.2 Data Layer Implementation
- [ ] Define TypeScript interfaces in `$lib/types/`
- [ ] Implement Dexie.js database schema in `$lib/db/`
- [ ] Create `IEventRepository` interface
- [ ] Implement `IndexedDBEventRepository`
- [ ] Create `ISettingsRepository` for user preferences
- [ ] Implement `LocalStorageSettingsRepository`
- [ ] Create repository factory/provider

#### 1.3 Service Layer
- [ ] `EventService` - business logic wrapper around repository
- [ ] `SettingsService` - API key management, preferences
- [ ] Svelte stores for reactive state (`$lib/stores/`)

#### 1.4 App Shell
- [ ] Root layout with mobile navigation
- [ ] Bottom tab bar component (Home, Log, History, Settings)
- [ ] Settings page with API key input
- [ ] Empty state components
- [ ] Loading/error state components

### File Structure (Phase 1)

```
src/
├── lib/
│   ├── types/
│   │   ├── events.ts          # PhysiologicalEvent, EventType
│   │   ├── presets.ts         # MealPreset, MacroData
│   │   └── settings.ts        # UserSettings, APIConfig
│   ├── db/
│   │   ├── schema.ts          # Dexie database definition
│   │   └── migrations.ts      # Version migrations
│   ├── repositories/
│   │   ├── interfaces/
│   │   │   ├── IEventRepository.ts
│   │   │   └── ISettingsRepository.ts
│   │   ├── IndexedDBEventRepository.ts
│   │   └── LocalStorageSettingsRepository.ts
│   ├── services/
│   │   ├── EventService.ts
│   │   └── SettingsService.ts
│   ├── stores/
│   │   ├── events.svelte.ts   # Svelte 5 runes-based store
│   │   └── settings.svelte.ts
│   └── components/
│       ├── layout/
│       │   ├── BottomNav.svelte
│       │   └── AppShell.svelte
│       └── ui/
│           ├── LoadingSpinner.svelte
│           └── EmptyState.svelte
├── routes/
│   ├── +layout.svelte
│   ├── +layout.js             # ssr = false, prerender = true
│   ├── +page.svelte           # Home/Dashboard
│   └── settings/
│       └── +page.svelte
└── service-worker.js
```

### Acceptance Criteria
- [ ] App loads offline after first visit
- [ ] Can store and retrieve test events from IndexedDB
- [ ] Settings persist across sessions
- [ ] Mobile navigation functional
- [ ] Lighthouse PWA score > 90

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
- [ ] Quick insulin log component
  - Default to current time
  - Default to last-used type (bolus/basal)
  - Whole number input (1-300 range)
  - Large touch targets for mobile
- [ ] Insulin type toggle (bolus/basal)
- [ ] Number pad or stepper for units
- [ ] Confirmation haptic/visual feedback
- [ ] "Just now" quick log button on home screen

#### 2.2 Meal Entry (Manual - Req 2.1)
- [ ] Meal logging form
  - Carbs (required)
  - Calories, protein, fat (optional)
  - Description/notes
  - Time picker (defaults to now)
- [ ] Quick macro calculator
- [ ] Recent meals list for quick re-entry

#### 2.3 Time Adjustment (Req 2.3)
- [ ] Edit modal for any event
- [ ] Timestamp picker component
- [ ] Swipe-to-edit on event list items
- [ ] Edit history tracking (in metadata)

#### 2.4 Event History
- [ ] Chronological event list
- [ ] Filter by event type
- [ ] Date range selector
- [ ] Pull-to-refresh pattern
- [ ] Infinite scroll or pagination

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
- [ ] Insulin can be logged in ≤3 taps from home
- [ ] Meal macros saved correctly to IndexedDB
- [ ] Events can be edited after creation
- [ ] History shows all events chronologically
- [ ] Works fully offline

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

| Library | Pros | Cons |
|---------|------|------|
| **Chart.js** | Simple, well-known | Less customizable |
| **Apache ECharts** | Powerful, mobile-optimized | Larger bundle |
| **Lightweight Charts** | Trading-style, performant | Limited chart types |
| **LayerCake** | Svelte-native, composable | More manual work |
| **Pancake** | Svelte-native, SSR-friendly | Less maintained |

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

## Phase 4: AI Integration

**Branch**: `phase-4/ai-integration`
**Dependencies**: Phase 1 (settings for API keys), Phase 2 (meal entry)
**Merge requirement**: Phase 1 required; Phase 2 recommended

### Objectives
- Photo-based meal recognition (Req 4.1, 4.2)
- Visual annotation of recognized food (Req 4.3)
- Nutrition label scanning (Req 4.4)
- API key configuration (Req 7.2)

### Tasks

#### 4.1 AI Service Layer
- [ ] `AIService` interface for food recognition
- [ ] Implementations for:
  - OpenAI Vision API
  - Google Gemini
  - Claude (Anthropic)
- [ ] API key validation and storage
- [ ] Rate limiting / error handling
- [ ] Fallback between providers

```typescript
interface IAIFoodService {
  recognizeFood(image: Blob): Promise<FoodRecognitionResult>;
  parseNutritionLabel(image: Blob): Promise<NutritionLabelResult>;
  isConfigured(): boolean;
}

interface FoodRecognitionResult {
  items: RecognizedFoodItem[];
  confidence: number;
  annotatedImageUrl?: string;
}
```

#### 4.2 Camera Integration
- [ ] Camera capture component (mobile-optimized)
- [ ] Image preview and retake
- [ ] Image compression before upload
- [ ] Gallery selection fallback

#### 4.3 Food Recognition Flow
- [ ] Capture/select photo
- [ ] Show loading state during AI processing
- [ ] Display recognized items with confidence
- [ ] Allow user to adjust/confirm macros
- [ ] Save with photo reference

#### 4.4 Nutrition Label Scanner
- [ ] Dedicated "scan label" mode
- [ ] Extract: serving size, calories, carbs, protein, fat
- [ ] User inputs number of servings
- [ ] Calculate totals

#### 4.5 Visual Annotation (Req 4.3)
- [ ] Overlay bounding boxes on recognized food
- [ ] Color-coded by food type
- [ ] Tap region to see item details

### File Structure (Phase 4)

```
src/lib/
├── services/
│   └── ai/
│       ├── IAIFoodService.ts
│       ├── OpenAIFoodService.ts
│       ├── GeminiFoodService.ts
│       ├── ClaudeFoodService.ts
│       └── AIServiceFactory.ts
├── components/
│   └── ai/
│       ├── CameraCapture.svelte
│       ├── FoodRecognitionResult.svelte
│       ├── AnnotatedFoodImage.svelte
│       ├── NutritionLabelScanner.svelte
│       └── MacroConfirmation.svelte
└── utils/
    └── imageProcessing.ts         # Compression, conversion
```

### Routes (Phase 4)

```
src/routes/
└── log/
    └── meal/
        ├── photo/
        │   └── +page.svelte       # Photo capture & recognition
        └── label/
            └── +page.svelte       # Nutrition label scanning
```

### Acceptance Criteria
- [ ] User can configure API key in settings
- [ ] Photo capture works on iOS and Android browsers
- [ ] AI returns macro estimates within 10 seconds
- [ ] User can adjust AI estimates before saving
- [ ] Nutrition label parsing extracts key values
- [ ] Graceful degradation when AI unavailable

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
  static: 'cache-first',     // App shell, JS, CSS
  api: 'network-first',      // AI API calls (when online)
  data: 'stale-while-revalidate'  // Not applicable for IndexedDB
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

| Layer | Testing Approach |
|-------|------------------|
| Repositories | Unit tests with mock IndexedDB |
| Services | Unit tests with mock repositories |
| Components | Component tests with Testing Library |
| E2E | Playwright for critical flows |

*Note: Testing frameworks are out of scope per requirements, but structure supports future addition.*

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

| Category | Technology | Version |
|----------|------------|---------|
| Framework | SvelteKit | 2.x |
| Language | TypeScript | 5.x |
| Styling | Tailwind CSS | 3.x |
| Database | Dexie.js (IndexedDB) | 4.x |
| Charting | TBD (LayerCake/ECharts) | - |
| PWA | Workbox | 7.x |
| Build | Vite | 5.x |

---

## Appendix: Data Model Research

### Event Log Paradigm Analysis

The requirements specify an event-log structure. This aligns with:

1. **Immutability**: Events are facts that occurred; editing creates new events
2. **Extensibility**: New `event_type` values without schema changes
3. **Time-series friendly**: Natural fit for BSL data and regression
4. **Audit trail**: Full history for medical/personal records

### IndexedDB vs Alternatives

| Storage | Capacity | Structure | Offline | Decision |
|---------|----------|-----------|---------|----------|
| LocalStorage | 5-10MB | Key-value | Yes | Too small |
| IndexedDB | 50MB+ | Structured | Yes | **Selected** |
| SQLite (WASM) | Unlimited | Relational | Yes | Overkill for v1 |
| PouchDB | 50MB+ | Document | Yes + Sync | Good, but adds dependency |

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

*Last updated: 2025-01-19*
