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

| Variable | Local Dev | Production |
|----------|-----------|------------|
| `AUTH_RP_ID` | `localhost` | `your-domain.vercel.app` |
| `AUTH_ORIGIN` | `http://localhost:5173` | `https://your-domain.vercel.app` |
| `AUTH_SESSION_SECRET` | Random 32+ char base64 | Random 32+ char base64 (different from local) |
| `AUTH_BOOTSTRAP_TOKEN` | Temporary, remove after setup | Temporary, remove after setup |
| `AUTH_CREDENTIALS_PATH` | `./data/credentials.json` | (optional, defaults to same) |

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "Invalid origin" error | Ensure `AUTH_ORIGIN` matches your browser URL exactly (including protocol) |
| YubiKey not detected | Try a different USB port, ensure browser supports WebAuthn |
| Bootstrap not working | Verify `AUTH_BOOTSTRAP_TOKEN` is set and no credentials exist yet |
| Session not persisting | Check `AUTH_SESSION_SECRET` is set and at least 32 characters |
| "Challenge expired" | Complete the YubiKey tap within 5 minutes of starting |

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
