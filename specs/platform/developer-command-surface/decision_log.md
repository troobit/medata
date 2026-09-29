# Decision Log: Developer Command Surface

## Quick Decisions

| ID | Date | Decision | Rationale |
|----|------|----------|-----------|
| Q1 | 2026-09-29 | Generate `make help` from a one-line `##` comment per target | The hand-written 52-line `help` had already drifted; a generated one cannot |
| Q2 | 2026-09-29 | `logs-device` → `logs` | Nothing else in the surface collects logs, so `-device` distinguishes it from nothing |
| Q3 | 2026-09-29 | `field-test` → `test-python`, and it runs the food-DB suite too | Two suites, one reason to run them; the name says which language, not which spec |
| Q4 | 2026-09-29 | Leave old target names standing in `CHANGELOG.md`, completed `tasks.md` files and bugfix reports | Those record what was run on a date; rewriting them would falsify the record |
| Q5 | 2026-09-29 | Prose lives in `docs/build-and-field-loop.md`, not in Makefile comments | A Makefile comment is read by whoever is already editing the Makefile; the audience for the loop's contract is whoever is about to run it |
| Q6 | 2026-09-29 | Derived data moves to `<checkout>/.build/xcode/<CONFIG>` | Replaces three hand-declared `DERIVED_*` variables, and the old fixed `/tmp/medata-<config>` paths were shared between checkouts — Xcode records absolute paths under `SourcePackages/checkouts`, so a worktree build corrupted the main checkout's package resolution (hit while verifying this work) |
| Q7 | 2026-09-29 | `field-discard` deletes `pulls/` as well as `captures/` | The ingest hard-links the wire copies into `captures/`, so leaving `pulls/` leaves the same bytes behind under another name |
| Q8 | 2026-09-29 | No index schema change for discarded captures | `field_diagnose` and `derive_dataset` already guard on the fixture existing, so the rows need no content-absent flag to be skipped safely |

---

## Decision 1: Name device targets after the configuration and segmenter axes

**Date**: 2026-09-29
**Status**: accepted

### Context

Seven targets covered a 3x2 matrix of Xcode configuration (Debug, Release,
ProductRelease) against segmenter source (the real `.mlpackage`, or the
`DEV_STUB_SEGMENTER` build), crossed with whether the build installs. Neither
axis appeared in any name. `deploy-device` deploys to the device, and so do
`deploy-release`, `deploy-release-stub` and `deploy-product`; `build-app` and
`build-release-check` differ in configuration and destination but read as
different kinds of thing; `build-release-check` is a build, not a check.

Choosing what to run therefore meant reading the recipes, and the help text grew
a paragraph per target to compensate — the classic sign that the names carry no
information.

### Decision

Two axes, named: `CONFIG=Debug|Release|ProductRelease` and
`SEGMENTER=model|stub`. Two verbs: `make app` (build, no device) and
`make deploy` (build, install, launch). Four one-word targets for the daily
combinations: `debug`, `dev`, `dev-stub`, `product`.

### Rationale

`CONFIG` is Xcode's own vocabulary — the values are the literal configuration
names in `MeData.xcodeproj`, so there is nothing to translate when reading an
`xcodebuild` invocation or a build log. `SEGMENTER` names the thing that has
actually cost days when it was wrong (`docs/agent-notes/device-build-and-test.md`
records testing against the stub unknowingly), and it is now impossible to
select by accident: it is a word in the command.

The four shortcuts exist because the general form is not what anyone types
twenty times a day. They are one line each and delegate to `deploy`, so there is
one recipe, not five.

### Alternatives Considered

- **Keep the verb-prefixed names and only document them better**: The help text
  was already four times the size of the recipes it described - Rejected because
  documentation cannot fix a name that does not distinguish its target from its
  siblings.
- **One `make deploy` with variables and no shortcuts**: Maximally small -
  Rejected because `make deploy CONFIG=Release SEGMENTER=model` is the single
  most-run command in the repo, and making the common case verbose to keep the
  target count at one is a false economy.
- **Name by purpose (`make ui`, `make capture`, `make ship`)**: Reads well and
  matches what the developer is about to do - Rejected because the mapping from
  purpose to configuration is a convention nothing enforces, and the moment a
  fourth purpose appears the names stop partitioning.

### Consequences

**Positive:**
- The command states the configuration and the segmenter, so a transcript or a
  shell history records which build was made.
- `CONFIG=Debug SEGMENTER=model` can be refused with a reason, because the
  combination is now expressible. It was previously just an absent target.
- Adding a configuration is a value, not a target.

**Negative:**
- Every old name is gone, and 40-odd files mention one. Living documents are
  updated; historical records deliberately are not (Q4), so an old task file
  now names a target that does not exist.
- `make dev` and `make debug` are one letter apart in meaning and three in
  spelling. `dev` is Release with the real model; `debug` is the Debug
  configuration.

---

## Decision 2: One `tools/deploy.sh` for all three configurations

**Date**: 2026-09-29
**Status**: accepted

### Context

`tools/deploy_release.sh`, `tools/deploy_release_stub.sh` and
`tools/deploy_product.sh` were 246 lines implementing overlapping subsets of the
same five steps: resolve the build stamp, check or substitute the segmenter,
`xcodebuild`, gate, install-with-retry and launch. The build-stamp expression
appeared in all three plus the Makefile — four copies, each with a comment
stating that it matched the others. The `CoreDeviceError 4000` retry appeared
four times. `deploy-device` had no script at all and open-coded the install in
the Makefile, so it was the one path where a fix to the install step had to be
remembered separately.

### Decision

One `tools/deploy.sh`, parameterised by `CONFIG`, `SEGMENTER` and `INSTALL`. It
owns the build stamp, and the Makefile no longer computes one.

### Rationale

The five steps are the same steps; only their parameters and which of them run
differ. Expressing that as one ordered script with two conditionals is smaller
than three scripts and removes the class of bug where a fix lands in one copy —
which had already happened to the install retry, absent from the Debug path.

Making the script the sole author of the build stamp matters more than the line
count. The stamp is the repo's mechanism for proving which binary is on the
phone; four independent implementations of it were four chances for the printed
stamp and the compiled-in stamp to disagree, which is exactly the failure the
stamp exists to catch.

### Alternatives Considered

- **Keep three scripts, factor the shared parts into `tools/lib/deploy_common.sh`**:
  Conventional, and keeps each entry point readable - Rejected because after
  factoring out the five shared steps each script is its own name plus two
  variable assignments, which is a Make target, not a file.
- **Move everything into the Makefile**: No shell files at all - Rejected
  because the `Package.swift` edit needs an `EXIT` trap to guarantee the revert,
  and a Make recipe runs each line in its own shell.

### Consequences

**Positive:**
- The build stamp, the install retry and the launch line have one
  implementation each.
- The Debug path gains the install retry it never had.
- A new configuration is a case label.

**Negative:**
- One file now carries three configurations' worth of conditionals; a reader
  after only the ProductRelease gate reads past the stub machinery to find it.
- A bug in `deploy.sh` breaks every deploy rather than one.

---

## Decision 3: `make field-discard` clears both sides and keeps the notes

**Date**: 2026-09-29
**Status**: accepted

### Context

`medata-corpus/captures` is 23 GB, and the device accumulates capture bundles
until the in-app slimmer arms at 25 GB. Copying that backlog is the field loop's
wall-clock bottleneck — `field_pull.py` does one `devicectl copy from` per file
because devicectl has no recursive pull — and `make field-pull` was the only path
that let the device delete anything, because deletion is authorised by a manifest
naming what the Mac verifiably received. So the only way to reclaim space was to
spend hours first receiving material nobody wanted, which is what `device-reset`
did.

There was no way to reclaim the Mac's 23 GB at all.

### Decision

One target, `make field-discard CONFIRM=yes`, reclaims the loop's space on both
sides. In order: pull the notes and the events DB (seconds), delete
`medata-corpus/captures` and `pulls`, uninstall the app — which removes its whole
data container — and reinstall at the ambient `CONFIG` and `SEGMENTER`. It
replaces `device-reset`.

Notes, the per-pull database snapshots and `index.sqlite` survive on the Mac. The
index keeps every capture row.

### Rationale

Retention of capture bundles buys re-derivation — replaying a capture through a
newer checkpoint. Retention of notes buys the triage ledger, which is keyed by
note id and regenerates merge-preservingly from `index.sqlite`; losing either
would silently drop routed work. The two have wildly different costs: 23 GB
against 27 MB. Discarding the expensive half and keeping the cheap half is
therefore not a compromise, it is the shape of the problem.

**The device half is a container wipe, not a selective prune, because a selective
prune is not expressible.** `FieldMaintenance.deleteIfHashMatches` deletes a
bundle only when the pulled manifest carries its SHA-256, and the Mac cannot know
that hash without reading the file — which is the copy being avoided. That check
is the handshake's entire safety property. Authorising deletion of uncopied
bundles would mean a new manifest verb that deletes without verifying, in the one
component whose job is to verify before deleting, and it would take effect only
after the app carrying it was itself built and deployed. Removing the container is
cruder, needs no app change, and is honest about being total.

Keeping the index rows costs nothing and keeps `field_report`'s denominators
honest — the capture happened, and an alignment figure computed over a corpus that
forgot it would look better than the truth. No schema change is needed for that:
`field_diagnose` and `derive_dataset` already guard on the fixture existing.

Both sides in one target, rather than two, because the developer's intent is
"reclaim the loop's space", and a target that cleared one side would leave the
other to be remembered.

### Alternatives Considered

- **A manifest entry that deletes without a hash check**: The selective prune,
  and the literal first plan for this work - Rejected because it puts a
  delete-without-verifying verb inside the component whose contract is
  verify-before-delete, and because it needs an app change to take effect at all,
  so it could not clear a phone running today's build.
- **Copy each bundle to a temporary file, hash it, authorise the delete, discard
  the copy**: Selective, and needs no app change - Rejected because the copy *is*
  the bottleneck; it reclaims the space at exactly the wall-clock cost the target
  exists to avoid.
- **Prune the Mac only, leave the device to the in-app slimmer**: Simpler, and
  the slimmer already sweeps to a 20 GB watermark - Rejected because the
  slimmer's job is to keep recording possible, not to reclaim on demand; it arms
  at 25 GB, so a developer wanting an empty phone still waits.
- **Archive to external storage before deleting**: Reversible - Rejected because
  a 23 GB archive is the thing being reclaimed, and an archive nobody will read
  is a slower delete.
- **Delete notes too, since they are addressed within one pull**: Matches the
  stated retention need - Rejected because they cost 27 MB and the triage
  ledger's routed records are keyed to them; the saving is a rounding error and
  the loss is tracked work.
- **Extend `field-pull` with a `--discard` flag**: No new entry point - Rejected
  because `field_pull.py` already refuses `--notes-only --prune` on the grounds
  that pruning is a full pull's business; adding a flag that deletes without
  copying to the tool whose contract is "delete only what was copied" puts two
  opposed guarantees in one file.

### Consequences

**Positive:**
- 23 GB is reclaimable in seconds, and the phone can be emptied without a
  multi-hour copy.
- The triage ledger and the alignment report are unaffected, because their
  inputs survive.
- `device-reset` disappears: it was this target with a full pull in front of it.
- The manifest handshake is untouched, so its safety property is intact.

**Negative:**
- Irreversible on both sides, and the device half is total — settings and the
  on-device meals database go with the captures, which a selective prune would
  have spared. `CONFIRM=yes` and the printed pre-flight are the only guards.
- The phone has no app between the uninstall and the install. The build runs
  before the uninstall, so the common failures (no model bundled, a broken
  compile) cannot reach that window, but an install or launch failure still
  leaves the phone bare until the deploy is rerun.
- `field-diagnose` and `field-derive` see a corpus whose replayable set is
  smaller than its recorded set, so a cycle run after a discard has less
  evidence available than its index implies.

---

## Decision 4: No tagging automation in the deploy targets

**Date**: 2026-09-29
**Status**: accepted

### Context

The brief for this work asked for `make dev` to optionally "tag a commit" — the
UI-attempt convention in `CLAUDE.md` and
`docs/agent-notes/device-build-and-test.md` names each attempt
`<surface>-attempt-N`, tagged on a clean tree so the build stamp reads without
`-dirty` and the sha identifies the attempt. Automating the tag alongside the
deploy is an obvious convenience: the deploy already knows the sha and already
knows whether the tree is clean.

### Decision

The deploy targets do not tag. `make dev` reports the stamp and the bundled
model; `git tag` stays a separate, hand-run command.

### Rationale

`CLAUDE.md` states the invariant directly: "Git branches and tags are the whole
mechanism — build no tooling around it." A `TAG=` variable is tooling around it,
and it is the kind that grows: the moment the deploy can tag, it wants to refuse
a dirty tree, then to check the name against the `<surface>-attempt-N` pattern,
then to list the existing attempts so `N` is right. That is a tag manager, built
into a deploy script, for a convention whose entire value is that nothing reads
it.

The friction being removed is one `git tag` after a deploy that already printed
the sha. That is not enough friction to justify the first step onto that path.

### Alternatives Considered

- **`make dev TAG=<name>` that tags on success and refuses a dirty tree**: The
  literal request; saves one command - Rejected as above; the invariant is
  explicit and the saving is one line of shell.
- **Print the suggested `git tag` command after a clean deploy**: No
  automation, and removes having to recall the convention - Rejected as
  needless: it fires on every clean deploy, and the overwhelming majority of
  deploys are not attempts. A hint that is wrong nineteen times out of twenty
  is noise.

### Consequences

**Positive:**
- The attempt convention stays a convention. Nothing can drift from it, because
  nothing implements it.
- `deploy.sh` stays a build-and-install script and never runs a mutating git
  command.

**Negative:**
- Tagging an attempt remains two commands, and forgetting the second one is
  still possible. The record of an untagged attempt is its build stamp in the
  device log, which is recoverable but not indexed.

### Impact

`make model CHECKPOINT=<path>` is the half of the brief that was built: which
model a build binds becomes a stated argument. The tagging half was declined.
