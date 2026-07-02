# MeData

iOS app that estimates carbohydrate content from 1–2 iPhone photos using deterministic on-device computer vision (LiDAR visual hull + bundled food-composition database).

This development cycle currently runs along the 'research' branch, with intent to merge to main when the outstanding MVP work is done.

## Hard invariants

- **No LLM and no network calls in the estimation path.** Estimation is deterministic geometry + Core ML segmentation + local SQLite lookups, fully offline.
- **Irish/British English spelling** in all docs, comments, and user-facing strings (Req 19.2). Lint with `bash tools/check_spelling.sh`.
- OS floor: iOS 17 / macOS 14. Primary device: iPhone 13 Pro Max (LiDAR); non-LiDAR fallback is two-view capture + ID-1 card for scale.
- The repo directory must be named `medata` for the Xcode project to resolve.

## Build, test, lint

- `swift build` / `swift test` from the repo root cover all SwiftPM modules (MedataCore, HarnessCore, HarnessCLI).
- The iOS app builds via `MeData/MeData.xcodeproj`.
- Always run `bash tools/check_spelling.sh` before committing docs or strings.

## Feature flags and generated artifacts

- `HARNESS_ENABLED` — Debug-only; gates harness/CLI code out of the shipping iOS binary. Never make shipped code depend on it.
- `DEV_STUB_SEGMENTER` — Debug uses a stub segmenter; Release uses the real Core ML model.
- `segmenter.mlpackage` is **gitignored and generated** by `tools/segmenter/export.py` — never hand-edit or commit it. `food_db.sqlite` is the bundled CoFID/AFCD database, built by `tools/food_db/`.

## Workflow

- Specs live in `specs/` (estimation/, ui/, data/) — follow `specs/PROCESS.md`; each spec has requirements, design, decision_log, prerequisites, and tasks. `specs/OVERVIEW.md` is the index.
- Session tracking lives in **`.nextup.md`** at the repo root (note the leading dot — treat it as `nextup.md` for the `/nextup` workflow).
- Module gotchas are in `docs/agent-notes/` — read the note for a module before changing it.
- `git push` is denied in `.claude/settings.local.json`; pushing is the user's call.
