---
references:
    - requirements.md
---
# Dev Auth Mode

## R1: Local dev without Yubikey auth

- [x] 1. Add AUTH_MODE env var ('on' | 'off')
  - Add to `/src/lib/server/auth/config.ts`
  - Default: 'off' (auth bypassed for local dev convenience)

- [x] 2. Modify login verify endpoint to bypass WebAuthn when AUTH_MODE=off
  - In `/src/routes/api/auth/login/verify/+server.ts`
  - When AUTH_MODE=off: skip WebAuthn verification, create session directly
  - Same login button click, same session cookie creation

- [x] 3. Update .env.example with AUTH_MODE=off

- [x] 4. Verify: `pnpm dev` → click login button → authenticated without Yubikey

## R2: Deployed dev with auth mode option

- [ ] 5. Verify: Deploy to Vercel with AUTH_MODE=off → login bypasses Yubikey

- [ ] 6. Verify: Deploy to Vercel with AUTH_MODE=on → Yubikey required

## R3: Simple mode switching

- [ ] 7. Add pnpm scripts for local mode switching
  - `"dev": "AUTH_MODE=off vite dev"`
  - `"dev:auth": "AUTH_MODE=on vite dev"`

- [ ] 8. Verify: `pnpm dev` bypasses auth, `pnpm dev:auth` requires Yubikey
