# Front end integration and server-side verification for WebAuthn-based authentication

## Incorporate explicitly:

- Current client-side WebAuthn flow and storage:
- AuthService.ts (localStorage users/credentials/session; 30-day expiry; multi-credential per user; uses navigator.credentials.create/get)
- auth.ts (Auth types and helpers like generateChallenge, base64 conversion)
- +page.svelte (UI under “Security” section; uses getAuthService(); registers users/credentials; toggles auth enabled)

### Current rendering/deployment configuration:

+layout.ts (ssr=false; prerender=true)
svelte.config.js (@sveltejs/adapter-vercel; prerender config)
app.d.ts (App.Locals placeholder exists but unused; relevant if introducing server hooks)
There are currently no SvelteKit +server.ts endpoints in src/routes (verify via repo structure); the server/auth layer will need to be introduced.

## Goal state (production pattern):

Only pre-authorized hardware keys/passkeys (e.g., specific YubiKey credential IDs) can access the deployed app.
WebAuthn assertions are verified on the server (not in the browser).
Session is established server-side (prefer HttpOnly cookie), and each request (at least each API request; ideally all SSR requests if SSR is enabled) is gated by auth middleware.
Authorized credential IDs are managed server-side (allowlist), with a safe bootstrap/enrollment mechanism for developers to add keys.
Backend is designed to be reusable by other frontends (clear API contract; separation between WebAuthn domain logic and HTTP framework glue).

### Key decision you must make (and document):

Since the UI is currently prerendered and ssr is disabled, “protecting routes” cannot rely on SSR-only middleware. You must propose one of:

1. Keep SSG UI, add backend/serverless auth API, and implement a client-side gate (app requires valid session before loading sensitive functionality), plus clarify what is and is not protected (static assets remain public).
2. Enable SSR (change +layout.ts and related configs) and use SvelteKit server hooks to enforce authentication on page requests and API requests.
3. Split into a dedicated backend service (separate Node service) plus static frontend; document deployment and routing assumptions.
   Pick a recommended approach and list alternatives with tradeoffs.

## Functional requirements to include (non-exhaustive; expand as needed):

- WebAuthn server verification:
  - Registration options endpoint (server generates challenge, rpId, expected origin)
  - Registration verification endpoint (server verifies attestation/credential, stores credential public key, counter, credentialId)
  - Authentication options endpoint (server generates challenge and allowCredentials based on allowlist and/or user mapping)
  - Authentication verification endpoint (server verifies assertion, updates counter, issues session)
- Credential allowlist:
  - Server-side persistence for authorized credential IDs and metadata (friendly name, addedAt, lastUsedAt)
  - Enrollment flow suitable for “developer adds YubiKey on backend” (e.g., bootstrap secret/token + admin-only endpoints; or offline CLI that writes allowlist; or env-based allowlist for simplest deployments)
  - Environment-specific allowlist (dev/staging/prod separation)
- Session management:
  - Secure cookie settings (HttpOnly, Secure, SameSite)
  - Expiration policy (align with current 30-day behavior but recommend safe defaults + rotation)
  - Server-side session storage strategy (choose and justify: signed cookie/JWT, Redis, DB)
  - Logout and session invalidation
- Route/API protection:
  - Auth middleware/hook for API routes (minimum)
  - If SSR is enabled, auth middleware for page requests as well
  - Clear “unauthenticated” UX (redirect to login, show access denied, etc.)
- Extensibility:
  - Backend auth logic in a framework-agnostic module (e.g., a service layer that can be reused by SvelteKit endpoints, Express, Cloudflare Workers, etc.)
  - Versioned API contract and DTOs independent from Svelte components
  - Keep current browser-only mode available for local/offline use if desired (explicitly decide and document)
- Security requirements:
  - HTTPS/secure context enforcement and environment configuration for rpId/origin
  - CSRF considerations for cookie-based sessions (SameSite, CSRF tokens where needed)
  - Replay protection via challenges; counter verification updates
  - Audit/logging requirements (minimal but actionable)

## Non-functional requirements:

- Verification approach: define manual verification checklists per phase (developer-run steps in local dev and production-like preview) that confirm expected behaviors end-to-end.
- Observability: minimal logging for auth events without leaking secrets.
- Deployment: Vercel/serverless compatibility (if chosen), local dev workflow, required env vars.
- Local Development: if separation between front and backend are required to mimic authentication flow, use docker or similar tools to provide this functionality.

You must reference concrete repo files that will likely need changes or additions, including but not limited to:

- AuthService.ts (will need refactor to call server endpoints instead of local verification/storage, or split into LocalAuthService vs ServerAuthClient)
- auth.ts (likely needs new shared DTOs or helpers; may split server-only types out)
- +page.svelte (UI will need to support enrollment/login flows that interact with server; differentiate local vs server mode)
- +layout.ts and/or introduction of src/hooks.server.ts (if SSR/protection is implemented server-side)
- Introduction of new SvelteKit endpoints: src/routes/api/auth/\*\*/+server.ts (or similar) if using SvelteKit backend
- svelte.config.js / deployment config if SSR or server routes require changes
- app.d.ts if adding Locals typings for authenticated user/session

Write the requirements document as a standalone artifact:

File: specs/dev-0/requirements.md
The document must be planned and phased, with acceptance criteria and a verification method per phase.

## Steps

Summarize current state (briefly) using repo specifics:

Confirm current WebAuthn is browser-only and stored in localStorage, and does not perform server-side assertion verification.
Note current SPA/SSG settings and implications for route protection.
Choose a recommended production architecture (from the decision options) and justify it with 3–6 concrete bullets.

Define a phased plan (at least 4 phases), each including:

Scope and deliverables
Files/modules to add/change (repo paths)
API endpoints/interfaces introduced
Acceptance criteria
Manual verification checklist (developer-run) for that phase
Specify environment configuration requirements:

Required env vars (names, purpose, examples as plain text)
How rpId and expectedOrigin are derived in dev vs prod
How allowlist is managed per environment
Describe the extensibility model:

Proposed module boundaries (client vs server; domain vs transport)
Minimal interface definitions (names only; no large code)
How a different frontend would integrate (e.g., mobile app) via the same backend API

## Output

Output ONLY the content that should be written to specs/dev-0/requirements.md, and specs/dev-0/tasks.md in Markdown.

Use clear headings.
Include a “Scope”, “Architecture Decision”, “Phases”, “API Contract (Draft)”, “Configuration”, “Verification”, and “Risks/Notes” section.

Use the rune tool to write to specs/dev-0/tasks.md based on the refined specs/dev-0/requirements.md

When referencing code locations, include exact repo paths (e.g., src/lib/services/auth/AuthService.ts).
Keep it implementation-oriented but not full of code; small illustrative snippets are allowed only as inline text (no fenced code blocks).
Examples
Example section content structure (use real repo paths; placeholder values allowed):

Architecture Decision:
Recommended: [Option X]
Alternatives: [Option Y], [Option Z]
Phase 1: Introduce server auth endpoints
Files: src/routes/api/auth/registration/options/+server.ts, src/routes/api/auth/registration/verify/+server.ts, …
Acceptance criteria: “Given an enrolled credentialId in allowlist, authentication returns 200 and sets session cookie”
Verification (manual checklist): “Run pnpm dev; enroll key via [mechanism]; confirm unauthenticated requests get 401; confirm authenticated session persists across reload”
Notes
Do not propose storing production allowlists or sessions in browser localStorage.
Do not propose creating or adding automated test suites; keep verification manual and developer-driven.
Make the bootstrap/enrollment story explicit and safe; there must be a way for a developer to add a new YubiKey credential to the backend allowlist without opening permanent public enrollment.
Ensure the plan remains compatible with the existing code style (service layer under src/lib/services, types under src/lib/types) and keeps the backend extensible for non-Svelte frontends via a clean API boundary.
