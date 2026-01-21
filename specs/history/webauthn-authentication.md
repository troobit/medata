# WebAuthn Server-Side Authentication

**Branch:** `dev-1`

## Overview

Implemented server-side WebAuthn authentication for single-user deployment. This replaced the browser-only implementation with proper server-verified authentication using hardware security keys (YubiKey/passkeys).

## Implementation Summary

Built a complete authentication system with:
- Server-side WebAuthn registration and assertion verification
- Secure session management with HttpOnly cookies
- Client-side auth gate protecting app functionality
- Bootstrap mechanism for initial credential enrollment
- Credential management UI for adding/removing security keys

## Architecture Decision

**Chosen: SSG UI + Server Auth API + Client Gate**

- Keeps static/prerendered UI for fast loads and CDN cacheability
- Adds SvelteKit API endpoints for authentication
- Client-side gate requires valid session before showing protected functionality
- Changed adapter from `adapter-static` to `adapter-vercel`

## Features Implemented

### Phase 1: Server Infrastructure & Registration
- Switched adapter from adapter-static to adapter-vercel
- Created WebAuthnService.ts with server-side verification logic using @simplewebauthn/server
- Created CredentialStore.ts for file-based credential persistence
- Implemented registration options endpoint with challenge generation
- Implemented registration verification endpoint with attestation verification
- Environment configuration for rpId, origin, and credentials path

### Phase 2: Authentication & Session Management
- Authentication options endpoint with challenge generation
- Authentication verification endpoint with assertion verification
- SessionService.ts for session management
- Secure HttpOnly cookie session creation (SameSite=Lax, Secure in production)
- Counter validation and update on each authentication
- Logout endpoint to clear sessions
- Session status endpoint for client verification
- hooks.server.ts with session validation middleware

### Phase 3: Client Integration & Auth Gate
- ServerAuthClient.ts for client-side API calls
- auth.svelte.ts reactive store for auth state
- AuthGate.svelte component protecting app content
- LoginPrompt.svelte with YubiKey authentication UI
- Integration at app root via +layout.svelte
- Session persistence across page reloads

### Phase 4: Credential Management & Bootstrap
- bootstrap.ts for first credential enrollment
- Bootstrap endpoint with one-time token validation
- Credentials list endpoint (authenticated)
- Credential update endpoint for friendly names
- Credential delete endpoint with lockout prevention (requires 1+ credential)
- Credential management UI in settings page
- Add additional credential flow for backup keys

## Files Changed

### Server Auth (Added)
- `src/lib/server/auth/WebAuthnService.ts` - WebAuthn registration/verification logic
- `src/lib/server/auth/SessionService.ts` - Session management
- `src/lib/server/auth/CredentialStore.ts` - Credential persistence
- `src/lib/server/auth/bootstrap.ts` - First credential enrollment
- `src/lib/server/auth/types.ts` - Server-side auth types
- `src/lib/server/auth/index.ts` - Module exports
- `src/hooks.server.ts` - Request authentication hook

### API Routes (Added)
- `src/routes/api/auth/register/options/+server.ts` - Generate registration challenge
- `src/routes/api/auth/register/verify/+server.ts` - Verify attestation, store credential
- `src/routes/api/auth/login/options/+server.ts` - Generate auth challenge
- `src/routes/api/auth/login/verify/+server.ts` - Verify assertion, create session
- `src/routes/api/auth/logout/+server.ts` - Clear session
- `src/routes/api/auth/session/+server.ts` - Check session validity
- `src/routes/api/auth/bootstrap/options/+server.ts` - Bootstrap registration options
- `src/routes/api/auth/bootstrap/verify/+server.ts` - Bootstrap verification
- `src/routes/api/auth/credentials/+server.ts` - List credentials
- `src/routes/api/auth/credentials/[id]/+server.ts` - Update/delete credential

### Client Components (Added)
- `src/lib/components/auth/AuthGate.svelte` - Protects app content
- `src/lib/components/auth/LoginPrompt.svelte` - Authentication UI
- `src/lib/components/auth/index.ts` - Module exports
- `src/lib/services/auth/ServerAuthClient.ts` - Client API wrapper
- `src/lib/services/auth/index.ts` - Module exports
- `src/lib/stores/auth.svelte.ts` - Reactive auth state

### Configuration (Added/Modified)
- `.env.example` - Environment variable documentation
- `svelte.config.js` - Changed to adapter-vercel
- `src/routes/+layout.svelte` - Integrated AuthGate
- `src/routes/settings/+page.svelte` - Credential management UI

### Dependencies Added
- `@simplewebauthn/server` - Server-side WebAuthn verification
- `@simplewebauthn/browser` - Browser credential API wrapper

## Environment Variables

| Variable | Purpose |
|----------|---------|
| `AUTH_RP_ID` | Relying Party ID (domain) |
| `AUTH_ORIGIN` | Expected origin for verification |
| `AUTH_SESSION_SECRET` | Secret for signing session cookies |
| `AUTH_BOOTSTRAP_TOKEN` | One-time token for initial enrollment |
| `AUTH_CREDENTIALS_PATH` | Path to credentials storage file |

## Documentation Updates

- `docs/auth.md` - YubiKey authentication setup guide for local and production

## Design Decisions

See `docs/design.md` for architectural decisions including:
- SSG + Server API hybrid architecture
- Single-user authentication model
- File-based credential storage
- Bootstrap token mechanism
