# Code Constitution: MeData

This document defines the coding standards, architectural patterns, and conventions that govern all code written for the MeData project. All contributions MUST adhere to these rules.

---

## 1. Core Principles

### 1.1 Data Ownership
Data ownership is a core value. End users MUST be able to encrypt, delete, upload, and export their data at all times. Design decisions SHALL favour user control over convenience.

### 1.2 Simplicity Over Complexity
Simple UI and quick inputs are necessary to ensure it is not laborious to input data, particularly on mobile devices. The system SHALL prefer simplicity over security at this early stage.

### 1.3 Extensible Data Design
Data design SHALL accommodate future growth and ownership, expanding to medical history, scans, and other biometric data. Data sharing (time-bound, consent-based) SHALL be architecturally possible without redesign.

### 1.4 Irish English
All user-facing text SHALL use Irish English spelling:
- colour (not color)
- behaviour (not behavior)
- analyse (not analyze)
- visualise (not visualize)
- recognise (not recognize)

---

## 2. Technology Stack

| Layer | Technology | Version |
|-------|------------|---------|
| Framework | SvelteKit | 2.x |
| UI Library | Svelte | 5.x (runes syntax) |
| Language | TypeScript | 5.x (strict mode) |
| Styling | Tailwind CSS | 4.x |
| Database | Azure Cosmos DB | NoSQL |
| Storage | Azure Blob Storage | - |
| Validation | Zod | 3.x |
| Build | Vite | 6.x |

---

## 3. Architecture

### 3.1 Layered Architecture
Code MUST follow this layered architecture:

```
┌─────────────────────────────────────────┐
│  Presentation Layer (Svelte Components) │
└─────────────────────┬───────────────────┘
                      │
┌─────────────────────▼───────────────────┐
│  Stores (Svelte 5 Runes State)          │
└─────────────────────┬───────────────────┘
                      │
┌─────────────────────▼───────────────────┐
│  Services (Business Logic)              │
└─────────────────────┬───────────────────┘
                      │
┌─────────────────────▼───────────────────┐
│  Repositories (Data Access Abstraction) │
└─────────────────────┬───────────────────┘
                      │
┌─────────────────────▼───────────────────┐
│  Storage (Cosmos DB / Blob Storage)     │
└─────────────────────────────────────────┘
```

### 3.2 Layer Rules

**Services MUST:**
- Be framework-agnostic (no Svelte imports)
- Return Promises, not reactive values
- Accept repository interfaces via constructor injection
- Contain all business logic

**Repositories MUST:**
- Implement defined interfaces (e.g., `IEventRepository`)
- Handle only data access operations
- Be swappable without affecting service layer

**Stores MUST:**
- Use Svelte 5 runes (`$state`, `$derived`)
- Wrap services for reactive state
- Handle loading/error states
- Not contain business logic

**Components MUST:**
- Consume stores or receive data via props
- Not directly access repositories or databases
- Use typed props interfaces

---

## 4. Directory Structure

```bash
src/
├── lib/
│   ├── components/          # Svelte UI components
│   │   ├── ai/              # AI food recognition components
│   │   ├── cgm/             # CGM graph capture components
│   │   ├── icons/           # Icon components
│   │   ├── import/          # Data import components
│   │   ├── layout/          # App shell, navigation
│   │   ├── local-estimation/ # Local food estimation
│   │   └── ui/              # Reusable primitives (Button, etc.)
│   ├── config/              # Configuration management
│   ├── data/                # Static data (lookup tables)
│   ├── db/                  # Database schema (Dexie/IndexedDB)
│   ├── repositories/        # Data access interfaces & implementations
│   ├── services/            # Business logic
│   │   ├── ai/              # AI provider implementations
│   │   ├── cgm/             # CGM processing services
│   │   ├── import/          # CSV parsing services
│   │   ├── local-estimation/ # Volume estimation services
│   │   └── modeling/        # Prediction models
│   ├── stores/              # Svelte 5 reactive stores
│   ├── types/               # TypeScript type definitions
│   └── utils/               # Pure utility functions
├── routes/                  # SvelteKit file-based routing
│   └── api/                 # Server routes (+server.ts)
└── app.d.ts                 # Global type declarations
```

---

## 5. Naming Conventions

### 5.1 Files

| Type | Pattern | Example |
|------|---------|---------|
| Component | PascalCase.svelte | `FoodRecognitionResult.svelte` |
| Service | PascalCase + Service.ts | `EventService.ts` |
| Repository Interface | I + PascalCase.ts | `IEventRepository.ts` |
| Repository Implementation | PascalCase + Repository.ts | `IndexedDBEventRepository.ts` |
| Store | camelCase.svelte.ts | `events.svelte.ts` |
| Types | camelCase.ts | `events.ts`, `ai.ts` |
| Utilities | camelCase.ts | `csvHelpers.ts` |
| Factory | PascalCase + Factory.ts | `FoodServiceFactory.ts` |
| Index/Barrel | index.ts | `index.ts` |

### 5.2 Code

| Element | Convention | Example |
|---------|------------|---------|
| Interfaces | PascalCase, prefix with I for repos | `IEventRepository`, `FoodItem` |
| Types | PascalCase | `EventType`, `MacroData` |
| Classes | PascalCase | `EventService`, `ClaudeFoodService` |
| Functions | camelCase | `createEvent`, `sumMacros` |
| Constants | UPPER_SNAKE_CASE | `EMPTY_MACROS`, `RETRY_DELAYS` |
| Variables | camelCase | `eventStore`, `loading` |
| Props | camelCase | `onCapture`, `variant` |
| Enums/Unions | Literal strings | `'meal' | 'insulin' | 'bsl'` |

### 5.3 Barrel Exports
Each feature directory MUST have an `index.ts` that exports all public members:

```typescript
// src/lib/components/ai/index.ts
export { default as CameraCapture } from './CameraCapture.svelte';
export { default as FoodRecognitionResult } from './FoodRecognitionResult.svelte';
```

---

## 6. TypeScript Patterns

### 6.1 Type Definitions

Types MUST be defined in dedicated files under `src/lib/types/`:

```typescript
// src/lib/types/events.ts
export interface MacroData {
  calories: number;
  carbs: number;
  protein: number;
  fat: number;
}

export type EventType = 'meal' | 'insulin' | 'bsl' | 'exercise';
```

### 6.2 Interface-Based Services

All services MUST implement interfaces:

```typescript
// Repository interface
export interface IEventRepository {
  create(event: CreateEventInput): Promise<PhysiologicalEvent>;
  getById(id: string): Promise<PhysiologicalEvent | null>;
  update(id: string, updates: UpdateEventInput): Promise<PhysiologicalEvent>;
  delete(id: string): Promise<void>;
  getByDateRange(start: Date, end: Date): Promise<PhysiologicalEvent[]>;
}

// Service interface
export interface IFoodRecognitionService {
  RecogniseFood(image: Blob, options?: RecognitionOptions): Promise<FoodRecognitionResult>;
  getProviderName(): string;
  isConfigured(): boolean;
}
```

### 6.3 Constructor Injection

Services MUST receive dependencies via constructor:

```typescript
export class EventService {
  constructor(private repository: IEventRepository) {}

  async createEvent(input: CreateEventInput): Promise<PhysiologicalEvent> {
    return this.repository.create(input);
  }
}
```

### 6.4 Strict TypeScript Config

The project MUST use strict TypeScript settings:

```json
{
  "compilerOptions": {
    "strict": true,
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true
  }
}
```

---

## 7. Svelte 5 Patterns

### 7.1 Component Props

Components MUST define props using typed interfaces:

```svelte
<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    variant?: 'primary' | 'secondary' | 'danger';
    disabled?: boolean;
    loading?: boolean;
    onclick?: () => void;
    children: Snippet;
  }

  let {
    variant = 'primary',
    disabled = false,
    loading = false,
    onclick,
    children
  }: Props = $props();
</script>
```

### 7.2 State Management with Runes

Stores MUST use Svelte 5 runes:

```typescript
// src/lib/stores/events.svelte.ts
function createEventsStore() {
  let events = $state<PhysiologicalEvent[]>([]);
  let loading = $state(false);
  let error = $state<string | null>(null);

  const todayStats = $derived.by(() => {
    // Compute derived state
  });

  async function loadRecent(limit: number = 20) {
    loading = true;
    error = null;
    try {
      events = await service.getRecentEvents(limit);
    } catch (e) {
      error = e instanceof Error ? e.message : 'Failed to load events';
    } finally {
      loading = false;
    }
  }

  return {
    get events() { return events; },
    get loading() { return loading; },
    get error() { return error; },
    get todayStats() { return todayStats; },
    loadRecent
  };
}

export const eventsStore = createEventsStore();
```

### 7.3 Content Projection (Snippets)

Use Svelte 5 Snippets for content projection:

```svelte
<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    children: Snippet;
    header?: Snippet;
  }

  let { children, header }: Props = $props();
</script>

<div class="card">
  {#if header}
    <div class="card-header">{@render header()}</div>
  {/if}
  <div class="card-body">{@render children()}</div>
</div>
```

### 7.4 Event Handlers as Props

Pass event handlers as callback props:

```svelte
<script lang="ts">
  interface Props {
    onCapture: (blob: Blob) => void;
    onCancel?: () => void;
  }

  let { onCapture, onCancel }: Props = $props();
</script>

<button onclick={() => onCapture(imageBlob)}>Capture</button>
```

---

## 8. Validation

### 8.1 Zod at API Boundaries

Zod validation MUST occur at API boundaries only. After validation, data is trusted internally:

```typescript
import { z } from 'zod';

const FoodItemSchema = z.object({
  name: z.string().min(1),
  quantity: z.number().positive(),
  unit: z.string().min(1),
  carbs: z.number().nonnegative(),
  protein: z.number().nonnegative(),
  fat: z.number().nonnegative(),
  calories: z.number().nonnegative()
});

// In API route
export async function POST({ request }) {
  const body = await request.json();
  const result = FoodItemSchema.safeParse(body);

  if (!result.success) {
    return json({ error: result.error.issues }, { status: 400 });
  }

  // Data is now trusted
  return json(await service.create(result.data));
}
```

### 8.2 Type Inference from Schemas

Infer TypeScript types from Zod schemas:

```typescript
const MealMetadataSchema = z.object({
  items: z.array(FoodItemSchema).min(1),
  totalCarbs: z.number().nonnegative(),
  source: z.enum(['manual', 'ai_image', 'label_scan', 'preset'])
});

type MealMetadata = z.infer<typeof MealMetadataSchema>;
```

---

## 9. Error Handling

### 9.1 Custom Error Classes

Services SHOULD define custom error classes:

```typescript
export class VisionServiceError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'VisionServiceError';
  }
}
```

### 9.2 Error Message Standards

Error messages MUST:
- Be pragmatic and actionable
- State what failed and suggest resolution
- NOT use apologetic language ("Sorry", "Oops")

```typescript
// Good
throw new Error('Upload failed: unsupported format.');

// Bad
throw new Error("Oops! Sorry, we couldn't process your image. Try a different file type");
```

### 9.3 Store Error Handling

Stores MUST handle errors gracefully:

```typescript
async function loadRecent(limit: number = 20) {
  loading = true;
  error = null;
  try {
    events = await service.getRecentEvents(limit);
  } catch (e) {
    error = e instanceof Error ? e.message : 'Failed to load events';
  } finally {
    loading = false;
  }
}
```

---

## 10. Styling

### 10.1 Tailwind CSS

All styling MUST use Tailwind CSS utility classes. Custom CSS is not permitted.

### 10.2 Brand Colours

```css
/* Brand accent: neon green */
--brand-accent: #63ff00;

/* Brand background: dark teal */
--brand-bg: #064e3b;

/* Primary background: gray-950 */
--bg-primary: #0a0a0a;
```

### 10.3 Component Variants

UI components MUST support variants via props:

```typescript
interface Props {
  variant?: 'primary' | 'secondary' | 'danger';
  size?: 'sm' | 'md' | 'lg';
}

const variantStyles = {
  primary: 'bg-brand-accent text-gray-900 hover:bg-brand-accent/90',
  secondary: 'bg-gray-700 text-white hover:bg-gray-600',
  danger: 'bg-red-600 text-white hover:bg-red-500'
};
```

### 10.4 Mobile-First

All components MUST be mobile-first:
- Support touch-friendly interaction sizes
- Use `env(safe-area-inset-bottom)` for bottom navigation
- Test on mobile viewports first
- Ensure over-scrolling up and down is not allowed

---

## 11. Factory Pattern

### 11.1 AI Provider Factory

Multiple provider implementations MUST be managed via factories:

```typescript
export function createFoodService(
  provider: AIProvider,
  settings: UserSettings
): IFoodRecognitionService | null {
  switch (provider) {
    case 'claude':
      return settings.claudeApiKey
        ? new ClaudeFoodService(settings.claudeApiKey)
        : null;
    case 'openai':
      return settings.openaiApiKey
        ? new OpenAIFoodService(settings.openaiApiKey)
        : null;
    // ...
  }
}
```

### 11.2 Fallback Chains

Services SHOULD support fallback chains:

```typescript
export async function recogniseFoodWithFallback(
  image: Blob,
  settings: UserSettings
): Promise<FoodRecognitionResult> {
  const providers: AIProvider[] = ['claude', 'openai', 'gemini'];

  for (const provider of providers) {
    const service = createFoodService(provider, settings);
    if (service?.isConfigured()) {
      try {
        return await service.RecogniseFood(image);
      } catch (e) {
        console.warn(`${provider} failed, trying next...`);
      }
    }
  }

  throw new Error('No AI providers available');
}
```

---

## 12. Data Source Tracking

### 12.1 Provenance

Every event MUST track its data source:

```typescript
type MealDataSource = 'manual' | 'ai_image' | 'label_scan' | 'preset';
type BSLDataSource = 'manual' | 'cgm_import' | 'graph_extraction' | 'api';
type InsulinSource = 'manual' | 'import';
```

### 12.2 Metadata

Event metadata MUST include source information:

```typescript
interface MealMetadata {
  source: MealDataSource;
  items: FoodItem[];
  totalCarbs: number;
  // ...
}
```

---

## 13. Testing

### 13.1 Repository Mocking

Tests MUST use mock repository implementations:

```typescript
class MockEventRepository implements IEventRepository {
  private events: PhysiologicalEvent[] = [];

  async create(input: CreateEventInput): Promise<PhysiologicalEvent> {
    const event = { ...input, id: crypto.randomUUID() };
    this.events.push(event);
    return event;
  }
}
```

### 13.2 Service Testing

Services MUST be testable independently of framework:

```typescript
describe('EventService', () => {
  let service: EventService;
  let mockRepo: MockEventRepository;

  beforeEach(() => {
    mockRepo = new MockEventRepository();
    service = new EventService(mockRepo);
  });

  it('creates events', async () => {
    const event = await service.logInsulin(5, 'bolus');
    expect(event.value).toBe(5);
  });
});
```

---

## 14. Documentation

### 14.1 JSDoc Comments

Services and complex functions MUST have JSDoc comments:

```typescript
/**
 * Business logic layer for physiological events
 * Framework-agnostic - returns Promises, no Svelte imports
 */
export class EventService {
  /**
   * Log a BSL reading
   * @param value - BSL value in mmol/L
   * @param unit - Unit of measurement (always mmol/L)
   * @param timestamp - When the reading was taken
   * @param options - Additional metadata options
   */
  async logBSL(
    value: number,
    unit: BSLUnit = 'mmol/L',
    timestamp: Date = new Date(),
    options?: BSLOptions
  ): Promise<PhysiologicalEvent> {
    // ...
  }
}
```

### 14.2 Component Comments

Components MUST have a brief description:

```svelte
<script lang="ts">
  /**
   * Button Component
   *
   * A reusable button component with primary, secondary, and danger variants.
   */
</script>
```

---

## 15. Configuration

### 15.1 Environment Variables

Server-side secrets MUST use environment variables with `VITE_` prefix for client-side:

```bash
# Server-side only
COSMOS_ENDPOINT=https://...
COSMOS_KEY=...

# Client-side accessible
VITE_OPENAI_API_KEY=...
```

### 15.2 Settings Merge

User settings MUST merge with environment defaults:

```typescript
export function mergeWithEnvSettings(userSettings: UserSettings): UserSettings {
  const envSettings = getEnvSettings();
  return {
    ...userSettings,
    openaiApiKey: userSettings.openaiApiKey || envSettings.openaiApiKey,
    // User settings take precedence
  };
}
```

---

## 16. Formatting

### 16.1 Prettier Config

```json
{
  "useTabs": true,
  "tabWidth": 2,
  "singleQuote": true,
  "trailingComma": "none",
  "printWidth": 100
}
```

### 16.2 Import Order

Imports MUST be ordered:
1. Svelte imports
2. External library imports
3. Internal type imports (`$lib/types`)
4. Internal module imports (`$lib/services`, `$lib/stores`)
5. Relative imports

```typescript
import type { Snippet } from 'svelte';
import { z } from 'zod';

import type { MacroData, EventType } from '$lib/types';
import type { IEventRepository } from '$lib/repositories';

import { eventsStore } from '$lib/stores';
import { EventService } from '$lib/services';

import { localHelper } from './helpers';
```

---

## Revision History

| Date | Author | Changes |
|------|--------|---------|
| 2025-01-28 | Initial | Core principles established |
| 2025-02-03 | Claude | Expanded with full coding conventions |
