# Consolidating the spec set

**Status**: proposed 2026-09-26, for discussion 2026-09-27. Nothing below has been applied.

## The problem, measured

`make spec-portfolio` on 2026-09-26 counts 73 spec folders (77 directories carry spec
files; the developer's count of 97 includes the meta files and the orbit variants). They
hold 570 decision-log entries. Two numbers explain why the set reads as byzantine:

| Signal | Value |
|---|---|
| Specs that describe the segmenter (model, palette, recipe, gates) | 9 |
| Specs that describe the two-view or support-plane geometry | 8, three of them bugfix folders |
| Decisions in `estimation/support-plane-reference` alone | 78 |
| Other specs that cite `estimation/pipeline` by name | 53 |
| Specs cited by nothing else | 3 |

Every folder obeys `PROCESS.md` §3 ("one coherent capability = one spec"). The sprawl is
not a rule violation. It is that **the folders are named after initiatives, not after parts
of the application**. `segmenter-foundation`, `model-production`, `estimation-quality`,
`myfoodrepo-bridge`, `snaq-parity`, `alternative-class-candidates`,
`resumable-segmenter-training` and `ml-feedback-loop` are eight time-boxed pieces of work on
one component. Each was the right unit to *do*; none is the right unit to *find*. The
question "what does the segmenter do today?" has no single answer, and the answer to "which
decision currently governs the support plane?" is somewhere in 78 entries plus the ones in
`two-view-trust`, `depth-grown-food-region` and three bugfix logs.

The same is true of the UI (`iphone-experience`, `home-router`, `design-handoff-00`,
`settings-information-architecture`, `unified-dark-theme`, `unified-entry-sheet` all describe
the shell) and of the glucose work (`libre-ingestion`, `cgm-connect`, `cgm-direct`,
`fingerprick-glucose`, `glucose-lock-widget`).

## What we want

1. One place per part of the application that says what it does now, and which decisions
   currently govern it. Findable by component name.
2. Initiatives keep their history (requirements as written, tasks, decision logs) because
   the reasoning is the asset, but they stop being the index.
3. The system keeps it that way without a person curating: new specs declare where they
   belong, and drift is caught mechanically, the way `/spec-janitor` and `/spec-cleanup`
   already work but against a structure that has a right answer.

## Approaches considered

**A. Big-bang merge into ten component folders.** Rewrite every spec into its component.
Rejected: it destroys 570 decision IDs that code comments, notes and other specs cite by
number; it is weeks of rewriting for one developer; and it repeats the mistake, because the
next initiative would either bloat a component spec or spawn a new folder anyway.

**B. Keep the folders, improve the index.** `OVERVIEW.md` is already a generated index;
add a component column and a search. Rejected as insufficient: the index would still list
initiatives, so the reader still opens eight folders to learn one component. It is the
current state with a better table.

**C. Two axes: components as the living truth, initiatives as history.** Add a thin layer
of **component specs**, one per part of the application, each a short living document
assembled from the accepted decisions of the initiatives that touched it. Initiatives stay
where they are, gain a `component:` declaration, and are archived (not deleted) once their
tasks close. Recommended, below.

**D. A knowledge graph or wiki tool.** Rejected: the repo's rule is to build no tooling
around what git and markdown already do; and a graph does not answer "what is true now",
it answers "what is connected".

## The recommended shape (C)

### Components

A closed list, the same way domains are closed. First cut, from the portfolio data:

| Component | Domain | Initiatives it absorbs today |
|---|---|---|
| `capture` | capture | rawframe-rgb-conversion, capture-bundle-recorder, shutter-blocked-feedback, the AR-session bugfixes |
| `segmenter` | estimation | segmenter-foundation, model-production, estimation-quality, myfoodrepo-bridge, snaq-parity, alternative-class-candidates, resumable-segmenter-training, ml-feedback-loop, unknown-food-nameable |
| `geometry` | estimation | pipeline (volume parts), support-plane-reference, two-view-trust, depth-grown-food-region, mv-volume-estimator, lidar-first-scale-fallback, the two-view and plane-fit bugfixes |
| `calibration` | estimation | nutrition5k-calibration, cross-dataset-calibration, pipeline-real-device-correctness, the harness bugfixes |
| `foods` | data | the food-database parts of pipeline, serving-adjust, food-db bugfixes |
| `records` | data | event-log-schema, manual-carb-intake, activity-events, records-deletion |
| `glucose-and-dosing` | data | libre-ingestion, cgm-connect, cgm-direct, fingerprick-glucose, insulin-dosing, dose-schedule, glucose-lock-widget |
| `shell` | ui | iphone-experience, home-router, design-handoff-00, settings-information-architecture, unified-dark-theme, unified-entry-sheet, loading-symbol-animation, bubble-only-cleanup |
| `meal-review` | ui | meal-review, shared-meal-components, mass-readout, result-view bugfixes |
| `tooling` | platform | build-provenance, clean-build-baseline, regression-suggestion-integration, spec-portfolio, the field loop |

`estimation/pipeline` is the one folder that spans three components. `PROCESS.md` §10
already names the seam and defers the split until a forcing function exists; this plan is
that forcing function for the *index* only. The folder stays whole; its requirement areas
are mapped to components in the component specs, not moved.

### A component spec is short and generated where it can be

`specs/<domain>/<component>/COMPONENT.md`, three sections:

- **What it does now.** Ten to thirty lines of prose. Hand-written, the one part that
  needs a person. Rewritten when an initiative closes, not edited continuously.
- **Governing decisions.** A generated table: every accepted, non-superseded decision from
  every initiative declaring this component, with its ID, title, date and source folder.
  Superseded and rejected entries are excluded; a decision that another initiative
  superseded shows the superseding ID. This is the answer to "which decision governs X".
- **Initiatives.** A generated list of the folders, with state (active, dormant, archived)
  and remaining tasks, the same data the portfolio already collects.

The generator is an extension of `tools/spec_portfolio/collect.py`, which already parses
every decision header and status line. The new work is one field and one output.

### Initiatives declare their component

One line of front matter in `requirements.md`, `prd.md` or `smolspec.md`:

```yaml
component: estimation/segmenter
```

Bugfix folders declare it in their report. A cross-component initiative declares one
component (the dominant one, `PROCESS.md` §3's rule) and lists the others under
`touches:`; its decisions appear in the primary component's table and are cross-listed in
the others.

### Archiving

An initiative whose tasks are all complete and whose decisions are all accepted or
superseded moves to `specs/<domain>/archive/<name>/` in a single commit, with a stub file
left at the old path that names the new one. Decision IDs do not change; links are
rewritten by the same pass (`spec-janitor` already has the machinery for ghost references).
The portfolio and the component tables read archived folders exactly as live ones. Git
holds the history; the tree holds what is current.

The first archive pass would move 31 complete initiatives and leave 42 live folders under
ten component headings. That is the whole visible change for a reader.

### Conflicts between decisions

Today a later decision in another folder can contradict an earlier one and nothing
notices. With the component table, two accepted decisions on one component with
overlapping titles or the same subject line become a lint finding
(`spec_janitor`'s judgment audit gets a mechanical input). Resolving one is a one-line
edit: mark the older `superseded by <folder> Decision N`. The known cases to resolve in
the first pass: the segmenter export bar (0.60 in early logs, 0.48 since
segmenter-foundation Decision 5), the per-staple tolerance (0.02 in the estimation-quality
PRD, shown to be inside the noise by R7 on 2026-09-26), and the support-plane definition
(support-plane-reference against the gravity-lock decision of 2026-09-25).

### Keeping it that way

- `collect.py` fails when a spec folder has no `component:` declaration, so a new spec
  cannot be created outside the map. `/starwave-creating-spec` and `/starwave-smolspec`
  ask for the component at creation.
- `/spec-janitor` gains two checks: initiatives eligible for archiving, and same-component
  decision pairs that look like conflicts. Both are reports, and the archive move is an
  approved batch, as its other repairs are today.
- `make spec-portfolio` regenerates the component specs' generated sections alongside the
  portfolio page. A component spec's prose carries a `reviewed:` date; the portfolio flags
  prose older than the newest accepted decision in its table.
- `OVERVIEW.md` becomes the component list with each component's live initiatives under
  it, generated as it is now. `DECISIONS.md` stops being hand-synthesised; it becomes the
  concatenation of the ten governing-decision tables.

## What it costs

- Writing ten "what it does now" sections: the only judgment work, about a day, and the
  part worth doing by hand because it is what a reader wants.
- Adding `component:` to 73 folders: mechanical, one pass, proposed by the tool and
  approved as a batch.
- The archive move: mechanical, one commit, reversible.
- Two extensions to `collect.py` and two checks in `spec-janitor`.

## What it does not do

It does not merge, rename or rewrite any initiative, and it does not change how work is
specified or executed. `PROCESS.md` §3 to §8 stand; §9 gains the component list and §10's
verdict on `pipeline` is unchanged.

## Sequence, if adopted

1. Agree the component list (the table above is a first cut; the names matter because they
   become paths).
2. Add `component:` declarations, tool-proposed, one approved batch.
3. Generate the ten component specs with empty prose; check the governing-decision tables
   for the three known conflicts and resolve them.
4. Write the ten prose sections.
5. Archive the 31 complete initiatives.
6. Regenerate `OVERVIEW.md` and `DECISIONS.md` from the new structure; retire the
   hand-written versions.
