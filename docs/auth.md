# YubiKey Authentication Setup

This guide covers enrolling a YubiKey for both local development and Vercel production.

## Prerequisites

- A YubiKey (or other FIDO2-compatible security key)
- Node.js installed locally
- Vercel CLI (for production deployment)

---

## Local Development Setup

### Step 1: Generate Secrets

Open a terminal and run:

```bash
# Generate session secret (save this somewhere safe)
openssl rand -base64 32

# Generate bootstrap token (temporary, for initial setup only)
openssl rand -hex 16
```

### Step 2: Configure Environment

```bash
cd /Users/ronan/repos/beetus/medata
cp .env.example .env.local
```

Edit `.env.local` with your generated values:

```bash
AUTH_RP_ID=localhost
AUTH_ORIGIN=http://localhost:5173
AUTH_SESSION_SECRET=<paste-your-session-secret>
AUTH_BOOTSTRAP_TOKEN=<paste-your-bootstrap-token>
AUTH_CREDENTIALS_PATH=./data/credentials.json
```

### Step 3: Start Development Server

```bash
pnpm dev
```

### Step 4: Enroll Your YubiKey

1. Open http://localhost:5173 in your browser
2. Click "Authenticate with Security Key"
3. Enter your bootstrap token when prompted
4. Insert your YubiKey and tap it when the browser prompts
5. You're now authenticated

### Step 5: Disable Bootstrap (Security)

After successful enrollment, remove or comment out the bootstrap token in `.env.local`:

```bash
# AUTH_BOOTSTRAP_TOKEN=<removed>
```

Restart the dev server. Bootstrap enrollment is now disabled.

---

## Vercel KV Storage

On Vercel, credentials are stored in Vercel KV (a serverless Redis-compatible key-value store) because the serverless function filesystem is read-only.

### Why Vercel KV?

- **Serverless-compatible**: Works with Vercel's read-only filesystem
- **Automatic TTL**: Challenge tokens expire automatically (no manual cleanup)
- **Low latency**: Edge-optimized for fast auth operations
- **Zero configuration**: Environment variables are auto-set when linked

### Setup Instructions

#### 1. Create a KV Store

Using the Vercel Dashboard:

1. Go to your project in the Vercel Dashboard
2. Navigate to **Storage** tab
3. Click **Create Database** → **KV**
4. Name it `medata-auth` (or any name you prefer)
5. Select your preferred region
6. Click **Create**

Note: The `vercel storage` CLI command is not available. Use the dashboard method above.

#### 2. Link KV to Your Project

The KV store must be linked to your project to auto-inject environment variables:

```bash
# Ensure you're in the project directory
cd /Users/ronan/repos/beetus/medata

# Link to Vercel (if not already linked)
vercel link

# Pull environment variables to local .env file
vercel env pull .env.local
```

#### 3. Verify Environment Variables

After linking, verify the KV variables are set:

```bash
# List production environment variables
vercel env ls production

# You should see:
# KV_REST_API_URL
# KV_REST_API_TOKEN
```

For local development with KV (optional):

```bash
# Pull KV credentials to local env
vercel env pull .env.local

# Check .env.local contains KV_REST_API_URL and KV_REST_API_TOKEN
cat .env.local | grep KV_
```

### How It Works

The app automatically detects the environment:

| Environment       | KV Variables Present?       | Storage Used                         |
| ----------------- | --------------------------- | ------------------------------------ |
| Local dev         | No                          | File-based (`AUTH_CREDENTIALS_PATH`) |
| Local dev         | Yes (via `vercel env pull`) | Vercel KV                            |
| Vercel production | Yes (auto-injected)         | Vercel KV                            |

### Troubleshooting KV

| Problem                         | Solution                                                       |
| ------------------------------- | -------------------------------------------------------------- |
| `KV_REST_API_URL not found`     | Run `vercel link` and `vercel env pull .env.local`             |
| `Unauthorized` KV errors        | Regenerate KV credentials in Vercel Dashboard                  |
| Credentials not persisting      | Verify KV store is linked to the correct project               |
| Local dev using KV unexpectedly | Remove `KV_REST_API_URL` from `.env.local` to use file storage |

---

## Vercel Production Setup

### Step 1: Generate Production Secrets

```bash
# Generate a NEW session secret for production (different from local)
openssl rand -base64 32

# Generate a bootstrap token for initial production setup
openssl rand -hex 16
```

### Step 2: Deploy to Vercel

If not already connected:

```bash
cd /Users/ronan/repos/beetus/medata
vercel link
```

### Step 3: Set Environment Variables

```bash
# Set the production domain (replace with your actual domain)
vercel env add AUTH_RP_ID production
# Enter: your-domain.vercel.app

vercel env add AUTH_ORIGIN production
# Enter: https://your-domain.vercel.app

# Set the session secret (mark as sensitive)
vercel env add AUTH_SESSION_SECRET production
# Paste your generated session secret

# Set the bootstrap token (temporary)
vercel env add AUTH_BOOTSTRAP_TOKEN production
# Paste your generated bootstrap token
```

### Step 4: Deploy

```bash
vercel --prod
```

### Step 5: Enroll Your YubiKey on Production

1. Open https://your-domain.vercel.app in your browser
2. Click "Authenticate with Security Key"
3. Enter your production bootstrap token
4. Insert your YubiKey and tap it
5. You're now authenticated on production

### Step 6: Remove Bootstrap Token (Critical)

After successful enrollment, remove the bootstrap token:

```bash
vercel env rm AUTH_BOOTSTRAP_TOKEN production
```

Redeploy to apply:

```bash
vercel --prod
```

---

## Adding Additional YubiKeys

Once authenticated (either local or production):

1. Navigate to credential management in the app
2. Click "Add Security Key"
3. Insert and tap your additional YubiKey
4. Give it a friendly name (e.g., "Backup YubiKey")

**Recommendation**: Always register at least 2 YubiKeys as backup.

---

## Recovery (If Locked Out)

If you lose access to all enrolled YubiKeys:

### Local Development

```bash
# Delete the credentials file
rm ./data/credentials.json

# Add a new bootstrap token to .env.local
# AUTH_BOOTSTRAP_TOKEN=<new-token>

# Restart dev server and re-enroll
pnpm dev
```

### Production

```bash
# Set a new bootstrap token
vercel env add AUTH_BOOTSTRAP_TOKEN production
# Enter a new token

# Redeploy
vercel --prod

# Enroll new YubiKey via the app
# Then remove the bootstrap token again
vercel env rm AUTH_BOOTSTRAP_TOKEN production
vercel --prod
```

---

## Environment Variables Reference

| Variable                | Local Dev                     | Production                                    |
| ----------------------- | ----------------------------- | --------------------------------------------- |
| `AUTH_RP_ID`            | `localhost`                   | `your-domain.vercel.app`                      |
| `AUTH_ORIGIN`           | `http://localhost:5173`       | `https://your-domain.vercel.app`              |
| `AUTH_SESSION_SECRET`   | Random 32+ char base64        | Random 32+ char base64 (different from local) |
| `AUTH_BOOTSTRAP_TOKEN`  | Temporary, remove after setup | Temporary, remove after setup                 |
| `AUTH_CREDENTIALS_PATH` | `./data/credentials.json`     | (optional, defaults to same)                  |

---

## Troubleshooting

| Problem                | Solution                                                                   |
| ---------------------- | -------------------------------------------------------------------------- |
| "Invalid origin" error | Ensure `AUTH_ORIGIN` matches your browser URL exactly (including protocol) |
| YubiKey not detected   | Try a different USB port, ensure browser supports WebAuthn                 |
| Bootstrap not working  | Verify `AUTH_BOOTSTRAP_TOKEN` is set and no credentials exist yet          |
| Session not persisting | Check `AUTH_SESSION_SECRET` is set and at least 32 characters              |
| "Challenge expired"    | Complete the YubiKey tap within 5 minutes of starting                      |

---

## Quick Reference Commands

```bash
# Local: Generate all secrets at once
echo "SESSION_SECRET: $(openssl rand -base64 32)"
echo "BOOTSTRAP_TOKEN: $(openssl rand -hex 16)"

# Vercel: List current env vars
vercel env ls production

# Vercel: Pull env vars to local .env file
vercel env pull .env.production.local
```

---

## Vercel KV Configuration

For Vercel deployments, MeData uses **Vercel KV** for credential storage instead of the local filesystem (which is read-only on serverless functions).

### Why Vercel KV?

- **Read-only filesystem**: Vercel serverless functions cannot write to the filesystem
- **Persistence**: KV data persists across deployments and function invocations
- **TTL support**: Authentication challenges auto-expire after 5 minutes
- **Zero configuration**: Environment variables are auto-injected when linked

### Setup Instructions

#### 1. Create a KV Store

**Via Vercel Dashboard:**

1. Go to your Vercel project → **Storage** tab
2. Click **Create Database** → **KV**
3. Name it (e.g., `medata-auth`)
4. Select a region close to your deployment
5. Click **Create**

**Via Vercel CLI:**

Note: The `vercel storage` command is not available in the CLI. Use the dashboard method above.

#### 2. Link KV Store to Project

```bash
# Link your local project to Vercel (if not already done)
vercel link

# Pull environment variables (includes KV credentials)
vercel env pull .env.local
```

This adds `KV_REST_API_URL` and `KV_REST_API_TOKEN` to your environment.

#### 3. Verify Configuration

```bash
# List environment variables for production
vercel env ls production

# Should show:
# KV_REST_API_URL
# KV_REST_API_TOKEN
# AUTH_RP_ID
# AUTH_ORIGIN
# AUTH_SESSION_SECRET
# AUTH_BOOTSTRAP_TOKEN (if not yet enrolled)
```

### Environment Variable Reference

| Variable                | Source        | Description                                           |
| ----------------------- | ------------- | ----------------------------------------------------- |
| `KV_REST_API_URL`       | Auto (Vercel) | KV REST API endpoint. Presence triggers KV mode.      |
| `KV_REST_API_TOKEN`     | Auto (Vercel) | KV authentication token.                              |
| `AUTH_CREDENTIALS_PATH` | Manual        | **Ignored** when KV is configured. Only used locally. |

### How It Works

The app automatically detects the storage backend:

```
KV_REST_API_URL set? → Use Vercel KV (KVCredentialStore)
                    → Use local file (FileCredentialStore)
```

- **Vercel preview/production**: Uses KV automatically
- **Local development**: Uses file-based storage at `AUTH_CREDENTIALS_PATH`
- **`vercel dev`**: Uses KV if you ran `vercel env pull`

### Testing KV Locally

To test KV storage locally:

```bash
# Pull Vercel environment variables
vercel env pull .env.local

# Run with Vercel dev server
vercel dev
```

Or set the KV variables manually in `.env.local` (not recommended for security).

### Troubleshooting

| Problem                                             | Solution                                                        |
| --------------------------------------------------- | --------------------------------------------------------------- |
| `ENOENT: no such file or directory, mkdir './data'` | KV is not configured. Run `vercel link && vercel env pull`      |
| `KV_REST_API_URL is not defined`                    | Ensure KV store is linked to your project in Vercel dashboard   |
| Credentials not persisting                          | Verify `KV_REST_API_URL` is set in Vercel environment variables |
| Challenge expired immediately                       | Check server time sync; KV TTL is 5 minutes                     |
| `Unauthorized` from KV                              | `KV_REST_API_TOKEN` may be invalid. Re-link the KV store        |

### Data Model

The KV store uses two keys:

| Key           | Value                | TTL              |
| ------------- | -------------------- | ---------------- |
| `credentials` | `StoredCredential[]` | None (permanent) |
| `challenge`   | `StoredChallenge`    | 5 minutes        |

### Security Notes

- KV credentials (`KV_REST_API_TOKEN`) should never be committed to version control
- The token is automatically scoped to your Vercel project
- Credentials in KV are encrypted at rest by Vercel
