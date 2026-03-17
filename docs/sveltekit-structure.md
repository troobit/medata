# SvelteKit Folder & File Structure Explained

## For the Intermediate Engineer (5-10 Years Experience)

You're coming from React/Next.js, Vue/Nuxt, or similar? Here's how SvelteKit thinks about structure differently.

---

## The Core Paradigm: **File-System Routing with Conventions**

SvelteKit adopts a **convention-over-configuration** philosophy similar to Next.js, but with distinct file naming patterns that encode behaviour rather than using configuration files.

```
src/
├── lib/                    # Your application code ($lib alias)
│   ├── components/         # Reusable UI components
│   ├── services/           # Business logic, API clients
│   ├── repositories/       # Data access layer
│   ├── stores/             # Svelte 5 reactive state
│   ├── types/              # TypeScript definitions
│   └── schemas/            # Zod validation schemas
│
├── routes/                 # File-system routing (pages + API)
│   ├── +page.svelte        # Route: /
│   ├── +layout.svelte      # Wraps all child routes
│   ├── capture/
│   │   └── +page.svelte    # Route: /capture
│   └── api/
│       └── meals/
│           ├── +server.ts              # API: GET/POST /api/meals
│           └── [id]/
│               └── +server.ts          # API: GET/PUT/DELETE /api/meals/:id
│
└── app.html                # HTML shell template
```

---

## Pattern 1: The `+` Prefix Means "Special"

Files prefixed with `+` are **reserved SvelteKit conventions** - the framework handles them automatically:

| File | Purpose | Runs On |
|------|---------|---------|
| `+page.svelte` | Page component (UI) | Client + SSR |
| `+page.ts` | Universal data loading | Client + Server |
| `+page.server.ts` | Server-only data loading | Server only |
| `+layout.svelte` | Layout wrapper (inherited by children) | Client + SSR |
| `+layout.ts` | Layout data loading | Client + Server |
| `+server.ts` | API endpoint handler | Server only |
| `+error.svelte` | Error boundary UI | Client + SSR |

**Why the `+` prefix?** It prevents naming collisions. Your own files can be named anything (`MealEditor.svelte`, `api-client.ts`), but SvelteKit files are always `+something`.

---

## Pattern 2: The `$lib` Alias

The `src/lib/` directory has a special alias: `$lib`. This is configured automatically by SvelteKit.

```typescript
// Instead of this nightmare:
import { sumMacros } from '../../../lib/utils/macros.js';

// You write:
import { sumMacros } from '$lib/utils/index.js';
```

This is enforced at build time - the path is replaced during compilation, making refactoring safer.

---

## Pattern 3: Layered Architecture via Convention

Looking at this project's structure, it follows a **Clean Architecture** pattern:

```
src/lib/
├── components/      # Presentation Layer - Svelte components
├── stores/          # State Layer - Svelte 5 runes-based stores
├── services/        # Application Layer - Business logic
├── repositories/    # Data Layer - Persistence interfaces
├── schemas/         # Validation Layer - Zod schemas
└── types/           # Domain Layer - TypeScript types
```

This isn't SvelteKit-mandated, but it's a common pattern. The framework doesn't care about `lib/` subfolders - that's your architecture choice.

---

## Pattern 4: Dynamic Routes with Brackets

Square brackets create **dynamic route segments**:

```
src/routes/
├── api/
│   └── meals/
│       ├── [id]/           # Dynamic: /api/meals/:id
│       │   └── +server.ts
│       └── day/
│           └── [date]/     # Dynamic: /api/meals/day/:date
│               └── +server.ts
```

Inside `+server.ts`, you access these via `params`:

```typescript
// src/routes/api/meals/[id]/+server.ts
export async function GET({ params }) {
    const meal = await getMeal(params.id);  // params.id from URL
    return json(meal);
}
```

**Advanced patterns:**
- `[...rest]` - Catch-all (matches multiple segments)
- `[[optional]]` - Optional parameter
- `[slug=matcher]` - Custom validation via `src/params/matcher.ts`

---

## Pattern 5: Layout Inheritance

Layouts cascade automatically down the route tree:

```
src/routes/
├── +layout.svelte      # Root layout (applies to ALL pages)
├── +page.svelte        # / (wrapped by root layout)
├── capture/
│   └── +page.svelte    # /capture (wrapped by root layout)
└── settings/
    ├── +layout.svelte  # Settings layout (wraps only /settings/*)
    ├── +page.svelte    # /settings (wrapped by both layouts)
    └── profile/
        └── +page.svelte # /settings/profile (wrapped by both layouts)
```

The nested layout receives `children` and renders them:

```svelte
<!-- src/routes/+layout.svelte -->
<script>
    let { children } = $props();  // Svelte 5 syntax
</script>

<nav>...</nav>
{@render children()}
```

**Layout reset:** Use `+page@.svelte` or `+layout@.svelte` to break inheritance and reset to root.

---

## Pattern 6: Server vs Universal Files

The naming convention controls **where code runs**:

| File | Runs on Server | Runs on Client | Use Case |
|------|----------------|----------------|----------|
| `+page.ts` | Yes (SSR) | Yes (navigation) | Fetch public APIs |
| `+page.server.ts` | Yes | No | Database access, secrets |
| `+server.ts` | Yes | No | REST API endpoints |

**In this project:**
- `+server.ts` files handle REST APIs (`/api/meals`, `/api/presets`)
- No `+page.server.ts` because pages fetch via client-side API calls
- Server-side code (Cosmos DB, Blob Storage) is isolated in `repositories/`

---

## Pattern 7: The `index.ts` Barrel Export

Each domain folder has an `index.ts` that re-exports public interfaces:

```typescript
// src/lib/components/index.ts
export { default as CameraCapture } from './CameraCapture.svelte';
export { default as MealEditor } from './MealEditor.svelte';
// ...

// Usage elsewhere:
import { CameraCapture, MealEditor } from '$lib/components/index.js';
```

This is a **barrel pattern** - it controls the public API of each module and enables tree-shaking.

---

## Pattern 8: Colocation vs Separation

SvelteKit supports two philosophical approaches:

**Colocation (feature-based):**
```
src/routes/meals/
├── +page.svelte
├── +page.server.ts
├── MealCard.svelte      # Component used only here
└── meal-utils.ts        # Logic used only here
```

**Separation (layer-based):** (This project uses this approach)
```
src/lib/components/MealCard.svelte
src/lib/services/meal-api.ts
src/routes/meals/+page.svelte
```

The choice depends on whether components are reused across routes. This project uses separation because `MealEditor` appears on multiple pages (home, capture, manual).

---

## Trade-offs to Understand

| Choice | Benefit | Cost |
|--------|---------|------|
| File-system routing | No route config file to maintain | Less flexibility for complex patterns |
| `$lib` alias | Clean imports, refactor-safe | Magic path (tooling must understand it) |
| `+` convention | Clear separation of concerns | Learning curve, easy to forget the `+` |
| Layout inheritance | DRY layouts | Can be surprising when you forget it cascades |
| `+server.ts` vs `+page.server.ts` | Clear API vs page data boundary | Two similar concepts to remember |

---

## Quick Mental Model

1. **`src/routes/`** = URLs (pages and API endpoints)
2. **`src/lib/`** = Your code (business logic, components)
3. **`+file`** = SvelteKit handles this
4. **No `+`** = Your code, you handle it
5. **`.server.`** = Never sent to browser
6. **`[brackets]`** = Dynamic segment

When you look at a SvelteKit project, the route structure *is* the documentation for what URLs exist.
