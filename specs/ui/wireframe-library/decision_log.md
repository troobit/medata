# Decision Log: Wireframe Library

Why each load-bearing choice was made. `requirements.md` holds the WHAT, `design.md` the HOW,
`prerequisites.md` the preconditions; this file holds only the reasoning, and does not restate them.

Every measurement quoted below was taken on this worktree at `591a6be`.

---

## Decision 1: The UI target artifact must be pointable, not merely precise

**Date**: 2026-08-17
**Status**: accepted

### Context

`specs/PROCESS.md` §5 states the rule this spec inherits: "**The target is an artifact, not a
memory.** For UI it is `design-system/MASTER.md` and the per-page docs in `design-system/pages/`".
The rule is right. The nominated artifact is the problem.

**Three options were commissioned, and that was correct.** `CLAUDE.md` asks that "a UI surface worth
deciding about SHOULD ship as **two or more attempts**, not one", and
`docs/agent-notes/device-build-and-test.md`, "Comparing UI attempts on the phone", describes the
`insulin-dosing` shape as "three whole App layers for one readout … Nothing merges until a person
looks at all three and picks one". The insulin-dosing feature ran exactly that convention. Options are
how the developer decides; generating several is the mechanism, not a fault in it.

The prose that briefed those options was as good as prose gets.
`specs/data/insulin-dosing/design-direction.md` is 443 lines of exceptionally high-fidelity
direction — exact tokens quoted from `App/Colors.swift`, point sizes ("44pt heavy mono"), opacities
("white @ 0.75"), control metrics ("h 48, medataAccent, r 12"), a Dynamic Type shed order, motion
with its Reduce Motion ternary, verbatim VoiceOver strings, a Forbidden list and explicit palette
assignment. It was committed in `0baaea8` on **2026-08-14**; the three attempts are all dated
**2026-08-16**, two days later, and attempt 1 quotes the document in its own code comments — it was
*followed*.

What went wrong is narrower and different: **the options came out unusable**, on three measured
counts.

- **Costly to produce.** `git diff --stat research...insulin-dosing-ui-1-on-research` is 8 files /
  542 insertions, attempt 2 is 17 files / 1,565, attempt 3 is 14 files / 1,015 — **3,122 lines of
  SwiftUI across three branches** to try three versions of one readout.
- **Costly to compare.** Each option needs `git checkout` plus `make deploy-device` to be seen at
  all, one at a time. The convention asks that "a person looks at all three"; nothing let a person
  look at all three **at once**, so the comparison happened from memory across rebuilds.
- **Impossible to reuse.** Having seen them, there was no way to say *"attempt 2's total row with
  attempt 1's plate control"* except by writing another paragraph of prose — which restarts the loop
  that produced the three attempts in the first place.

### Decision

The UI target artifact becomes a medium that can be **pointed at**: an HTML **rendering** per option
for surfaces under design, a **surface x state catalogue** for surfaces that exist, and **named
zones** so a part of one option can be cited and combined with a part of another. Prose stays for
what a rendering cannot carry, as commentary around them rather than as the target.

### Rationale

The 443-line document is not evidence that prose is imprecise. It is maximally precise, it was fresh,
it was read and it was followed. It is evidence that **even perfect prose cannot be pointed at**:
there is no way to indicate a region of it, hold it beside another one, or take half of it. Prose is a
poor medium for *describing* a look; SwiftUI is an expensive medium for *trying* one at roughly a
thousand lines an option. A wireframe is cheap enough to try and concrete enough to point at, a
catalogue makes the surface set visible, and a zone name makes a region of an option citable.

The goal is therefore not fewer options. It is options that are cheap to produce, comparable side by
side, and reusable as the description of what you want to see next.

### Alternatives Considered

- **Write a longer, stricter design-direction document**: More sections, tighter language, a
  mandatory structure section - Rejected because precision is not the missing property. The existing
  document is at the fidelity ceiling of the format and was followed; a longer one is still a thing
  you cannot point at. The handoff literature the candidate research surveyed agrees — teams passing
  twenty-page redline documents do worse than teams passing one artifact and a conversation.
- **Commission one attempt instead of three, so nothing diverges**: Removes the comparison problem by
  removing the comparison - Rejected outright: looking at options is how the choice gets made here,
  and `CLAUDE.md` mandates "two or more attempts, not one". What has to fall is the cost of an
  option, not the number of them.
- **A machine-checked prose schema (front-matter, required fields)**: Keep prose, add structure -
  Rejected as the worst of both: it still does not render, so it still cannot be pointed at, and it
  invents a format nobody but this repo reads.
- **Rely on the on-device gate to arbitrate between options**: The phone is the real judge - Rejected
  as a target artifact, and kept as the acceptance test it already is. The gate shows one build at a
  time, which is the bottleneck being described here rather than a way out of it.

### Consequences

**Positive:**
- The medium matches what it is asked to do: options render, so they can be looked at; zones have
  names, so parts of them can be cited and recombined.
- `specs/PROCESS.md` §5 keeps its rule and gets a better artifact; no process is invented.
- The visual argument (a rendering) and the structural argument (a catalogue) stop competing for the
  same document.

**Negative:**
- `specs/PROCESS.md` §5's wording now names artifacts that are being frozen (Decision 10), so that
  section needs an edit or it becomes the next stale reference.
- Prose still carries everything a rendering cannot — decomposition, state models, settings keys —
  so the format is demoted, not eliminated, and the boundary between the two is a judgment call.
- **Nothing mechanically forces an option to be wireframed before it is built in SwiftUI.** That
  stays a habit. The lever is that wireframing is cheaper than not — roughly a hundred lines against
  roughly a thousand — which is a better lever than a rule, and still not a guarantee.

---

## Decision 2: Reject the entire external design-tool and design-token-platform field

**Date**: 2026-08-17
**Status**: accepted

### Context

A four-scout survey evaluated more than forty candidates: canvas tools (Figma, Figma + Code Connect +
Dev Mode MCP, Penpot self-hosted), component browsers (Storybook web, playbook-ios, ShowcaseKit,
Storybook-SwiftUI), snapshot suites (pointfreeco/swift-snapshot-testing, getsentry/SnapshotPreviews,
fastlane snapshot), token platforms (Tokens Studio, Supernova, Style Dictionary v5, Terrazzo,
Dispersa, Design Token Kit, DTCG 2025.10 and its Resolver Module), sinks (Xcode asset catalogues),
diagram-as-code (Excalidraw, tldraw, PlantUML Salt, Mermaid), prompt-to-UI SaaS (v0, Lovable, Google
Stitch), a JSON/YAML UI DSL rendered by a repo-local script, and SwiftUI's own `#Preview`.

The repo's constraints are unusual and they do most of the filtering: one developer, no designer, an
offline-first product, a Make + Swift + Python toolchain with no Node anywhere, and a **primary
author who is a coding agent** — which cannot drag rectangles in a GUI.

### Decision

Reject the whole external-tool field. The library is plain files in this repository: static HTML
wireframes, a markdown catalogue, a Python token generator and a bash check.

### Rationale

Two constraints eliminate nearly everything without needing a per-tool argument. First, the artifact
must be **reviewable text in git**; anything whose source of truth is a hosted service or a binary
document fails on contact. Second, the artifact must be **authorable by an agent**; anything designed
around a human manipulating a canvas is being used the hard way at best. What survives is text files
in the tree, which is also what the repo already does everywhere else.

### Alternatives Considered

- **Figma (and Figma + Code Connect + Dev Mode MCP)**: Industry default, MCP server for agent access
  - Rejected: the design file is not in the repo and is not text. Cost seals it — Starter seats get
    up to 20 MCP tool calls per *month* and Professional View/Collab seats 6, so agent throughput
    needs a paid Dev seat. `docs/agent-notes/wireframe-intake.md` already files Figma under "Figma
    option (heavier, deferred)".
- **Penpot, self-hosted**: Open-source, open file format, better ethics than Figma - Rejected: the
  live document lives in a server database and the `.penpot` export is a ZIP of JSON plus binary
  assets, so git sees a binary blob. It also asks a solo developer to run Postgres and Redis to hold
  fourteen wireframes.
- **Storybook (web renderer)**: Mature component browser - Rejected: there is no web app on
  `research` to document — the SvelteKit app is stranded on `main` — so it would document a facsimile
  nothing imports, which is exactly the `design-handoff-00` failure. It also adds Node, Vite, a
  lockfile and a dev server to a repo with none.
- **Tokens Studio / Supernova**: Purpose-built token platforms - Rejected: both are Figma-shaped and
  hosted (Tokens Studio's solo tier including the platform is €169/month), neither does anything for
  the layout and structure question that options are actually generated to answer, and both insert a
  human GUI step into an agent-authored workflow.
- **Style Dictionary v5 / DTCG + a resolver**: The most defensible token pipeline on the market -
  Rejected: it adds Node to a Make + Swift + Python repo, ships no SwiftUI `Color` format (UIColor
  literals only), and has no way to emit `Color(uiColor: .systemGroupedBackground)` — so the 12
  adaptive tokens in `App/Colors.swift` would be flattened to fixed RGB. A custom format is
  mandatory, at which point the platform has bought nothing on the hard part.
- **A JSON/YAML UI DSL rendered to HTML by a repo-local script**: Theoretically the cleanest —
  a constrained vocabulary in which an agent cannot invent an off-token colour - Rejected: it means
  maintaining a UI framework, for one app, with one developer. Every SwiftUI construct the DSL does
  not model is invisible, so the DSL permanently trails the app, the renderer becomes the thing that
  must be trusted, and nothing validates the renderer. It ships nothing on day one.
- **SwiftUI `#Preview` as the library**: Apple-native, zero dependency - Rejected as the *library*
  and kept as a possible verification mirror. A `#Preview` is Swift that must compile, so it
  presupposes the view exists — the chicken-and-egg this work is trying to break. `App/ResultView.swift`
  declares `let record: MealRecord` and `let store: any PersistenceStore`, so previewing it needs a
  mock store *and* a build of an app target whose imports include ARKit, RealityKit, Segmentation and
  CaptureKit. It is also effectively unused today: exactly one `#Preview` exists in `App/`, in
  `App/MedataLoadingSymbol.swift`.
- **Golden screenshot corpus / snapshot testing**: Mechanical, catches real pixel drift - Rejected:
  it needs a test target this repo deliberately does not run (`CLAUDE.md`: "do not add new test
  scaffolding unless explicitly asked"), it compares a build against its own past rather than two
  options against each other, and it requires the code to exist first — so it says nothing at the
  moment the choice is being made.

### Consequences

**Positive:**
- No SaaS seat, no subscription, no account, no `node_modules`, no lockfile, no dev server.
- Everything is diffable text a reviewer or an agent reads directly in a pull request.
- Nothing to keep alive across tool upgrades: the dependencies are a browser, `python3` and `bash`.

**Negative:**
- No canvas. A future collaborator who thinks in Figma has nothing to open, and onboarding them means
  either exporting or reopening this decision.
- Hand-written HTML gives up everything a real design tool does for free: component instances, auto
  layout, variants, light/dark switching and shared libraries.
- Rejecting Style Dictionary means the token generator is ours to maintain, small as it is.

### Impact

Sets the shape of every other decision here. `design-system/`, `tools/design_tokens/` and
`tools/check_surfaces.sh` all follow from "plain files in this repository".

---

## Decision 3: Wireframes are static HTML at true device metrics, not SwiftUI

**Date**: 2026-08-17
**Status**: accepted

### Context

Once the library is repo-local text (Decision 2), the remaining question is the language. SwiftUI is
tempting: it is the shipping language, so a wireframe would need no translation, and components could
in principle be shared.

This repo has already run that experiment. `design-system/wireframes/design-handoff-00/` rendered the
same bundle twice: the JSX screen set is **1,033 lines** (`capture.jsx` 104, `result.jsx` 169,
`shell.jsx` 121, `supporting.jsx` 359, `trends.jsx` 280) plus **544 lines** of shared
`styles/wireframe.css`; the parallel SwiftUI sketch under `MedataApp/` is **2,229 lines**. Roughly
2x, for the same picture. Worse, the SwiftUI sketch did not stay a sketch — it grew
`Pipeline/EstimationPipeline.swift`, `Pipeline/CaptureService.swift`, `Models/MealStore.swift` and
`Models/Meal.swift`. It became a second app, with no enforcement in either direction.

### Decision

Wireframes are self-contained HTML files at true iPhone 16 Pro metrics (402x874pt), linking
`design-system/tokens.css` and `design-system/wireframe.css`, under
`design-system/wireframes/<surface>/<attempt>.html`.

### Rationale

The measured 2x cost is decisive on its own for an artifact whose whole value is being cheap enough
to throw away. The precedent adds the second reason: a SwiftUI wireframe drifts toward being a
parallel implementation, because SwiftUI is a language for building apps and the gravity is
one-directional. HTML has no such gravity — it cannot accidentally acquire a pipeline.

The attempt convention makes the saving concrete. `docs/agent-notes/device-build-and-test.md`,
"Comparing UI attempts on the phone", is already how UI choices are made; moving the attempts
upstream of SwiftUI replaces three App-layer branches totalling 3,122 insertions with three files of
roughly a hundred lines each — `design-system/wireframes/insulin-dose/attempt-1.html` is 104 lines,
`attempt-2.html` is 100, and `attempt-3.html`, which proposes a different surface set, is 160. The
same options that cost three branches cost 364 lines here, and they can then be opened together.

### Alternatives Considered

- **SwiftUI wireframes in a `Wireframes` SwiftPM module**: No translation step, shared components -
  Rejected on the measured 2x cost, on this repo's own rotted precedent, and because it cannot build
  on the macOS host that `make build` runs on (see Decision 13, "No SwiftPM `Tokens` target").
- **A DEBUG-only in-app wireframe gallery**: Renders on the real device with real Dynamic Type -
  Rejected: it links thousands of lines of view code behind a `#if DEBUG` entry point, which
  contradicts the precedent stated in `Package.swift`'s own header for `HARNESS_ENABLED` — defined
  only on the harness targets "so the shipping iOS app binary contains zero harness code".
- **ASCII art or Mermaid in markdown**: Cheapest possible, already in the repo - Rejected: it cannot
  show typographic hierarchy, real spacing or colour, which is most of what a UI attempt is deciding.
  It is also what `design-system/pages/*.md` already is — the artifact Decision 1 demotes from being
  the target, on the grounds that it cannot be pointed at.

### Consequences

**Positive:**
- Roughly half the lines of the SwiftUI equivalent, opened in a browser with no build step.
- Structurally incapable of becoming a second app.
- Renders the same on any machine, and needs no simulator, no device and no Xcode.

**Negative:**
- **HTML can lie.** Dynamic Type, safe areas, `ViewThatFits`, SF Symbol metrics and system font
  rendering are all approximated. Every metric in a wireframe is a starting position to check on the
  phone, never a result — `design-system/wireframes/README.md` says this out loud rather than leaving
  it to be discovered.
- Two dialects to keep in one's head; CSS habits leak into SwiftUI reviews and vice versa.
- The 12 `Color(uiColor:)` tokens have no fixed sRGB value, so `design-system/tokens.css` emits them
  at documented dark-appearance values marked `approx`. Wireframes are OLED-dark by construction and
  say nothing trustworthy about a light appearance.

---

## Decision 4: Options are composed from named zones, declared once per surface

**Date**: 2026-08-17
**Status**: accepted

### Context

Generating several options is only useful if a person can then say which parts of which one they
want. That sentence has a canonical form — *"attempt 2's total row with attempt 1's plate control"* —
and today it has no writable form at all. The options differ at exactly that granularity: the three
insulin-dosing attempts disagreed about the second line of the readout, about the entry chrome, and
about whether the surface carries a dose readout at all, and the only way to describe a mixture was
another paragraph of prose.

The vocabulary for saying it already exists in the tree, three times over and under three spellings.
`App/MealReviewView.swift` names its regions `photoSection`, `totalRow`, `primaryAction`,
`scaleControl`, `accessoryLine`, `foodRow`; `design-system/pages/meal-review.md` has a "Layout zones"
block; and `specs/data/insulin-dosing/design-direction.md` §2 fixes the order — "photo (40%) /
totalRow / primaryAction / scale control / 1px divider / scrolling rows". None of the three is citable
from a spec, and none of them appears in a rendered option.

### Decision

A surface declares a **named zone list once**, in `design-system/surfaces.md` under the section that
owns the surface. Every option for that surface marks the same names in its markup —
`<section data-zone="total-row">` — and an option is then expressible as a **table of zone choices**,
recorded in `design-system/wireframes/<surface>/composition.md` while the options are live and moved
into the owning spec's `decision_log.md` when the implementation lands. Zones are declared only where
they earn their keep: 23 surfaces declare them today, across 19 distinct lists, and most rows declare
none.

### Rationale

A zone name is the smallest thing that makes composition writable. With one, the sentence the
developer wants becomes a six-row table — `design-system/wireframes/insulin-dose/composition.md` is
the worked example, taking `total-row` from attempt 2 and `food-rows` from attempt 3 while leaving
the rest at attempt 1 — and that table is unambiguous, short, and directly buildable as `attempt-4`
or as the SwiftUI. It is the description of what you want to see next, in place of the prose
paragraph that previously had to carry it.

Declaring the list once per surface, in the catalogue, is what keeps it a shared vocabulary rather
than something each wireframe reinvents; taking the names from what the code and the page files
already call these regions is what keeps it from being a new invention at all. And a composed option
is an ordinary option: it is written as a wireframe and compared like the rest.

Zones cost nothing to have. They generate no code, no Swift type has to exist for one, nothing
imports anything because of one, and `tools/check_surfaces.sh` does not read them.

### Alternatives Considered

- **Whole-screen reference only ("go with attempt 2")**: No new vocabulary, and the attempt tags
  already exist - Rejected: it cannot express "attempt 2's total row with attempt 1's plate control",
  so it forces an all-or-nothing choice between options that were never all-or-nothing. It is the
  status quo, and it is what leaves the good parts of the losing attempts on the branch.
- **A formal component or JSON schema for each option (typed component tree, props)**: Machine-
  readable, diffable, composable by construction - Rejected: it is the UI DSL the candidate survey
  already turned down in the same terms — every construct the schema does not model is invisible, so
  it permanently trails the app, and the renderer becomes the thing that must be trusted. It also
  buys schema churn on every new control, for a vocabulary whose entire job is to let two people mean
  the same region by the same word.
- **Free-text description of the parts you liked**: No mechanism at all, write a paragraph - Rejected
  because that is precisely the prose that could not be pointed at. It restarts the loop documented
  in the first decision, one level down.
- **Diff the wireframe HTML between attempts**: Free, mechanical, already available - Rejected: a
  diff compares markup, not intent. It reports moved elements and changed class names, has no name
  for "the total row", and two regions that read identically can diff wildly while two that diff
  trivially can mean different things.

### Consequences

**Positive:**
- "Take the best of each" becomes a real operation with a written form: a table of zone choices, in
  minutes, buildable as the next wireframe or as the brief for the Swift.
- The vocabulary is declared once and shared, so options for one surface argue about the same regions
  under the same names.
- No runtime, build or code cost. A zone is a `data-zone` attribute and a line in the catalogue.

**Negative:**
- **Zones are a convention, not a construct.** Nothing checks that an implementation respects the
  boundaries its wireframe declared, and `make surfaces` cannot see them. Two people could agree the
  zone table and still build different things inside a zone.
- A zone choice does not settle decomposition. Attempts 1 and 2 rendered the second line identically
  in places; one inlined it in `App/MealReviewView.swift`, the other extracted
  `App/DoseReadoutLine.swift`. Zones say what a region looks like, never how it is factored in Swift.
- Not every proposition is a zone choice. Attempt 3's move — that this surface carries no dose readout
  and that three entry sheets become one — has no row in a zone table; it belongs in the surface-delta
  table of Decision 14.
- Zone lists are hand-maintained per surface. Renaming a zone silently breaks every composition table
  citing it, and nothing checks for the dangling reference.
- **A composed option is still an option, not a decision.** Zone-picking makes a fourth candidate
  cheap to express; it does not make it right, and it still has to be looked at on the phone.

---

## Decision 5: Every surface under design gets one side-by-side compare page

**Date**: 2026-08-17
**Status**: accepted

### Context

Comparison, not authoring, was the binding constraint. `docs/agent-notes/device-build-and-test.md`
requires that "Nothing merges until a person looks at all three and picks one", and the repo gives a
person no way to do it: each of `insulin-dosing-ui-1-on-research`, `-2-` and `-3-` needs a
`git checkout` and a `make deploy-device` to be seen at all, one at a time, on the one phone. The
three options together are 3,122 insertions, and every look at them costs a rebuild.

So the comparison happened from memory, across rebuilds, between things that were on screen minutes
apart. The judgments being made are relative — is attempt 2's second line worth the width it costs
against attempt 1's? — and a relative judgment made from memory is a memory test.

### Decision

Each surface under design gets one `design-system/wireframes/<surface>/compare.html`, which places
**every option for that surface in one page, adjacent, at true iPhone 16 Pro metrics**, opening by
double-clicking the file. Zone outlines toggle on, and a per-zone view puts one region of every option
side by side. It is disposable with the folder it lives in.

### Rationale

Simultaneity is the whole property. Two renderings on one screen answer a relative question directly,
and the per-zone view does the same at the granularity the zone vocabulary of Decision 4 introduces —
`total-row` from all three options, in a row, is the exact picture needed to fill in one line of a
composition table. This is the highest-value artifact for the loop the developer actually runs, and
it costs one HTML page per surface being designed.

The page carries its own copy of each option's screen markup, deliberately: a `file://` page cannot
read its siblings, and the alternative is a server or a build step in a repo that has neither. The
duplication is bounded by Decision 6 — the options and the compare page are deleted together, so it
lives for days.

### Alternatives Considered

- **Deploy each attempt to the phone in turn**: The status quo, and the real device is the real judge
  - Rejected as the *comparison* mechanism, because it is the complaint itself: a rebuild and a
    reinstall between every look, so the options are never co-present. It stays exactly as it is as
    the acceptance gate, which is a different job — choosing between options, then proving the chosen
    one works.
- **Screenshots pasted into a document**: Easy, and it lives in the spec - Rejected: they are stale
  the moment an option changes, they are scaled to whatever the document does, so the width and shed
  questions that the comparison is *about* get answered at the wrong metrics, and the shot is one
  state of one option.
- **One wireframe with a toggle between options**: One file instead of four, and the switch is
  instant - Rejected: it hides exactly the simultaneity that makes comparison work. A toggle is
  sequential viewing with a faster switch — the same memory test, milliseconds instead of minutes —
  and it collapses the options into one file, so they stop being separable artifacts that can be
  tagged, deleted or taken apart.
- **A generator or dev server that composes the options into a page**: Removes the duplicated markup
  - Rejected: the repo has no Node and Decision 2 keeps it that way, and a build step for a page that
    lives a fortnight is more machinery than the duplication it removes.

### Consequences

**Positive:**
- The convention's own requirement — a person looks at all three — becomes satisfiable for the first
  time, at real device metrics, with no rebuild between looks.
- Zone outlines make the parts visible as parts, so a composition table can be written while looking
  at the thing it describes.
- No dependency beyond a browser opening a local file: no server, no build, no framework.

**Negative:**
- **Each option's markup exists twice** — in its own file and in the compare page. Edit one and the
  other is silently wrong, and nothing checks that they agree.
- The page is assembled by hand and grows by hand as options are added; nothing generates it.
- A browser side by side is still a browser. Dynamic Type, safe areas and `ViewThatFits` remain
  approximations, so the page chooses between options and never proves one works.
- It is per surface. Whether a whole flow hangs together is still a question only the phone answers.

---

## Decision 6: Wireframes are disposable — deleted when the implementation lands

**Date**: 2026-08-17
**Status**: accepted

### Context

Every prior parallel-artifact attempt in this repository has rotted, and the rate is measured.
`design-system/` was last touched **2026-08-09**; since 2026-06-01 `App/` has taken **115 commits**
against `design-system/`'s **16**, and those sixteen cluster in two bursts.

Rot also happens *under active maintenance*, which is the more damning finding.
`design-system/wireframes/design-handoff-00/MANIFEST.md` row 11 records "Graph is the launch root;
Capture / Data / Settings present as covers from Graph". `App/AppRoot.swift` says otherwise in its own
header comment: "The launch root is `HomeView`, a pure router". That row was written on 2026-07-04 and
`App/HomeView.swift` landed on 2026-07-10 in "Shell re-root & Graph demotion" — **six days later**, while
someone was actively maintaining the manifest. Both deviations are attributed to the user: row 10 to
*"user direction after seeing the implementation"*, row 11 to *"user direction; camera-first launch was
unwanted in developer use"*. The dominant rot cause is therefore the design changing **after** the phone
showed it, which no forward-only wireframe-to-code flow can catch.

### Decision

A wireframe exists only while its surface is being designed. When the implementation lands the folder
is deleted, the chosen attempt is rendered to `design-system/archive/ios-v0/<id>.png`, and that row in
`design-system/surfaces.md` flips to `shipped`.

### Rationale

This is the entire maintenance strategy, and it works by construction rather than by discipline: a
file that does not outlive its decision cannot go stale. It also fixes the accountability problem —
with a permanent wireframe, "is this current?" is an unanswerable question that quietly resolves to
"no"; with a disposable one, the wireframe's existence *is* the claim that the surface is under
design.

Deleting the wireframe loses nothing that matters, because the parts worth keeping are kept
elsewhere: the zone-choice table and its reasons move into the owning spec's `decision_log.md` — the
worked example is `design-system/wireframes/insulin-dose/composition.md` — and the winning rendering
is preserved as a screenshot. What is deleted is the way of looking, not the record of what was
chosen or why.

### Alternatives Considered

- **Keep every wireframe permanently, maintained alongside the code**: The obvious design-system
  shape - Rejected on the 7:1 update-cadence measurement above and on the `MANIFEST.md` row-11
  evidence that even a maintained table rots inside a week. A permanent library of this size is a
  second codebase nobody has agreed to maintain.
- **Keep them but mark each with a "last verified against `<sha>`" stamp**: Makes staleness visible
  rather than preventing it - Rejected: it is a manual field, so it rots the same way the content
  does, and a stale stamp is indistinguishable from an honest one.
- **Move them to a `wireframes/archive/` folder on implementation instead of deleting**: Preserves
  the losing attempts - Rejected: an archived HTML file still looks live to a future reader and still
  turns up in searches. A PNG under `design-system/archive/ios-v0/` is self-evidently a snapshot, and
  git already holds the deleted files for anyone who wants them.

### Consequences

**Positive:**
- Zero ongoing maintenance cost, guaranteed structurally rather than promised.
- The presence of `design-system/wireframes/<surface>/` becomes a live signal that a surface is under
  design.
- Losing attempts do not accumulate as clutter that later readers must date.

**Negative:**
- **Nothing mechanically forces a wireframe to precede the implementation.** That stays a habit, and
  the only lever is that an option in HTML is about a tenth of the cost of the same option in
  SwiftUI.
- Recovering a deleted attempt means a `git log`, which is friction exactly when someone wants to
  revisit a rejected option.
- The deletion step is manual and easy to skip, so stale folders will appear; the check does not
  currently detect one.
- A wireframe still cannot settle decomposition. Attempts 1 and 2 rendered the dose line identically
  in places; one inlined it in `App/MealReviewView.swift`, the other extracted
  `App/DoseReadoutLine.swift`. A rendering has no channel for that distinction, and neither does a
  zone choice.

---

## Decision 7: Existing layouts are preserved as a catalogue plus screenshots, not wireframes

**Date**: 2026-08-17
**Status**: accepted

### Context

The developer's instruction was that every current UI layout be captured. Taken literally with hand-drawn
wireframes that is roughly 390 states across the iOS app, and `design-system/surfaces.md` as written
now enumerates **418 state rows across 67 surfaces**. At the `design-handoff-00` rate of about 80
lines of HTML per screen this is a multi-week effort producing an artifact that Decision 6 says should
not exist permanently anyway.

It is also aimed at the wrong target. `App/*.swift` is already the canonical answer for a shipped
surface, and the phone renders it on demand — a hand-drawn wireframe of a screen that already ships
generates no option, because the option it would show is the thing that shipped.

### Decision

Preservation of existing layouts is a **complete surface x state catalogue** (`design-system/surfaces.md`)
plus **rendered screenshots** under `design-system/archive/ios-v0/<id>.png`. No hand-drawn wireframes
are produced for surfaces that already ship.

### Rationale

Separating the two goals makes the work tractable and honest. Option generation is served by
wireframes and their compare page, and only for surfaces being designed. The baseline/reference goal
— defining the app **as it is**, so a new option can be described as a difference from something,
and so the best of each attempt can be taken deliberately — is served by a catalogue and
photographs, which are cheap and exactly as accurate as the thing they were taken from.

Screenshots have the property the prose page files lack: they are drift-free by construction. A
photograph of the app on 2026-08-17 is a true statement forever, because it is dated by what it is.
Superseding it means a new `-vN` generation, not an edit.

### Alternatives Considered

- **Hand-draw all ~390 states as HTML**: Literal reading of that instruction, maximum coverage -
  Rejected on cost against no option value: a hand-drawn copy of a screen that already ships is a
  redrawing of the answer. It also contradicts Decision 6 by creating a permanent wireframe corpus.
- **Catalogue only, no screenshots**: Cheapest, all text - Rejected: the catalogue records structure
  and states, not what the screen looks like, and "define the app as-is" needs both. The state column
  is a sentence; a screenshot is the layout.
- **Screenshots only, no catalogue**: A photo album of the app - Rejected: pixels cannot be checked
  against a closed enum, cannot say which state source produced them, and cannot be cited from a
  spec. It is precisely the text layer that makes the images navigable.

### Consequences

**Positive:**
- A single file defines the app as it is, and is the baseline every future UI decision moves from.
- Screenshots cannot drift; they are superseded, never corrected.
- The two goals are separated, so each part of the work can say which one it serves.

**Negative:**
- **Backfilling shipped surfaces generates no options.** It buys a baseline — the thing a new option
  is described as a difference from — and the spec must not claim more for it than that.
- `design-system/surfaces.md` is a **new artifact that can itself go stale**. It is text describing
  code, which is the rot class this spec was written around; only the check (Decision 15) holds it to
  the code, and only along the axes the check can see.
- Screenshots are binary blobs in a git repository — not reviewable in a diff, and they add weight
  permanently. There are 378 rows currently marked `pending` and 0 captured.
- Capture is manual and device-bound, so the archive will lag the catalogue for a long time.

---

## Decision 8: The catalogue is keyed on surface x state, not surface

**Date**: 2026-08-17
**Status**: accepted

### Context

The obvious catalogue shape is one row per screen. The repo already has that shape in
`design-system/pages/`: fourteen files, one per screen. `design-system/pages/capture.md` is 129 lines
organised by layout zone — top bar, bubble level, telemetry capsule, bottom row — with three of the
screen's states given a heading of their own ("Transient surfaces", "Estimating state", "Permission
denied"). `CaptureState` in `App/CaptureState.swift` has 8 cases, one of which (`permissionDenied`)
carries a `PermissionSubject` and so renders 2 distinguishable screens; `design-system/surfaces.md`
catalogues **16 rows** under `capture/`. The page file is a description of the screen's furniture, and
its states are an aside.

Per-screen granularity also cannot be checked. A screen either exists or it does not; that is a
boolean a `grep` can already answer. Whether every case of `ConfidenceLevel` has a described
appearance is the question that actually goes unanswered, and it is invisible at screen granularity.

### Decision

One row per **surface x state**. The `id` is `<surface>/<state>` in kebab-case — for example
`meal-review/very-low` — and each row carries a **state source**: the thing in code that produces it,
such as `CaptureState.trackingLost`, `confidence < 0.20` or `records.isEmpty`.

### Rationale

The state source is what makes a row checkable. Because the state column names a closed enum case,
`tools/check_surfaces.sh` can parse the cases out of the Swift source and assert that each one appears
— so adding a case to `CaptureState` fails the check instead of silently going undocumented. That is
the one mechanical guarantee this catalogue can offer, and it only exists at state granularity.

The `id` doubles as the **citation key**: the same string names the catalogue row, the wireframe
filename `design-system/wireframes/<surface>/<attempt>.html`, the archive filename
`design-system/archive/ios-v0/<id>.png`, and any reference from a spec, a rune task or an agent
prompt. One key, everywhere, which is what makes a cross-document reference resolvable at all.

### Alternatives Considered

- **One row per surface**: Smaller, matches the existing `design-system/pages/` shape - Rejected: it
  is roughly 67 rows instead of 418, but a `capture` row cannot say which of the 16 capture states it
  describes and is unfalsifiable against a closed enum. It is also the granularity
  `design-system/pages/` already has, and which left every state question unanswered.
- **One row per surface, with states as a free-text list inside a cell**: A compromise that keeps the
  file short - Rejected: a list inside a cell is prose again, cannot be linted per state, and cannot
  carry a per-state archive path or status.
- **Key the row on the Swift type name rather than a kebab-case id**: Compiler-adjacent, renames are
  visible - Rejected: seven `dose-notification/*` rows have no struct at all (they are keyed on the
  construction site), and a type name cannot express a state. The type still appears, in the
  `surface` column.

### Consequences

**Positive:**
- The catalogue is checkable against closed enums, which is the only mechanical drift guard available.
- One citation key spans catalogue, wireframe, archive and specs.
- The state set becomes visible, and its size is itself information — 418 states is the honest measure
  of the app's surface area.

**Negative:**
- The file is large. At 1,021 lines it is already past the point where it is read end to end, and it
  will grow.
- **A catalogue keyed on surface x state describes the surface set rather than proposing one.** It
  cannot say that an option adds activity surfaces or folds three entry sheets into one — attempt 1
  built no activity surfaces while attempts 2 and 3 did, and no row anywhere records that as a
  choice. The surface-delta contract of Decision 14 is where that is written.
- Row ids are a hand-maintained namespace. Renaming one is a breaking change to every spec citing it,
  and nothing checks for a dangling citation.
- States that are combinatorial rather than enumerable (a banner state crossed with a confidence
  level) are recorded by judgment, so the row set is not fully derivable.

---

## Decision 9: The UI↔data binding is recorded as names only

**Date**: 2026-08-17
**Status**: accepted

### Context

The developer's constraint was explicit: the catalogue must let you translate between app UI and data
easily, **without introducing cross-layer dependencies**. The temptation in the other direction is
strong — a typed binding, a generated mapping, a `Codable` manifest the app reads at runtime — and
each one couples the UI layer to the data layer through the documentation.

The layer boundary is already weak. Of the 22 `App/*View.swift` and `App/*Sheet.swift` files, **18
import one of the six data products the `data` column names** — 25 import lines in all: `Persistence`
x10, `Pipeline` x7, `Foods` x3, `PortableContracts` x2, `CaptureKit` x2, `Segmentation` x1. Widening the
module list to every directory under `MedataCore/Sources/`, which is what `tools/check_surfaces.sh` does,
takes that to 19 of 22 — the extra file is `App/GlucoseConnectionsView.swift` importing
`GlucoseIngestion`.

### Decision

The `data` column names the MedataCore product and type as a **documentation join** —
`Persistence · MealRecord` — and nothing more. It generates no code, creates no import and adds no
build-time coupling. It records the **intended** binding, not the observed one.

### Rationale

Naming both sides is sufficient for the stated goal: a human or an agent can translate between the UI
and the data without opening both trees. `specs/PROCESS.md` §3 already prescribes exactly this
mechanism for cross-domain work — a cross-domain capability "*references* the other domains' specs
rather than duplicating them" — so this is the house pattern applied to a table rather than a new
idea.

Recording the *intended* binding is the subtle half. Deriving the column from actual imports would
bake today's 19 violations in as if they were the design, and the catalogue would then defend the
thing it should expose. The `view-model` column takes the opposite stance and records what is
**actually** there, with `—` where no model owns the surface — so the two columns together show both
the intent and the gap.

### Alternatives Considered

- **A generated typed binding (a `SurfaceBinding` enum, or a Swift file emitted from the table)**:
  Compiler-checked, a rename would fail the build - Rejected: it is precisely the cross-layer
  dependency the constraint forbids, and it would make the documentation a build input, so a
  catalogue edit could break the app.
- **Derive the `data` column from the actual `import` lines**: Automatic and always true - Rejected:
  it would encode 19 layer violations as the design, and it describes what the file imports rather
  than what the surface is about — `App/HomeView.swift` imports `GlucoseWidgetShared` and
  `Persistence`, which says little about which surface reads what.
- **Omit the column entirely**: Keeps the catalogue purely visual - Rejected: it drops the developer's
  stated requirement, and the translation problem it solves is real and recurring.

### Consequences

**Positive:**
- Meets the constraint exactly: translation without coupling, and no import crosses the seam because
  of this work.
- Follows a mechanism `specs/PROCESS.md` already prescribes, so no new convention is introduced.
- The gap between `view-model` (actual) and `data` (intended) becomes legible instead of implicit.

**Negative:**
- A names-only join is **unchecked**. `Persistence · MealRecord` can name a type that no longer
  exists and nothing fails; only the layer report touches this area, and only advisorily.
- Recording intent rather than observation means the column can be aspirational, and a reader cannot
  tell an intended binding from an achieved one without reading the code.
- Someone will eventually want the generated binding, and this decision will have to be re-argued.

---

## Decision 10: `design-system/pages/*.md` is frozen to `archive/pages-v0/`, not deleted or maintained

**Date**: 2026-08-17
**Status**: accepted

### Context

`design-system/pages/` holds 14 prose page files. They are named by `specs/PROCESS.md` §5 as the UI
target artifact, they have not been touched since **2026-08-09**, and Decision 1 demotes the format
from target to commentary. They are not worthless: they carry intent, phrasing and rationale that the
code does not, and
`design-system/MASTER.md` still directs a reader to them — "then check `design-system/pages/<screen>.md`
for screen-specific overrides; if present, the page file wins".

Three options were live: keep maintaining them, delete them, or freeze them.

### Decision

Move the 14 page files verbatim to `design-system/archive/pages-v0/`, write-once, never edited.
Superseded only by a new `-vN` generation.

### Rationale

Freezing converts a false claim into a true one. A file under `design-system/pages/` claims to
describe the app now, and increasingly does not. The identical file under `archive/pages-v0/` claims
to describe the app as of the moment it was frozen, which stays true forever and costs nothing to
maintain.

Deleting would throw away the only written record of *why* several screens look the way they do, for
which no replacement exists. Maintaining would keep a second prose description of every surface in
step with the code, at the measured 7:1 cadence disadvantage, for an artifact Decision 1 has just
stopped treating as the target.

### Alternatives Considered

- **Delete them**: Cleanest tree, git keeps the history - Rejected: intent and phrasing are not
  recoverable from code, and `git log` archaeology is a poor substitute for a file a reader can find.
- **Keep maintaining them alongside the catalogue**: No disruption, `specs/PROCESS.md` §5 keeps
  working unchanged - Rejected: two artifacts describing the same surfaces is two things to keep in
  step, and the measured maintenance rate says one of them loses. It also recreates the format this
  spec is retiring.
- **Merge their content into the catalogue rows**: Preserve the value, drop the files - Rejected:
  most of what they carry is rationale and phrasing, which does not fit a table cell, and the
  merge is a large hand-editing job with a high chance of silent loss.

### Consequences

**Positive:**
- Nothing is lost, and nothing further has to be maintained.
- The `-vN` archive convention gets its first use, and applies uniformly to `ios-v0`, `web-v0` and
  `pages-v0`.
- `design-system/` stops containing files that assert stale facts about the current app.

**Negative:**
- Frozen prose is still prose, and a reader who finds `archive/pages-v0/capture.md` may still believe
  it. The folder name is the only warning.
- `design-system/MASTER.md` and `specs/PROCESS.md` §5 both point at the old location and must be
  edited, or this decision creates two new stale references while removing fourteen.
- Whatever those files say that the catalogue does not is now archived rather than current, so some
  live intent becomes historical by administrative action.

---

## Decision 11: Capture the SvelteKit screens as `web-v0` now, as an expiring option

**Date**: 2026-08-17
**Status**: accepted

### Context

The older SvelteKit web app is stranded on `main` and is not being carried forward; catalogued out it
comes to 28 surfaces and 101 states across 22 source files — 4 routes, a layout, a document template
and 16 components. `CLAUDE.md` states the cycle "currently runs along the 'research' branch, with
intent to merge to main when the MVP work is done", so `main` will stop being the Svelte app.

The source survives in git history regardless. What expires is the ability to **run** it: `main`'s
`package.json` asks for `@sveltejs/kit ^2.15.0`, `vite ^6.0.0` and `svelte ^5.0.0`, and its
`pnpm-lock.yaml` resolved those to 2.50.2, 6.4.1 and 5.49.2 against a machine that now has node v26.7.0
and pnpm 11.22.0. Nothing has verified that install and dev-server still resolve.

### Decision

Capture the SvelteKit screens as screenshots under `design-system/archive/web-v0/<id>.png` while the
toolchain still runs, and record those surfaces now as a **frozen half** of
`design-system/surfaces.md` — 28 `web/`-prefixed surfaces, **101 rows**, every one at
`status: web-v0`, with one successor-mapping entry per surface. The frozen half is counted separately
from the iOS half and is outside the ratchet.

### Rationale

The capture costs an afternoon now and becomes impossible later, which is the definition of an option
worth exercising early. The rows are the text layer that makes those pictures usable: they name what
each screen did and which iOS surface, if any, carries it now — **eight web surfaces have no iOS
successor at all**, including editing a saved meal, gallery import and several typed food items in
one meal. That list exists nowhere else, and it is exactly the material an option for an iOS surface
would be drawn from.

Freezing rather than ratcheting answers the objection that these rows have no Swift declaration to be
checked against. `tools/check_surfaces.sh` reads the whole file but ratchets the iOS numbers only, so
`covered=61 total=61` is unaffected by 101 rows nothing in this tree can verify, and the frozen
numbers move only if the freeze is found to have missed something on `main`. They declare no zones,
for the same reason: zones exist so options can be pointed at, and no options are being generated for
a frozen app. Where a web surface is wanted as a design input, the zone list belongs to the iOS
surface that would carry it.

### Alternatives Considered

- **Screenshots only, no rows**: Keeps `design-system/surfaces.md` purely iOS - Rejected: a pixel
  cannot be cited from a spec and cannot say which iOS surface succeeded it. The successor mapping is
  the part with lasting value and it is text; without it the archive is a folder of pictures of an
  app nobody remembers the shape of.
- **Catalogue them inside the iOS ratchet**: One number for everything - Rejected: they have no Swift
  declaration, no state source and no view-model, so every checkable column is empty, and folding
  them in would inflate `covered` with rows that can never be verified. A separately counted frozen
  half says the same thing without corrupting the one mechanical guarantee the catalogue offers.
- **Skip the capture; the source is in git at `adc3b56`**: Zero effort - Rejected: source is not a
  screenshot, and reconstructing 28 rendered surfaces from a stranded SvelteKit tree in a year is a
  far larger job than photographing them this week, if it is possible at all.
- **Port the Svelte screens to HTML wireframes**: Makes them live artifacts - Rejected: they are not
  being carried forward, so this is effort spent on a dead branch, and Decision 6 says wireframes
  exist only for surfaces under design.

### Consequences

**Positive:**
- An irreversible loss is prevented for the cost of one session.
- The alternative information architecture stays available as material for future options, and the
  eight dropped capabilities are written down instead of being rediscovered by accident.
- The `-vN` archive convention covers both platforms uniformly, and the ratchet stays honest because
  the frozen half is counted apart from it.

**Negative:**
- It runs a Node toolchain once, in a repo that otherwise has none, and needs backend configuration
  the `.env.example` only partly mocks.
- 101 unverifiable rows now sit in a 1,021-line file. Nothing in this worktree can check them; a
  reader who doubts one has to `git show main:src/...`, and `status: web-v0` plus the section heading
  are the only things marking them as historical.
- The window may already have closed, in which case the honest outcome is to record those surfaces as
  unarchivable rather than leaving `pending` rows that never resolve. All 101 are `pending` today.
- More binary blobs in the repository, for screens that will never ship.

---

## Decision 12: Tokens generate one-directionally from `App/Colors.swift`

**Date**: 2026-08-17
**Status**: accepted

### Context

Hand-copied token lists drift, and this repo has the receipt. `App/Colors.swift` declares 22
`static let` tokens; the hand-written Swift snippet inside `design-system/MASTER.md` declares 18 and
is missing four — `bandActivity`, `seriesActivity`, `seriesInsulinBasal` and `seriesInsulinBolus`.

Colour is also the one axis on which the three options stayed directly comparable: the same token name
meant the same hue in all three, because it was expressed as a machine artifact rather than prose.
The qualification matters, and it cuts both ways. Attempts 2 and 3 both *added* tokens, and
incompatibly — attempt 2 added `seriesActivityAerobic` / `seriesActivityAnaerobic` /
`seriesActivityMixed` (hue encodes a modelled covariate), attempt 3 added a single `seriesActivity`
(hue encodes nothing). That is a genuine difference of proposal, and worth having; what it shows is
that a shared token file makes existing tokens comparable and says nothing about new ones.

### Decision

`tools/design_tokens/tokens_to_css.py` parses the `static let` lines of `App/Colors.swift` into
`design-system/tokens.css` custom properties. Generation runs in one direction only;
`App/Colors.swift` stays hand-written and authoritative, and `App/` does not change. The hand-copied
snippet in `design-system/MASTER.md` is replaced by a pointer to `App/Colors.swift`.

### Rationale

One-directional generation removes the drift class entirely: there is no second hand-maintained copy
to fall behind. The generator matches the convention the repo already uses for derived artifacts —
`tools/food_db/generate.py` and `tools/segmenter/export.py`, both run from the repository root, both
producing files nobody hand-edits.

Keeping `App/Colors.swift` as the source rather than a neutral token file preserves the property that
made colour comparable across options in the first place: the app's tokens are the tokens, not a copy
that agrees with them. The naming rule is mechanical with no exceptions — every `static let <name>` becomes
`--medata-<kebab(name)>`, so `medataAccent` becomes `--medata-medata-accent`. It reads awkwardly once,
and costs no remembered exception in any hand-written wireframe.

### Alternatives Considered

- **A neutral `tokens.json` as the source, generating both Swift and CSS**: The textbook design-token
  shape - Rejected: it makes `App/Colors.swift` generated, so a colour change stops being an ordinary
  Swift edit, and `App/` changes — which this work explicitly does not do. It also cannot express
  `Color(uiColor: .systemGroupedBackground)` without inventing a representation for adaptive colours.
- **Keep the hand-copied snippet in `design-system/MASTER.md`, and lint it against `App/Colors.swift`**:
  Smaller change, keeps `MASTER.md` self-contained - Rejected: a linted copy is still a copy, so every
  token addition needs two edits and the lint's only job is to complain about the second one being
  missing. Generating the artifact is strictly less work than checking a duplicate.
- **Bidirectional sync**: Edit either side - Rejected: the failure modes are conflict resolution and
  silent overwrites, for a file that changes a few times a year.

### Consequences

**Positive:**
- The `MASTER.md` drift is closed at the source, not patched.
- One hand-maintained colour list in the whole repository.
- A wireframe's hue comes from a token or it is wrong, and `design-system/wireframe.css` names no hue
  outside the generated set.

**Negative:**
- A wireframe cannot introduce a colour the app does not already have without first editing
  `App/Colors.swift` — a real constraint on designing forward, and precisely the case attempts 2 and 3
  ran into when each proposed its own activity palette. An option whose whole idea is a new hue costs
  a Swift edit before it can be drawn.
- `design-system/tokens.css` must be regenerated by hand; nothing runs the generator automatically,
  so it can fall behind `App/Colors.swift` between runs.
- The 12 `Color(uiColor:)` tokens are emitted at approximate dark-appearance values — 13 properties
  carry the `approx` note, because `bandActivity` inherits it from the token it aliases — so the CSS is
  not a faithful rendering of the app's adaptive palette.
- Neutrals stay outside the pipeline. `App/Colors.swift` defines one white level (`captureChromeBG` at
  `white.opacity(0.10)`), so a wireframe's other white opacities are hand-written against the OLED chrome
  convention rather than against a token.
- Colour is one axis of a design system. Spacing, type and motion remain prose.

---

## Decision 13: No SwiftPM `Tokens` target — the generator is a script under `tools/`

**Date**: 2026-08-17
**Status**: accepted

### Context

The attractive version of shared tokens is a SwiftPM `Tokens` target holding `App/Colors.swift`, with
a wireframe module depending on it: `make build` would then go red whenever the two fell out of step,
and nothing would have to be remembered.

Two independent critics tested this and it does not survive. `Makefile`'s `build:` target is
`swift build`, run on the macOS host. `Package.swift` declares `platforms: [.iOS(.v17), .macOS(.v14)]`
and SwiftPM has no per-target platform gate, so a `Tokens` target is compiled for macOS. Twelve of the
22 tokens in `App/Colors.swift` use `Color(uiColor:)`, which does not compile there — `swiftc -typecheck`
on a two-line file containing `let c = Color(uiColor: .label)` fails on this machine with
`error: no exact matches in call to initializer`, because SwiftUI on macOS vends no `uiColor:`
initialiser at all. Every existing target in `Package.swift` is platform-neutral;
`grep -rln 'import SwiftUI' MedataCore/Sources/` and the same for `UIKit` both return nothing.

### Decision

No SwiftPM target is created for tokens or wireframes. `tools/design_tokens/tokens_to_css.py` is a
stdlib-only Python script run from the repository root.

### Rationale

The mechanism's entire claim was that it is mechanical rather than aspirational, and it fails on
contact. Both escapes destroy it: mirroring the 12 tokens under `#if canImport(UIKit)` with NSColor
equivalents recreates the second hand-maintained copy that Decision 12 exists to eliminate, while
wrapping the target in `#if os(iOS)` makes `make build` compile an empty target on the host, so the
red build never fires on the fast local loop and only appears under a multi-minute device
`xcodebuild`.

A generator sidesteps the platform problem entirely and matches how every other derived artifact in
this repo is produced.

### Alternatives Considered

- **`Tokens` target with `#if canImport(UIKit)` and NSColor mirrors**: Keeps the compiler in the loop
  - Rejected: it is a second hand-maintained copy of 12 tokens, which is the exact `MASTER.md` drift
    being closed.
- **`Tokens` target wrapped in `#if os(iOS)`**: Compiles everywhere, empty on the host - Rejected:
  the drift guard then never fires on `make build`, so the target's only justification is gone while
  its cost remains.
- **Add the tokens to the Xcode project instead of SwiftPM**: The app target is iOS, so
  `Color(uiColor:)` compiles - Rejected: `App/Colors.swift` is already in the Xcode project; that is
  where it lives. The question was whether a *second* consumer could share it through SwiftPM, and
  the answer is no.

### Consequences

**Positive:**
- `make build` keeps working, unchanged, with no new target and no platform conditionals.
- The generator follows the established `tools/*/` convention and depends on nothing beyond `python3`.
- A costly false start is documented, so the idea does not get proposed again without the evidence.

**Negative:**
- **The compiler is not in the loop.** Nothing goes red when `design-system/tokens.css` falls behind
  `App/Colors.swift`; regeneration is a remembered step.
- The parse is a regular-expression reader of Swift, so a `static let` written in an unmodelled form
  raises rather than being understood — the script is coupled to the current style of one file.
- Two languages are now involved in the token path where one was hoped for.

---

## Decision 14: A per-feature surface-delta table records what an option does to the surface set

**Date**: 2026-08-17
**Status**: accepted

### Context

Zones compose *within* a surface. The other half of what an option proposes is a change *to the set
of* surfaces, and nothing so far can express it. Attempt 1 built **no activity surfaces at all** — no
`App/ActivitySheet.swift`, no `App/ActivityModel.swift` — while attempts 2 and 3 both did. Attempt 3
went further and consolidated three entry sheets into `App/LogSheet.swift`, which describes itself as
"ONE manual-entry surface, three modes … This is that third sheet refusing to exist", and removed
`private struct ChipFlow: Layout` from `App/TrendsView.swift` on the way past.

Those are propositions, not accidents, and they are the most interesting thing any of the three
options said. But a wireframe shows one surface, so it cannot show the absence of a surface; a
catalogue keyed on surface x state describes the surfaces that exist, so it cannot propose a different
set; and a zone table has no row for "this surface, and two others, become one". The proposition was
legible only as a `git diff --stat`.

### Decision

Every UI-touching spec's `requirements.md` carries a surface-delta table —
`| surface | change | catalogue id | note |`, with `change` one of `add`, `modify`, `delete`,
`consolidate`, or `—` for a surface named as deliberately out of scope. It is written **before**
implementation, one table per option where options differ at this level, and read against what a
branch actually contains.

### Rationale

Its job is **composition, not policing**. The table is the surface-set half of an option's
description, in the same spirit as the zone table: `consolidate` naming
`carb-entry`, `insulin-dose` and `activity` into one id is exactly what attempt 3 proposed, written
in four cells instead of inferred from a diff. Two options can then be compared at this level as
readily as at the zone level, and a composed option can take attempt 3's consolidation while taking
attempt 2's `total-row` — a combination that is currently unsayable in any medium.

Catching an unintended omission is a useful side effect and not the purpose. It happens to fall out:
if a table says `add` for the activity surfaces and a branch has none, the gap is visible against a
written list rather than being something somebody has to notice. That is worth having, but it is the
by-product of writing the proposition down, not the reason to write it.

### Alternatives Considered

- **Rely on the zone table alone**: One composition mechanism, not two - Rejected: zones name regions
  *within* a surface and have no vocabulary for a surface appearing, disappearing or absorbing two
  others. `App/LogSheet.swift` is not a zone choice.
- **Rely on the catalogue alone**: One artifact, already checked - Rejected: the catalogue describes
  the surfaces that exist. An option is a proposal about what should exist next, which is a different
  statement and needs a different table.
- **Read the delta off `git diff --stat` after the fact**: Free, and always accurate about the branch
  - Rejected: it is available only once the SwiftUI exists, which is after the expensive part, and it
    reports files rather than surfaces. It also cannot express an option that has not been built.
- **A machine-checked delta (parse the table, diff against the branch's structs)**: Automatic
  enforcement - Rejected for now: it needs a per-branch checkout and a mapping from struct to surface
  that only a human can currently make. The table is read by a person, and should earn automation
  before being given it.
- **Put the delta table in `design.md` instead of `requirements.md`**: It looks like structure -
  Rejected: it is a statement of what must be true after the change, which is `requirements.md`'s
  question under `specs/PROCESS.md` §2.

### Consequences

**Positive:**
- An option's surface-set proposition becomes writable and comparable, so "attempt 3's consolidation
  with attempt 2's readout" is a thing two tables can express together.
- The table is short — a handful of rows per feature — and cites catalogue ids, so it resolves against
  `design-system/surfaces.md`.
- Omissions nobody intended show up against a written list, without the table having to be framed as
  a rule anybody is policing.

**Negative:**
- It adds a required section to every UI-touching `requirements.md`, and `specs/PROCESS.md` needs to
  say so or it will be skipped.
- Nothing checks it. An unwritten table records nothing, and a table written after the branch exists
  is a description rather than a proposal.
- It asks the author to enumerate surfaces in advance, which is hardest exactly when a design is at
  its earliest and most worth exploring.
- Surface granularity is coarse. `modify` covers everything from a changed word to a rebuilt screen;
  the zone table is what says which, and only for surfaces that declare zones.

---

## Decision 15: The catalogue is checked by `make surfaces`, and coverage is a ratchet

**Date**: 2026-08-17
**Status**: accepted

### Context

A catalogue that describes code will drift from it unless something holds the two together. The repo
already has the shape for this: `make spell` runs `tools/check_spelling.sh`, which is **168 lines** of
bash for the much easier job of grepping a fixed word list. `CLAUDE.md`'s MVP gate forbids the
alternative — "do not add new test scaffolding unless explicitly asked", and the app-target files
under `MeData/Tests/` are "documentation contracts, not an executable suite".

Two details shape the check. A `struct .*: View` grep under-detects: `ChipFlow: Layout`,
`MaskContourShape: Shape`, `ARPreviewView: UIViewRepresentable` and
`ShareSheet: UIViewControllerRepresentable` are all invisible to it — and `ChipFlow` is exactly the
component one attempt removed, where nothing outside a `git diff` said so. And a boolean pass/fail
invites the cheap green: a catalogue whose rows are all `planned` satisfies "every struct has a row"
while documenting nothing.

### Decision

`tools/check_surfaces.sh`, wired to `make surfaces`, checks struct coverage across
`View|Shape|Layout|UIViewRepresentable|UIViewControllerRepresentable|Widget`, checks that every case
of each named state enum appears as a state source, and reports coverage as a **ratchet** —
`covered=N total=M` against `covered_min` in `tools/surfaces_baseline.txt`, failing on regression
rather than on a threshold. A struct counts as covered only when one of its rows is `shipped`. The
frozen `web-v0` half of the catalogue is read but not ratcheted, for the reasons in Decision 11; today
the check prints `covered=61 total=61 baseline=61`.

### Rationale

The wider conformance list is the difference between a check that would have caught the `ChipFlow`
deletion and one that would not. Parsing the enum *cases* out of Swift while hard-coding only the enum
*names* keeps the editorial choice in the script and the facts in the source, so adding a case shows
up as a catalogue miss rather than passing silently.

The ratchet exists because a green check over unwritten rows is worse than today's visibly-absent
file: it converts an obvious gap into a false assurance. Requiring `shipped` for coverage means the
number can only be raised by writing real rows, and the baseline is bumped in the same commit that
earns it.

Bash and a Make target keep the check inside the conventions the repo already runs, with no test
target and no new scaffolding. The realistic size is not 60 lines: the estimate before writing it was
150–250, and `tools/check_surfaces.sh` came out at 330. The spec records the real number rather than the
estimate that flattered it.

### Alternatives Considered

- **A percentage threshold ("fail below 80% coverage")**: Familiar from coverage tools - Rejected:
  it invites a scramble to the threshold and then permanent stasis, and picking the number is
  arbitrary. A ratchet needs no number and never regresses.
- **A boolean check ("every struct has a row")**: Simplest to write and to pass - Rejected: it is
  passed by a file full of `planned` rows, which is the cheap green this decision exists to prevent.
- **A test in the SwiftPM package instead of a shell script**: Runs under `make test` with everything
  else - Rejected: the catalogue is markdown describing the *app* target, which the SwiftPM package
  cannot see, and `CLAUDE.md` forbids new test scaffolding.
- **A Python script rather than bash**: Easier parsing, and `python3` is already required by
  `tools/design_tokens/tokens_to_css.py` - Rejected for consistency with `tools/check_spelling.sh`,
  which is the check this one sits beside in the Makefile. This is a close call and would be a
  reasonable thing to revisit if the awk grows further.

### Consequences

**Positive:**
- The catalogue is held to the code along the two axes that can be checked mechanically: declared
  surfaces and closed-enum cases.
- Coverage can only improve, and improving it requires real rows.
- No new test target, no CI dependency, one more `make` verb beside `spell`.

**Negative:**
- **The ratchet can be gamed.** Marking a row `shipped` raises the number, and nothing verifies that
  the row's content is true — only that a row exists with the right status.
- It is 330 lines of bash and awk parsing Swift declarations by regular expression. It will
  mis-parse an unusual declaration, and the failure will look like a catalogue error rather than a
  script error.
- Nothing runs it. There is no CI, so `make surfaces` is a target someone must type, and this repo
  already has precedent for rules whose scripts nobody runs.
- The checks are blind to everything that is not a struct declaration or an enum case: a wrong `data`
  cell, a stale `state` sentence, a stale wireframe folder and a zone list no implementation respects
  all pass.

---

## Decision 16: The layer check is report-only initially

**Date**: 2026-08-17
**Status**: accepted

### Context

The view-model seam exists but is not enforced. Of the 22 `App/*View.swift` and `App/*Sheet.swift`
files, 18 import one of the six data products the `data` column names, and 19 import some module under
`MedataCore/Sources/` — the wider list is what the check reads, so 19 is the number it prints.
`App/BenchmarkView.swift` alone imports `Benchmark`, `Foods`, `Persistence` and `Segmentation`.

Decision 9 makes this seam a first-class column in the catalogue, so the check can see it. The
question is what it should do about it.

### Decision

The layer check lists view and sheet files importing a MedataCore module directly and prints
`layer_violations=N (report-only)`. It never fails `make surfaces`.

### Rationale

Failing on day one would fail on 19 of 22 files for pre-existing reasons unrelated to any change being
made, and a check that is red before you start is a check that gets switched off — taking the three
useful checks down with it. Report-only makes the number visible on every run, which is the
precondition for it ever falling, without holding unrelated work hostage.

The module list is read off `MedataCore/Sources/` rather than hard-coded, so a new product appears in
the report automatically and the check cannot rot on that axis.

### Alternatives Considered

- **Fail on any direct import**: Enforces the seam immediately - Rejected: it fails on 19 of 22 files
  today, which means it fails on every commit until a large refactor lands. The predictable outcome
  is the check being disabled or the target being avoided.
- **Fail on an increase in the count (a ratchet, as in Decision 15)**: Prevents the number growing -
  Rejected for now, though it is the natural next step. The count is currently sensitive to file
  renames and to the module list, so it needs to be observed for a while before it can carry a
  failure.
- **Omit the layer report entirely**: Keeps the check focused - Rejected: Decision 9 makes the seam a
  column in the catalogue, and a documented seam nobody measures is the same class of claim this spec
  was written to stop making.

### Consequences

**Positive:**
- The three checks that can be true today stay enforceable, so `make surfaces` is worth running.
- The violation count is printed on every run, so a regression is at least visible.
- The module list derives from the source tree and cannot go stale.

**Negative:**
- **A report-only check may stay report-only forever.** Nothing in this spec commits to a date or a
  target for turning it on, and there is no plan here to reduce the 19.
- A number nobody is accountable for is easy to stop reading; report-only output is the kind of thing
  that becomes scenery.
- The heuristic is file-name based (`App/*View.swift` and `App/*Sheet.swift`), so a view in a
  differently-named file is not counted, and the number understates the real figure.

### Impact

`tools/check_surfaces.sh` check 4, and the `view-model` / `data` columns of `design-system/surfaces.md`
that give it something to be about.

---
