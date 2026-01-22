# Git Worktree Merge Requirements

## Overview

Merge three feature branches (`auth`, `logoui`, `dev-2`) back into `dev-0`, avoiding merge conflicts through strategic rebasing and conflict resolution.

## Current State

### Worktrees

| Worktree                           | Branch   | Commit    | Status                        |
| ---------------------------------- | -------- | --------- | ----------------------------- |
| `/Users/ronan/repos/beetus/medata` | `dev-0`  | `661ba4f` | Base branch                   |
| `/Users/ronan/repos/beetus/auth`   | `auth`   | `afbd711` | 5 commits ahead of dev-0      |
| `/Users/ronan/repos/beetus/logoui` | `logoui` | `7af2e6d` | 6 commits ahead of dev-0      |
| `/Users/ronan/repos/beetus/dev-2`  | `dev-2`  | `fc1c25e` | Older parallel implementation |

### Branch Relationships

- **dev-0**: Current working branch, tracks `origin/dev-0`
- **auth**: Branched from `dev-0` at `e83dacc` (vercel auth plan)
- **logoui**: Branched from `dev-0` at `661ba4f` (HEAD of dev-0)
- **dev-2**: Older branch with parallel logo implementation, diverged much earlier

### Feature Completion Status

#### auth branch - COMPLETE

All 16 tasks completed:

- Phase 1: Interface extraction & FileCredentialStore refactor
- Phase 2: Vercel KV implementation (KVCredentialStore)
- Phase 3: Store factory & integration with all API routes
- Phase 4: Environment configuration & documentation
- Phase 5: Testing & verification

#### logoui branch - NEARLY COMPLETE

36/42 tasks completed:

- Phase 0-5: All complete (core component, animation, variants, favicons, integration)
- Phase 6: Demo page partially complete (3 tasks remaining - verification only)

#### dev-2 branch - SUPERSEDED

- Contains earlier parallel implementation of logo component
- All 33 tasks marked complete BUT lacks Phase 6 demo page
- **Decision**: logoui is the canonical logo implementation; dev-2 can be archived

## Conflict Analysis

### Files Modified by Multiple Branches

| File                    | auth            | logoui            | Resolution Strategy    |
| ----------------------- | --------------- | ----------------- | ---------------------- |
| `.env.example`          | Adds KV vars    | Adds LOGO_VARIANT | Combine both additions |
| `specs/logoui/tasks.md` | Earlier version | Latest version    | Keep logoui version    |
| `src/lib/db/schema.ts`  | Modified        | Modified          | Manual review needed   |

### auth-exclusive Changes (safe to merge)

- `docs/auth.md` - new documentation
- `src/lib/server/auth/*` - 8 new/modified files
- `src/routes/api/auth/*` - all auth endpoints
- `package.json` / `pnpm-lock.yaml` - @vercel/kv dependency
- `src/routes/log/insulin/+page.svelte` - minor change

### logoui-exclusive Changes (safe to merge)

- `src/lib/components/ui/Logo.svelte` - new component
- `static/favicon-*.svg` - 3 new favicons
- `static/apple-touch-icon-*.png` - 6 new icons
- `src/app.html` - favicon reference
- `src/routes/+layout.svelte` - Logo integration
- `src/routes/+page.svelte` - Logo usage
- `src/routes/history/+page.svelte` - Logo usage
- `src/routes/import/cgm/+page.svelte` - Logo usage

## Merge Strategy

### Recommended Approach: Auth-First Merge + UI Sync

1. **Merge auth into dev-0** (clean merge, brings auth system to main development)
2. **Sync dev-0 into logoui worktree** (pull auth changes, allowing continued UI development with auth available)
3. **Continue UI development on logoui** (with auth features now accessible)
4. **Merge logoui into dev-0 when ready** (final integration)
5. **Archive dev-2** (superseded by logoui)

### Why Not Merge dev-2?

- logoui contains all dev-2's logo work PLUS:
  - Phase 6 demo page
  - Proper spec naming (`specs/logoui/` not `specs/dev-2/`)
  - Cleaner commit history (rebased from dev-0)
- dev-2 has stale `.vercel/output/` build artifacts committed (should be gitignored)
- Merging both would create unnecessary conflicts

## Requirements

### R1: Validate Branch Completeness

Before merging, verify each branch is in a working state:

- [ ] auth: All tests pass, KV integration verified
- [ ] logoui: Build succeeds, logo renders correctly

### R2: Merge auth First

- auth has the smallest diff from dev-0
- No conflicts expected with pure fast-forward or clean merge
- Brings in @vercel/kv dependency needed for deployment

### R3: Sync logoui with dev-0 for Continued Development

- Merge dev-0 into logoui branch (brings auth into UI development environment)
- Resolve any conflicts (primarily .env.example)
- Keep logoui's version of `specs/logoui/tasks.md`
- logoui worktree remains active for continued UI development with auth features

### R3a: Ongoing UI Development on logoui

- logoui worktree can continue receiving UI-related work
- Auth system is available for integration testing
- Merge back to dev-0 when UI work reaches a milestone

### R4: Handle .env.example Merge

Combine additions from both branches:

```env
# Auth (from auth branch)
KV_REST_API_URL=
KV_REST_API_TOKEN=

# Logo (from logoui branch)
PUBLIC_LOGO_VARIANT=default
```

### R5: Archive dev-2

After successful merge:

- Remove dev-2 worktree: `git worktree remove dev-2`
- Delete branch: `git branch -D dev-2`
- Document in commit message that logoui superseded dev-2

### R6: Clean Up Worktrees (Partial - Keep logoui Active)

After auth merge complete:

- Remove auth worktree: `git worktree remove auth`
- **Keep logoui worktree active** for continued UI development
- Remove logoui later when UI work complete and merged to dev-0
- Archive dev-2 immediately (superseded)

### R7: Push to Remote

After local merge verified:

- Push dev-0 to origin
- Delete remote tracking branches if any

## Conflict Prevention Rules

1. **Never edit the same file in both worktrees simultaneously**
2. **Rebase frequently to minimize drift**
3. **Keep feature branches focused on single concerns**
4. **Use clear commit messages for conflict resolution**

## Validation Checklist

### After Auth Merge (dev-0)

- [ ] `pnpm install` succeeds
- [ ] `pnpm build` succeeds
- [ ] `pnpm dev` starts without errors
- [ ] Auth bootstrap flow works locally

### After Sync (logoui worktree)

- [ ] `pnpm install` succeeds in logoui worktree
- [ ] `pnpm build` succeeds with auth + logo features
- [ ] `pnpm dev` starts without errors
- [ ] Logo component renders with animation
- [ ] Auth bootstrap flow works in logoui environment
- [ ] All spec task files are in `specs/` directory
- [ ] No `.vercel/output/` artifacts in repo
