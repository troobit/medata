# Design Decisions

This document records architectural and design decisions made during MeData development.

## Data Architecture

### Decision: Event-Log Paradigm

**Context:** Needed a flexible data model to track diverse physiological events (meals, insulin, BSL, exercise).

**Decision:** Use a long-form event log where each row represents a single event with fixed columns (`timestamp`, `event_type`, `value`) and flexible `metadata` (JSON).

**Rationale:**

- New metrics added as `event_type` entries, not schema changes
- Supports time-series analysis across event types
- Enables regression models across multiple variables
- Future multi-user support without structural changes

**Trade-offs:**

- JSON metadata requires parsing for queries
- Less efficient than normalised tables for simple queries

---

### Decision: Horizontal Partitioning by Timestamp

**Context:** Event log grows over time; needed efficient querying for recent data.

**Decision:** Partition data by timestamp (daily/weekly) for data skipping and query optimisation.

**Rationale:**

- Most queries target recent time windows
- Reduces I/O for common operations
- Supports archival of older data

---

## UI Architecture

### Decision: Svelte 5 with Runes

**Context:** Migrating from Svelte 4 to Svelte 5 during development.

**Decision:** Use Svelte 5 runes (`$state`, `$derived`, `$effect`) for reactive state management.

**Rationale:**

- More explicit reactivity model
- Better TypeScript integration
- Improved performance characteristics
- Future-proof for Svelte ecosystem

---

### Decision: Contained Button Animations

**Context:** `hover:scale-105` caused button collision in dense layouts.

**Decision:** Use inner element transforms or box-shadow instead of scaling button bounds. Added animation prop with variants: `none`, `subtle`, `full`.

**Rationale:**

- Prevents layout shift on hover
- Respects `prefers-reduced-motion`
- Configurable per-use-case

---

### Decision: Svelte Spring for Interactions

**Context:** Custom CSS ripple/shimmer animations were difficult to maintain and coordinate.

**Decision:** Replace with Svelte 5 `Spring.of()` and `svelte/transition` functions.

**Rationale:**

- Consistent with Svelte patterns
- Physics-based, more natural feel
- Easier to coordinate with component lifecycle

---

## AI Services

### Decision: Multi-Provider AI Architecture

**Context:** Needed flexibility to use different AI providers for food estimation.

**Decision:** Factory pattern with provider-specific implementations (Azure, Gemini, Claude, OpenAI, Bedrock, Local).

**Rationale:**

- Swap providers without UI changes
- Support offline via local models (Ollama/LLaVA)
- Cost optimisation by provider selection
- Resilience through fallback providers

**Interface:**

```typescript
interface FoodService {
  estimateNutrition(image: Blob): Promise<FoodEstimate>;
}
```

---

### Decision: Prompt Enhancement Pipeline

**Context:** AI estimates vary in accuracy; user corrections provide valuable feedback.

**Decision:** Store original estimates and corrections to build enhancement pipeline.

**Rationale:**

- Corrections train better prompts over time
- Per-user calibration possible
- Enables accuracy metrics and model comparison

---

## Local Estimation

### Decision: Reference Card Detection

**Context:** Portion size estimation requires scale reference.

**Decision:** Use credit card edge detection with perspective correction.

**Rationale:**

- Standard, known dimensions (85.6mm x 53.98mm)
- Users typically carry one
- Enables volume calculation from image

---

### Decision: USDA FNDDS Integration

**Context:** Needed food density data for volume-to-macro conversion.

**Decision:** Integrate USDA Food and Nutrient Database for Dietary Studies with category search.

**Rationale:**

- Comprehensive, peer-reviewed data source
- Free and public domain
- Covers wide range of foods

---

## Authentication

### Decision: SSG UI + Server Auth API + Client Gate

**Context:** Needed to add authentication while preserving static site benefits.

**Alternatives Considered:**

1. Full SSR (rejected: loses prerender benefits, slower page loads)
2. Separate backend service (rejected: overkill for single-user)

**Decision:** Keep static/prerendered UI, add SvelteKit API endpoints for auth, client-side gate for protected content.

**Rationale:**

- Minimal disruption to existing architecture
- Preserves fast initial load and CDN cacheability
- Clear separation between public shell and protected data
- Simpler deployment (static assets + serverless functions)

**Trade-offs:**

- Static HTML/JS technically public (but contains no sensitive data)
- Auth gate enforced client-side for UI, server-side for data access

---

### Decision: Single-User Authentication Model

**Context:** Application is personal health tracker, not multi-tenant.

**Decision:** Implement single-owner model with hardware key allowlist.

**Rationale:**

- Simpler than full user management
- Hardware keys provide strong authentication
- Multiple keys supported for redundancy/backup

---

### Decision: File-Based Credential Storage

**Context:** Needed credential persistence for single-user deployment.

**Decision:** Store credentials in JSON file on filesystem.

**Rationale:**

- Simple for single-user case
- No database dependency
- Easy backup/recovery
- Works with serverless (Vercel Functions)

**Trade-offs:**

- Not suitable for multi-user
- Serverless persistence may require external storage (Vercel KV) for production

---

### Decision: Bootstrap Token Mechanism

**Context:** First credential enrollment needs secure bootstrapping.

**Decision:** One-time bootstrap token in environment variables.

**Rationale:**

- Secure initial enrollment without existing auth
- Token removed after first use
- Environment-based = separate from code

**Security Notes:**

- Token visible to deployment administrators
- Must be removed immediately after enrollment
- Short-lived by design

---

### Decision: HttpOnly Session Cookies

**Context:** Session storage needed for authenticated state.

**Decision:** Use HttpOnly, Secure, SameSite=Lax cookies.

**Rationale:**

- HttpOnly prevents XSS access to session
- Secure ensures HTTPS-only in production
- SameSite=Lax provides CSRF protection
- 7-day sliding expiry balances security and convenience

---

## Modelling

### Decision: Decay Function Models

**Context:** Insulin, carbohydrates, and alcohol have time-dependent effects.

**Decision:** Model biological half-life and compounding effects with decay functions.

**Rationale:**

- Insulin: ~4-5 hour action curve
- Carbohydrates: variable absorption by glycaemic index
- Alcohol: ~0.015 BAC/hour metabolism rate
- Time-of-day affects insulin sensitivity

---

### Decision: Confidence Intervals for Recommendations

**Context:** Insulin dose recommendations carry health risk.

**Decision:** Provide recommendations with confidence intervals, not single values.

**Rationale:**

- Acknowledges model uncertainty
- User makes final decision
- Avoids liability for exact dosing

---

## Future Extensibility

### Decision: Module Boundaries

**Context:** Needed clean separation for future expansion.

**Decision:** Server-only code in `src/lib/server/`, client services in `src/lib/services/`, stores in `src/lib/stores/`.

**Rationale:**

- Server code never bundled to client
- Clear interface boundaries
- Swappable implementations (e.g., credential store)

```
src/lib/
├── server/           # Server-only (never bundled to client)
├── services/         # Client-side service layer
├── stores/           # Reactive state (Svelte 5 runes)
├── components/       # UI components
├── types/            # Shared types
├── config/           # Configuration constants
├── data/             # Static data (USDA database, etc.)
├── db/               # IndexedDB/Dexie database layer
├── repositories/     # Data access layer
└── utils/            # Shared utilities
```
