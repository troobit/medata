# Requirements: UI Wireframe Library

## Introduction

This repository already has a way of deciding what a screen should look like: build it more than once and
look at the results. `docs/agent-notes/device-build-and-test.md`, under "Comparing UI attempts on the phone",
describes the heaviest shape of that convention — "three whole App layers for one readout, on
`insulin-dosing-ui-{1,2,3}-on-research`, tagged `insulin-dosing-ui-attempt-{1,2,3}-on-research`. Nothing
merges until a person looks at all three and picks one." **Three options for one surface is the intended
outcome of that convention, not a failure of it.** This spec exists because the options, once made, are
unusable.

Three costs, all measured in this tree:

- **Costly to produce.** `git diff --shortstat research...insulin-dosing-ui-{1,2,3}-on-research` reports 8
  files / 542 insertions, 17 files / 1,565 insertions and 14 files / 1,015 insertions — **3,122 inserted
  lines of Swift and supporting code across three branches** to try three versions of one readout.
- **Costly to compare.** Each option needs `git checkout <tag-or-branch> && make deploy-device` to be seen at
  all, one at a time. The convention asks that "a person looks at all three"; nothing lets a person look at
  all three *at once*, so the comparison happens from memory, across rebuilds.
- **Impossible to reuse.** Having looked, there is no way to say *"attempt 2's total row with attempt 1's
  plate control"* except by writing another paragraph of prose — which restarts the same loop that produced
  the three attempts.

The third cost is what `specs/data/insulin-dosing/design-direction.md` demonstrates. Committed `0baaea8` on
2026-08-14, it is 443 lines carrying exact colour tokens quoted from `App/Colors.swift`, point sizes,
opacities, control metrics, a Dynamic Type shed order, motion behaviour, verbatim VoiceOver strings and an
explicit Forbidden list. Attempt 1 quotes it in its own code comments: it was followed, not ignored. It is
about as precise as prose gets, and it still could not be used, after the fact, to say which part of which
option to keep. **A document that describes a whole screen cannot be pointed at a region of one.** Prose is an
awkward medium for describing a look and a useless one for indicating a part of it; SwiftUI is an expensive
medium for trying one. A wireframe is cheap enough to try and concrete enough to point at.

The existing written target also rots, measurably and even under maintenance. `specs/PROCESS.md` requires
that "The target is an artifact, not a memory", and names `design-system/MASTER.md` and the per-page docs in
`design-system/pages/` as that artifact. Those files were last committed on 2026-08-09 (`4a469d6`); since
that date `App/` has taken 18 commits touching 29 files and 2,353 inserted lines.
`design-system/MASTER.md` carries a hand-copied Swift token list with 18 `static let` lines against the 22 in
`App/Colors.swift`. `design-system/wireframes/design-handoff-00/MANIFEST.md` row 11 states "Graph is the
launch root" while `App/AppRoot.swift:102` presents `HomeView`; that same manifest attributes its deviations
to "user direction after seeing the implementation", which is the dominant rot cause and one no forward-only
wireframe-to-code flow can catch.

This spec upgrades the artifact `specs/PROCESS.md` already mandates rather than inventing a new process. It
replaces prose pages as the primary reference with a catalogue of every surface and state the app can render;
preserves the current layouts by capture rather than by redrawing; gives each surface a named zone vocabulary
so that options can be pointed at, compared side by side and recombined; makes the option files themselves
disposable so they cannot rot, while keeping the record of what was chosen; derives colour tokens in one
direction from the code that owns them; and adds a per-spec surface-delta contract that records what each
option does to the set of surfaces, so options can be combined at that level too.

## Definitions

- **Surface** — a distinct renderable thing in the app: a screen, cover, sheet, overlay, component, control,
  row, shape, layout, representable, widget or notification. Not necessarily a `View`: `ChipFlow: Layout`,
  `MaskContourShape: Shape`, `ARPreviewView: UIViewRepresentable` and `ShareSheet:
  UIViewControllerRepresentable` are all surfaces and all invisible to a `struct .*: View` search.
- **State** — a distinguishable visual state of one surface, phrased as what you would see on the phone.
- **Catalogue id** — `<surface>/<state>` in kebab-case, e.g. `meal-review/very-low`. Rows of the frozen
  web generation carry a `web/`-prefixed surface, so their ids read as three segments —
  `web/home/loaded` is the surface `web/home` in the state `loaded`.
- **Generation** — one frozen capture of the app's appearance, named `-vN` (`ios-v0`, `web-v0`, `pages-v0`).
- **Option** (an **attempt**) — one of several renderings or implementations of the same surface, made to be
  looked at beside the others and chosen between. Several options for one surface is the expected shape of
  UI work here, not a defect. Options are numbered to match the existing `<surface>-attempt-N` tag convention
  in `docs/agent-notes/device-build-and-test.md`, "Comparing UI attempts on the phone", where `N` is "only
  the order the attempts were tried in — not a ranking, not a version".
- **Zone** — a named region of a surface: the part a person points at when comparing two options for the same
  screen — `total-row`, `scale-control`, `food-rows`. Zone names are declared once per surface in the
  catalogue and reused by every option for that surface. A zone is a naming convention for a region, not a
  code construct.
- **Composition** — an option expressed as a table of zone choices: which option each zone is taken from, and
  why. A composed option is an ordinary option.
- **Surface delta** — the set of surfaces a spec or an option adds, modifies, deletes or consolidates.

## Non-goals

- **No design SaaS and no JavaScript toolchain.** Not Figma, Penpot, Storybook, Tokens Studio or Supernova.
  No seat to buy, no `node_modules`, no build step a future reader has to reconstruct.
- **Not a SwiftUI wireframe catalogue.** Rejected on measured cost inside this repo — `design-handoff-00`
  rendered the same screens twice, at 1,033 lines of JSX plus 544 shared CSS against 2,229 lines of Swift —
  and on that same bundle's own rot record.
- **Not a visual-regression suite, and no new test target.** `CLAUDE.md` states the MVP gate is "does it
  build + does it look right on device" and "do not add new test scaffolding unless explicitly asked".
- **No tooling built around git tags.** `CLAUDE.md` says of the attempt convention: "Git branches and tags
  are the whole mechanism — build no tooling around it."
- **No replacement of the on-device gate.** This work moves the *choice* earlier, upstream of SwiftUI. The
  gate — a person looking at the screen of an iPhone 16 Pro — is unchanged.
- **No code generation and no new dependency between the UI and data layers.** See [2](#2). Zones generate
  nothing either; see [8.10](#8.10).
- **No hand-drawn wireframe for every catalogued state.** Preservation is by capture; see [3](#3).

## Accepted limits

These are known and accepted, not defects to be designed away. They are stated here rather than in
`design.md` because they bound what the spec can be held to.

1. <a name="L1"></a>**Nothing mechanically forces an option to be wireframed before it is built in SwiftUI.**
   That stays a habit. What this spec offers instead is that wireframing is *cheaper* than not — roughly 100
   lines of HTML against the 542, 1,565 and 1,015 the three insulin-dosing attempts cost in Swift. Cost is a
   better lever than a rule, but it is not a guarantee.
2. <a name="L2"></a>**A wireframe does not settle decomposition, state models or settings keys, and neither
   does a zone choice.** Attempts 1 and 2 of the insulin dose readout render the same line; one built it
   inline in `App/MealReviewView.swift`, the other extracted `App/DoseReadoutLine.swift`. A rendering has no
   channel for that distinction, and naming the region does not create one: a zone says what a region looks
   like, never how it is factored in Swift. Where the factoring matters it belongs in the decision, not in
   the zone table.
3. <a name="L3"></a>**Zones are a convention, not a construct.** Nothing checks that a SwiftUI implementation
   respects the zone boundaries its wireframe declared, and nothing can — no Swift type has to exist for a
   zone. Two people could agree a zone table and still build different things inside a zone. The value is
   only that they mean the same region by the same word.
4. <a name="L4"></a>**HTML can lie** about Dynamic Type, safe-area insets and `ViewThatFits`. A wireframe is
   evidence about layout and hierarchy, never about adaptive behaviour. It is a medium for choosing between
   options, not for proving one works.
5. <a name="L5"></a>**A composed option is still an option, not a decision.** Picking zones from three
   attempts makes a fourth candidate cheap to express; it does not make it right. It is looked at on the
   phone like any other, and the on-device gate is unchanged.
6. <a name="L6"></a>**Backfilling shipped surfaces serves the baseline, and that is its whole
   justification.** It is not claimed to help with generating options, because it does not: `App/*.swift` is
   already the canonical answer for a surface that ships. The backfill defines the app as it is, so that a
   change is described against a known baseline and the best parts of several options can be taken
   deliberately. Each part of this work states which goal it serves.
7. <a name="L7"></a>**The check is a real script with real maintenance cost**, not a 60-line grep. The
   estimate before writing it was 150–250 lines; `tools/check_surfaces.sh` as written is 330, against
   `tools/check_spelling.sh`'s 168 for a materially easier job. Understating this would be dishonest about
   what is being taken on.

## Requirements

### 1. <a name="1"></a>The Surface Catalogue

**User Story:** As the developer deciding what a screen should become, I want one file naming every surface
and state the app can render, so that a change is described against a known baseline instead of against my
memory of the app.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL maintain a single markdown catalogue carrying one row per surface ×
   state for every renderable surface of the iOS app, covering `App/` and `MeData/MeDataWidgets/`.
2. <a name="1.2"></a>Each row SHALL carry: the catalogue id, the surface, its file, its kind, the state, the
   state source, the owning view-model, the data it is bound to, the direction of that binding, its archive
   status, and its lifecycle status.
3. <a name="1.3"></a>The catalogue id SHALL be `<surface>/<state>` in kebab-case and SHALL be unique across
   the catalogue.
4. <a name="1.4"></a>The catalogue id SHALL be the single citation key for a surface state, used unchanged
   by specs, rune tasks, agent prompts, wireframe filenames and archive filenames.
5. <a name="1.5"></a>WHEN any document, task or prompt refers to a surface state, it SHALL cite the
   catalogue id and quote the state, and SHALL NOT cite a row number, a table position or a screen title.
6. <a name="1.6"></a>The state source SHALL name the thing in code that produces the state — an enum case, a
   predicate, or a stored flag — so that the row can be checked against the code rather than read as prose.
7. <a name="1.7"></a>The lifecycle status SHALL be drawn from a closed set distinguishing a surface that
   ships today (`shipped`), one designed but not built (`planned`), one withdrawn (`retired`), and one
   belonging to the frozen web generation (`web-v0`).
8. <a name="1.8"></a>The binding direction SHALL be drawn from the closed set `read`, `write`, `read-write`,
   `none`.
9. <a name="1.9"></a>WHERE a renderable type is deliberately not catalogued, the catalogue SHALL carry an
   explicit exemption naming that type together with a reason, in the same row, so an exemption cannot lose
   its justification. An exemption with no reason SHALL fail the check ([7.2](#7.2)) rather than excuse the
   type.
10. <a name="1.10"></a>WHERE a surface is reachable only under a Debug or UI-test harness path, it SHALL be
    catalogued, and its state source SHALL make the harness condition visible.
11. <a name="1.11"></a>The catalogue SHALL cover the iOS app on the authoritative branch. The SvelteKit
    screens on `main` SHALL be preserved by capture ([3.2](#3.2)) rather than as live rows; a row for a
    web-generation surface SHALL be carried only where that surface is being taken forward as a design
    input, and SHALL then carry status `web-v0`.
12. <a name="1.12"></a>The catalogue SHALL state its own coverage figures — surfaces catalogued, state rows,
    renderable types covered, exemptions, rows by status, and screenshots captured — so a reader can see
    what is *not* yet covered without running anything.
13. <a name="1.13"></a>The catalogue SHALL describe the app as it is. WHEN a row would describe an intention
    rather than the shipped behaviour, it SHALL carry status `planned` and SHALL NOT be counted as coverage
    ([7.5](#7.5)).

### 2. <a name="2"></a>The UI-To-Data Join

**User Story:** As someone holding a surface id, I want to know which data type is behind it without opening
both layers, so that translating between the app's UI and its data is cheap and does not tempt me to wire
them together.

**Acceptance Criteria:**

1. <a name="2.1"></a>Each row SHALL name the MedataCore product and type the surface is intended to be bound
   to, by name only, or `—` where the surface touches no data.
2. <a name="2.2"></a>Each row SHALL name the view-model that owns the surface, or `—` where none does.
3. <a name="2.3"></a>The join SHALL be documentation only: it SHALL introduce no import, no generated
   binding, no build-time coupling and no code of any kind. This is the mechanism `specs/PROCESS.md`
   prescribes for cross-domain capabilities, which "references the other domains' specs rather than
   duplicating them".
4. <a name="2.4"></a>The data cell SHALL record the *intended* binding and SHALL NOT be derived from the
   imports actually present in a view file. Deriving it would record today's violations as though they were
   the design: of the 22 `App/*View.swift` and `App/*Sheet.swift` files, 18 import one of the six named data
   products directly and 19 import some MedataCore module, which is the count `tools/check_surfaces.sh`
   prints as `layer_violations`.
5. <a name="2.5"></a>The view-model cell, by contrast, SHALL record what is actually there, so that `—`
   states plainly that no model owns the surface today.
6. <a name="2.6"></a>WHEN a reader has a catalogue id, the catalogue alone SHALL be sufficient to name the
   data type behind it; WHEN a reader has a data type, the catalogue alone SHALL be sufficient to name the
   surfaces intended to show it.

### 3. <a name="3"></a>The Frozen Archive

**User Story:** As the developer moving the app forward, I want the current layouts preserved exactly as
they render, so that nothing is lost when a surface is redesigned and nothing has to be redrawn by hand to
preserve it.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL preserve each shipped iOS surface state as a rendered screenshot in
   the `ios-v0` generation, named by its catalogue id, so that a screenshot and a row are found by the same
   key.
2. <a name="3.2"></a>The system SHALL capture the SvelteKit screens on `main` as the `web-v0` generation.
   This is an expiring option: it costs an afternoon while the toolchain still builds and becomes
   unavailable afterwards, so it SHALL be captured before any work that depends on that toolchain
   continuing to run.
3. <a name="3.3"></a>The system SHALL freeze the 14 prose page files currently in `design-system/pages/`
   verbatim as the `pages-v0` generation.
4. <a name="3.4"></a>An archived generation SHALL be write-once: once captured, no file in it is edited.
5. <a name="3.5"></a>WHEN an archived surface changes, the archive SHALL NOT be updated in place; a new
   `-vN` generation SHALL be captured instead, and the earlier generation SHALL remain readable.
6. <a name="3.6"></a>The archive SHALL be the preservation mechanism for existing layouts. The project SHALL
   NOT hand-draw wireframes for catalogued states as a preservation exercise.
7. <a name="3.7"></a>Once the prose pages are frozen, they SHALL NOT be maintained as a live reference; the
   catalogue and the archive together SHALL be the reference for how the app looks and behaves today.

### 4. <a name="4"></a>Disposable Wireframes

**User Story:** As the developer choosing between three looks for a screen, I want each option to cost a
short HTML file instead of an App layer, so that generating options is cheap and none of the files I generate
has to be maintained afterwards.

**Acceptance Criteria:**

1. <a name="4.1"></a>WHEN a surface is being decided, the system SHALL carry two or more self-contained HTML
   renderings of it. One rendering is a draft, not a decision. How the options are then compared and
   recombined is [8](#8).
2. <a name="4.2"></a>Each rendering SHALL be at true iPhone 16 Pro portrait metrics — 402 × 874 points, one
   point drawn as one pixel — so that a measurement taken from a wireframe is the measurement written in
   Swift.
3. <a name="4.3"></a>Each rendering SHALL declare, in its own file, the catalogue id it renders, its attempt
   number, the one thing it is testing, and the zones it marks ([8.3](#8.3)).
4. <a name="4.4"></a>Every hue in a rendering SHALL come from the generated token file ([5](#5)); a
   rendering SHALL NOT name a hue that `App/Colors.swift` does not define. Neutrals are the stated
   exception: black, white and white-at-opacity, which `design-system/MASTER.md` already treats as the
   OLED chrome convention rather than as tokens, and the greys of the furniture drawn outside the phone
   screen.
5. <a name="4.5"></a>A wireframe SHALL exist only while its surface is being decided. WHEN the
   implementation of that surface lands, the wireframe SHALL be deleted, the chosen rendering SHALL be
   captured into `ios-v0` under its catalogue id, and the corresponding catalogue rows SHALL move to
   `shipped`. What is deleted is the option *file*; the record of what was chosen is kept ([8.9](#8.9)).
6. <a name="4.6"></a>No requirement, task or check SHALL depend on a wireframe remaining accurate after its
   decision is made. Zero ongoing maintenance is the design: a file that does not outlive its decision
   cannot go stale.
7. <a name="4.7"></a>Wireframe attempt numbering SHALL match the existing on-device convention — "One tag
   per attempt: `<surface>-attempt-N`" (`docs/agent-notes/device-build-and-test.md`, "Comparing UI attempts
   on the phone") — so that attempt *N* of a wireframe and the tagged build implementing it carry the same
   number and the same surface name.
8. <a name="4.8"></a>The wireframes SHALL move option-making upstream of SwiftUI, so that generating three
   looks costs three short HTML files rather than three App-layer implementations; the three insulin-dosing
   attempts totalled 3,122 inserted lines of Swift and supporting code.
9. <a name="4.9"></a>WHEN an option is chosen, the reason SHALL be recorded in the owning spec's
   `decision_log.md`, because the wireframe that showed it is about to be deleted.

### 5. <a name="5"></a>The Colour Token Pipeline

**User Story:** As someone writing a wireframe, I want its colours to be the app's colours by construction,
so that no hand-copied token list can drift again.

**Acceptance Criteria:**

1. <a name="5.1"></a>The system SHALL derive the wireframe colour tokens from `App/Colors.swift` in one
   direction only.
2. <a name="5.2"></a>`App/Colors.swift` SHALL remain hand-written and authoritative, and the pipeline SHALL
   NOT modify any file under `App/`.
3. <a name="5.3"></a>Every `static let` token in `App/Colors.swift` SHALL appear in the generated output
   under a mechanical naming rule with no per-token exceptions, so that no remembered carve-out is needed to
   use one.
4. <a name="5.4"></a>The generated output SHALL declare that it is generated, name its source file, and name
   the command that regenerates it.
5. <a name="5.5"></a>WHERE a token has no fixed value because the platform resolves it per appearance, the
   generated output SHALL emit the dark-appearance value and SHALL mark that value as an approximation.
6. <a name="5.6"></a>The hand-copied Swift token list in `design-system/MASTER.md` SHALL be replaced by a
   pointer to `App/Colors.swift`, and the design system SHALL NOT carry a second hand-maintained copy of the
   token set. The current copy carries 18 of the 22 tokens.
7. <a name="5.7"></a>The pipeline SHALL NOT add a SwiftPM target and SHALL NOT change what `make build` or
   `make test` compile.
8. <a name="5.8"></a>Regenerating the tokens SHALL be a single command requiring no dependency beyond what
   the repository already assumes for its other generators.

### 6. <a name="6"></a>The Surface-Delta Contract

**User Story:** As the developer holding three options for a feature, I want each one to state plainly what
it does to the *set* of surfaces, so that I can compare the options at that level and combine them
deliberately — and so that a change nobody meant to make shows up as a difference rather than as a surprise.

The zone table ([8](#8)) composes options *within* one surface. This table records what an option does *to
the set of* surfaces. The two are complementary, and neither can express the other's content.

**Acceptance Criteria:**

1. <a name="6.1"></a>Every spec whose implementation touches the UI SHALL carry, in its `requirements.md`, a
   surface-delta table stating for each affected surface: the surface, the change, the catalogue id, and a
   note.
2. <a name="6.2"></a>The change SHALL be drawn from the closed set `add`, `modify`, `delete`,
   `consolidate`, and `—` for a surface named as deliberately out of scope — a row saying "this must
   survive unchanged". `private struct ChipFlow: Layout`, which still stands at `App/TrendsView.swift:503`
   and which attempt 3 removed, is the kind of surface such a row is written for.
3. <a name="6.3"></a>The surface-delta table SHALL be written before implementation begins, as part of the
   requirements gate `specs/PROCESS.md` describes — "Do not start design before requirements are agreed, or
   code before its plan exists".
4. <a name="6.4"></a>WHEN an option is reviewed, its actual surface set SHALL be compared against the table,
   and every surface it adds, deletes or consolidates that the table does not carry SHALL be recorded. The
   record exists so the options can be compared and combined at the level of the surface set; noticing an
   unintended change is a useful side effect of keeping it, not its purpose.
5. <a name="6.5"></a>WHEN an option omits a surface the table carries, that omission SHALL be recorded with
   the same standing as an unplanned addition, because it is equally a difference between the options.
   Attempt 1 building no activity surfaces at all, where attempts 2 and 3 both did, is the case this
   criterion exists for: it is a real difference between the options and belongs in the comparison rather
   than being found later.
6. <a name="6.6"></a>The record SHALL distinguish a difference that was commissioned — several options for
   one surface, deliberately, which is the expected shape of UI work here — from one nobody intended, and
   SHALL NOT treat the first as a defect.
7. <a name="6.7"></a>WHERE a spec changes no surface, its surface-delta table SHALL say so explicitly rather
   than being omitted, so that an absent table is always a defect and never a claim.
8. <a name="6.8"></a>The surface-delta table SHALL cite catalogue ids ([1.4](#1.4)); WHERE a spec adds a
   surface that has no row yet, it SHALL state the id it will take.
9. <a name="6.9"></a>WHERE an option's proposition is a change to the set of surfaces rather than to the
   inside of one, it SHALL be recorded here and SHALL NOT be forced into a zone table ([8.7](#8.7)).
   Attempt 3 is the worked example: `App/LogSheet.swift` on `insulin-dosing-ui-3-on-research` describes
   itself as "ONE manual-entry surface, three modes … This is that third sheet refusing to exist", which is
   a `consolidate` row naming the ids involved, and is not sayable as a choice of region.

### 7. <a name="7"></a>The Catalogue Check

**User Story:** As the developer, I want one command that tells me where the catalogue has fallen behind the
code, so that its authority survives contact with a month of commits.

**Acceptance Criteria:**

1. <a name="7.1"></a>The system SHALL provide a single command, invoked through the repository `Makefile`,
   that reports the catalogue's state against the code and exits non-zero when a failing condition below
   holds.
2. <a name="7.2"></a>The check SHALL fail WHEN a struct in `App/` or `MeData/MeDataWidgets/` conforming to
   `View`, `Shape`, `Layout`, `UIViewRepresentable`, `UIViewControllerRepresentable` or `Widget` has neither
   a catalogue row nor an exemption with a reason. The conformance set SHALL be wider than `View`, because
   `ChipFlow: Layout` — the component attempt 3 removed — is invisible to a `View`-only search.
3. <a name="7.3"></a>The check SHALL fail WHEN a case of a named state enum does not appear as a state row
   for its surface. The set of enum *names* is an editorial choice; their *cases* SHALL be read from the
   Swift source at check time, so that adding or renaming a case surfaces as a catalogue miss rather than
   passing silently.
4. <a name="7.4"></a>The check SHALL report coverage as counted numbers — covered and total — and SHALL fail
   WHEN the covered count regresses below a recorded baseline.
5. <a name="7.5"></a>A row alone SHALL NOT count as coverage; only a row describing a shipped surface SHALL.
   A green check over rows that are all `planned` is worse than today's visibly absent file.
6. <a name="7.6"></a>WHEN the covered count rises above the baseline, the check SHALL say so and name the
   value to record, so that progress is locked in deliberately rather than silently.
7. <a name="7.7"></a>The check SHALL list every view file importing a MedataCore data product directly, and
   this layer report SHALL be report-only: it SHALL NOT fail the check. Failing on it today would fail on 19
   of 22 files on the first run, and a check that always fails is a check that gets switched off. Promoting
   it to a failing condition is a later decision, to be recorded in `decision_log.md`.
8. <a name="7.8"></a>The check SHALL emit compact key=value lines naming its numbers, without narration.
9. <a name="7.9"></a>The check SHALL NOT be a test target and SHALL NOT be wired into the commit path;
   `specs/PROCESS.md` states that alignment is enforced "at the review gate instead" and that structural
   checks belong in CI as non-blocking, "not as a commit-blocking hook".
10. <a name="7.10"></a>WHEN the check fails, its output SHALL name the offending struct, enum case or count
    together with the file and line where it was found, so that a failure is actionable without a second
    investigation.
11. <a name="7.11"></a>The check SHALL NOT verify anything about zones. Nothing about a zone is mechanically
    checkable ([L3](#L3)); a check that pretended otherwise would be reporting on a naming convention as
    though it were a build artifact.

### 8. <a name="8"></a>Options, Zones and Composition

**User Story:** As the developer who asked for three looks at one screen, I want to see all of them at once,
name the parts I am comparing, and say "that total row with that plate control" in a form somebody can build,
so that having options is worth something after they exist.

This is the part that makes "take the best of each" an operation rather than a wish. Without it, the three
insulin-dosing attempts could only be seen one at a time, and the only way to describe a mixture of them was
another paragraph of prose.

**Acceptance Criteria:**

1. <a name="8.1"></a>The catalogue SHALL declare, once per surface, the named zones of that surface, and
   every option for that surface SHALL reuse those names rather than inventing its own, so that the
   vocabulary for pointing at a region is shared instead of per wireframe.
2. <a name="8.2"></a>A zone name SHALL be taken from what the code and the existing page files already call
   that region — for example `MealReviewView`'s `totalRow`, `primaryAction`, `scaleControl` and
   `accessoryLine` (`App/MealReviewView.swift`) and the "Layout zones" block of
   `design-system/pages/meal-review.md` — so that the vocabulary is recognised rather than learnt.
3. <a name="8.3"></a>Each option SHALL mark its zones in its own markup, using the declared names, so that a
   region can be selected and shown on its own.
4. <a name="8.4"></a>Zones SHALL be declared only WHERE a surface is a plausible subject of design options.
   A surface with nothing to point at that a state row does not already name SHALL declare none, and an
   option for such a surface SHALL carry no zone marks.
5. <a name="8.5"></a>WHEN two or more options exist for a surface, the system SHALL provide a single page
   placing every one of them adjacent, at the same true device metrics as the individual options
   ([4.2](#4.2)), openable without a server, a build step or a framework. Comparison SHALL NOT require a
   checkout, a rebuild or a deploy per option.
6. <a name="8.6"></a>That page SHALL be able to outline and label the zones on demand, and to show one named
   zone across all options together, so that the parts being compared are visible as parts.
7. <a name="8.7"></a>An option SHALL be expressible as a table of zone choices — one row per zone of the
   surface, naming the option that zone is taken from and the reason — and that table SHALL be sufficient,
   without further prose, as the brief for the next wireframe or for the SwiftUI implementation.
8. <a name="8.8"></a>A composed option SHALL be a first-class option: it takes the next attempt number, is
   written as a wireframe like any other, and is compared on the same terms. It SHALL NOT be treated as a
   special case, and it SHALL NOT be treated as a decision until it has been seen on the phone
   ([L5](#L5)).
9. <a name="8.9"></a>WHEN the implementation lands and the option files are deleted ([4.5](#4.5)), the zone
   choices and their reasons SHALL be preserved in the owning spec's `decision_log.md` as an Enhanced Nygard
   entry, the chosen render SHALL be preserved in `ios-v0` under its catalogue id, and the catalogue row
   SHALL flip to `shipped`. The record of what was chosen and why SHALL outlive the wireframes that showed
   it.
10. <a name="8.10"></a>Zones SHALL generate no code and SHALL require no Swift type, no import and no build
    step. A zone is a name for a region and nothing else.
11. <a name="8.11"></a>A zone choice SHALL describe only what a region looks like. WHERE the decision is
    about how a region is factored in Swift, or about the set of surfaces itself, it SHALL be recorded in
    the decision or in the surface-delta table ([6.9](#6.9)) rather than in the zone table.
