# ML feedback loop

Spec: `specs/estimation/ml-feedback-loop/`. Two halves — a `FIELD_LOOP`-gated
on-device note layer, and a Mac-side ingest/diagnose/close cycle. This note
covers the **Swift core** phase (tasks 1–6) and the **on-device capture** phase
(tasks 7–12); the Python half gets its own section as it lands.

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
