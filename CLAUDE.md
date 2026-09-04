# MeData

iOS app that estimates carbohydrate content from 1–2 iPhone photos using deterministic on-device computer vision (LiDAR visual hull + bundled food-composition database).

This development cycle currently runs along the 'research' branch, with intent to merge to main when the MVP work is done.

## Hard invariants

- **No LLM and no network calls in the estimation path.** Estimation is deterministic geometry + Core ML segmentation + local SQLite lookups, fully offline.
- **Proper spelling** in all docs, comments, and user-facing strings — enforced by `make spell` (`tools/check_spelling.sh`), not restated in specs.
- OS floor: **iOS 26.5** for the app (the MedataCore SwiftPM package + host tooling still target iOS 17 / macOS 14 loosely — see `docs/agent-notes/swift-package.md`). **Hardware floor: iPhone 16 Pro**. Primary device: iPhone 16 Pro (devicectl id `6AD781BA-89FF-5A82-A2A1-B5EC9469F465`, name `you`). The non-LiDAR two-view + ID-1-card capture path is **retained, not descoped** (segmenter-foundation Decision 26): the tool must stay as widely available as possible, so non-LiDAR iOS 26.5 devices fall through to two-view + ID-1 card for scale; when LiDAR is present it is used. The hardware floor is a recommendation for measured targets, not an engine-boundary gate (`docs/ios-device-setup.md`).
- **Developer-phase UI copy: no reassurance or disclaimer messaging** (privacy notes, read-only warnings, data-preservation notices) in any screen — the developer already knows. About is the sole legal/attribution surface; functional accuracy signals (calibration banner, very-low retake) are not disclaimers and stay.
- The repo directory must be named `medata` for the Xcode project to resolve.

## Build, test, lint

- Use the repo-root **Makefile**: `make build` / `make test` / `make spell` for the SwiftPM core; `make deploy-device`, `make deploy-release-stub`, `make logs-device` for the on-device loop (see `docs/agent-notes/device-build-and-test.md`).
- `make test` prints TWO totals — XCTest and swift-testing. Always report both; the swift-testing slice alone is not "the" test count.
- The iOS app builds via `MeData/MeData.xcodeproj`; every Make-deployed build logs `event=launch buildStamp=… segmenterSource=…` — match the stamp before trusting device output.
- Always run `make spell` before committing docs or strings.

## Test gate (MVP)

Less is more. The gate for app/UI work is: **does it build + does it look right on device**. Keep the MedataCore math tests green (`make test`); do not add new test scaffolding unless explicitly asked. The app-target files under `MeData/Tests/` and `MeData/UITests/` are **documentation contracts, not an executable suite** — no committed test target runs them; never claim to have run them or write new ones expecting execution (see `docs/agent-notes/ui-capture-flow.md`).

Because that gate is a person looking at a screen, a UI surface worth deciding about SHOULD ship as **two or more attempts**, not one: commit each on a clean tree and tag it `<surface>-attempt-N`, or merge both behind a developer-phase switch when they can coexist. `git describe --tags <build-stamp sha>` then names which attempt is installed. Git branches and tags are the whole mechanism — build no tooling around it. Convention and the three shapes: `docs/agent-notes/device-build-and-test.md`, "Comparing UI attempts on the phone".

## Feature flags and generated artifacts

- `HARNESS_ENABLED` — Debug-only; gates harness/CLI code out of the shipping iOS binary. Never make shipped code depend on it.
- `DEV_STUB_SEGMENTER` — Debug uses a stub segmenter; Release uses the real Core ML model.
- `segmenter.mlpackage` is **gitignored and generated** by `tools/segmenter/export.py` — never hand-edit or commit it. The bundled food databases are `cofid_db.sqlite` + `afcd_db.sqlite` (CoFID + AFCD, CoFID-wins merge), built by `tools/food_db/generate.py` and committed under `MedataCore/Sources/Foods/Resources/`.

## Workflow

- Specs live in `specs/` (estimation/, ui/, data/) — follow `specs/PROCESS.md`; each spec has requirements, design, decision_log, prerequisites, and tasks. `specs/OVERVIEW.md` is the index.
- Module gotchas are in `docs/agent-notes/` — read the note for a module before changing it.
