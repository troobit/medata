# MeData

Personal diabetes tracking app. Logs meals (with AI-powered macro estimation), insulin doses, BSL readings, and exercise. Offline-first with IndexedDB storage.

## Quick Start

```bash
pnpm install
cp .env.example .env.local
```

Generate secrets and add to `.env.local`:

```bash
# Session secret
openssl rand -base64 32

# Bootstrap token (remove after first enrollment)
openssl rand -hex 16
```

```bash
pnpm dev
```

Open http://localhost:5173, enter your bootstrap token, and register your security key.

> [!TIP]
> For development without hardware keys, enable Chrome DevTools → Application → WebAuthn → Virtual authenticator.

## Vercel Deployment

### 1. Create KV Store

```bash
vercel storage add kv medata-auth
```

### 2. Set Environment Variables

```bash
vercel env add AUTH_RP_ID production        # your-domain.vercel.app
vercel env add AUTH_ORIGIN production       # https://your-domain.vercel.app
vercel env add AUTH_SESSION_SECRET production
vercel env add AUTH_BOOTSTRAP_TOKEN production
```

### 3. Deploy

```bash
vercel --prod
```

After enrolling your key, remove the bootstrap token:

```bash
vercel env rm AUTH_BOOTSTRAP_TOKEN production && vercel --prod
```

## Environment Sync

Push local env to Vercel:

```bash
# Push all from .env.local to production
cat .env.local | grep -v '^#' | grep '=' | while IFS='=' read -r key value; do
  echo "$value" | vercel env add "$key" production
done
```

Pull Vercel env to local:

```bash
vercel env pull .env.local
```

## Documentation

See [docs/auth.md](docs/auth.md) for detailed authentication setup, Vercel KV configuration, and troubleshooting.
