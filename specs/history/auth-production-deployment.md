# Auth Production Deployment

**Branch:** `auth`

## Overview

Production deployment fixes and UI refinement for the WebAuthn authentication system. This spec addressed Vercel deployment issues, missing PWA assets, error handling improvements, and UI consistency.

## Implementation Summary

Resolved production deployment blockers and improved user experience:

- Replaced file-based credential storage with Vercel KV for serverless compatibility
- Configured all required environment variables for Vercel production
- Generated missing PWA icon assets
- Implemented graceful error handling for missing configuration
- Standardised UI styling across all pages
- Updated documentation with correct deployment domain

## Features Implemented

### Vercel File System Fix

- Identified code attempting to write to `./data` directory (incompatible with serverless)
- Replaced local file storage with Vercel KV for credential persistence
- Updated CredentialStore to use KV REST API

### Environment Configuration

- Configured `AUTH_RP_ID` for WebAuthn Relying Party identification
- Configured `AUTH_ORIGIN` for verification
- Configured `AUTH_SESSION_SECRET` for secure cookie signing
- Configured `AUTH_BOOTSTRAP_TOKEN` for initial credential enrolment
- Documented Vercel KV setup (manual dashboard configuration required)

### PWA Icon Assets

- Reviewed and ran `scripts/generate-icons.js`
- Generated `icon-192.png` and `icon-512.png`
- Generated `icon-192-maskable.png` and `icon-512-maskable.png`
- Eliminated 404 errors for PWA manifest icons

### Graceful Error Handling

- Updated `createWebAuthnConfig` to return structured errors instead of throwing
- Modified auth endpoints to return user-friendly configuration error responses
- Improved error messages to avoid leaking implementation details

### UI Style Consistency

- Audited all pages against simplified home page style
- Applied consistent dark theme (`bg-gray-800`, `bg-gray-800/50` cards)
- Standardised typography hierarchy and colour-coded icons
- Unified padding, border radius, and hover states across pages

### Documentation Updates

- Updated `docs/auth.md` with actual deployment domain (`medata-rtob.vercel.app`)
- Replaced placeholder domains with correct values
- Clearly marked configurable values as placeholders where appropriate

## Files Changed

### Server Auth (Modified)

- `src/lib/server/auth/CredentialStore.ts` - Vercel KV integration
- `src/lib/server/auth/WebAuthnService.ts` - Structured error returns

### API Routes (Modified)

- `src/routes/api/auth/*/+server.ts` - Graceful error responses

### Static Assets (Added)

- `static/icon-192.png`
- `static/icon-512.png`
- `static/icon-192-maskable.png`
- `static/icon-512-maskable.png`

### Configuration (Modified)

- `.env.example` - Updated environment variable documentation

### Documentation (Modified)

- `docs/auth.md` - Updated with production domain

## Environment Variables

| Variable               | Status | Description                              |
| ---------------------- | ------ | ---------------------------------------- |
| `AUTH_RP_ID`           | Set    | WebAuthn Relying Party ID                |
| `AUTH_ORIGIN`          | Set    | Expected origin for verification         |
| `AUTH_SESSION_SECRET`  | Set    | Secret for signing session cookies       |
| `AUTH_BOOTSTRAP_TOKEN` | Set    | One-time token for initial enrolment     |
| `KV_REST_API_URL`      | Manual | Vercel KV endpoint (dashboard setup)     |
| `KV_REST_API_TOKEN`    | Manual | Vercel KV auth token (auto when linked)  |

## Design Decisions

- **Vercel KV over Postgres**: KV chosen for simpler key-value credential storage; no relational queries needed
- **Structured errors**: API returns JSON error objects rather than throwing, improving client error handling
- **Manual KV setup**: Documented as manual step since CLI doesn't support KV creation
