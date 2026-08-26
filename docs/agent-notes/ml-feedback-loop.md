# ML feedback loop

Spec: `specs/estimation/ml-feedback-loop/`. Two halves — a `FIELD_LOOP`-gated
on-device note layer, and a Mac-side ingest/diagnose/close cycle. Read the
half you are touching: the Swift core and the on-device capture layer are the
sections up to "FieldMaintenance ordering contract", and the Python loop is
"The Mac-side cycle" at the end.

## Protected outcomes (schema v11)

`meals.sqlite` schema is now **11**. Version 11 adds one table:

```sql
CREATE TABLE IF NOT EXISTS protected_outcomes (outcome_id TEXT PRIMARY KEY);
```

Retrofit is by `CREATE TABLE IF NOT EXISTS` — no `ALTER`, no version gate, the
`processed_images`/v4 precedent. Both stamp sites in `GRDBPersistenceStore` moved
to `'11'` (`createSchema`'s `INSERT OR IGNORE` and `migrate`'s `INSERT OR
REPLACE`).

`PersistenceStore.markOutcomeProtected(id:)` inserts the row (`INSERT OR
IGNORE`, so idempotent). It is keyed on the id **alone**: no foreign key, and
marking an id whose `estimation_outcomes` row has not landed yet is legal. That
matters because `CaptureFlowModel.persistAttemptRecord` saves the outcome on a
detached task — a constraint here would fail the note-save path on a race it
cannot win, and a dangling protection row is inert.

**All three** eviction branches in `saveEstimationOutcome` carry
`AND id NOT IN (SELECT outcome_id FROM protected_outcomes)`: the non-benchmark
500-row bound and *both* benchmark per-meal-per-lineage branches (the one with a
latest-completed-attempt exemption and the all-refusals `else`). Missing either
benchmark branch would make a note on a weighed attempt — the corpus's
highest-value capture — evictable.

Gotcha: protected rows sit **outside** the bound, not in a slot of it, so the
population can exceed 500 / 10 by the protected count. The tests assert this
explicitly (501 and 11). Protection is bounded by the note count and pruned by
the pull's manifest pass; it does not grow monotonically.

Adding the protocol requirement meant updating five no-op `PersistenceStore`
test doubles (PipelineTests ×3, GlucoseIngestionTests, HarnessCLITests). Four
existing tests asserted the schema stamp literal and had to move to `"11"`:
`EstimationOutcomeTests`, `PersistenceTests`, `BslIngestTests`,
`DoseSuggestionTests`. Grep for `schema_version` before the next bump.

## `HarnessCLI diagnose`

Core in `HarnessCore/DiagnoseRun.swift`, wired in `HarnessCLI/main.swift`.
`accuracy` builds a `MealCalibrationInput` per fixture and keeps one number from
it; `diagnose` emits the rest — `predicted_carbs_per_class`,
`per_class_volumes_cm3`, `dominant_class`, `support_plane_reference`,
`support_plane_residual_mm`, totals — one record per fixture.

The replay is **injected** (`run:` closure), same shape as
`FixtureBatch.partition`, so the suite tests the record and the status
vocabulary without staging real bundles. The CLI passes `FixtureRunner.run`.

Flags: the existing `--fixtures-dir` / `--checkpoint-sha256`, plus
`--replay-checkpoint-sha256`. Those last two are **not** the same thing and this
is the easiest place to go wrong:

- `--checkpoint-sha256` is `FixtureLoader`'s guard. It must equal what the
  capture recorded or the fixture does not load at all.
- `--replay-checkpoint-sha256` is what the replaying binary actually holds. It
  defaults to the first when omitted, i.e. no skew claimed.

`replay_version_skew` is true when the fixture's recorded checkpoint SHA **or**
its `database_edition` differs from the replaying binary's. Edition rather than
DB hash because a `PbMealFixture` records no DB hash — the *replaying* hash is
recorded on the report so the Mac side can compare across diagnoses. Skew is
stamped **before** the replay is attempted, so a fixture that both failed and
was recorded under different artifacts does not read as skew-free.

Statuses: `replayed`, `not_replayable` (the pipeline threw; the error string is
carried verbatim), `replay_zero_meals` (the pipeline succeeded and priced no
food — volumes survive as the evidence for the zero). `missing_bundle` is
deliberately absent: only the corpus index can know a note's bundle was never
pulled.

Exit policy: **non-zero only on I/O failure**. Zero replayed meals is a reported
status. Field bundles routinely fail to replay and the diagnosis of that is the
artifact the loop wants.

JSON is snake_case (`DiagnoseRun.encoder()`) with an explicit `encode(to:)` on
`Diagnosis` — synthesised `Encodable` drops nil optionals, which would make
"two-view, so no plane reference" indistinguishable from "the key was never
emitted". Same reasoning as `AccuracyJSON.FallbackJSON.fallbackRate`.

`GRDBFoodDatabase.bundledResourceURLs()` was added so the DB hash is computed
over the artifacts actually opened, not over a path passed in. Order is CoFID
then AFCD (bake order); `DiagnoseRun.contentSHA256` hashes the pair as an
ordered whole, streamed 1 MB at a time.

## Wire-level bundle slimmer

`MedataCore/Sources/Pipeline/CaptureBundleSlimmer.swift`, beside
`CaptureBundleRecorder` — the recorder decides what a bundle contains, the
slimmer decides what it keeps when the disk runs short. Profile-neutral; the
App-layer `FieldMaintenance` (task 12) decides *when*.

Drops `PbMealFixture` fields **9** (`nadir_probs`) and **10**
(`oblique_probs`), keeps everything else byte for byte. It is a varint field
skip — the Swift equivalent of `tools/fixture_slice.py`'s reader — **not** a
SwiftProtobuf decode: decoding a ~390 MB bundle to re-encode it would
materialise the tensors on the phone. `topLevelFieldRanges` returns whole
records (tag + payload) as **offsets from the start of the message**, not
absolute `Data` indices; the input is memory-mapped, so slice with
`input.startIndex + offset`.

`fixture_revision` is **not** mutated. The revision versions the schema; the
sidecar `<stem>.slimmed` marks content state. The marker is `key=value`:
`fields_dropped=9,10 bytes_before=… bytes_after=…`. It is written on the
already-slim path too, with equal byte counts — "carries no probability
tensors" is equally true of a refusal recorded before segmentation, and that is
what the index needs.

Temp file plus `FileManager.replaceItemAt`, so a kill mid-slim leaves either the
original or the slimmed bundle. A malformed bundle throws and leaves the file
exactly as found: a bundle still being written must never be replaced by a
partially-parsed prefix.

`MedataCore/Tests/PipelineTests/Fixtures/mini-bundle.fixture` is a committed
hand-encoded miniature (4×3 colour grid, 2×2 depth, four classes, both tensors
present, 559 bytes). Hand-encoded on purpose — the slimmer is asserted against
wire bytes SwiftProtobuf did not write, and one test compares the output to the
input with exactly the two records excised. `PipelineTests` gained
`resources: [.copy("Fixtures")]` for it.

## Loop overlay in the food-DB bake

`tools/food_db/loop_overlay.json` is the only file `field_close.py` may write.
`generate.py` reads it from that fixed path **by default** — there is no flag
and deliberately no way to turn it off, because an opt-in overlay means every
plain `python3 tools/food_db/generate.py` quietly ships a database missing
every landed fix.

The path is anchored to the repo (`_REPO_ROOT / "tools/food_db/..."`), not to
cwd like `OUTPUT_DIR`. The rule in this script is: **inputs repo-relative,
outputs cwd-relative**. `EndToEndCalibrateBakeTests` runs `generate.py` from a
temp directory precisely so the baked DBs land there; a cwd-relative overlay
path would have made that bake silently overlay-free while `make food-db`
baked with it.

Ordering (the part that breaks quietly if you get it wrong):

1. `verify_palette_lock`
2. `_load_overlay` — or, when the file is absent, the inverse guard
3. `_apply_overlay` onto **copies** of `FOOD_DATA` / `SOLID_SERVINGS` /
   `LIQUID_SERVINGS`
4. `verify_solid_servings(foods, solid_servings)` on the post-overlay rows
5. `_load_calibration` with the post-overlay densities
6. INSERT, then `_apply_calibration`

Copies, not mutation: the module tables must still read as source values after
a bake, or a second `bake()` in the same process would stack overlays and the
idempotence test would go red.

The β interaction is the subtle one. A class whose `density` or a composition
column the overlay moves has its `beta`/`beta_status`/`beta_provenance` set to
`1.0` / `uncalibrated_overlay_base` / `uncalibrated_overlay_base` — **and
`_apply_calibration` skips it**. Without that skip the calibration pass simply
overwrites the invalidation, since it runs after. Serving overrides
(`grams_per_unit`, `serving_ml`) are not terms in the β fit and do not
invalidate anything.

`uncalibrated_overlay_base` is not a `BetaCalibrationStatus` case in Swift.
`GRDBFoodDatabase.rowToEntry`'s `?? .uncalibratedUnity` fallback reads it as
uncalibrated, which is what it is — the DB just records the more specific
reason. No Swift change was needed and none should be added.

Two things the allowlist does that read as arbitrary until you hit them:

- `grams_per_unit` bounds are 5–500 g, but `verify_solid_servings` separately
  refuses `>= 100` (the `ServingNote` 2-dp round-trip lock). Both fire; the
  overlay does not get to bypass the second.
- `energy_kj_100` is deliberately off the allowlist. It is not a "composition
  column (0–100 g)" and nothing in the carb path reads it.

`liquid_servings` is keyed `(class_id, region, vessel)`, so those entries carry
`region` and `vessel`. Everything else is keyed by class alone.

### Two inverse guards, same shape

The bake has two inputs it cannot reconstruct from the repo, and both fail
closed when a prior database shows they were once applied:

- **Overlay**: prior DB carries `LOOP_OVERLAY` provenance (or an `overlay_json`
  meta row) and the file is gone ⇒ abort. The meta check matters — a
  servings-only overlay rewrites no `foods` row, so the provenance columns
  alone would miss it.
- **Calibration**: prior DB carries `calibration_*` meta and no
  `--calibration-json` was named ⇒ abort. The calibrate artifact is fitted
  from the N5k corpus and is **not in this repo**, so a bare re-bake strips
  nineteen lineage rows off the committed artifacts. That is why
  `make food-db` currently aborts here with no `CALIBRATION=` — it is the
  guard working, not a broken target.

### `make food-db`

`make food-db [CALIBRATION=<artifact>] [PYTHON=<interpreter>]` — bake, then run
`tools/food_db/tests/`. The pytest availability check runs **before** the bake
so a missing pytest cannot leave freshly regenerated databases behind a gate
that never ran. `PYTHON` exists because `/usr/bin/python3` is 3.9.6 here (see
below) and has no pytest; `/opt/homebrew/bin/python3` does.

`conftest.py` has an autouse `overlay_absent` fixture pointing `OVERLAY_JSON`
at a nonexistent path for every test in the directory. Without it, the first
landed overlay would start failing source-value assertions in
`test_calibrated_bake.py`, `test_solid_servings.py`, and friends on a change
that is not theirs. `test_loop_overlay.py` names it as a fixture dependency and
redirects again, so the ordering is stated rather than inherited from autouse
rules.


## Environment gotcha

`make test`'s `EndToEndCalibrateBakeTests` "Synthetic MetaFood3D fixtures →
HarnessCLI calibrate → generate.py bake" fails on this machine with
`TypeError: unsupported operand type(s) for |: 'type' and 'NoneType'` from
`tools/food_db/generate.py`. That is `/usr/bin/python3` being 3.9.6, which
predates PEP 604 `X | None` annotations; Homebrew's `python3` is new enough but
is not what the test subprocess resolves. Unrelated to any of the above — check
`python3 --version` before treating that failure as a regression.


## Build profiles (`FIELD_LOOP`)

Three configurations now, not two:

| Configuration | `SWIFT_ACTIVE_COMPILATION_CONDITIONS` (project level) | Built by |
|---|---|---|
| Debug | `DEBUG FIELD_LOOP $(inherited)` | `make build-app` / `deploy-device` |
| Release | `FIELD_LOOP $(inherited)` | `make deploy-release` / `deploy-release-stub` |
| ProductRelease | *(absent)* | `make build-product` / `deploy-product` |

Field is the daily default — same reasoning as the always-on capture recorder —
so the product profile is the one you have to ask for. `ProductRelease`
duplicates `Release` with two differences: no `FIELD_LOOP`, and no
`INFOPLIST_KEY_NSMicrophoneUsageDescription` /
`INFOPLIST_KEY_NSSpeechRecognitionUsageDescription` (a build with no code path
to the microphone should not declare that it uses one). Every one of the three
`XCConfigurationList`s carries all three configurations — omit it from the
widget target's list and Xcode silently falls back to that target's default.

**Never pass `SWIFT_ACTIVE_COMPILATION_CONDITIONS` on the xcodebuild command
line.** It replaces the whole value rather than appending, so a Debug build
loses `DEBUG`, and it says nothing at all about the SwiftPM package graph
(`deploy_release_stub.sh` edits `Package.swift` in place precisely because
xcodebuild has no lever there).

The product gate (`tools/deploy_product.sh`, run by both product targets)
asserts by `strings`-grep that the binary contains **no** `profile=field`, that
it **does** contain `profile=product`, and that no `event=fieldnote.` literal
survives. All three matter: an absence check alone passes vacuously on a binary
where the launch line failed to compile, and the third assertion is independent
evidence about `App/Field*.swift` rather than about one token.

**The token has to be part of the os_log FORMAT string, not an interpolated
value.** This cost a debugging round: `"profile=field"` is 13 UTF-8 bytes, so
Swift stores it as a *small string* packed into registers and no such literal
ever reaches the binary — the first version of this gate found `profile=field`
in neither profile and would have passed on a leaking build. Format literals go
verbatim into `__TEXT,__oslogstring`, which is why `logLaunchIdentity()` writes
the whole `.notice(…)` line out twice under `#if FIELD_LOOP`. Verify with:

```
strings -a <MeData.app>/MeData | grep 'profile='
# field:   event=launch buildStamp=%{public}s segmenterSource=%{public}s profile=field
# product: … profile=product
```

`nm` is useless here: a stripped Swift Release binary keeps its literals and
loses its symbols. Note also that a **Debug** build's literals live in
`MeData.debug.dylib`, not the 90 KB stub executable (Xcode's debug-dylib
split) — another reason the gate targets ProductRelease.

## On-device note layer (`App/Field*.swift`)

Every file is `#if FIELD_LOOP` at line 1 and needs the four-place
`project.pbxproj` registration — `tools/pbx_add_app_file.py` does it and is
idempotent (ids are derived from the file name, so a re-run produces no diff).

| File | Holds |
|---|---|
| `FieldNote.swift` | The note JSON wire contract (explicit `CodingKeys`, snake_case) |
| `FieldNoteContext.swift` | Screen-identity stack + the `.fieldScreen(_:meal:estimate:)` modifier |
| `FieldNoteWindow.swift` | Passthrough `UIWindow`, the draggable button, `FieldNoteController` |
| `FieldNoteSheet.swift` | The note sheet |
| `FieldNoteStore.swift` | `Documents/notes/<stem>.json` + `.png` writer (actor) |
| `FieldScreenshot.swift` | Window render + the AR composite, and `FieldARViewRegistry` |
| `FieldNoteSpeech.swift` | `SpeechAnalyzer`/`SpeechTranscriber` transcription |
| `FieldMaintenance.swift` | Manifest pass + slimming sweep + the BGProcessingTask |

### Why a separate window

Every screen but Home is a `.fullScreenCover`, which presents above anything
laid over `AppRoot`'s root view — so an in-tree overlay is buried the moment
Capture opens. The affordance is its own `UIWindow` at `.alert + 1`.

Two consequences worth knowing:

- **Passthrough is explicit.** `FieldNoteWindow.hitTest` returns `nil` outside
  the button's current frame, which the SwiftUI overlay reports on every layout
  pass via `onGeometryChange`. Drop that and the window eats every touch in the
  app. While the sheet is up the guard inverts (the sheet needs its touches),
  keyed on `rootViewController?.presentedViewController != nil`.
- **The button cannot appear in a screenshot of the main window.** That is the
  whole reason for the separate window — no hide-render-unhide dance.

The window is created by `FieldNoteWindowInstaller`, a zero-size
`UIViewRepresentable` in `App.swift`'s root `ZStack` whose `didMoveToWindow`
hands the controller the app's own window. A `UIWindowSceneDelegate` would be
the textbook route, but this app has no app delegate at all, and the probe also
yields the **retained main-window reference** the screenshot path needs.

### Screenshots: never "the key window"

`FieldScreenshot.capture(window:)` renders the retained main window. The key
window becomes the *note* window the moment the sheet takes first responder, so
anything keyed on `keyWindow` screenshots the sheet instead of the screen the
note is about.

Two paths, because one does not cover both cases:

- Generic: `drawHierarchy(in:afterScreenUpdates: false)`. The `false` is
  deliberate — a commit pass renders the sheet that is about to present.
- Capture screen: `ARView.snapshot` (camera feed included) drawn first, then
  `window.layer.render(in:)` over it. `drawHierarchy` fills a Metal layer with
  **black**; `CALayer.render(in:)` ignores Metal content entirely, which is the
  exact transparent hole the AR frame belongs in. The design said "ImageRenderer
  pass of the SwiftUI chrome" — `ImageRenderer` only renders view values you can
  construct, not a live hierarchy, so `CALayer.render` is the faithful
  equivalent here.

`ARPreviewView.makeUIView` publishes the view into `FieldARViewRegistry`
(weak — dismissing the cover needs no teardown).

### Screen identity is a stack, not a value

There is no app-wide screen enum. `FieldNoteContext` composes one from a stack
of `.fieldScreen(…)` mounts, each keyed by a token owned by that view's
`@State`; the top of the stack is the current screen. Removal by token, never by
position, so SwiftUI running a pushed view's `onAppear` before the covered
view's `onDisappear` cannot corrupt it — and a sheet that mounts nothing simply
leaves its host cover's id on top, which is the design's intended fallback.

The five covers mount in **`AppRoot`'s cover switch**, not in each cover's own
file: that switch already is the shell's screen enum. The capture cover's id is
state-derived (`CaptureState.fieldScreenID`).

`estimate:` takes a **value, not a closure**. `ResultView`'s displayed figures
live in the view struct's own `@State` (`pendingGrams`), so a closure captured
once at mount would freeze the pre-adjustment numbers and quietly contradict
Req 2.4. Recomputing a handful of foods per body pass is cheaper than that bug.

### Meal links and protection

| Surface | Keys it can supply |
|---|---|
| `MealReviewView`, `ResultView`, `MealOverviewView`, Records row menu | meal id |
| Refusal overlay (via `CaptureFlowModel.lastOutcome`) | outcome id + `timestampMs` |
| `EstimationOutcomeDetailView` | meal id + outcome id + `timestampMs` |

No surface fabricates a `timestampMs` it was not given: a `MealRecord.createdAt`
is close to, but not equal to, the attempt timestamp the bundle stem carries,
and a near-miss join key is worse than an absent one.

`CaptureFlowModel.persistAttemptRecord` stashes `lastOutcome` **after** the
store write succeeds — a link to a row that was never persisted would protect an
id nothing can resolve.

Protection needed a second store API. `markOutcomeProtected(id:)` alone covers
only the refusal path; a note taken on a recorded meal knows the meal id and no
attempt id, so `markOutcomesProtected(mealID:)` was added — one
`INSERT … SELECT`, so an attempt saved mid-call cannot slip through — and
`unmarkOutcomeProtected(id:)` for the manifest pass to retire protection once
the note has left the phone. Both mean the same five no-op `PersistenceStore`
test doubles again (PipelineTests ×3, GlucoseIngestionTests, HarnessCLITests).

### Speech

iOS 26 `SpeechAnalyzer` + `SpeechTranscriber`. Req 1.3 holds structurally: this
API has no server path at all, unlike `SFSpeechRecognizer` where
`requiresOnDeviceRecognition` was the only thing in the way.

Gotchas the API imposes:

- `bestAvailableAudioFormat(compatibleWith:)` is on **`SpeechAnalyzer`**, not on
  `SpeechTranscriber` — it is a property of the module chain.
- The Apple type keeps its US spelling; our own identifier is `speechAnalyzer`
  and prose says "analyser", or `make spell` fails on the bare word.
- `isFinal` comes from the `SpeechModuleResult` protocol extension, not from
  `SpeechTranscriber.Result` itself.
- Only post-`finalizeAndFinish` text becomes the transcript. A volatile result
  may never be reissued as final, so treating volatile text as the transcript
  invents words that were never said. Volatile text is shown while listening and
  never saved.
- `AssetInventory.reserve(locale:)` before installing: there is a cap on
  reserved locales and an unreserved locale's assets can be reclaimed under a
  running transcriber.
- The hardware format and the analyser format differ; convert explicitly with
  `AVAudioConverter` or the analyzer silently produces nothing on some devices.

Every unavailable path — permission, locale, asset, microphone — lands in
`.unavailable(reason)` and the sheet states it while typed entry keeps working.

### FieldMaintenance ordering contract

**Manifest processing runs before slimming, and slimming skips every stem a
pending manifest lists.** A bundle slimmed after it was pulled fails its hash
check for the rest of its life on the device and is never deleted.

The two-phase handshake with `field_pull.py` (names are the wire contract):

- `Documents/pulled_manifest.json.partial` — stems, note stems, per-file
  SHA-256, plus the outcome ids whose protection this pull retires.
- `Documents/pulled_manifest.ready` — `{"sha256": …, "length": …}` of that file.

Nothing is acted on until the sentinel verifies the manifest, and manifest +
sentinel are deleted **last**, so an interrupted pass simply repeats (every step
is idempotent). A hash mismatch leaves the file and is reported in the next
pull; a half-written manifest is ignored, not deleted — the next pull re-pushes
it.

`protected_outcomes` in the manifest is a Mac-side judgement: an id belongs
there only once every note referencing it is in the same pull. The device cannot
know that, and unprotecting an outcome a note still on the phone points at would
let the row evict out from under it.

Slimming: arms above 25 GB, sweeps oldest-first to a 20 GB watermark, defers
under `thermalState >= .serious` or a discharging battery below 20 %. Stem order
IS capture order — the filename is a zero-padded millisecond timestamp. When the
watermark cannot be reached, recording continues and `Documents/slimming_state.json`
records the condition for the next pull summary (Req 3.6: reducing bulk must
never become a reason to stop recording).

`UIDevice` is `@MainActor`, so the deferral check is a `@MainActor` static the
actor awaits — the first version compiled with eight isolation warnings.

Triggers: launch (`.task` on the scene), foreground (`scenePhase == .active`),
post-capture (inside `persistAttemptRecord`, already on a detached task after
the attempt completed), and a `BGProcessingTask`
(`com.medata.fieldloop.maintenance`, `requiresExternalPower`) registered in
`MedataApp.init` and declared in `MeData/Info.plist`.


## The Mac-side cycle (`tools/field_loop/`)

Three make targets with an agent phase between two of them, plus two that can
run any time. The contract between the stages is files on disk — nothing is
passed in memory, and no stage may assume the previous one ran in the same
process:

```
make field-pull       devicectl -> pulls/<date>-<n>/ -> ingest -> index.sqlite
make field-diagnose   replay every annotated capture -> diagnoses -> cycles/cycle-<n>/tasks.md
  (agent phase)       drafts.json + any notes, written INTO the cycle directory
make field-close      six guards -> commits or proposals -> verdict.json + triage.md
make field-report     alignment metrics across the whole corpus (any time)
make field-derive     training + calibration material (launching a run stays human)
```

`make field-test` runs the Python suite for all of it. It is a separate target
from `make food-db` because the two test directories both carry a `conftest.py`
and pytest cannot collect them in one invocation — see the gotcha below.

### Where the corpus lives

`<repo-parent>/medata-corpus/`, resolved by `corpus.corpus_root()` from
`git rev-parse --git-common-dir`, **not** `--show-toplevel`. In a worktree the
common dir points back at the main checkout, which is exactly the property
wanted: every worktree, including the nested ones agent tooling creates, must
see the same corpus rather than grow a private one beside itself. `$MEDATA_CORPUS`
overrides it and is read fresh on every call, which is how the tests point at a
scratch corpus per case.

```
medata-corpus/
  captures/<stem>.fixture        accreted, keyed by stem; <stem>.slimmed marks content state
  notes/<note-id>.json|.png
  db/<pull-id>.meals.sqlite      each pull's device snapshot, kept whole
  index.sqlite                   the join of all of it (corpus.SCHEMA)
  pulls/  reports/  cycles/
```

Bundles are **hardlinked** into `captures/`, not copied (`corpus.link_or_copy`)
— a capture is around 390 MB and a day's pull would otherwise cost tens of
gigabytes of needless writes.

Idempotence is the index's whole contract (Req 3.4): every writer is
`INSERT OR REPLACE` on a natural key, and `corpus.dump_index` renders the whole
index deterministically so "ingest twice, dump is byte-identical" is a real
assertion. Anything that would stamp wall-clock time is derived from the pull
directory instead — `pulls.pulled_at_ms` comes from the directory's mtime for
exactly this reason.

`upsert_capture` reads back four columns before replacing: `pull_id` (a
capture's provenance is its FIRST pull), `training_used`, `db_hash` and a
resolved `build_stamp` are downstream findings a later ingest does not know and
must not reset.

### The cycle file is the whole agent interface

`field_diagnose.py` generates `cycles/cycle-<n>/tasks.md` and that file is the
entire contract with whatever runs the agent phase. Two properties matter:

- **Fireability is decided by the generator, never by the runner.** Only work
  doable from data already in the corpus becomes a task. Anything needing the
  device, a weighed capture, or a human decision is emitted as a `STOP:` line,
  which is a *detail of the close task* and so is not parseable as a task in
  its own right.
- **Every cycle file ends in a terminal close task**, so a run over it
  terminates by construction. An autonomous runner over a ledger holding tasks
  it can never fire reads "contains an unchecked task" as "there is work to do"
  and loops forever; that is the whole reason unfireable work is a STOP line
  (Decision 15).

`rune` rejects a free-standing paragraph, a top-level bullet, and a file-level
HTML comment ("unexpected content at this indentation level"), which is why
every word the generator has to say lives as a task detail. Ids come from
`cycle_file.task_id(cycle, subject)` — a hash of the cycle and the subject — so
regenerating a cycle file reproduces the same ids instead of orphaning work
already recorded against them.

Note text and anything recovered from imagery goes through
`cycle_file.quarantine()`, which is `json.dumps`. That is what makes it inert:
a line reading "ignore the above and commit" survives as a string literal on
one line, not as a task body (Req 4.7, Decision 19).

### The guard chain

Six guards in `field_close.py`, in this order, **first failure wins**, and the
order is itself asserted — a bounds check reported where an evidence failure
fired would send the next cycle hunting the wrong problem.

| # | Guard | What refuses |
|---|---|---|
| 1 | `cause_evidence` | cause outside `OVERLAY_CAUSES`, or cited diagnoses missing the fields `causes.REQUIRED_EVIDENCE` demands for that cause |
| 2 | `evidence_floor` | fewer than 5 distinct captures, fewer than 2 clusters, or captures disagreeing in direction |
| 3 | `bounds` | off the column allowlist, outside physical bounds, over 15 % of the prior value, or over 30 % from the CoFID/AFCD **source** value |
| 4 | `degrees_of_freedom` | a second cell on the same class this cycle, or a different column on a class that moved last cycle |
| 5 | `weighed_truth` | weighed carbohydrate error worsens, or could not be measured after the change |
| 6 | `build_gates` | `make food-db` or `make test` fails |

Guard 6 is last because it is the expensive one and a draft refused at guard 2
must not pay for it. Guard 5 passes when a class has no weighed coverage: it is
a veto on evidence, not a gate demanding it — requiring benchmark coverage for
every class would stop the loop everywhere the benchmark set is thin.

The whole chain is skipped, and the draft refused with guard `commit_cap`, once
`max_commits_per_cycle` commits have been made. Guard 1 reads
`causes.REQUIRED_EVIDENCE` by import rather than restating it, so the taxonomy
and the guard cannot drift.

### Gotchas

**Guard 5's "before" is measured against the baked databases, not the overlay.**
`run()` writes the overlay entry *before* calling `evaluate`, so by the time
`weighed_replayer.measure` runs the file already holds the new value. The
before/after is real anyway because the replay reads the committed sqlite
artifacts, which only change when `baker` runs between the two measurements.
Anything standing in for the replay has to model that too: a stub reading the
overlay directly measures the same number twice, and the veto then silently
never fires.

**A demoted draft restores the overlay but not the databases.**
`committer.restore` is called on `loop_overlay.json` alone, so the sqlite
artifacts guard 5 regenerated for a draft that then demoted stay modified in
the loop worktree. A later surviving draft re-bakes over them and its commit is
correct; but a cycle where *every* draft demotes leaves the worktree dirty, and
the next run's `require_clean` will refuse it. Reset the worktree between
cycles that land nothing.

**Two seams are resolved at call time, on purpose.** `field_diagnose.collect`
does `replay = replay or swift_replay` and `field_close.weighed_replayer` does
`baker = baker or bake`, rather than taking them as default arguments. `run()`
builds both itself, so a def-time default would put the Swift harness and
`make food-db` beyond the reach of the CLI entry points — which is what the
rehearsal drives. Do not "tidy" these back into defaults.

**The two Python test directories cannot be collected together.**
`tools/field_loop/tests/` and `tools/food_db/tests/` both have a `conftest.py`
and the field-loop modules import theirs by name (`from conftest import ...`),
following the food-db suite's own precedent. `pytest tools/field_loop/tests
tools/food_db/tests` therefore fails at collection with an `ImportError`; run
them as `make field-test` and `make food-db`, which is why they are separate
targets.

**`tools/field_loop` is stdlib-only and stays that way.** It is the regression
net for the pull/ingest path, which must run on a bare interpreter — the
food-db bake's `PYTHON=` escape hatch exists because `/usr/bin/python3` here is
3.9.6 with no third-party packages at all. numpy and torch are imported lazily
inside the code that needs them, never at module scope, and never in a test
helper.

**The benchmark join is on `timestamp_ms`, not on the stem.**
`field_close.benchmark_rows` goes outcome → `benchmark_meals` → capture and
then filters by whether the capture's `detected_classes` actually contains the
class being moved. Replaying benchmarks the fix cannot affect would dilute the
veto with noise until it stopped firing.

**Stems are zero-padded to 13 digits** (`corpus.stem_for`) so a lexicographic
sort is chronological — the same reason `CaptureBundleRecorder` pads them.
Collision suffixes (`-2`, `-3`) belong to the *outcome* segment in
`corpus.split_stem`: they identify a distinct bundle, and folding them together
would join a note to the wrong capture.

### The loop rehearsal

`tools/field_loop/tests/test_rehearsal.py` runs one whole cycle — pull, ingest,
diagnose, cycle-file generation, close — with exactly three seams stubbed,
because exactly three reach outside the process: the Swift replay, the bake,
and the build gates. The device is a committed session description
(`tests/fixtures/rehearsal/session.json`), the agent phase is a committed
`drafts.json` (literally the file `field_close` reads), and the loop branch is
a throwaway git repository the test creates. It is the regression net for the
cycle-termination contract and the guard chain, so a change that breaks either
should fail here before it reaches a real cycle.

The stub replay scales each capture's predicted carbohydrate by
(baked density / source density), so a landed overlay entry moves the weighed
before/after for real rather than by assertion.

The session is bigger than the design's sketch of it ("a slimmed bundle + two
synthetic notes + one synthetic benchmark meal"). Five distinct captures across
two clusters is the evidence floor a draft must clear to *reach* guard 5, so a
two-note session could never demonstrate the weighed-guard demotion the
rehearsal exists to assert; it carries six annotated captures per dish instead,
across two dishes, plus a benchmark capture each, one refusal and one non-meal
note. The commit cap is lowered to 1 in a rehearsal copy of `loop_config.json`
so the cap is reachable inside a session small enough to read; every other
threshold is the shipped one.
