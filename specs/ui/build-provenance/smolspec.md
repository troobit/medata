# Build Provenance — Make the Existing Stamp Honest, Keep Tagging UI Attempts

## Overview

The ask was "where it makes sense, add commit tags/hashes for UI version
changes". Surveying what already exists, most of that ask is already met and
the rest fights a standing convention:

- **A commit hash is already stamped into every Make-built binary.**
  `BUILD_STAMP := <git short sha>-<YYYYMMDD-HHMMSS>` (`Makefile:34`, repeated
  as the `${BUILD_STAMP:-…}` default in `tools/deploy_release.sh:16` and
  `tools/deploy_release_stub.sh:26`) is injected as the `MEDATA_BUILD_STAMP`
  xcodebuild setting, substituted into the `MedataBuildStamp` Info.plist key,
  read back at launch (`App/App.swift:182-190`), logged as
  `event=launch buildStamp=… segmenterSource=…`, and written onto every
  correction record (`App/MealReviewModel.swift:144-145, 623`;
  `CorrectionRecord.proto` field 9).
- **Git tags for UI attempts are already the practice.** Two of the repo's
  three tags are exactly that — `tilt-guide-attempt-1`, `tilt-guide-attempt-2`
  — and the convention is written down in
  `docs/agent-notes/tilt-aim-guide.md:44`.
- **Numbered design handoffs already version the design source**
  (`design-handoff-NN`; `specs/ui/design-handoff-00/decision_log.md:18`).

So there is exactly one real gap, and it is a correctness gap, not a
versioning gap: **the stamp is not dirty-aware**. `git rev-parse --short HEAD`
names the commit, not the tree that was compiled. A build made from a modified
working tree — which is the normal state during UI iteration — claims the clean
HEAD sha. Two builds from different trees at the same commit are distinguished
only by their wall-clock suffix, and nothing in the stamp says either was
dirty. Since the stamp's entire documented job is "match the on-device stamp
against the deploy output before trusting a captured trail"
(`docs/agent-notes/device-build-and-test.md:66-79`), a stamp that silently
misdescribes the tree is worse than one that admits it.

This smolspec proposes only that fix, plus writing down the tag convention
that is already being followed. Everything else the ask could have meant is
rejected below with reasons.

## Requirements

- `BUILD_STAMP` MUST record whether the working tree had uncommitted changes
  to tracked files at build time. Format becomes
  `<sha>[-dirty]-<YYYYMMDD-HHMMSS>` — the `-dirty` marker sits with the sha it
  qualifies, and a clean build's stamp is byte-identical to today's.
- The three definitions MUST stay identical (`Makefile:34`,
  `tools/deploy_release.sh:16`, `tools/deploy_release_stub.sh:26`) so an
  overridden `BUILD_STAMP` and a defaulted one behave the same. Both deploy
  scripts already resolve the sha with `git -C "$REPO_ROOT" rev-parse`, so the
  dirty check MUST carry the same `-C "$REPO_ROOT"`
  (`git -C "$REPO_ROOT" diff --quiet HEAD`) — without it a deploy invoked from
  another directory measures whichever tree the shell happens to be sitting in.
- Dirtiness MUST be measured against tracked files only
  (`git diff --quiet HEAD`), not `git status --porcelain`.
  - **Corrected 2026-08-14.** This clause previously justified itself by claiming
    that `segmenter.mlpackage`, being generated and gitignored, would make a
    `--porcelain` check report dirty on every build. That is false, and was
    measured to be false: `--porcelain` hides ignored files unless `--ignored` is
    passed, so a tree carrying only that artefact reports the empty string. The
    reasoning was wrong even though the conclusion is right; it is corrected here
    rather than quietly deleted, because the wrong version was transcribed into
    `docs/agent-notes/device-build-and-test.md` and will be recognised there.
  - The real divergence is **untracked but not ignored** files — a new agent note,
    a scratch script, a half-written spec. Those are routine mid-session, they say
    nothing about whether the built sources differ from the commit, and a stamp
    that reads `dirty` because a markdown file is unstaged carries no information
    about the binary it labels.
- `make deploy-release-stub` MUST NOT self-report dirty for its own
  Package.swift edit. It already refuses to run against a modified
  Package.swift (`tools/deploy_release_stub.sh:34-38`) and the stamp is
  computed before the edit (`Makefile:34` is `:=`, expanded at parse time;
  the script's default is evaluated at line 26, ahead of the `perl -pi` at
  line 54) — so the honest pre-edit state is what gets stamped, and the
  stub-ness is already carried by `segmenterSource=stub`. This requirement is
  a check on the change, not new work.
- `docs/agent-notes/device-build-and-test.md` MUST document the new format and
  what `-dirty` means for trust in a capture round.
- `docs/agent-notes/tilt-aim-guide.md`'s per-design tag practice MUST be
  generalised into one short paragraph in
  `docs/agent-notes/device-build-and-test.md`: when a UI attempt is worth
  comparing against later, tag its commit `<design>-attempt-N`. No numbering
  scheme, no version label, no tooling.
- **No new version label is introduced anywhere.** Pipeline Decision 50 stands:
  everything reads "v0" until main; provenance *mechanisms* are retained,
  version *labels* are not minted.

## Implementation Approach

One expression, three files:

```make
GIT_SHA    := $(shell git rev-parse --short HEAD)$(shell git diff --quiet HEAD || echo '-dirty')
BUILD_STAMP := $(GIT_SHA)-$(shell date +%Y%m%d-%H%M%S)
```

and the shell equivalent in both deploy scripts, preserving the
`${BUILD_STAMP:-…}` override. Nothing downstream parses the stamp — it is
displayed (`App/EstimationLogView.swift:152`), logged, and stored as an opaque
string — so widening the format breaks no reader. Under 20 lines including the
doc paragraphs.

**Explicitly out of scope, with reasons:**

- **A version/build row in Settings or About.** The stamp's consumer is the
  developer reading `make logs-device` output beside the deploy line; it is
  already visible there and in the correction-record detail view. An in-app
  row is a screen change for an audience of one who has a faster path, and
  About is the legal/attribution surface, not a diagnostics surface.
- **Bumping or displaying `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`.**
  Both are untouched Xcode defaults (1.0 / 1). Incrementing them would be
  precisely the internal versioning pipeline Decision 50 forbids pre-release.
- **A "UI version" or design-system revision label.** Same objection, more
  directly: it would be a label with no released consumer to mean anything to.
  Numbered handoffs already version the design source.
- **A commit SHA field in the handoff manifest.** Already proposed and
  rejected — `specs/ui/design-handoff-00/decision_log.md:295-322`, Decision 10:
  self-referential (a SHA written inside the commit it describes is either
  wrong or needs a second commit), and `git log -- <path>` answers it free.
- **Stamping screenshots.** There is no screenshot pipeline and no committed
  screenshots (`static/` holds brand SVGs only). This would be all-new
  machinery to solve a problem nobody has reported.
- **Putting the build stamp on `PbMealRecord` / `estimation_outcomes`.** This
  is a genuine hole — an unreviewed capture has no record of which binary
  produced it — but it is a schema change to the estimation data model, which
  PROCESS.md §5 puts squarely outside smolspec scope. It is also *not* a UI
  concern, so it does not belong in this spec. If it is wanted, it belongs in
  an estimation spec, and it should be weighed against the prior finding that
  inferring behaviour from a build stamp is "right only by coincidence"
  (`specs/estimation/alternative-class-candidates/decision_log.md:157`).
- **De-duplicating the two `MedataBuildStamp` plist reads** (`App/App.swift`,
  `App/MealReviewModel.swift`). Real duplication, two lines, no defect — and
  `App/` is under concurrent edit. Not worth a coordination cost.

## Risks and Assumptions

- **Assumption:** no tool parses `buildStamp` positionally. Verified — the only
  non-definition mentions are display, logging, docs, and a test literal.
- **Risk:** `git diff --quiet HEAD` costs a stat walk on every `make` parse.
  Negligible on this repo, and it runs once per invocation.
- **Risk:** the marker desensitises — nearly every hand-driven deploy during
  active UI work will read `-dirty`, so its presence is not alarming. Its
  *value* is the converse: a stamp *without* `-dirty` is now a real claim that
  the binary matches the commit, which is what an archived capture round or a
  tagged attempt needs.
- **Gate:** `make build-app` green, `make spell` clean, and one deploy showing
  the new stamp shape in the launch line.
