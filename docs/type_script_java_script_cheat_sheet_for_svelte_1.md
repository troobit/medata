# TypeScript / JavaScript Cheat Sheet for Svelte (MeData-Aligned)

This document is a **syntax, paradigm, and code-reading reference** aligned with the **MeData Developer Guide**. It is written for backend and infrastructure engineers (Terraform, CI/CD, Azure, Python) who are new to **TypeScript, Svelte 5, and browser runtimes**.

The goal is not to teach frontend development exhaustively, but to enable you to **read existing code confidently**, understand small functions quickly, and recognise architectural intent.

Irish English spelling is used throughout.

---

## 1. JavaScript vs TypeScript (Project Context)

### JavaScript (JS)
- Dynamically typed
- Executes in browser or Node.js
- No compile-time guarantees

### TypeScript (TS)
- Superset of JavaScript
- Adds static typing and interfaces
- Compiles to JavaScript
- Used everywhere in this project (`<script lang="ts">`)

**Mental model**  
TypeScript ≈ Python with type hints, but enforced at build time. Comparable to Terraform variable and object type definitions.

---

## 2. Modules, Imports, and Barrel Files

```ts
// src/lib/services/claude-food-recognition.ts
export class ClaudeFoodRecognitionService { ... }
```

```ts
// src/lib/services/index.ts
export * from './claude-food-recognition.js';
```

```ts
import { ClaudeFoodRecognitionService } from '$lib/services';
```

- Each file is a module
- `index.ts` files are **barrels** (re-export convenience)
- `$lib/` is a SvelteKit alias to `src/lib/`

---

## 3. Classes and `constructor()`

```ts
export class GeminiFoodRecognitionService {
    private client: GoogleGenerativeAI | null = null;

    constructor() {
        const apiKey = env['GEMINI_API_KEY'];
        if (apiKey) {
            this.client = new GoogleGenerativeAI(apiKey);
        }
    }
}
```

### What `constructor()` means
- Runs when `new ClassName()` is called
- Used for dependency initialisation and configuration
- No async work allowed directly

**Analogy**: Terraform module initialisation using provided variables.

---

## 4. Interfaces (Contracts, Not Implementations)

```ts
export interface IFoodRecognitionService {
    recognise(image: Blob, labelContext?: LabelContext): Promise<FoodRecognitionResult>;
    isConfigured(): boolean;
    getProviderName(): string;
}
```

- Interfaces define **what must exist**, not how
- Compile-time only (erased at runtime)
- Similar to Python ABCs or protocol classes

Used heavily to:
- Swap AI providers
- Enforce service behaviour

---

## 5. Reading Function Signatures

```ts
recognise(image: Blob, labelContext?: LabelContext): Promise<FoodRecognitionResult>;
```

Breakdown:
- `image: Blob` → required browser binary object
- `labelContext?:` → optional parameter (`undefined` allowed)
- Returns `Promise<FoodRecognitionResult>`

Meaning:
> This function starts work now and produces a result later.

You must use:
```ts
const result = await service.recognise(image);
```

---

## 6. Promises and `async` / `await`

### What a Promise Is
A `Promise<T>` represents future completion of a value.

Mental model:
- Terraform apply
- CI pipeline job step

### `async` behaviour
```ts
async function f(): Promise<number> {
    return 42;
}
```

- Always returns a Promise
- `return value` becomes `Promise.resolve(value)`

### Consuming a Promise
```ts
const value = await f();
```

---

## 7. Error Handling Patterns

### Typed errors
```ts
export class FoodRecognitionError extends Error {
    constructor(
        public readonly code: FoodRecognitionErrorCode,
        message: string
    ) {
        super(message);
    }
}
```

Purpose:
- Error classification
- Mapping to HTTP status codes

Used in API routes:
```ts
if (e instanceof FoodRecognitionError) {
    switch (e.code) { ... }
}
```

---

## 8. Web Runtime Types You Will See

### `Blob`
- Binary data (images, files)
- Produced by camera, file input, fetch

### `ArrayBuffer`
- Raw memory buffer

### `Uint8Array`
- Byte-level view of an ArrayBuffer

---

## 9. Worked Example: `blobToBase64`

```ts
async function blobToBase64(blob: Blob): Promise<string> {
    const buffer = await blob.arrayBuffer();
    const bytes = new Uint8Array(buffer);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]!);
    }
    return btoa(binary);
}
```

What happens:
1. Blob → raw bytes
2. Bytes → binary string
3. Binary → Base64

Notes:
- `!` is a non-null assertion
- Required because TS cannot prove bounds safety

Used when:
- Sending images in JSON
- Calling AI APIs

---

## 10. Svelte 5 Runes (Critical)

```ts
let count = $state(0);
let doubled = $derived(count * 2);

$effect(() => {
    console.log(count);
});
```

| Rune | Meaning |
|-----|--------|
| `$state` | Reactive mutable state |
| `$derived` | Computed value |
| `$effect` | Side-effect on change |
| `$props()` | Component inputs |

Think of these as **language-level reactivity**, not libraries.

---

## 11. Component Communication

### Parent → Child (props)
```svelte
<CameraCapture onCapture={handleCapture} />
```

### Child → Parent (callbacks)
```ts
onCapture({ foodImage: blob });
```

No global event bus. Data flows explicitly.

---

## 12. API Routes (`+server.ts`)

```ts
export const POST: RequestHandler = async ({ request }) => {
    const body = await request.json();
    return json({ data: result });
};
```

Key facts:
- Runs server-side only
- Can access secrets
- Used as backend controllers

Analogy: FastAPI route handlers.

---

## 13. Zod Validation

```ts
const Schema = z.object({
    imageBase64: z.string().min(1)
});
```

Purpose:
- Runtime validation
- Safe parsing (`safeParse`)
- Equivalent to Pydantic models

---

## 14. Repository Pattern

```ts
export interface MealRepository {
    save(meal: Meal): Promise<void>;
}
```

- Abstracts data storage
- Cosmos implementati