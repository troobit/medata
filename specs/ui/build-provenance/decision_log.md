# Decision Log: Build Provenance

## Decision 1: Scope the "commit tags for UI versions" ask down to making the build stamp dirty-aware

**Date**: 2026-08-14
**Status**: proposed

### Context

The stated want was "where it makes sense, add commit tags/hashes for UI version changes". A survey of the repo found that most of that already exists. Every Make-built binary carries `<git short sha>-<timestamp>` from `Makefile:34` (mirrored in `tools/deploy_release.sh:16` and `tools/deploy_release_stub.sh:26`) through the `MEDATA_BUILD_STAMP` xcodebuild setting and the `MedataBuildStamp` Info.plist key, logged at launch (`App/App.swift:182-190`) and written onto every correction record (`App/MealReviewModel.swift:144-145, 623`). Git tags for UI attempts are already the practice (`tilt-guide-attempt-1`, `tilt-guide-attempt-2`), documented in `docs/agent-notes/tilt-aim-guide.md:44`. Numbered design handoffs already make the design source a versioned artefact.

What does not exist is any indication of whether the tree that was compiled matched the commit named in the stamp. `git rev-parse --short HEAD` is not `git describe --dirty`. During UI iteration the tree is almost always modified, so the stamp routinely names a commit whose content was not what shipped to the device. The stamp's documented purpose is to let a capture round be trusted (`docs/agent-notes/device-build-and-test.md:66-79`), and stale binaries have already invalidated whole rounds.

### Decision

Change `BUILD_STAMP` to `<sha>[-dirty]-<YYYYMMDD-HHMMSS>`, using `git diff --quiet HEAD` against tracked files, in all three definition sites; document the format and generalise the existing `<design>-attempt-N` tag practice into `docs/agent-notes/device-build-and-test.md`. Introduce no new version label anywhere.

### Rationale

This is the only part of the ask that fixes a way the repo can currently mislead its own developer, and it is roughly one expression in three files. Everything else the ask could mean is either already satisfied, previously rejected, or in direct conflict with pipeline Decision 50's ban on internal version labels before release. A stamp that can say "dirty" also makes its silence meaningful: a clean stamp becomes a real claim that the binary matches the commit, which is what a tagged UI attempt or an archived capture round needs in order to be reproducible.

Tracked-file dirtiness rather than full `git status` is deliberate: `segmenter.mlpackage` is generated and gitignored, and scratch files are routine, so a `--porcelain` check would mark every build dirty and carry no information.

### Alternatives Considered

- **Mint a UI version label or design-system revision number**: Give the UI its own version axis so changes can be cited by label - Rejected: pipeline Decision 50 (`specs/estimation/pipeline/decision_log.md:1759`) holds that version markers exist only where a released consumer would read them, and preserves provenance mechanisms while banning labels. A pre-release UI version would be a label with no consumer.
- **Add a commit SHA field to the design handoff manifest**: Pin each handoff to its commit explicitly - Rejected: already decided against in `specs/ui/design-handoff-00/decision_log.md:295-322` (Decision 10) as self-referential ceremony; `git log -- <path>` answers it for free.
- **Surface the build stamp in Settings or About**: Make the running build visible in-app - Rejected: the audience is one developer who already reads it from `make logs-device` next to the deploy output, and it is visible in the correction-record detail view (`App/EstimationLogView.swift:152`). About is the legal/attribution surface.
- **Stamp screenshots with the commit**: Tie visual artefacts to their build - Rejected: no screenshot pipeline and no committed screenshots exist; this would be entirely new machinery for an unreported problem.
- **Put the build stamp on `PbMealRecord` / `estimation_outcomes`**: Close the hole where an unreviewed capture records nothing about its binary - Rejected *for this spec*: it is a schema change to the estimation data model, outside smolspec scope per PROCESS.md §5, and not a UI concern. It also has to answer the prior finding that inferring behaviour from a build stamp is "right only by coincidence" (`specs/estimation/alternative-class-candidates/decision_log.md:157`).
- **Do nothing**: The stamp's timestamp already distinguishes builds - Rejected: a timestamp distinguishes builds but says nothing about whether either matched its commit, which is the question a capture round actually asks.

### Consequences

**Positive:**
- A stamp without `-dirty` becomes a checkable claim that the binary matches the named commit; archived capture rounds and tagged UI attempts become reproducible.
- No new versioning axis, no new file format, no schema change, no app-code change.
- The three stamp definitions stay identical, so overridden and defaulted stamps keep behaving the same.

**Negative:**
- Most hand-driven deploys during UI work will read `-dirty`, so the marker will be common and easy to ignore.
- The stamp string grows, and the format is now conditional — anything written later that parses it must handle both shapes.
- The genuine gap (unreviewed captures carrying no build identity at all) stays open, deferred to an estimation spec.

### Impact

`Makefile:34`, `tools/deploy_release.sh:16`, `tools/deploy_release_stub.sh:26`, and `docs/agent-notes/device-build-and-test.md`. No `App/`, Info.plist, or pbxproj changes; no persistence or protobuf changes.

---
