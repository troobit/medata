# Repo history gotchas

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
