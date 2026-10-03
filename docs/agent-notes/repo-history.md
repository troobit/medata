# Repo history gotchas

## Local cleanup and pending decoder landing (2026-10-03)

Today's reachable commits are on `research` except `230d0bb` and its staging
merge `1cd8d52`, retained on `staging/decoder` for the existing R17 completion
watcher. Recovery commands and watcher behaviour are in
`segmenter-run-queue.md`. Both linked worktrees were removed; the watcher
uses the branch from the main checkout and does not need its old worktree.

Deleted local refs: `bugfix/segmenter-output-stride-ignored` (its changed
files are identical in research commit `e26e3f4`),
`doc/mvp-gap-rebaseline` (superseded by today's `394b359` rewrite), and
`worktree-ui-wireframe-library-spec` (ancestor of retained
`wireframe-library-delivery`). Remote refs remain. Other unmerged branches
were retained. The wireframe worktree's ignored screenshots and
`Package.resolved` were copied to `tmp/worktree-archive/wireframe-library/`
before removal; build caches were discarded.

## Rewritten main lineage (May 2026)

`origin/main`'s five pre-refocus commits were rewritten at some point
(same messages and trees, different hashes: `9213772…adc3b56` on the
remote vs `a17a271…d062061` in `research`'s ancestry). Until July 2026
the two branches shared only the root commit, which made GitHub report
PR #25 (research → main) as conflicting even though the end trees were
byte-identical (tree `904c390`).

Fixed with an `ours`-strategy merge of `origin/main` into `research`
(commit `e481f0d`) — zero content change, it only ties the histories so
the merge-base is sane. Do not "clean up" that merge commit or rebase it
away; dropping it re-splits the histories and the PR goes back to
conflicting.

## Web-era artefacts

The pre-refocus web app (Food-Recognition API, Azure, Vercel, favicon
PWA) is fully descoped. `.env.example` and the npm/Vercel/.env ignore
patterns were removed in `0be833f`. Still legitimately present despite
web-era looks: `static/` (icon.svg is the AppIcon/brand-glyph source of
truth; favicon SVGs are brand sources) and `.orbit.yaml` (consumed by
the user's orbit orchestration tool, see specs/PROCESS.md §4).

A Vercel GitHub integration may still be attached to the repository
(the vercel bot commented on PR #25 in May 2026) — removing it is a
GitHub/Vercel dashboard action, not something in-repo.
