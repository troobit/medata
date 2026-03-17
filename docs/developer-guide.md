# MeData Developer Guide

**Version:** 1.0
**Last Updated:** 2026-02-10
**Target Audience:** Developers with backend experience (Python, Terraform, Azure) who are new to web frontend and Svelte

---

## Table of Contents

1. [Project Overview](#1-project-overview)
2. [Technology Stack](#2-technology-stack)
3. [Project Structure](#3-project-structure)
4. [Svelte 5 Fundamentals](#4-svelte-5-fundamentals)
5. [AI Integration Architecture](#5-ai-integration-architecture)
6. [Component Architecture](#6-component-architecture)
7. [Adding a New AI Provider (Tutorial)](#7-adding-a-new-ai-provider-tutorial)
8. [Data Flow Walkthrough](#8-data-flow-walkthrough)
9. [Common Development Tasks](#9-common-development-tasks)
10. [Testing](#10-testing)
11. [Related Documentation](#11-related-documentation)

---

## 1. Project Overview

MeData is a personal health tracking app for Type 1 diabetes management. The core feature is **photo-based food macro estimation**: photograph a meal, AI identifies the food and estimates carbohydrates/protein/fat, then the user saves this data.

### Key Concepts

| Term | Definition |
|------|------------|
| **Macros** | Macronutrients - carbohydrates, protein, and fat measured in grams |
| **BSL** | Blood Sugar Level (measured in mmol/L in Australia/UK) |
| **Meal** | A logged food event with timestamp, food items, and total macros |
| **Preset** | A saved meal template for quick re-logging (e.g., "Morning Oatmeal") |

### Design Philosophy

From the project constitution (`specs/constitution.md`):
- **Data Ownership**: Users can export, delete, and control all their data
- **Simplicity**: Quick inputs, minimal friction (especially on mobile)
- **No Paternalism**: No health warnings or disclaimers - the user is medically informed
- **Irish English**: Use colour, behaviour, analyse, recognise (not US spellings)

---

## 2. Technology Stack

| Layer | Technology | Python Equivalent |
|-------|------------|-------------------|
| **Framework** | SvelteKit 2.x | Flask/FastAPI + Jinja |
| **UI Library** | Svelte 5 | (no direct equivalent) |
| **Language** | TypeScript 5.x | Python with type hints |
| **Styling** | Tailwind CSS 4.x | Bootstrap classes |
| **Database** | Azure Cosmos DB | CosmosDB SDK |
| **Blob Storage** | Azure Blob Storage | Azure Storage SDK |
| **Validation** | Zod | Pydantic |
| **Build Tool** | Vite | (bundler, no Python equiv) |
| **Package Manager** | pnpm | pip/poetry |

### Mental Model for Python Developers

Think of SvelteKit as combining:
- **Flask/FastAPI** (API routes in `src/routes/api/`)
- **Jinja templates** (but reactive - UI updates automatically when data changes)
- **A build system** (compiles everything to optimised JavaScript)

The key difference: Svelte components are **reactive**. When you change a variable, the UI updates automatically. No manual DOM manipulation.

---

## 3. Project Structure

```
src/
├── lib/                          # Shared code (not routes)
│   ├── components/               # UI components (*.svelte files)
│   │   ├── CameraCapture.svelte
│   │   ├── FoodRecognitionResult.svelte
│   │   ├── MealEditor.svelte
│   │   └── index.ts              # Barrel export
│   ├── services/                 # Business logic (framework-agnostic)
│   │   ├── food-recognition.ts   # Interface definition
│   │   ├── claude-food-recognition.ts  # Claude implementation
│   │   └── index.ts
│   ├── repositories/             # Data access abstraction
│   │   ├── meal-repository.ts    # Interface
│   │   ├── cosmos-meal-repository.ts  # Cosmos implementation
│   │   └── index.ts
│   ├── types/                    # TypeScript type definitions
│   │   ├── meal.ts
│   │   └── index.ts
│   ├── schemas/                  # Zod validation schemas
│   │   ├── meal.ts
│   │   └── index.ts
│   ├── stores/                   # Reactive state (Svelte 5 runes)
│   │   └── toast.svelte.ts
│   └── utils/                    # Pure utility functions
│       └── macros.ts
├── routes/                       # SvelteKit file-based routing
│   ├── +page.svelte              # Home page (/)
│   ├── +layout.svelte            # Root layout (wraps all pages)
│   ├── capture/
│   │   └── +page.svelte          # /capture route
│   ├── manual/
│   │   └── +page.svelte          # /manual route
│   └── api/                      # Server-side API endpoints
│       ├── meals/
│       │   ├── +server.ts        # POST /api/meals
│       │   └── [id]/
│       │       └── +server.ts    # GET/PUT/DELETE /api/meals/:id
│       └── ai/
│           └── recognise/
│               └── +server.ts    # POST /api/ai/recognise
├── app.html                      # HTML shell
├── app.css                       # Global styles
└── app.d.ts                      # Global TypeScript declarations
```

### Key Directories

| Directory | Purpose | Terraform Analogy |
|-----------|---------|-------------------|
| `src/lib/services/` | Business logic, provider implementations | Provider implementations |
| `src/lib/repositories/` | Data access abstraction | Backend configurations |
| `src/lib/types/` | Type definitions | Variable type definitions |
| `src/routes/api/` | HTTP endpoints | (API Gateway handlers) |
| `src/routes/*.svelte` | Page components | (UI, no direct analogy) |

---

## 4. Svelte 5 Fundamentals

### 4.1 Component Structure

A Svelte component is a single `.svelte` file with three sections:

```svelte
<!-- MyComponent.svelte -->
<script lang="ts">
    // TypeScript code - runs when component mounts

    // Props (inputs from parent) - like function arguments
    interface Props {
        name: string;
        onSave: (data: string) => void;
    }
    let { name, onSave }: Props = $props();

    // Reactive state - like a mutable variable that triggers UI updates
    let count = $state(0);

    // Derived value - like a computed property, auto-recalculates
    let doubled = $derived(count * 2);

    // Functions
    function increment() {
        count += 1;  // UI automatically updates!
    }

    // Effect - runs when dependencies change (like useEffect in React)
    $effect(() => {
        console.log(`Count is now ${count}`);
        return () => { /* cleanup function */ };
    });
</script>

<!-- Template - HTML with Svelte syntax -->
<div>
    <h1>Hello {name}</h1>
    <p>Count: {count}, Doubled: {doubled}</p>
    <button onclick={increment}>Increment</button>
</div>

<style>
    /* Scoped CSS - only applies to this component */
    h1 { color: green; }
</style>
```

### 4.2 Svelte 5 Runes (Key Syntax)

| Rune | Purpose | Python Analogy |
|------|---------|----------------|
| `$state(value)` | Reactive variable | Mutable variable |
| `$derived(expr)` | Computed value | `@property` with caching |
| `$props()` | Component inputs | Function parameters |
| `$effect(() => {})` | Side effect on change | `@observe` decorator |
| `$bindable()` | Two-way binding | Mutable reference |

### 4.3 Template Syntax

```svelte
<!-- Conditionals -->
{#if condition}
    <p>True case</p>
{:else if otherCondition}
    <p>Other case</p>
{:else}
    <p>Fallback</p>
{/if}

<!-- Loops (key is important for performance) -->
{#each items as item (item.id)}
    <span>{item.name}</span>
{/each}

<!-- Await blocks (for promises) -->
{#await promise}
    <p>Loading...</p>
{:then value}
    <p>Result: {value}</p>
{:catch error}
    <p>Error: {error.message}</p>
{/await}

<!-- Event handlers -->
<button onclick={handleClick}>Click me</button>
<input onchange={handleChange} />

<!-- Binding (two-way) -->
<input bind:value={name} />

<!-- Component composition -->
<ChildComponent prop={value} onEvent={handler} />
```

### 4.4 SvelteKit Routing

Routes are defined by file structure:

| File Path | Route URL |
|-----------|-----------|
| `src/routes/+page.svelte` | `/` |
| `src/routes/about/+page.svelte` | `/about` |
| `src/routes/meals/[id]/+page.svelte` | `/meals/:id` (dynamic) |
| `src/routes/api/meals/+server.ts` | `POST/GET /api/meals` |

**API Routes** (`+server.ts`) are server-side only:

```typescript
// src/routes/api/meals/+server.ts
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';

export const GET: RequestHandler = async ({ params }) => {
    // This runs on the server, never in the browser
    return json({ data: 'hello' });
};

export const POST: RequestHandler = async ({ request }) => {
    const body = await request.json();
    // Validate, save to database, etc.
    return json({ success: true });
};
```

---

## 5. AI Integration Architecture

### 5.1 Overview

The AI integration follows a **three-layer architecture**:

```
┌─────────────────────────────────────────────────────────────────────┐
│  Browser (Client)                                                   │
│  capture/+page.svelte → fetch('/api/ai/recognise')                  │
└───────────────────────────────────┬─────────────────────────────────┘
                                    │ HTTP POST (JSON)
┌───────────────────────────────────▼─────────────────────────────────┐
│  API Route (Server)                                                 │
│  src/routes/api/ai/recognise/+server.ts                             │
│  - Validates request with Zod                                       │
│  - Instantiates the appropriate service                             │
│  - Returns structured response or HTTP error                        │
└───────────────────────────────────┬─────────────────────────────────┘
                                    │ Method call
┌───────────────────────────────────▼─────────────────────────────────┐
│  Service Layer                                                      │
│  src/lib/services/claude-food-recognition.ts                        │
│  - Contains the AI prompts                                          │
│  - Calls the AI provider's SDK                                      │
│  - Parses response, handles errors                                  │
└───────────────────────────────────┬─────────────────────────────────┘
                                    │ HTTPS
┌───────────────────────────────────▼─────────────────────────────────┐
│  External AI Provider                                               │
│  api.anthropic.com (Claude)                                         │
└─────────────────────────────────────────────────────────────────────┘
```

### 5.2 File Responsibilities

#### Interface: `src/lib/services/food-recognition.ts`

Defines the contract that **any** AI provider must implement:

```typescript
// Like a Python ABC (Abstract Base Class)
export interface IFoodRecognitionService {
    /**
     * Recognise food items in an image.
     * @param image - The food image as a Blob
     * @param labelContext - Optional nutrition label image
     * @returns Recognition result with food items and macros
     */
    recognise(image: Blob, labelContext?: LabelContext): Promise<FoodRecognitionResult>;

    /** Check if API key is configured */
    isConfigured(): boolean;

    /** Get provider name for logging/display */
    getProviderName(): string;
}

// Error types for consistent error handling
export type FoodRecognitionErrorCode =
    | 'TIMEOUT'        // 10-second timeout exceeded
    | 'AI_FAILURE'     // AI service error
    | 'NO_ITEMS'       // No food detected in image
    | 'NOT_CONFIGURED' // API key missing
    | 'INVALID_IMAGE'; // Bad image format

export class FoodRecognitionError extends Error {
    constructor(
        public readonly code: FoodRecognitionErrorCode,
        message: string
    ) {
        super(message);
        this.name = 'FoodRecognitionError';
    }
}
```

#### Implementation: `src/lib/services/claude-food-recognition.ts`

The Claude-specific implementation:

```typescript
export class ClaudeFoodRecognitionService implements IFoodRecognitionService {
    private client: Anthropic | null = null;
    private readonly timeout = 10000; // 10 seconds

    constructor() {
        const apiKey = env['ANTHROPIC_API_KEY'];
        if (apiKey) {
            this.client = new Anthropic({ apiKey });
        }
    }

    isConfigured(): boolean {
        return this.client !== null;
    }

    getProviderName(): string {
        return 'claude';
    }

    async recognise(image: Blob, labelContext?: LabelContext): Promise<FoodRecognitionResult> {
        // 1. Build message content (images first, then prompt)
        // 2. Call Claude API with timeout
        // 3. Parse JSON response
        // 4. Transform to FoodRecognitionResult
        // 5. Handle errors appropriately
    }
}
```

**Key sections to know:**

| Lines | Content | When to Edit |
|-------|---------|--------------|
| 19-66 | `FOOD_RECOGNITION_PROMPT` | Change how AI identifies food |
| 68-125 | `FOOD_RECOGNITION_WITH_LABEL_PROMPT` | Change label scanning behaviour |
| 128-154 | `FOOD_RECOGNITION_SCHEMA` | Add/modify response fields |
| 269 | `model: 'claude-sonnet-4-5-20250514'` | Change Claude model |
| 201 | `timeout = 10000` | Change timeout duration |

#### API Route: `src/routes/api/ai/recognise/+server.ts`

HTTP endpoint that bridges browser and service:

```typescript
import { json, error } from '@sveltejs/kit';
import { z } from 'zod/v4';
import { ClaudeFoodRecognitionService } from '$lib/services/claude-food-recognition.js';
import { FoodRecognitionError } from '$lib/services/food-recognition.js';

// Zod schema validates incoming requests
const RecogniseRequestSchema = z.object({
    imageBase64: z.string().min(1),
    mimeType: z.enum(['image/jpeg', 'image/png']),
    labelBase64: z.string().optional(),
    labelMimeType: z.enum(['image/jpeg', 'image/png']).optional()
});

export const POST: RequestHandler = async ({ request }) => {
    // 1. Parse and validate request body
    const body = await request.json();
    const parseResult = RecogniseRequestSchema.safeParse(body);
    if (!parseResult.success) {
        return error(400, { message: 'Invalid request' });
    }

    // 2. Create service instance
    const service = new ClaudeFoodRecognitionService();

    // 3. Check configuration
    if (!service.isConfigured()) {
        return error(503, { message: 'AI recognition unavailable.' });
    }

    // 4. Perform recognition
    try {
        const result = await service.recognise(foodImage, labelContext);
        return json({ data: result });
    } catch (e) {
        // 5. Map errors to HTTP status codes
        if (e instanceof FoodRecognitionError) {
            switch (e.code) {
                case 'TIMEOUT': return error(504, { message: e.message });
                case 'NO_ITEMS': return error(422, { message: e.message });
                default: return error(502, { message: e.message });
            }
        }
        return error(500, { message: 'Recognition failed.' });
    }
};
```

### 5.3 AI Prompt Design

The prompts are documented in detail in `specs/ai-prompt-design.md`. Key points:

**Prompt Structure:**
1. Role definition ("You are a nutrition analysis assistant...")
2. Context (diabetes management, carb accuracy needed)
3. Step-by-step instructions
4. Output format specification (JSON schema)
5. Examples of expected output

**Portion Estimation Guidelines** (from prompt):
- Closed fist ≈ 1 cup (240ml)
- Palm (no fingers) ≈ 85g protein
- Thumb tip ≈ 1 tablespoon (15ml)
- Standard dinner plate ≈ 26cm diameter

**Confidence Scoring:**
- 0.8+ = High confidence (clearly visible, standard portion)
- 0.5-0.8 = Medium (partially obscured, unusual container)
- <0.5 = Low (blurry, unidentifiable)

### 5.4 Response Schema

The AI must return this JSON structure:

```json
{
    "items": [
        {
            "name": "Grilled chicken breast",
            "quantity": 150,
            "unit": "g",
            "carbs": 0,
            "protein": 35,
            "fat": 5,
            "confidence": 0.85,
            "servingsEstimated": null
        }
    ],
    "overallConfidence": 0.85,
    "notes": "Optional observations about the meal"
}
```

---

## 6. Component Architecture

### 6.1 Capture Flow State Machine

The photo capture flow is implemented as a **state machine** in `src/routes/capture/+page.svelte`:

```
                    ┌─────────────┐
                    │   capture   │ Initial state
                    └──────┬──────┘
                           │ Photo taken
                    ┌──────▼──────┐
                    │   preview   │ Show photo, confirm/retake
                    └──────┬──────┘
                           │ Confirmed
                    ┌──────▼──────┐
                    │ recognising │ Loading spinner
                    └──────┬──────┘
                           │
            ┌──────────────┼──────────────┐
            │ Success      │              │ Error
     ┌──────▼──────┐       │       ┌──────▼──────┐
     │   results   │       │       │    error    │
     └──────┬──────┘       │       └──────┬──────┘
            │ Confirmed    │              │ Retry/Manual
            │              │              │
     ┌──────▼──────┐       │              │
     │   editing   │◄──────┴──────────────┘
     └──────┬──────┘
            │ Save
            ▼
     (Navigate to home)
```

Each state renders a different component:

| State | Component | Responsibility |
|-------|-----------|----------------|
| `capture` | `CameraCapture.svelte` | Camera access, photo taking |
| `preview` | `ImagePreview.svelte` | Show captured photo |
| `recognising` | (inline spinner) | Loading state |
| `results` | `FoodRecognitionResult.svelte` | Display AI results |
| `error` | `AIErrorFallback.svelte` | Error handling |
| `editing` | `MealEditor.svelte` | Edit and save meal |

### 6.2 Component Communication

Components communicate via **props** (parent→child) and **callbacks** (child→parent):

```svelte
<!-- Parent: capture/+page.svelte -->
<script lang="ts">
    let flowState = $state<FlowState>('capture');
    let capturedImage: Blob | null = $state(null);

    function handleCapture(result: CaptureResult) {
        capturedImage = result.foodImage;
        flowState = 'preview';  // State transition
    }
</script>

<!-- Pass callback as prop -->
<CameraCapture onCapture={handleCapture} onCancel={handleCancel} />
```

```svelte
<!-- Child: CameraCapture.svelte -->
<script lang="ts">
    interface Props {
        onCapture: (result: CaptureResult) => void;
        onCancel?: () => void;
    }
    let { onCapture, onCancel }: Props = $props();

    function capturePhoto() {
        // ... capture logic ...
        onCapture({ foodImage: blob, source: 'camera' });  // Call parent
    }
</script>
```

### 6.3 Key Components

#### CameraCapture.svelte
- Uses `navigator.mediaDevices.getUserMedia()` for camera access
- Captures to `<canvas>` then converts to Blob
- Supports gallery upload as fallback
- Optionally captures nutrition label (second image)

#### FoodRecognitionResult.svelte
- Displays AI-identified food items
- Shows confidence badges (green/yellow/red)
- Calculates and shows total macros
- Actions: Use Results, Retry, Manual Entry

#### MealEditor.svelte
- Editable list of food items
- Auto-recalculates totals when items change
- Timestamp picker (defaults to now)
- Save as preset option
- Uses `$derived` for reactive totals

#### FoodItemCard.svelte
- Individual food item display
- Inline editing of name and macros
- Delete button
- Confidence indicator (if from AI)

---

## 7. Adding a New AI Provider (Tutorial)

This step-by-step guide shows how to add Google Gemini as an AI provider.

### Step 1: Create the Service File

Create `src/lib/services/gemini-food-recognition.ts`:

```typescript
/**
 * Gemini food recognition service implementation.
 * Implements IFoodRecognitionService interface.
 */
import {
    type IFoodRecognitionService,
    type FoodRecognitionResult,
    type LabelContext,
    FoodRecognitionError
} from './food-recognition.js';
import type { RecognisedFoodItem, MacroData } from '$lib/types/index.js';
import { sumMacros } from '$lib/utils/index.js';
import { env } from '$env/dynamic/private';

// Import Gemini SDK (you'll need to: pnpm add @google/generative-ai)
import { GoogleGenerativeAI } from '@google/generative-ai';

// Prompt template - same structure as Claude, adjust wording if needed
const FOOD_RECOGNITION_PROMPT = `You are a nutrition analysis assistant helping a person with Type 1 diabetes track their food intake. Your task is to identify foods in the image and estimate macronutrients as accurately as possible.

CONTEXT:
- The user needs accurate carbohydrate estimates for insulin dosing
- Precision matters more than conservative estimates
- The user is medically informed and does not need health disclaimers

ANALYSIS INSTRUCTIONS:

1. IDENTIFY each distinct food item visible in the image
2. ESTIMATE the portion size using visual cues:
   - Standard plate sizes (dinner plate ~26cm, side plate ~15cm)
   - Common reference objects if visible (cutlery, hands, cups)
   - Typical serving sizes for the identified food
3. CALCULATE macronutrients for each item based on portion estimate
4. ASSIGN a confidence score (0-1) reflecting:
   - Clarity of food identification (0.9+ if clearly visible)
   - Portion estimation certainty (reduce if size unclear)
   - Food preparation uncertainty (reduce if cooking method unclear)

OUTPUT FORMAT:
Return ONLY valid JSON matching this structure:
{
  "items": [
    {
      "name": "Food name",
      "quantity": 150,
      "unit": "g",
      "carbs": 25,
      "protein": 8,
      "fat": 12,
      "confidence": 0.85,
      "servingsEstimated": null
    }
  ],
  "overallConfidence": 0.85,
  "notes": "Optional observations"
}

All macro values in grams. Confidence between 0 and 1.`;

// Response type from Gemini (matches our expected structure)
interface GeminiRecognitionResponse {
    items: Array<{
        name: string;
        quantity: number;
        unit: string;
        carbs: number;
        protein: number;
        fat: number;
        confidence: number;
        servingsEstimated: number | null;
    }>;
    overallConfidence: number;
    notes?: string;
}

/**
 * Convert a Blob to base64 string.
 */
async function blobToBase64(blob: Blob): Promise<string> {
    const buffer = await blob.arrayBuffer();
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]!);
    }
    return btoa(binary);
}

/**
 * Gemini food recognition service.
 */
export class GeminiFoodRecognitionService implements IFoodRecognitionService {
    private client: GoogleGenerativeAI | null = null;
    private readonly timeout = 10000; // 10-second timeout

    constructor() {
        const apiKey = env['GEMINI_API_KEY'];
        if (apiKey) {
            this.client = new GoogleGenerativeAI(apiKey);
        }
    }

    isConfigured(): boolean {
        return this.client !== null;
    }

    getProviderName(): string {
        return 'gemini';
    }

    async recognise(image: Blob, labelContext?: LabelContext): Promise<FoodRecognitionResult> {
        if (!this.client) {
            throw new FoodRecognitionError('NOT_CONFIGURED', 'Gemini API key not configured.');
        }

        const startTime = Date.now();
        console.log(`[gemini] Starting recognition - image: ${(image.size / 1024).toFixed(1)}KB`);

        try {
            // Get the generative model
            const model = this.client.getGenerativeModel({ model: 'gemini-1.5-flash' });

            // Convert image to base64
            const imageBase64 = await blobToBase64(image);
            const mimeType = image.type || 'image/jpeg';

            // Build parts array
            const parts: Array<{ text: string } | { inlineData: { mimeType: string; data: string } }> = [
                {
                    inlineData: {
                        mimeType,
                        data: imageBase64
                    }
                }
            ];

            // Add label image if provided
            if (labelContext?.labelImage) {
                const labelBase64 = await blobToBase64(labelContext.labelImage);
                parts.push({
                    inlineData: {
                        mimeType: labelContext.labelImage.type || 'image/jpeg',
                        data: labelBase64
                    }
                });
            }

            // Add prompt
            parts.push({ text: FOOD_RECOGNITION_PROMPT });

            // Create timeout controller
            const controller = new AbortController();
            const timeoutId = setTimeout(() => controller.abort(), this.timeout);

            // Call Gemini API
            const result = await model.generateContent(parts);
            clearTimeout(timeoutId);

            const response = result.response;
            const text = response.text();

            const apiTime = Date.now() - startTime;
            console.log(`[gemini] API response received in ${apiTime}ms`);

            // Parse JSON response
            let parsed: GeminiRecognitionResponse;
            try {
                // Try to extract JSON from the response (may be wrapped in markdown)
                let jsonText = text;
                const jsonMatch = jsonText.match(/```(?:json)?\s*([\s\S]*?)```/);
                if (jsonMatch && jsonMatch[1]) {
                    jsonText = jsonMatch[1].trim();
                }
                parsed = JSON.parse(jsonText);
            } catch {
                throw new FoodRecognitionError('AI_FAILURE', 'Invalid JSON response from AI.');
            }

            // Check for no items
            if (!parsed.items || parsed.items.length === 0) {
                throw new FoodRecognitionError(
                    'NO_ITEMS',
                    'No food items recognised. Retry or enter manually.'
                );
            }

            // Transform response to our format
            const items: RecognisedFoodItem[] = parsed.items.map((item) => ({
                name: item.name,
                quantity: item.quantity,
                unit: item.unit,
                carbs: Math.max(0, item.carbs),
                protein: Math.max(0, item.protein),
                fat: Math.max(0, item.fat),
                confidence: Math.min(1, Math.max(0, item.confidence))
            }));

            const totalMacros: MacroData = sumMacros(items);
            const processingTimeMs = Date.now() - startTime;

            console.log(`[gemini] Recognition complete in ${processingTimeMs}ms - ${items.length} item(s)`);

            return {
                items,
                totalMacros,
                confidence: Math.min(1, Math.max(0, parsed.overallConfidence)),
                provider: this.getProviderName(),
                processingTimeMs
            };
        } catch (error) {
            const elapsed = Date.now() - startTime;
            console.error(`[gemini] Recognition failed after ${elapsed}ms:`, error);

            // Handle timeout
            if (error instanceof Error && error.name === 'AbortError') {
                throw new FoodRecognitionError(
                    'TIMEOUT',
                    'Recognition timed out. Try again or enter manually.'
                );
            }

            // Re-throw FoodRecognitionErrors
            if (error instanceof FoodRecognitionError) {
                throw error;
            }

            // Wrap other errors
            throw new FoodRecognitionError(
                'AI_FAILURE',
                error instanceof Error ? error.message : 'AI recognition unavailable.'
            );
        }
    }
}
```

### Step 2: Add Environment Variable

Add to `.env.example` and `.env.local`:

```bash
# AI Provider Configuration
ANTHROPIC_API_KEY=sk-ant-...
GEMINI_API_KEY=your-gemini-api-key-here

# Which provider to use: 'claude' or 'gemini'
AI_PROVIDER=claude
```

### Step 3: Update the API Route

Modify `src/routes/api/ai/recognise/+server.ts` to support provider selection:

```typescript
import { json, error } from '@sveltejs/kit';
import type { RequestHandler } from './$types';
import { z } from 'zod/v4';
import { ClaudeFoodRecognitionService } from '$lib/services/claude-food-recognition.js';
import { GeminiFoodRecognitionService } from '$lib/services/gemini-food-recognition.js';
import { FoodRecognitionError, type IFoodRecognitionService } from '$lib/services/food-recognition.js';
import { env } from '$env/dynamic/private';

const RecogniseRequestSchema = z.object({
    imageBase64: z.string().min(1),
    mimeType: z.enum(['image/jpeg', 'image/png']),
    labelBase64: z.string().optional(),
    labelMimeType: z.enum(['image/jpeg', 'image/png']).optional()
});

/**
 * Create the appropriate AI service based on configuration.
 */
function createService(): IFoodRecognitionService {
    const provider = env['AI_PROVIDER'] || 'claude';

    switch (provider) {
        case 'gemini':
            return new GeminiFoodRecognitionService();
        case 'claude':
        default:
            return new ClaudeFoodRecognitionService();
    }
}

function base64ToBlob(base64: string, mimeType: string): Blob {
    const binaryString = atob(base64);
    const bytes = new Uint8Array(binaryString.length);
    for (let i = 0; i < binaryString.length; i++) {
        bytes[i] = binaryString.charCodeAt(i);
    }
    return new Blob([bytes], { type: mimeType });
}

export const POST: RequestHandler = async ({ request }) => {
    // Parse and validate
    let body: unknown;
    try {
        body = await request.json();
    } catch {
        return error(400, { message: 'Invalid JSON in request body.' });
    }

    const parseResult = RecogniseRequestSchema.safeParse(body);
    if (!parseResult.success) {
        const firstError = parseResult.error.issues[0];
        return error(400, {
            message: `${firstError?.path.join('.') || 'Input'} is invalid.`
        });
    }

    const { imageBase64, mimeType, labelBase64, labelMimeType } = parseResult.data;

    // Create service based on configuration
    const service = createService();

    if (!service.isConfigured()) {
        return error(503, {
            message: 'AI recognition unavailable. Enter macros manually.'
        });
    }

    // Convert images
    let foodImage: Blob;
    try {
        foodImage = base64ToBlob(imageBase64, mimeType);
    } catch {
        return error(400, { message: 'Invalid image data.' });
    }

    let labelContext: { labelImage: Blob } | undefined;
    if (labelBase64 && labelMimeType) {
        try {
            labelContext = { labelImage: base64ToBlob(labelBase64, labelMimeType) };
        } catch {
            return error(400, { message: 'Invalid label image data.' });
        }
    }

    // Perform recognition
    try {
        const result = await service.recognise(foodImage, labelContext);
        return json({ data: result });
    } catch (e) {
        if (e instanceof FoodRecognitionError) {
            switch (e.code) {
                case 'TIMEOUT':
                    return error(504, { message: e.message });
                case 'NO_ITEMS':
                    return error(422, { message: e.message });
                case 'NOT_CONFIGURED':
                    return error(503, { message: e.message });
                case 'INVALID_IMAGE':
                    return error(400, { message: e.message });
                default:
                    return error(502, { message: e.message });
            }
        }

        console.error('Food recognition error:', e);
        return error(500, { message: 'Recognition failed. Try again.' });
    }
};
```

### Step 4: Export from Index

Update `src/lib/services/index.ts`:

```typescript
export * from './food-recognition.js';
export * from './claude-food-recognition.js';
export * from './gemini-food-recognition.js';
export * from './meal-api.js';
export * from './preset-api.js';
```

### Step 5: Install Dependencies

```bash
pnpm add @google/generative-ai
```

### Step 6: Test

1. Set `AI_PROVIDER=gemini` in `.env.local`
2. Set your `GEMINI_API_KEY`
3. Run `pnpm dev`
4. Navigate to `/capture` and test with a food photo

### Summary: Files Changed

| File | Change |
|------|--------|
| `src/lib/services/gemini-food-recognition.ts` | **NEW** - Provider implementation |
| `src/lib/services/index.ts` | Export new service |
| `src/routes/api/ai/recognise/+server.ts` | Add provider selection logic |
| `.env.example` | Add new env vars |
| `.env.local` | Configure API key |
| `package.json` | Add dependency (via pnpm) |

---

## 8. Data Flow Walkthrough

### Complete Flow: Photo to Saved Meal

```
1. User taps "Capture" button on home page
   └── Navigate to /capture

2. CameraCapture component
   └── getUserMedia() → video stream
   └── User taps "Take Photo"
   └── canvas.toBlob() → Blob
   └── onCapture({ foodImage: Blob })

3. capture/+page.svelte (state: preview → recognising)
   └── blobToBase64(image)
   └── fetch('/api/ai/recognise', { body: { imageBase64, mimeType } })

4. +server.ts (API route)
   └── Zod validation
   └── new ClaudeFoodRecognitionService()
   └── service.recognise(image)

5. ClaudeFoodRecognitionService
   └── Build message content [image, prompt]
   └── client.messages.create({ model, messages })
   └── Parse JSON response
   └── Return FoodRecognitionResult

6. +server.ts
   └── return json({ data: result })

7. capture/+page.svelte (state: results)
   └── FoodRecognitionResult component displays items
   └── User taps "Use These Results"
   └── onConfirm(items)

8. capture/+page.svelte (state: editing)
   └── MealEditor component
   └── User can edit items, adjust macros
   └── totals = $derived(sumMacros(items)) - auto-updates
   └── User taps "Save Meal"
   └── onSave(meal)

9. capture/+page.svelte
   └── fetch('/api/meals', { body: CreateMealInput })

10. /api/meals/+server.ts
    └── Validate with Zod
    └── mealRepository.save(meal)
    └── Return success

11. capture/+page.svelte
    └── toastStore.success('Meal saved')
    └── goto('/') - navigate home
```

---

## 9. Common Development Tasks

### Where to Edit for Common Tasks

| Task | File(s) | Notes |
|------|---------|-------|
| Change AI prompt | `src/lib/services/claude-food-recognition.ts` | Lines 19-125 |
| Change AI model | `src/lib/services/claude-food-recognition.ts` | Line 269 |
| Add AI response field | `claude-food-recognition.ts` + `types/meal.ts` | Schema + type |
| Change button colours | Component `.svelte` files | Look for `bg-brand-accent` |
| Change error messages | `src/lib/components/AIErrorFallback.svelte` | |
| Add new page | Create `src/routes/<name>/+page.svelte` | |
| Add new API endpoint | Create `src/routes/api/<name>/+server.ts` | |
| Add new data type | `src/lib/types/meal.ts` + `src/lib/schemas/meal.ts` | |
| Change validation rules | `src/lib/schemas/*.ts` | Zod schemas |
| Change loading spinner | `src/routes/capture/+page.svelte` | Lines 269-277 |
| Add new component | Create in `src/lib/components/` | Export from `index.ts` |

### Getting Started

1. **Clone and install:**
   ```bash
   git clone <repo-url> && cd medata
   pnpm install
   ```

2. **Copy environment file:**
   ```bash
   cp .env.example .env
   ```

3. **Configure food recognition backend** — choose one:

   **Option A — Local Ollama (free, no account needed):**
   ```bash
   # Install Ollama: https://ollama.com
   # Pull a vision model:
   ollama pull llava

   # .env settings:
   RECOGNITION_BASE_URL=http://localhost:11434
   RECOGNITION_MODEL=llava
   # RECOGNITION_API_KEY=        (not needed for local)
   RECOGNITION_MOCK_MODE=false
   RECOGNITION_TIMEOUT_MS=60000  # increase for large models on first inference
   ```

   **Option B — Cloud model (DeepSeek, Claude via proxy, etc.):**
   ```bash
   RECOGNITION_BASE_URL=https://api.deepseek.com
   RECOGNITION_MODEL=deepseek-chat
   RECOGNITION_API_KEY=sk-your-key-here
   RECOGNITION_MOCK_MODE=false
   RECOGNITION_TIMEOUT_MS=10000
   ```

   **Option C — Mock mode (no backend needed):**
   ```bash
   RECOGNITION_MOCK_MODE=true
   # All other RECOGNITION_* vars are ignored in mock mode.
   # Returns realistic fake food data with a simulated 500-1500ms delay.
   ```

4. **Azure credentials** (for data persistence):
   ```bash
   AZURE_COSMOS_CONNECTION_STRING=your-connection-string
   AZURE_BLOB_STORAGE_URL=your-blob-url-with-sas-token
   ```

5. **Start the dev server:**
   ```bash
   pnpm dev
   ```
   The server starts at **`https://localhost:5173`** (HTTPS is required for camera access).

6. **Mobile testing:**
   - Find your LAN IP: `ipconfig getifaddr en0` (macOS) or `hostname -I` (Linux)
   - On your phone, visit `https://192.168.x.x:5173`
   - Accept the self-signed certificate warning
   - Camera and all features work over LAN

> **Tip:** If using a large local model (Ollama 7B+), increase `RECOGNITION_TIMEOUT_MS` to `30000`-`60000`. First inference is slower while the model loads into memory.

### Running Commands

```bash
# Start dev server (hot reload, HTTPS)
pnpm dev

# Run tests
pnpm test

# Type checking
pnpm check

# Build for production
pnpm build
```

### Environment Variables

See `.env.example` for the full list with comments. Key variables:

| Variable | Required | Description |
|----------|----------|-------------|
| `RECOGNITION_BASE_URL` | Yes* | OpenAI-compatible endpoint URL |
| `RECOGNITION_MODEL` | Yes* | Model name for the endpoint |
| `RECOGNITION_API_KEY` | No | API key (omit for local endpoints) |
| `RECOGNITION_MOCK_MODE` | No | Set `true` to skip real API calls |
| `RECOGNITION_TIMEOUT_MS` | No | Request timeout, default 10000ms |
| `AZURE_COSMOS_CONNECTION_STRING` | Yes | Cosmos DB connection string |
| `AZURE_BLOB_STORAGE_URL` | Yes | Blob storage URL with SAS token |

*Not required when `RECOGNITION_MOCK_MODE=true`.

---

## 10. Testing

### Test Files

Tests use Vitest and live alongside source files:

```
src/lib/utils/macros.ts       # Source
src/lib/utils/macros.test.ts  # Test
```

### Running Tests

```bash
# Run all tests
pnpm test

# Run once (CI mode)
pnpm test:run

# Run specific file
pnpm test src/lib/utils/macros.test.ts
```

### Writing Tests

```typescript
// src/lib/services/food-recognition.test.ts
import { describe, it, expect, vi } from 'vitest';
import { ClaudeFoodRecognitionService } from './claude-food-recognition.js';

describe('ClaudeFoodRecognitionService', () => {
    it('returns false for isConfigured when no API key', () => {
        // Environment doesn't have ANTHROPIC_API_KEY
        const service = new ClaudeFoodRecognitionService();
        expect(service.isConfigured()).toBe(false);
    });

    it('returns "claude" for getProviderName', () => {
        const service = new ClaudeFoodRecognitionService();
        expect(service.getProviderName()).toBe('claude');
    });
});
```

---

## 11. Related Documentation

| Document | Path | Content |
|----------|------|---------|
| **Specification** | `specs/specification.md` | Product requirements, user stories |
| **Design** | `specs/design.md` | Technical architecture, component design |
| **AI Prompt Design** | `specs/ai-prompt-design.md` | Detailed prompt templates, confidence guidelines |
| **Constitution** | `specs/constitution.md` | Coding standards, naming conventions |
| **Requirements** | `specs/requirements.md` | Numbered requirements (Req 1.1, etc.) |
| **Decision Log** | `specs/decision_log.md` | Architectural decisions and rationale |

### External Resources

- [Svelte 5 Documentation](https://svelte.dev/docs)
- [SvelteKit Documentation](https://svelte.dev/docs/kit)
- [Anthropic Claude API](https://docs.anthropic.com)
- [Azure Cosmos DB SDK](https://learn.microsoft.com/en-us/azure/cosmos-db/nosql/sdk-nodejs)
- [Zod Documentation](https://zod.dev)
- [Tailwind CSS](https://tailwindcss.com/docs)

---

## Revision History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2026-02-10 | 1.0 | Claude | Initial developer guide |
