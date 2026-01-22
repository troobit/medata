# WebAuthn Server-Side Authentication Requirements

## Scope

This document defines requirements for implementing server-side WebAuthn authentication for a **single-user** deployment. The goal is to protect the application with hardware key authentication (YubiKey/passkey) verified on the server, replacing the current browser-only implementation.

**In Scope:**

- Single-user authentication (one owner with multiple hardware keys)
- Server-side WebAuthn assertion verification
- Secure session management with HttpOnly cookies
- Hardware key allowlist management
- SvelteKit API endpoints for auth flow
- Client-side auth gate for protected functionality

**Out of Scope (Explicitly Removed):**

- Multi-user support and user management
- User registration/enrollment UI for arbitrary users
- Role-based access control
- Social login or alternative auth methods

---

## Current State Summary

| Aspect           | Current Implementation                            |
| ---------------- | ------------------------------------------------- |
| Auth Flow        | Browser-only WebAuthn via `navigator.credentials` |
| Storage          | localStorage for users, credentials, sessions     |
| Session          | 30-day client-side expiry                         |
| Render Mode      | SSR disabled (`ssr=false`), prerender enabled     |
| Adapter          | `@sveltejs/adapter-static`                        |
| Server Endpoints | None exist                                        |
| Verification     | Client-side only (no server verification)         |

**Key Files:**

- `src/routes/+layout.ts` - SSR/prerender config
- `svelte.config.js` - Adapter configuration
- `src/lib/services/` - Service layer pattern
- `src/lib/types/` - Type definitions
- `app.d.ts` - App locals (currently unused)

---

## Architecture Decision

### Recommended: Option 1 - SSG UI with Server Auth API + Client Gate

**Approach:** Keep the static/prerendered UI, add SvelteKit API endpoints for authentication, and implement a client-side gate that requires valid session before showing protected functionality.

**Justification:**

- Minimal disruption to existing SSG/offline-capable architecture
- Preserves fast initial load and CDN cacheability of static assets
- Clear separation between public shell and protected data/functionality
- Simpler deployment (static assets + serverless functions)
- Allows graceful degradation for local/offline development mode
- Single API boundary that could serve other clients in future

**Tradeoffs Accepted:**

- Static HTML/JS is technically public (but contains no sensitive data)
- Auth gate enforced client-side for UI, server-side for data access
- Requires adapter change from `adapter-static` to `adapter-vercel` or `adapter-node`

### Alternatives Considered

**Option 2: Enable Full SSR**

- Pros: Server-side route protection, no client-side gate needed
- Cons: Larger architectural change, loses prerender benefits, slower page loads

**Option 3: Separate Backend Service**

- Pros: Maximum flexibility, language-agnostic backend
- Cons: More complex deployment, additional infrastructure, overkill for single-user

---

## Phases

### Phase 1: Server Infrastructure & Registration Endpoints

**Scope:** Establish server-side auth foundation with credential registration flow.

**Deliverables:**

- Switch adapter to support server endpoints
- Create WebAuthn registration options endpoint
- Create WebAuthn registration verification endpoint
- Implement credential storage (file-based for single-user simplicity)
- Environment configuration for rpId and origin

**Files to Add/Change:**

- `svelte.config.js` - Change to `@sveltejs/adapter-vercel` or `@sveltejs/adapter-node`
- `src/routes/api/auth/register/options/+server.ts` - Generate registration challenge
- `src/routes/api/auth/register/verify/+server.ts` - Verify attestation, store credential
- `src/lib/server/auth/WebAuthnService.ts` - Server-side WebAuthn logic
- `src/lib/server/auth/CredentialStore.ts` - Credential persistence
- `src/lib/server/auth/types.ts` - Server-side auth types
- `.env.example` - Document required environment variables

**API Endpoints:**

- `POST /api/auth/register/options` - Returns registration options with challenge
- `POST /api/auth/register/verify` - Verifies attestation and stores credential

**Acceptance Criteria:**

- Server generates valid WebAuthn registration options with correct rpId
- Attestation verification succeeds for valid hardware key response
- Credential (credentialId, publicKey, counter) persists server-side
- Invalid attestation returns appropriate error response

**Verification Checklist:**

1. Run `pnpm dev` and confirm server starts without errors
2. Call `/api/auth/register/options` and verify response contains challenge, rpId, user info
3. Complete registration flow with YubiKey; confirm credential stored in server storage
4. Verify stored credential contains credentialId, publicKey, counter, createdAt
5. Attempt registration with invalid attestation; confirm 400 error returned

---

### Phase 2: Authentication Endpoints & Session Management

**Scope:** Implement authentication flow with server-verified assertions and secure session cookies.

**Deliverables:**

- Authentication options endpoint (challenge generation)
- Authentication verification endpoint (assertion verification)
- Session creation with HttpOnly secure cookies
- Session validation middleware
- Logout endpoint

**Files to Add/Change:**

- `src/routes/api/auth/login/options/+server.ts` - Generate auth challenge
- `src/routes/api/auth/login/verify/+server.ts` - Verify assertion, create session
- `src/routes/api/auth/logout/+server.ts` - Clear session
- `src/routes/api/auth/session/+server.ts` - Check session validity
- `src/lib/server/auth/SessionService.ts` - Session management logic
- `src/hooks.server.ts` - Request authentication hook

**API Endpoints:**

- `POST /api/auth/login/options` - Returns authentication options with allowCredentials
- `POST /api/auth/login/verify` - Verifies assertion, sets session cookie, returns success
- `POST /api/auth/logout` - Clears session cookie
- `GET /api/auth/session` - Returns current session status

**Acceptance Criteria:**

- Authentication challenge includes only allowlisted credential IDs
- Valid assertion from registered key creates session cookie
- Session cookie is HttpOnly, Secure (in production), SameSite=Lax
- Counter is validated and updated on each authentication
- Invalid/replayed assertions are rejected
- Logout clears session and cookie

**Verification Checklist:**

1. Call `/api/auth/login/options` and verify challenge and allowCredentials returned
2. Authenticate with registered YubiKey; confirm session cookie set
3. Call `/api/auth/session` with cookie; confirm authenticated status
4. Call `/api/auth/session` without cookie; confirm unauthenticated status
5. Verify counter increments after each successful authentication
6. Call `/api/auth/logout`; confirm cookie cleared and session invalid
7. Attempt auth with wrong credential; confirm rejection

---

### Phase 3: Client Integration & Auth Gate

**Scope:** Integrate client-side UI with server auth and implement authentication gate.

**Deliverables:**

- Client auth service that calls server endpoints
- Auth gate component that protects app functionality
- Login UI with hardware key prompt
- Session status indicator
- Local development mode bypass (optional, configurable)

**Files to Add/Change:**

- `src/lib/services/auth/ServerAuthClient.ts` - Client-side API wrapper
- `src/lib/services/auth/index.ts` - Export auth client
- `src/lib/components/AuthGate.svelte` - Protects child content until authenticated
- `src/lib/components/LoginPrompt.svelte` - UI for initiating authentication
- `src/routes/+layout.svelte` - Integrate auth gate at app root
- `src/lib/stores/auth.svelte.ts` - Reactive auth state store

**Acceptance Criteria:**

- App shows login prompt when no valid session exists
- Successful authentication reveals protected app content
- Session persists across page reloads (cookie-based)
- Logout returns user to login prompt
- Auth state is reactive and updates UI appropriately

**Verification Checklist:**

1. Load app without session; confirm login prompt displayed
2. Authenticate with YubiKey; confirm app content becomes visible
3. Refresh page; confirm still authenticated (session persists)
4. Click logout; confirm returned to login prompt
5. Verify all data-fetching API calls include session validation

---

### Phase 4: Credential Management & Bootstrap

**Scope:** Implement secure credential enrollment and management for the single owner.

**Deliverables:**

- Bootstrap mechanism for initial credential enrollment
- Add additional credentials to existing allowlist
- Remove credentials from allowlist
- Credential metadata (friendly name, last used timestamp)
- Admin-only credential management (protected by existing session)

**Files to Add/Change:**

- `src/routes/api/auth/credentials/+server.ts` - List credentials (authenticated)
- `src/routes/api/auth/credentials/[id]/+server.ts` - Update/delete credential
- `src/lib/server/auth/bootstrap.ts` - First-credential enrollment logic
- `src/routes/settings/+page.svelte` - Credential management UI
- `.env` - Bootstrap token for initial enrollment

**API Endpoints:**

- `GET /api/auth/credentials` - List all registered credentials (requires auth)
- `PATCH /api/auth/credentials/[id]` - Update credential metadata
- `DELETE /api/auth/credentials/[id]` - Remove credential from allowlist
- `POST /api/auth/bootstrap` - One-time initial enrollment (requires bootstrap token)

**Acceptance Criteria:**

- Bootstrap allows first credential registration with valid token
- Bootstrap token only works once or for limited time window
- Authenticated user can add additional credentials
- Authenticated user can view and manage existing credentials
- At least one credential must remain (prevent lockout)
- Credentials display friendly name and last-used timestamp

**Verification Checklist:**

1. Set bootstrap token in environment; register first credential via bootstrap
2. Confirm bootstrap endpoint disabled after successful first enrollment
3. Authenticate and add second credential via settings UI
4. Verify both credentials appear in credential list with metadata
5. Update friendly name of a credential; confirm persisted
6. Attempt to delete last remaining credential; confirm prevented
7. Delete one credential when multiple exist; confirm removed from allowlist

---

## API Contract (Draft)

### Types

**RegistrationOptions**

- challenge: string (base64url)
- rpId: string
- rpName: string
- userId: string (base64url)
- userName: string
- userDisplayName: string
- attestation: "none"
- authenticatorSelection: { residentKey, userVerification }

**RegistrationVerifyRequest**

- credential: PublicKeyCredential (serialized)

**AuthenticationOptions**

- challenge: string (base64url)
- rpId: string
- allowCredentials: Array<{ id: string, type: "public-key" }>
- userVerification: "preferred"

**AuthenticationVerifyRequest**

- credential: PublicKeyCredential (serialized)

**SessionStatus**

- authenticated: boolean
- expiresAt: string (ISO timestamp) | null

**CredentialInfo**

- id: string
- friendlyName: string
- createdAt: string
- lastUsedAt: string | null

---

## Configuration

### Environment Variables

| Variable                | Purpose                               | Example                                                         |
| ----------------------- | ------------------------------------- | --------------------------------------------------------------- |
| `AUTH_RP_ID`            | Relying Party ID (domain)             | `localhost` (dev), `app.example.com` (prod)                     |
| `AUTH_ORIGIN`           | Expected origin for verification      | `http://localhost:5173` (dev), `https://app.example.com` (prod) |
| `AUTH_SESSION_SECRET`   | Secret for signing session cookies    | 32+ random characters                                           |
| `AUTH_BOOTSTRAP_TOKEN`  | One-time token for initial enrollment | Random UUID or passphrase                                       |
| `AUTH_CREDENTIALS_PATH` | Path to credentials storage file      | `./data/credentials.json`                                       |

### Environment-Specific Configuration

**Development:**

- `AUTH_RP_ID=localhost`
- `AUTH_ORIGIN=http://localhost:5173`
- Bootstrap token set in `.env.local` (gitignored)
- Credentials stored in local `./data/` directory

**Production (Vercel):**

- `AUTH_RP_ID` and `AUTH_ORIGIN` set via Vercel environment variables
- `AUTH_SESSION_SECRET` stored securely in Vercel
- `AUTH_BOOTSTRAP_TOKEN` set once, then removed after enrollment
- Credentials stored in Vercel KV or filesystem (depending on persistence needs)

---

## Extensibility Model

### Module Boundaries

```
src/lib/
├── server/           # Server-only code (never bundled to client)
│   └── auth/
│       ├── WebAuthnService.ts    # Framework-agnostic WebAuthn logic
│       ├── SessionService.ts     # Session management
│       ├── CredentialStore.ts    # Credential persistence interface
│       └── types.ts              # Server-side types
├── services/
│   └── auth/
│       ├── ServerAuthClient.ts   # Client API wrapper
│       └── index.ts
├── components/
│   ├── AuthGate.svelte
│   └── LoginPrompt.svelte
└── stores/
    └── auth.svelte.ts            # Reactive auth state
```

### Interface Definitions

- `ICredentialStore` - Interface for credential persistence (file, KV, database)
- `ISessionStore` - Interface for session storage (cookie, Redis)
- `WebAuthnConfig` - Configuration object for rpId, origin, timeouts
- `AuthClient` - Interface for client-side auth operations

### Alternative Frontend Integration

The auth API is designed as a standalone REST API:

- Any client that can make HTTP requests can authenticate
- Session is cookie-based (works with browsers) or can return token for non-browser clients
- Mobile app would call same `/api/auth/*` endpoints
- API responses use standard JSON format with clear DTOs

---

## Verification

### Manual Testing Protocol

Each phase includes a verification checklist. Additionally:

**End-to-End Flow Test:**

1. Fresh deployment with no credentials
2. Use bootstrap token to enroll first YubiKey
3. Verify bootstrap disabled after enrollment
4. Load app, authenticate with enrolled key
5. Access protected functionality
6. Add second YubiKey as backup
7. Logout, authenticate with backup key
8. Remove first key, verify second still works
9. Attempt removal of last key, verify prevented

**Security Verification:**

- Confirm session cookie has HttpOnly flag
- Confirm session cookie has Secure flag (production)
- Confirm session cookie has SameSite=Lax
- Attempt replay of captured assertion, verify rejected
- Verify counter validation prevents assertion replay

---

## Risks and Notes

### Risks

1. **Credential Storage Durability** - File-based storage on serverless may not persist. Consider Vercel KV or external storage for production.

2. **Lockout Risk** - Single-user with no recovery mechanism. Mitigation: require multiple credentials, document recovery process.

3. **Bootstrap Security** - Bootstrap token in environment is visible to anyone with deployment access. Mitigation: use short-lived token, disable after use.

### Notes

- Do not store credentials or sessions in browser localStorage for production use
- Keep browser-only mode available for local development by checking environment flag
- Session expiry should be configurable; default to 7 days with sliding window
- All auth events should be logged (without secrets) for debugging
- Consider rate limiting on auth endpoints to prevent brute force
