# Build and field loop

Every developer command is a target in the repo-root `Makefile`; `make help`
lists them. This page is the part that does not fit on one line: what the build
axes mean, how a model is paired to a build, and the order and file contracts of
the field loop. Module-level gotchas stay in `docs/agent-notes/`.

## The two build axes

An app build is a point on two axes, and both are words in the command.

**`CONFIG`** is the literal Xcode configuration name in `MeData.xcodeproj`:

| `CONFIG` | What it is |
|---|---|
| `Debug` | `-Onone`, `HARNESS_ENABLED`, `DEV_STUB_SEGMENTER`, `FIELD_LOOP` |
| `Release` | optimised, `FIELD_LOOP` — the daily build |
| `ProductRelease` | `Release` minus `FIELD_LOOP`, so the field-note layer is absent at compile time rather than switched off at run time (ml-feedback-loop Req 9) |

**`SEGMENTER`** is which segmenter the binary binds: `model` for the bundled
`.mlpackage`, `stub` for the `DEV_STUB_SEGMENTER` build. `Debug` defines the stub
unconditionally in `Package.swift` and cannot bind a model; asking for
`CONFIG=Debug SEGMENTER=model` is refused with that reason.

Two verbs cross those axes — `make app` builds without a device, `make deploy`
builds, installs and launches — and four targets name the combinations anyone
actually types:

| Target | Equivalent | For |
|---|---|---|
| `make debug` | `deploy CONFIG=Debug SEGMENTER=stub` | UI and non-capture work |
| `make dev` | `deploy CONFIG=Release SEGMENTER=model` | the everyday capture build |
| `make dev-stub` | `deploy CONFIG=Release SEGMENTER=stub` | capture testing with no model exported |
| `make product` | `deploy CONFIG=ProductRelease SEGMENTER=model` | the shipping profile |

`make dev-stub` exists because neither neighbour works for capture testing
without a model: the Debug stub runs at about 20 s/mask under `-Onone`, so the
shutter never arms, and plain `Release` has no segmenter to load and crashes at
launch. Release plus the stub is the only combination that arms the shutter
without a model, and it is produced by making the `Package.swift` define
unconditional for the duration of the build. That has to be a tracked-file edit
rather than an environment variable, because Xcode caches the evaluated manifest
and does not re-evaluate it when only the environment changes — an env-driven
flag can silently build the wrong configuration. `tools/deploy.sh` reverts the
manifest under an `EXIT` trap, so a failed build restores it too, and it refuses
to start if `Package.swift` already has uncommitted changes, because the revert
is a `git checkout`.

`CONFIG=ProductRelease` runs the shipping gate on the built binary whether or not
it installs: `profile=field` absent, `profile=product` present, and no
`event=fieldnote.` literals. The middle assertion is what makes the other two
mean anything — an absence proves nothing unless the line that would have carried
the token compiled at all. All three read `strings`, not `nm`: a stripped Swift
Release binary keeps its literals and loses its symbol names.

Derived data goes to `<checkout>/.build/xcode/<CONFIG>`, which is per-checkout on
purpose. Xcode records absolute paths under `SourcePackages/checkouts`, so two
worktrees sharing one derived-data directory corrupt each other's package
resolution.

## Pairing a model to a build

```
make model CHECKPOINT=tools/segmenter/build/checkpoint_r16_size641_seed1.pt TARGET_SIZE=641
```

`TARGET_SIZE` must match the checkpoint's `train_config.target_size` in its
lineage file (513 for every run before R16; `export.py` defaults to 513). The
app reads the input side from the model, so no code changes when the size does.

`tools/segmenter/export.py` writes `segmenter.mlpackage` into
`MedataCore/Sources/Pipeline/Resources/` and stamps the first 12 hex of the
checkpoint's SHA-256 into the Core ML metadata as `medata.modelVersion`. Every
`SEGMENTER=model` build prints that id before compiling, and every capture the
install records carries it as `MealRecord.segmenterSource` (`coreml_<id>`, visible
in Settings → Estimation log).

Print it because nothing else records it. Swapping the bundled model is a
directory copy: the build stamp names the *commit*, never the model inside the
binary. A launch line proves the stamp and stub-versus-real; only a capture
proves which model an install binds.

Two consequences of the `.mlpackage` being generated and gitignored:

- **A fresh worktree has no model**, so `make dev` and `make product` fail there
  until you export one or copy the directory across from another checkout.
- **`make model` needs the segmenter venv** (`tools/segmenter/.venv/bin/python`,
  overridable as `SEGMENTER_PYTHON`) and competes with a live training run for
  the MPS device. Check `tools/segmenter/build/queue/runner.log` first —
  `docs/agent-notes/segmenter-run-queue.md` has the queue's mechanics.

## Checking a build is the build you think it is

Stale binaries on the device have silently invalidated whole capture rounds.
Every Make-built binary logs one line at launch:

```
event=launch buildStamp=<sha>[-dirty]-<timestamp> segmenterSource=stub|coreml profile=field|product
```

`tools/deploy.sh` prints the same stamp, and matching the two is the check. A
plain Xcode Run logs `buildStamp=unstamped`, because the stamp arrives through
the `MEDATA_BUILD_STAMP` build setting that only the Make targets set.

`-dirty` means tracked files differed from `HEAD` when the build was made, so the
binary cannot be rebuilt from the named commit. It is measured with
`git diff --quiet HEAD` rather than `git status --porcelain`: the routine
mid-session divergence is untracked-but-unignored files — a new agent note, a
scratch script — which say nothing about whether the built sources differ. During
active UI work nearly every deploy reads `-dirty`, so its presence is
unremarkable and the information is in its absence. A clean stamp is a checkable
claim, which is what a tagged UI attempt or an archived capture round needs.

`make logs` collects the last `LOG_LAST` (default 10m) of device logs filtered to
`subsystem == "ie.medata.app"`. It is post-hoc only: `log stream` is host-only and
devicectl has no log subcommand, so macOS offers no scriptable live stream for an
iOS device — live viewing is Console.app. Anything a pull must show has to be
logged at `.notice` or above, because `log collect` reads only the device's
persisted store and iOS does not persist `.info`.

## The field loop

Notes and captures recorded on the phone become tracked work and training
material through a sequence of Make targets with an **agent phase** between two
of them. The contract between stages is files on disk; no stage may assume the
previous one ran in the same process.

```
make field-pull       devicectl → pulls/<date>-<n>/ → ingest → index.sqlite
make field-notes      notes + events DB only → ingest                    (seconds)
make field-triage     corpus notes → the rolling triage ledger
  (routing phase)     an agent routes each unchecked item to one destination
make field-diagnose   annotated captures → diagnoses → cycles/cycle-<n>/tasks.md
  (agent phase)       drafts.json written INTO the cycle directory
make field-close      six guards → commits or proposals → verdict.json
make field-report     alignment metrics                              (any time)
make field-derive     training + calibration inputs                  (any time)
make field-score      weighed captures → accuracy + calibrate        (any time)
make field-discard    reclaim the space both sides hold
make field-export     the whole corpus as learnable JSONL            (any time)
```

### Getting material off the phone

**`make field-notes` is the one to reach for during a session.** It copies the
notes and the events-database snapshot and nothing else, so feedback written
minutes ago reads back in seconds. It works on any branch and for work with
nothing to do with captures, because the note affordance is a separate window
over every screen in any `FIELD_LOOP` build. It never prunes the device.

**`make field-pull` is the whole session**, capture bundles included, ingested
idempotently into `<repo-parent>/medata-corpus/`, and it pushes back the manifest
that authorises the device to delete what the Mac verifiably received. devicectl
has no recursive pull, so this is one `copy from` per file — on a large backlog it
is the loop's wall-clock bottleneck, and device-side slimming is the mitigation
rather than a faster transport. `PULL_DIR=<path>` re-ingests a directory already
on disk and needs no device.

Read the summary, not the exit code. A pull exits 0 in plenty of states worth
looking at: `db_integrity=absent`, `outcomes=0` or `joins_resolved=0` on a pull
that carried notes means the notes landed with nothing to attach to.

Notes are never evicted by any in-app path and leave the phone only once a
manifest confirms the Mac holds them, so a note is safe there indefinitely.

### Reclaiming the space

`make field-discard CONFIRM=yes` is the only destructive target. In order, it:

1. pulls the notes and the events DB off the phone (`make field-notes`);
2. builds the replacement (`make app`), so a missing model or a broken compile
   fails here rather than after the phone has been wiped;
3. deletes `medata-corpus/captures/` and `medata-corpus/pulls/`;
4. uninstalls the app, which removes its whole data container;
5. installs and launches the build from step 2, honouring `CONFIG` and
   `SEGMENTER`.

**What survives**: on the Mac, the notes, the per-pull database snapshots and
`index.sqlite` — three orders of magnitude smaller than the bundles, and what the
triage ledger and the alignment report are computed from. The index keeps every
capture row, so `field_report`'s denominators stay honest; `field_diagnose` and
`derive_dataset` already guard on the fixture existing, so a discarded capture is
skipped rather than fatal. **What does not**: every capture bundle on both sides,
and the phone's settings and local meals database.

Step 3 is a container wipe rather than a selective prune because
`FieldMaintenance` deletes a bundle only when the pulled manifest carries its
SHA-256, and the Mac cannot know that hash without reading the file — which is
the copy being avoided. That check is the handshake's whole safety property, so
the discard goes around it rather than weakening it.

It is irreversible on both sides, and there is no backup: a second copy of tens
of gigabytes is the thing being reclaimed. `CONFIRM=yes` is the only guard, and
the pre-flight prints both sides' counts before anything is deleted.

### Turning material into work

`make field-triage` regenerates
`specs/estimation/ml-feedback-loop/triage.md` from the index. It is
merge-preserving — checked items keep their `routed:` record — and refuses a
ledger with uncommitted edits, so a routing pass in flight cannot be clobbered.
Routing each unchecked item to exactly one destination is the agent step; the
destinations are enumerated in the spec's `design.md`.

`make field-diagnose [CYCLE=<n>]` replays every annotated capture through
`HarnessCLI diagnose`, attributes each estimation-versus-stated gap, and writes
`cycles/cycle-<n>/tasks.md`. That file holds only tasks fireable from the corpus
and ends in a terminal close task, so a run over it terminates by construction;
work needing the device or a human is a STOP line, never a task.
`REPLAY_SHA=<sha256>` stamps version skew explicitly.

`make field-close CYCLE=<n>` is the loop's **sole committer**: agent sessions
executing a cycle file draft overlay entries into `drafts.json` and never run git
themselves. Each draft passes six guards in order — cause-specific evidence,
evidence floor, bounds, one degree of freedom per class, weighed-truth veto,
build gates — and the first refusal demotes it to a patch in the cycle directory.
Survivors land one commit each, pairing the overlay edit with the regenerated
databases. Run it in a dedicated worktree: it refuses a dirty tree, and refuses
`research` and `main`.

```
make worktree name=field-loop branch=field-loop
make field-close CYCLE=3 REPO=../medata-field-loop APPLIED_AT=2026-08-30
```

`PROBE_IMAGE=<path>` reads one image through every enabled reference adapter and
records the result in the verdict, so a broken standby is found before the active
adapter needs replacing.

### Measuring and deriving

`make field-report [CYCLE=<n>] [OUT=<file>]` answers whether the gap is
shrinking. Output is `key=value` lines with every figure beside its cell count
and `insufficient` below the minimum. Captures already used as training material
are excluded from the evaluation set and both set sizes are printed, so the
metric cannot be inflated by evaluating on trained-on captures. Stated values are
labelled developer-stated throughout — the weighed surface is `benchmark_meals`,
not this report.

`make field-derive OUT=<merged corpus> | CALIBRATION_OUT=<dir>` turns the
captures carrying signal into training and calibration material. Field data joins
train and val only, never the frozen leak-free anchor, capped at the configured
share of the merged train set. Every consumed capture leaves the alignment
metric's evaluation set, which is why the evaluation floor blocks a derivation
that would starve a cell. It prepares inputs and records the commands; launching
a run stays a human step.

```
make field-derive OUT=data/merged_foodseg_foodrec2022 IDENT=anthropic:claude-opus-5:2026-06
make field-derive CALIBRATION_OUT=/tmp/field-calibration
```

The calibration side takes only weighed truth, and that is entered on the phone:
the review screen's "…" → **Weighed mass** (field builds) writes a
`fidelity=weighed` `benchmark_meals` row linked to the capture's outcome, which
`make field-pull` carries in `meals.sqlite`. No hand edit of `index.sqlite` is
needed; `docs/agent-notes/field-truth-sessions.md` has the data path.

`CALIBRATION_OUT` is written as one directory per segmenter checkpoint, and each
`<dir>/<checkpoint>/` is a complete HarnessCLI input; the derivation prints the
`accuracy` and `calibrate` command for each. The loader refuses a bundle from
another checkpoint because β_c belongs to the segmenter that labelled the volume,
so a mixed set is split rather than admitted. Each bundle is an APFS clone of the
corpus copy with the weighed truth appended as fixture fields 17/18, which is
where `accuracy` reads it — on APFS no data is copied, and the corpus files are
never written. The group's `run_summary.json` carries, per fixture, that truth
and the review: the classes the user relabelled and the regions they rejected,
from the corpus `corrections` table. A bundle no longer in `captures/` is found
in `pulls/*/captures/` or `reports/` when its SHA-256 matches the indexed capture.
A re-run replaces the groups an earlier run wrote.

`make field-score [OUT=<dir>]` is the whole scoring pass in one command: it runs
the calibration derivation into `OUT` (default `.build/field-score/`), then
`accuracy` and `calibrate` over each checkpoint group with that group's run
summary, and prints:

- one line per capture: path, support plane, scored volume, mass and carbs
  against the weighed truth with their errors, the same meal priced at the
  segmenter's own labels, and the classes after review;
- the set's MAPE and MAE for carbs as reviewed, mass as reviewed, and carbs as
  labelled;
- per checkpoint, the β `calibrate` baked or why it baked none — the 30-plate
  floor, and each plate the purity or support-plane gate excluded.

Given `--ingest-summary`, `accuracy` and `calibrate` apply the review before
scoring: a renamed region's volume moves to the class the review named, a
rejected region is dropped, and the meal is re-priced at β = 1. In `calibrate`
this happens before the τ_purity gate, which would otherwise drop every plate
whose segmenter label differs from the truth's class. Amount corrections are not
applied. A Nutrition5k or MetaFood3D summary has no review, so those runs are
unchanged. Each group's harness JSON and stderr stay beside its bundles
(`accuracy.json`, `accuracy.log`, `calibrate.json`, `calibrate.log`). The
replays use the debug HarnessCLI and take about four minutes for five captures.

### Exporting the calculus

`make field-export [OUT=<file>]` emits one JSONL record per capture. Every
estimation quantity the device records lives in `outcomes.measurements_json` — a
single opaque TEXT column that neither `field-report` nor `field-derive` reads —
so this promotes it to named fields and joins each capture to its corrections and
any weighed truth. Refused rows are included and are the point: a two-view
refusal is the evidence the non-LiDAR fallback is measured on, and it is the row
carrying both tilts and the card candidate count.

**Sentinels export as null.** `SupportPlaneFitStats` documents `-1` as "the fit
refused before a residual was computed", and the refusal path returns a
default-constructed value, so a refused row's `candidates=0 inliers=0
residual=-1` describes nothing having run. Exported raw those become zeros and a
negative millimetre no fit produces. Each is emitted `null` with a
`placeholders` list naming it, so a later training or calibration pass cannot
learn from padding. On the corpus as of 2026-09-29: 183 rows, 289 suppressed
placeholders.

`fixture_present` says whether the bundle survived the last `field-discard` —
`false` means the row is readable but not replayable.

### Where the corpus lives

`<repo-parent>/medata-corpus/`, resolved from `git rev-parse --git-common-dir`
rather than `--show-toplevel`. In a worktree the common directory points back at
the main checkout, which is the property wanted: every worktree, including the
nested ones agent tooling creates, sees the same corpus instead of growing a
private one beside itself. `$MEDATA_CORPUS` overrides it and is read fresh on
every call, which is how the tests point at a scratch corpus per case.

## Tests

`make test` runs the SwiftPM suites and prints **both** totals — XCTest and
swift-testing. Never report one framework's slice as the test count. It skips the
roughly 20-minute support-plane corpus beam search, which is `make test-corpus`.

`make test-python` runs the two Python suites as two pytest invocations, because
both directories carry a `conftest.py` and the field-loop modules import theirs by
name, so pytest cannot collect them together. Xcode's `python3` has no pytest, so
this usually needs `PYTHON=/opt/homebrew/bin/python3` — the same escape hatch
`make food-db` documents. As of 2026-10-03 it is 129 food-DB tests and 264
field-loop tests.

The app-target files under `MeData/Tests/` and `MeData/UITests/` are
documentation contracts, not an executable suite: no committed test target runs
them.
