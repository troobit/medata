---
references:
    - requirements.md
---
# Worktree Merge

## Phase 1: Validation

- [x] 1. Verify auth branch builds and tests pass in worktree

- [x] 2. Verify logoui branch builds successfully in worktree

- [x] 3. Confirm dev-2 is fully superseded by logoui (no unique features)

- [x] 4. Document any uncommitted changes in worktrees before merge

## Phase 2: Merge auth Branch into dev-0

- [x] 5. Checkout dev-0 and ensure clean working state

- [x] 6. Merge auth branch into dev-0 (expect fast-forward or clean merge)

- [x] 7. Run pnpm install to update lockfile with @vercel/kv

- [x] 8. Verify build succeeds after auth merge

- [x] 9. Test auth bootstrap flow works on dev-0

## Phase 3: Sync dev-0 into logoui Worktree

- [x] 10. In logoui worktree, merge dev-0 to bring in auth changes

- [x] 11. Resolve .env.example conflict: combine KV vars + LOGO_VARIANT

- [x] 12. Resolve src/lib/db/schema.ts conflict if present (keep both changes)

- [x] 13. Keep logoui version of specs/logoui/tasks.md

- [x] 14. Run pnpm install in logoui worktree

- [x] 15. Verify build succeeds with auth + logo combined

- [x] 16. Test auth bootstrap flow works in logoui environment

- [x] 17. Test Logo component renders with animation

## Phase 4: Archive dev-2

- [x] 18. Remove dev-2 worktree: git worktree remove /Users/ronan/repos/beetus/dev-2

- [x] 19. Delete dev-2 branch: git branch -D dev-2

- [x] 20. Verify .vercel/output artifacts not in repository (gitignored)

## Phase 5: Partial Cleanup (Keep logoui Active)

- [x] 21. Remove auth worktree: git worktree remove /Users/ronan/repos/beetus/auth

- [x] 22. Verify git worktree list shows dev-0 and logoui only

- [x] 23. Push dev-0 to origin: git push origin dev-0

## Phase 6: Continue UI Development (logoui remains active)

- [x] 24. Continue UI work on logoui branch with auth features available

- [x] 25. Periodically sync dev-0 changes into logoui if needed

## Phase 7: Final Merge (when UI complete)

- [ ] 26. Merge logoui into dev-0 when UI work reaches milestone

- [ ] 27. Run full validation on dev-0: pnpm install && pnpm build && pnpm dev

- [ ] 28. Remove logoui worktree: git worktree remove /Users/ronan/repos/beetus/logoui

- [ ] 29. Push final dev-0 to origin

- [ ] 30. Create PR from dev-0 to main
