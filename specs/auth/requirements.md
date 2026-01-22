# Authentication Requirements

## R1: Vercel Deployment Environment Configuration

The deployed Svelte app at https://medata-rtob.vercel.app/ throws environment-related errors. All required environment variables must be properly configured in Vercel for production.

### Required Environment Variables for Production

| Variable               | Description                                       | Example                                 |
| ---------------------- | ------------------------------------------------- | --------------------------------------- |
| `AUTH_RP_ID`           | WebAuthn Relying Party ID (domain)                | `medata-rtob.vercel.app`                |
| `AUTH_ORIGIN`          | Expected origin for WebAuthn verification         | `https://medata-rtob.vercel.app`        |
| `AUTH_SESSION_SECRET`  | Secret for signing session cookies (min 32 chars) | Generated via `openssl rand -base64 32` |
| `AUTH_BOOTSTRAP_TOKEN` | Temporary token for initial credential enrolment  | Generated via `openssl rand -hex 16`    |
| `KV_REST_API_URL`      | Vercel KV endpoint (auto-set when KV linked)      | Auto-populated by Vercel                |
| `KV_REST_API_TOKEN`    | Vercel KV auth token (auto-set when KV linked)    | Auto-populated by Vercel                |

### Current Status (2026-01-23)

| Variable               | Status                                                             |
| ---------------------- | ------------------------------------------------------------------ |
| `AUTH_RP_ID`           | ✅ Set in Vercel Production                                        |
| `AUTH_ORIGIN`          | ✅ Set in Vercel Production                                        |
| `AUTH_SESSION_SECRET`  | ✅ Set in Vercel Production                                        |
| `AUTH_BOOTSTRAP_TOKEN` | ✅ Set in Vercel Production                                        |
| `KV_REST_API_URL`      | ❌ **Not set** - KV store needs to be created via Vercel Dashboard |
| `KV_REST_API_TOKEN`    | ❌ **Not set** - Auto-populated when KV is linked                  |

### Manual Action Required

Vercel KV must be configured via the Vercel Dashboard (the CLI doesn't support KV creation):

1. Go to https://vercel.com/rtob/medata → **Storage** tab
2. Click **Connect Store** → **Create New** → **KV**
3. Name it `medata-auth` and select a region
4. Link it to the project

### Observed Errors to Fix

1. ~~**AUTH_RP_ID not set**: `Error: AUTH_RP_ID environment variable is required`~~ ✅ Fixed
2. ~~**AUTH_SESSION_SECRET not set**: `Session configuration unavailable.`~~ ✅ Fixed
3. **File system access on Vercel**: `ENOENT: no such file or directory, mkdir './data'` - requires Vercel KV configuration (see above)

## R2: PWA Icon Assets Missing

The manifest.json references icon files that do not exist in the static directory:

- `icon-192.png` - 404 error
- `icon-512.png` - 404 error
- `icon-192-maskable.png` - 404 error
- `icon-512-maskable.png` - 404 error

A script exists at `scripts/generate-icons.js` but needs to be run to generate these assets.

## R3: Graceful Degradation for Missing Environment Variables

Authentication API endpoints should provide clear, user-friendly error messages when environment variables are not configured, rather than crashing or returning cryptic errors.

Current behaviour: Throws `Error: AUTH_RP_ID environment variable is required` which leaks implementation details.

Desired behaviour: Return a structured error response indicating the app is misconfigured for authentication.

## R4: Simplified UI Style Consistency

The front-end pre-login page has been simplified. The rest of the site should follow this simplified style:

### Style Characteristics

- Dark theme with `bg-gray-800`, `bg-gray-800/50` cards
- Clean header with Logo component and descriptive tagline
- Minimal padding (`px-4 py-6`)
- Card-based layouts with `rounded-xl` or `rounded-lg`
- Colour-coded icons (blue for insulin, green for meals, yellow for BSL, etc.)
- Simple grid layouts (2-column for quick actions, 3-column for stats)
- Subtle hover states (`hover:bg-gray-700`)
- Consistent typography hierarchy:
  - Page title: `text-2xl font-bold text-white`
  - Section headers: `text-lg font-semibold text-gray-200`
  - Labels: `text-sm font-medium text-gray-400`
  - Values: `text-2xl font-bold` with semantic colours
  - Helper text: `text-xs text-gray-500`

### Pages to Review

All pages should be audited for consistency with this simplified style pattern.

## R5: Documentation Update - Correct Domain

Documentation in `docs/auth.md` references placeholder domains like `your-domain.vercel.app`. These should be updated with the actual deployment domain `medata-rtob.vercel.app` where applicable, or clearly marked as placeholders.
