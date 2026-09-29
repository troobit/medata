# Developer Command Surface

## Overview

The repo-root `Makefile` is the one true way to build, deploy, log and run the
field loop (`docs/agent-notes/device-build-and-test.md`). It has accreted to 391
lines, of which 52 are a hand-maintained `help` target that drifts from the
recipes below it, and its device surface is seven targets across two axes that
are never named:

| Target | Xcode configuration | Segmenter | Installs |
|---|---|---|---|
| `build-app` | Debug | stub | no |
| `deploy-device` | Debug | stub | yes |
| `build-release-check` | Release | model | no |
| `deploy-release` | Release | model | yes |
| `deploy-release-stub` | Release | stub | yes |
| `build-product` | ProductRelease | model | no |
| `deploy-product` | ProductRelease | model | yes |

The two axes — **configuration** and **segmenter** — are what a developer
actually chooses, and neither appears in any target name. `deploy-device` reads
as "the one that deploys to the device", which all of them do; `deploy-release`
and `deploy-release-stub` differ in the segmenter, which the name hints at only
by suffix; `build-release-check` is a build, not a check. Three shell scripts
(`tools/deploy_release.sh`, `deploy_release_stub.sh`, `deploy_product.sh`, 246
lines) implement overlapping subsets of the same five steps, and the build-stamp
expression is duplicated verbatim in all three plus the Makefile, each copy
carrying a comment saying it matches the others.

The field loop's eight targets have the opposite problem: each is one phase of a
documented sequence with a file contract between phases, but the sequence is
recorded only inside a 802-line agent note, and the help text spends 22 lines on
their parameters. There is also no way to reclaim the space the loop consumes —
`medata-corpus/captures` is 23 GB and the device accumulates bundles until the
in-app slimmer arms at 25 GB, so pulling a session is the loop's wall-clock
bottleneck even when nothing in the backlog is wanted.

## Requirements

### Device and build targets

- The command surface MUST name the configuration and the segmenter as the two
  axes they are: `CONFIG=Debug|Release|ProductRelease` and
  `SEGMENTER=model|stub`.
- One target MUST build the app without a device (`make app`) and one MUST
  build, install and launch it (`make deploy`); both MUST honour `CONFIG` and
  `SEGMENTER`.
- The daily combinations MUST each have a one-word target: `make debug`
  (Debug), `make dev` (Release + real model), `make dev-stub` (Release +
  stub), `make product` (ProductRelease + gate).
- `CONFIG=Debug SEGMENTER=model` MUST be refused with the reason, because the
  Debug configuration defines `DEV_STUB_SEGMENTER` unconditionally in
  `Package.swift` and cannot bind a real model.
- `SEGMENTER=model` MUST refuse to build when no `segmenter.mlpackage` is
  bundled, and MUST print the bundled model's 12-hex `medata.modelVersion`
  before building, because swapping the model is a directory copy that leaves no
  other trace.
- `SEGMENTER=stub` on a non-Debug configuration MUST restore `Package.swift`
  whether the build succeeds or fails.
- `CONFIG=ProductRelease` MUST run the existing three-assertion `strings` gate
  on the built binary, whether or not it installs.
- One target MUST export a named checkpoint into the app bundle
  (`make model CHECKPOINT=<path>`), so which model a build binds is a stated
  argument rather than the residue of an earlier `cp -R`.
- The build stamp MUST be computed in exactly one place.
- Derived data MUST be per-checkout. The three fixed `/tmp/medata-<config>`
  paths were shared between worktrees, and Xcode records absolute paths under
  `SourcePackages/checkouts`, so one checkout's build broke another's package
  resolution — the same class of bug as the shared test log fixed on 2026-08-13.
- Every device target MUST keep the transient-`CoreDeviceError 4000` install
  retry and the deployed-stamp echo, which are what make a device trail
  trustworthy.

### Field loop

- `make field-notes` MUST stay the seconds-long pull (notes and the events DB,
  no capture bundles) and `make field-pull` the full one; the difference MUST be
  stated in one line of `make help` and in a prose document, not only in an
  agent note.
- One target (`make field-discard`) MUST reclaim the loop's space on **both**
  sides — the Mac's `medata-corpus/captures` and the device's capture bundles —
  without copying the latter first, and MUST replace `device-reset`, whose first
  step was the full pull being avoided.
- `make field-discard` MUST preserve notes, the per-pull database snapshots and
  `index.sqlite`, because the triage ledger is keyed by note id and its
  merge-preserving regeneration depends on them.
- `make field-discard` MUST refuse unless the caller passes `CONFIRM=yes`, MUST
  print what it is about to delete before deleting anything, and MUST perform
  that check before the notes pull rather than after.
- The two Python test suites (`tools/food_db/tests`, `tools/field_loop/tests`)
  MUST run from one target (`make test-python`) as two pytest invocations, since
  their `conftest.py` files cannot be collected together.
- The loop's phase sequence, its file contracts and every target's parameters
  MUST be documented in `docs/build-and-field-loop.md`, referenced from
  `make help`.

### Help and hygiene

- `make help` MUST be generated from a one-line `##` comment on each target, so
  it cannot drift from the target list.
- Explanatory prose that is not a one-line target summary MUST live in
  `docs/build-and-field-loop.md` or the relevant agent note, not in the
  Makefile.
- Renames MUST be applied to living documents (`README.md`, `CLAUDE.md`,
  `docs/`), and MUST NOT rewrite historical records (`CHANGELOG.md`, completed
  `specs/**/tasks.md`, `specs/bugfixes/**/report.md`) — those record what was
  run at the time.
- `make spell` MUST pass.

## Implementation Approach

### `tools/deploy.sh` — one script for all three configurations

The three deploy scripts collapse into one, driven by environment variables and
sequencing the same five steps every configuration needs:

```
CONFIG=Debug|Release|ProductRelease   SEGMENTER=model|stub   INSTALL=0|1
```

1. Validate the pair (reject `Debug`+`model`; default `SEGMENTER` to `stub` for
   Debug and `model` otherwise).
2. `SEGMENTER=model` → require `MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage`
   and print its `medata.modelVersion`.
   `SEGMENTER=stub` on a non-Debug configuration → rewrite the `Package.swift`
   define to unconditional under an `EXIT` trap that restores it.
3. `xcodebuild` at `CONFIG`, into `/tmp/medata-<config>`, against
   `id=$DEVICE_UDID` when installing and `generic/platform=iOS`
   (`CODE_SIGNING_ALLOWED=NO`) when not.
4. `ProductRelease` → the `strings` gate (`profile=field` absent,
   `profile=product` present, no `event=fieldnote.` literals).
5. `INSTALL=1` → install with the one retry, launch `--terminate-existing`,
   echo the stamp and the segmenter.

The build stamp is computed here and nowhere else.

### `tools/field_loop/field_discard.py`

A new entry point beside its siblings, covering the **Mac side only**: survey the
corpus, then delete `corpus_root()/captures` and `corpus_root()/pulls` and restore
the empty layout. `pulls/` goes too because the ingest hard-links the wire copies
into `captures/`, so leaving it leaves the same bytes under another name. The
index rows stay: `field_diagnose` and `derive_dataset` already guard on the
fixture existing, so no content-absent flag is needed for them to skip a
discarded capture, and `field_report`'s denominators stay honest.

**The device side is not a manifest push.** `FieldMaintenance.deleteIfHashMatches`
deletes a bundle only against its SHA-256, and the Mac cannot know that hash
without reading the file — the copy being avoided. `make field-discard` therefore
wipes the container (`devicectl device uninstall app`) and reinstalls, which needs
no app change and is total rather than selective. Decision 3 records why the
manifest was not extended.

### Makefile

391 → ~190 lines. `help` becomes a four-line `awk` over `##` comments with
`##@` section headers. Names change as follows; every other target keeps its
name.

| Was | Is |
|---|---|
| `build-app` | `make app CONFIG=Debug` |
| `deploy-device` | `make debug` |
| `build-release-check` | `make app` (Release is the default `CONFIG`) |
| `deploy-release` | `make dev` |
| `deploy-release-stub` | `make dev-stub` |
| `build-product` | `make app CONFIG=ProductRelease` |
| `deploy-product` | `make product` |
| `logs-device` | `make logs` |
| `field-test` | `make test-python` (now also runs the food-DB suite) |
| `device-reset` | `make field-discard CONFIRM=yes` |
| — | `make model CHECKPOINT=…` |

### Verification

`make help` lists every target; `make spell`; `make app CONFIG=Debug`,
`make app CONFIG=ProductRelease` and `make app CONFIG=Release SEGMENTER=stub` all
build with no device attached — the second exercising the product gate, the third
the `Package.swift` edit and its revert; `make test-python`; and a device
`make dev-stub` whose launch line reports the stamp the deploy printed.

Because `segmenter.mlpackage` is generated and gitignored, a fresh worktree has
none, so any `SEGMENTER=model` verification there needs the directory copied in
from a checkout that has one. This is a property of the model artifact, not of the
refactor, and is documented rather than fixed.

## Risks

- **A live training run.** `tools/segmenter/run_queue.sh` is executing R8b in
  the main checkout. This work touches neither `tools/segmenter/` nor the
  queue, and runs in a worktree, so the run is unaffected; `make model` is
  documented as contending with a live run for the MPS device.
- **Muscle memory and agent transcripts.** Old target names appear in 40-odd
  files. Living documents are updated; historical records are not, so a reader
  of an old task file will see `make deploy-release`. The rename table above is
  the mapping, and `make help` is authoritative.
- **`field-discard` deletes 23 GB irreversibly**, and the device half deletes
  captures that were never copied. Mitigated by the explicit `CONFIRM=`
  argument, by printing both sides' counts first, and by preserving notes and
  the index — never by a backup, because a 23 GB backup is the thing being
  reclaimed.
