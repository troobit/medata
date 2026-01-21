---
references:
  - requirements.md
  - ../../src/lib/server/auth/CredentialStore.ts
  - ../../src/lib/server/auth/types.ts
metadata:
  architecture: Storage adapter pattern with environment-aware factory
  scope: Vercel KV credential persistence for serverless deployment
---

# Vercel KV Credential Storage

## Phase 1: Interface Extraction & File Store Refactor

- [ ] 1. Create ICredentialStore.ts interface extracted from existing CredentialStore
  - Define all public methods as interface contract
  - Export interface from auth module index

- [ ] 2. Rename CredentialStore.ts to FileCredentialStore.ts
  - Update class name to FileCredentialStore
  - Implement ICredentialStore interface explicitly
  - Update all imports across the codebase

- [ ] 3. Update src/lib/server/auth/index.ts exports
  - Export ICredentialStore interface
  - Export FileCredentialStore class
  - Maintain backward compatibility with getCredentialStore

## Phase 2: Vercel KV Implementation

- [ ] 4. Install @vercel/kv package
  - Add to dependencies
  - Verify types are included

- [ ] 5. Create KVCredentialStore.ts implementing ICredentialStore
  - Use @vercel/kv client for all operations
  - Store credentials array under 'credentials' key
  - Store challenge under 'challenge' key with TTL

- [ ] 6. Implement credential methods in KVCredentialStore
  - getCredentials: kv.get<StoredCredential[]>('credentials')
  - addCredential: Append to array and kv.set
  - updateCredential: Find, update, and kv.set
  - removeCredential: Filter and kv.set
  - getCredentialById: Get array and find
  - hasCredentials/getCredentialCount: Get array and check length

- [ ] 7. Implement challenge methods with TTL in KVCredentialStore
  - setChallenge: kv.set with ex option (300 seconds)
  - getChallenge: kv.get with expiry check
  - clearChallenge: kv.del

## Phase 3: Store Factory & Integration

- [ ] 8. Create credentialStoreFactory.ts
  - Check for KV_REST_API_URL environment variable
  - Return KVCredentialStore when KV configured
  - Fall back to FileCredentialStore for local dev
  - Cache singleton instance

- [ ] 9. Update all API routes to use factory
  - src/routes/api/auth/bootstrap/options/+server.ts
  - src/routes/api/auth/bootstrap/verify/+server.ts
  - src/routes/api/auth/register/options/+server.ts
  - src/routes/api/auth/register/verify/+server.ts
  - src/routes/api/auth/login/options/+server.ts
  - src/routes/api/auth/login/verify/+server.ts
  - src/routes/api/auth/credentials/+server.ts
  - src/routes/api/auth/credentials/[id]/+server.ts

- [ ] 10. Remove credentialsPath from WebAuthnConfig
  - Update WebAuthnConfig type to make credentialsPath optional
  - Update createWebAuthnConfig to not require path when KV available
  - Store factory handles path internally for file-based store

## Phase 4: Environment & Configuration

- [ ] 11. Update .env.example with Vercel KV documentation
  - Add KV_REST_API_URL and KV_REST_API_TOKEN placeholders
  - Document that these are auto-set by Vercel
  - Note that AUTH_CREDENTIALS_PATH is only for local dev

- [ ] 12. Add Vercel KV section to docs/auth.md
  - Setup instructions using Vercel dashboard
  - CLI commands for linking KV store
  - Environment variable verification steps

- [ ] 13. Update README.md with Vercel deployment section
  - Add "Deploying to Vercel" section after "Getting Started"
  - Include Vercel KV setup steps
  - Document environment variables for production
  - Add troubleshooting for common KV issues

## Phase 5: Testing & Verification

- [ ] 14. Test local development with file-based store
  - Verify bootstrap flow works locally
  - Confirm credentials persist in ./data/credentials.json
  - Test login/logout cycle

- [ ] 15. Test Vercel preview deployment with KV
  - Deploy to preview environment
  - Complete bootstrap flow with YubiKey
  - Verify credential persists across requests
  - Test login with registered credential

- [ ] 16. Verify challenge TTL behavior
  - Start registration, wait >5 minutes, attempt verify
  - Confirm challenge expired error returned
  - Verify no stale challenges accumulate in KV
