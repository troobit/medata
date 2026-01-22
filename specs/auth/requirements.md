# Vercel KV Credential Storage Requirements

## Problem Statement

The current file-based `CredentialStore` fails on Vercel deployments because serverless functions have a **read-only filesystem**. The error manifests as:

```
ENOENT: no such file or directory, mkdir './data'
```

This prevents YubiKey registration (bootstrap) and any credential persistence on Vercel preview and production environments.

## Scope

**In Scope:**

- Vercel KV-based credential store implementation
- Environment-aware store factory (file for local dev, KV for Vercel)
- Challenge storage with TTL (auto-expiry)
- README documentation updates for Vercel KV setup
- Migration path from file-based to KV-based storage

**Out of Scope:**

- Database migrations (no existing production data)
- Other storage backends (Postgres, Supabase, etc.)
- Multi-tenant credential separation

---

## Architecture

### Storage Adapter Pattern

Create an abstract `ICredentialStore` interface that both `FileCredentialStore` and `KVCredentialStore` implement. A factory function selects the appropriate implementation based on environment.

```
src/lib/server/auth/
├── CredentialStore.ts          # Current file-based (rename to FileCredentialStore)
├── KVCredentialStore.ts        # New Vercel KV implementation
├── ICredentialStore.ts         # Interface definition
├── credentialStoreFactory.ts   # Factory function
└── types.ts                    # Shared types
```

### Vercel KV Data Model

**Key Structure:**

| Key           | Value Type           | Description                         |
| ------------- | -------------------- | ----------------------------------- |
| `credentials` | `StoredCredential[]` | Array of all registered credentials |
| `challenge`   | `StoredChallenge`    | Current active challenge (with TTL) |

**TTL Strategy:**

- Challenges: 5-minute TTL (matches existing `CHALLENGE_EXPIRY_MS`)
- Credentials: No TTL (permanent until explicitly deleted)

### Environment Detection

```typescript
function getCredentialStore(): ICredentialStore {
  if (process.env.KV_REST_API_URL) {
    return new KVCredentialStore();
  }
  return new FileCredentialStore(process.env.AUTH_CREDENTIALS_PATH);
}
```

---

## Vercel KV Setup

### Required Environment Variables

| Variable            | Description             | How to Obtain           |
| ------------------- | ----------------------- | ----------------------- |
| `KV_REST_API_URL`   | Vercel KV REST endpoint | Auto-set when KV linked |
| `KV_REST_API_TOKEN` | Vercel KV auth token    | Auto-set when KV linked |

### Setup Commands

```bash
# Create KV store in Vercel dashboard or via CLI
vercel storage add kv medata-auth

# Link to project (auto-sets env vars)
vercel link
vercel env pull .env.local
```

---

## Interface Contract

```typescript
interface ICredentialStore {
  // Credentials
  getCredentials(): Promise<StoredCredential[]>;
  getCredentialById(id: string): Promise<StoredCredential | undefined>;
  addCredential(credential: StoredCredential): Promise<void>;
  updateCredential(id: string, updates: Partial<StoredCredential>): Promise<void>;
  removeCredential(id: string): Promise<void>;
  hasCredentials(): Promise<boolean>;
  getCredentialCount(): Promise<number>;

  // Challenge
  getChallenge(): Promise<StoredChallenge | undefined>;
  setChallenge(challenge: StoredChallenge): Promise<void>;
  clearChallenge(): Promise<void>;
}
```

---

## Acceptance Criteria

1. **KV Store Works on Vercel**
   - Bootstrap flow completes successfully on Vercel preview
   - YubiKey registration persists across function invocations
   - Login works with stored credentials

2. **Local Development Unchanged**
   - File-based storage continues to work without KV configuration
   - No breaking changes to existing `.env.local` setup

3. **Challenge TTL**
   - Expired challenges auto-delete via KV TTL
   - No manual cleanup required

4. **Documentation Updated**
   - README includes Vercel KV setup instructions
   - docs/auth.md updated with KV configuration

---

## Risks

1. **KV Cold Start Latency** - First request after cold start may be slower. Mitigation: KV is already optimized for edge.

2. **KV Rate Limits** - Free tier has request limits. Mitigation: Auth operations are infrequent; single-user won't hit limits.

3. **Local Testing of KV** - Can't test KV locally without Vercel CLI. Mitigation: Use `vercel dev` or mock in tests.
