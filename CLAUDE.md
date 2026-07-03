# MeData

iOS app that estimates carbohydrate content from 1–2 iPhone photos using deterministic on-device computer vision (LiDAR visual hull + bundled food-composition database).

This development cycle currently runs along the 'research' branch, with intent to merge to main when the outstanding MVP work is done.

## Hard invariants

- **No LLM and no network calls in the estimation path.** Estimation is deterministic geometry + Core ML segmentation + local SQLite lookups, fully offline.
- **Irish/British English spelling** in all docs, comments, and user-facing strings (Req 19.2). Lint with `bash tools/check_spelling.sh`.
- OS floor: iOS 17 / macOS 14. Primary device: iPhone 13 Pro Max (LiDAR); non-LiDAR fallback is two-view capture + ID-1 card for scale.
- The repo directory must be named `medata` for the Xcode project to resolve.

## Build, test, lint

- Use the repo-root **Makefile**: `make build` / `make test` / `make spell` for the SwiftPM core; `make deploy-device`, `make deploy-release-stub`, `make logs-device` for the on-device loop (see `docs/agent-notes/device-build-and-test.md`).
- `make test` prints TWO totals — XCTest and swift-testing. Always report both; the swift-testing slice alone is not "the" test count.
- The iOS app builds via `MeData/MeData.xcodeproj`; every Make-deployed build logs `event=launch buildStamp=… segmenterSource=…` — match the stamp before trusting device output.
- Always run `make spell` before committing docs or strings.

## Test gate (MVP)

Less is more. The gate for app/UI work is: **does it build + does it look right on device**. Keep the MedataCore math tests green (`make test`); do not add new test scaffolding unless explicitly asked. The app-target files under `MeData/Tests/` and `MeData/UITests/` are **documentation contracts, not an executable suite** — no committed test target runs them; never claim to have run them or write new ones expecting execution (see `docs/agent-notes/ui-capture-flow.md`).

## Feature flags and generated artifacts

- `HARNESS_ENABLED` — Debug-only; gates harness/CLI code out of the shipping iOS binary. Never make shipped code depend on it.
- `DEV_STUB_SEGMENTER` — Debug uses a stub segmenter; Release uses the real Core ML model.
- `segmenter.mlpackage` is **gitignored and generated** by `tools/segmenter/export.py` — never hand-edit or commit it. The bundled food databases are `cofid_db.sqlite` + `afcd_db.sqlite` (CoFID + AFCD, CoFID-wins merge), built by `tools/food_db/generate.py` and committed under `MedataCore/Sources/Foods/Resources/`.

## Workflow

- Specs live in `specs/` (estimation/, ui/, data/) — follow `specs/PROCESS.md`; each spec has requirements, design, decision_log, prerequisites, and tasks. `specs/OVERVIEW.md` is the index.
- Session tracking lives in **`nextup.md`** at the repo root  for the `/nextup` workflow.
- Module gotchas are in `docs/agent-notes/` — read the note for a module before changing it.
- `git push` is denied in `.claude/settings.local.json`; pushing is the user's call.
