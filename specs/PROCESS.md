# Spec-Driven Development Process

**Audience:** anyone adding or changing a feature in MeData.

**Status:** the governing description of how specs are written, tracked, and turned into
code in this repository. It documents the process *as practised* (the "starwave" spec
skills, `rune`, decision logs) and matures it for the roadmap: an Android port and new
data input streams (biometrics, blood glucose, and other signals layered on top of the
carb-estimation core).

This file is the **process** source of truth. The **product/architecture** sources of
truth are the specs themselves ([`OVERVIEW.md`](OVERVIEW.md) indexes them) and
[`docs/architecture.md`](../docs/architecture.md). For cross-cutting decisions see
[`DECISIONS.md`](DECISIONS.md).

---

## 1. Core principle: the spec is the source of truth

Every non-trivial change is described before it is built, and the description outlives the
change. Code implements a spec; it does not replace it. When code and spec disagree, that
is a defect in one of them to be reconciled, not a state to leave standing.

This buys three things that matter as the project grows past one person and one platform:

- **Onboarding.** A new developer, expert, or agent reads the spec folder, not the diff
  history, to understand *what* a subsystem does and *why*.
- **Portability.** The Android port reuses the algorithm and data specs unchanged; only
  the platform-binding layer is re-specified (see §9).
- **Auditability.** The estimation pipeline is grounded in published research and clinical
  constraints. The decision logs record why each modelling choice was made, so a reviewer
  can check the work, maths, and reasoning against the cited sources.

## 2. Separation of concerns: one spec, distinct artifacts

A feature is described by **separate, scoped artifacts**, each answering one question.
Keeping them separate is what lets different *concerns* — and later different *people* —
own different parts of the same feature without colliding.

| Artifact | Answers | Concern / future owner | Driven by |
|---|---|---|---|
| `requirements.md` | **What** must be true, and for whom | Product / clinical / domain | `/starwave:requirements` |
| `design.md` | **How** it is built — architecture, data models, algorithms, maths | Engineering / protocol | `/starwave:design` |
| `tasks.md` | **Execution** — the ordered, trackable checklist (optional in iterative mode, §5) | Implementer (dev or agent) | `/starwave:tasks`, `rune` |
| `decision_log.md` | **Why** each load-bearing choice was made | Whoever made the call | maintained as decisions land |
| `prerequisites.md` | Preconditions/inputs a large spec assumes | Engineering | created for large specs |

Today **one developer wears all the hats** and the AI agents assist within each. The
separation is not bureaucracy — it is the seam along which the team will later split:
when other SME's offer their time and expertise, they own `requirements.md` or `design.md`
respectively, and the boundary already exists. Build for that seam now; do not collapse
the documents into one just because only one non-machine entity is in the loop currently.

## 3. Directory structure, spec boundaries, and naming

A spec is a **folder under `specs/<domain>/<capability>/`**. The path encodes two things: a
*domain* (the layer of concern, from a fixed list) and a *capability* (the one coherent
thing this spec delivers). Both are kebab-case.

```
specs/
├── PROCESS.md             # this file — how specs are developed
├── OVERVIEW.md            # generated index — regenerate, don't hand-merge (see §9)
├── DECISIONS.md           # meta decision log — cross-cutting decisions distilled
├── <domain>/              # one of the fixed domains below
│   └── <capability>/      # one coherent capability = one spec
│       ├── requirements.md   # the WHAT (EARS acceptance criteria)
│       ├── design.md         # the HOW (architecture, data models, algorithms)
│       ├── tasks.md          # the EXECUTION ledger (rune-managed; optional, §5)
│       ├── decision_log.md   # the WHY (Enhanced Nygard ADR entries)
│       └── prerequisites.md  # optional — preconditions for large specs
└── bugfixes/
    └── <bug-name>/           # fix-bug reports keep their own decision_log.md
```

### Domains

Every spec belongs to exactly one domain. The set is **closed** — adding a domain is itself
a logged decision, not an ad-hoc choice. For Medata:

| Domain | Owns | Example specs |
|---|---|---|
| `platform` | app shell, build, OS/runtime bindings (iOS today, Android later) | app foundation, packaging |
| `capture` | sensor/AR/photo acquisition and the raw inputs | `rawframe-rgb-conversion` |
| `estimation` | the on-device CV/geometry/maths → carb pipeline | the core (`pipeline/`), `mv-volume-estimator`, `lidar-first-scale-fallback` |
| `data` | persistence, schemas, food/nutrition databases, **data-input streams** (biometrics, glucose) | `event-log-schema` |
| `ui` | user-facing surfaces, navigation, interaction, visual design | `iphone-experience`, `shutter-blocked-feedback` |

### Boundary: is it a new spec, or an extension?

- **Extension** — it refines or grows an *existing* capability and shares its acceptance
  bar. Add a requirement section to that spec; do not spawn a folder.
- **New spec** — it delivers a *new* user- or system-visible capability with its own
  acceptance bar. One capability per folder; a capability that needs two unrelated
  acceptance bars is two specs.
- **Cross-domain capability** — give it ONE home: the domain whose acceptance criteria
  dominate. It *references* the other domains' specs rather than duplicating them.

### Naming a spec

1. **Pick the domain** — the one layer that owns the primary outcome (where most of the
   acceptance criteria live).
2. **Name the capability** as a concrete noun phrase for *what it delivers*.

Do **not** name a spec after:
- the **layer** (`screen`, `tab`, `ui`, `view`) — the domain already says that;
- the **effort or phase** (`cleanup`, `v2`, `real-device-correctness`, `refinement`) — name
  the durable capability, not the project that produced it;
- the generic word **`feature`** — everything is a feature; it carries no information.

**Worked example.** *"A new tab that auto-adds meals/drinks I consume frequently."* Apply
the procedure: it is a **new** capability (its own acceptance bar — a frequent-items list,
one-tap add, recency/frequency ranking). Its acceptance criteria are about an interactive
surface, so the domain is **`ui`** (even though it writes to `data`, which it references).
The capability is *quick-add of frequent consumables* → **`specs/ui/quick-add-frequent-items/`**.
Not `feature` (vacuous), not `screen`/`tab`/`ui` (those are the layer, i.e. the domain),
not `data-input` (it consumes the `data` domain but does not own it).

### Legacy names

The estimation core was renamed from the flat `research/` into `estimation/pipeline/`. For
continuity its `DECISIONS.md` citation-key label stays `research` (e.g. `research D9`), now
resolving to `specs/estimation/pipeline/decision_log.md`. Separately, some migrated specs
kept **effort-flavoured capability names** (`pipeline-real-device-correctness`,
`bubble-only-cleanup`); they now live
under the right domain but their *name* still predates the convention. The convention binds
new specs; a legacy name is corrected when its spec is next substantially revised — a rename
is an additive move plus a reference rewrite (see §9), done one capability at a time.

**Small changes use one file, not five.** A change under ~80 LOC touching 1–3 files with
clear requirements is a **smolspec**: a single `smolspec.md` (Overview / Requirements /
Implementation Approach / Risks) plus a `tasks.md` and `decision_log.md`. See
`specs/estimation/lidar-first-scale-fallback/` for the shape. Do not manufacture a full five-document
spec for a simple and easily implemented change.

## 4. The development loop

The loop is sequential with an **explicit approval gate** between phases. The front door is
**`/nextup`**: it reads `nextup.md` at the repo root and routes the stated intent — resume an
existing spec at its current phase, hand a small job to a focused skill, or start a *new* spec.
`/nextup` is a router, not an executor; it classifies and hands off, never doing the work
itself. New-spec work is routed into the chain below, orchestrated by `/starwave:creating-spec`,
and each phase has a skill that drives it. Routing a new capability through that chain is what
fixes its domain and capability name up front (§3) — a spec never gets a file before it has a
convention-correct home.

```mermaid
flowchart TD
    idea([idea / nextup.md]) --> nextup{{"/nextup — route intent"}}
    nextup -->|new or resumed spec| scope{① Scope assessment}
    scope -->|small change| smol["smolspec.md"]
    scope -->|full spec| req["② requirements.md (EARS)"]
    req -->|gate: approve| design["③ design.md (research-grounded)"]
    design -->|gate: approve| tasks["④ tasks.md (rune ledger)"]
    tasks -->|gate: approve| impl["⑤ implementation"]
    smol -->|gate: approve| impl
    impl -->|tasks tracked per-commit| review{{"⑥ review gate: code matches requirements + design · all tasks complete · decision_log + OVERVIEW updated"}}
```

1. **Scope assessment** — research the affected code, estimate size, choose smolspec vs
   full spec. When uncertain, default to the full spec.
2. **Requirements** — the *what*, in EARS (§6). No solutions here.
3. **Design** — the *how*. For Medata this is research-grounded: cite the literature and
   record the maths. No code yet.
4. **Tasks** — decompose design into an ordered checklist mapped back to requirements,
   created with `rune` (§7).
5. **Implementation** — execute the `rune` ledger in order with `make-it-so` (works a whole
   phase, delegating tasks to subagents) or `next-task` (one task group at a time); update the
   ledger per commit (§7).
6. **Review** — the SSOT gate (§8).

This linear path is the **full-spec** loop. Smolspecs collapse phases 2–4 into one document;
**iterative** work (§5) replaces the task ledger with a target-and-converge loop. The
*gates* still apply in every mode.

**The gates are the process.** Do not start design before requirements are agreed, or code
before its plan exists — a `tasks.md` ledger in full/smol mode, or an agreed target and
acceptance band in iterative mode (§5). For a solo developer the "approval" is a deliberate
self-review (the
`/explain-like` skill is useful here — explaining the design at three levels surfaces gaps),
with `sendit` shipping the spec documents to the external review folder when a human sign-off
is wanted; the gate is real even when the approver and author are the same person.

## 5. Choosing the mode: full spec, smolspec, or iterative

Three modes. Pick by the *nature* of the work, not size alone.

**Full spec** — a feature with a definable correct answer. The default; required for
anything touching the estimation maths, the data model, refusal/safety paths, or a public
contract, regardless of line count.

**Smolspec** — small, isolated change. Use only when *all* hold: <80 LOC, 1–3 files, single
component, clear requirements, no breaking changes, no cross-cutting concerns (security,
performance, privacy, clinical safety). If *any* fails, use the full spec.

**Iterative (taste/target-driven)** — work that converges on a *target* by judgement rather
than against a fixed pass/fail list: UI look-and-feel, motion, copy tone; and
research/calibration tuning (per-class β_c, confidence thresholds) where you tune toward an
accuracy target on the test set. Here "complete" is replaced by *"near enough is good enough
against the target"*. A `tasks.md` ledger often adds nothing — there is no fixed, orderable
checklist, only a loop you stop when the result meets the bar.

### The iterative loop

`requirements.md` still defines the **targets and acceptance bands** — what "good enough"
means, measurably where it can be (e.g. "carb MAE ≤ target on the v1 set", "matches the
design-system spacing scale", "shutter reachable one-handed"). `design.md` records the
approach and points at the reference. Then iterate:

```mermaid
flowchart LR
    build[build / tune] --> observe[observe real output]
    observe --> compare{within<br/>acceptance band?}
    compare -->|no| adjust[adjust toward target]
    adjust --> build
    compare -->|yes| stop([stop — log the bar hit])
```

- **The target is an artifact, not a memory.** For UI it is `design-system/MASTER.md` and
  the per-page docs in `design-system/pages/`; for tuning it is the accuracy target and the
  test set. Iterating against a *written* target is what keeps "taste" reviewable.
- **Observe with real output** — screenshots / on-device runs (the `verify` and `run`
  skills, the loop in `docs/agent-notes/device-build-and-test.md`), never assumptions.
- **Get an independent read** — the `ui-ux-reviewer` skill, or a second-opinion critique
  from an `mcp-devtools` agent (`gemini-agent` / `codex-agent`) against the design-system
  reference, catches taste drift a single author misses. `swiftui-forms` covers form layout.
- **Stop at the bar.** When the output is inside the band, stop — do not gold-plate. Record
  the bar reached and any conscious "near enough" trade-offs in `decision_log.md`.

**`tasks.md` is optional in this mode.** When the work is a convergence loop rather than an
orderable checklist, omit it — the targets in `requirements.md` plus the decision log carry
the state. (Sibling precedent: rune's `batch-positional-file-arg` and
`general/TECH-IMPROVEMENTS.md` ship without a tasks ledger.) Add a `tasks.md` only when
discrete, separable steps actually emerge.

## 6. Requirements in EARS

Acceptance criteria use EARS (Easy Approach to Requirements Syntax) with `SHALL`, **each**
criterion individually anchored so design and tasks can reference it:

```markdown
### 1. Long-Form Event Log Table
**User Story:** As a data scientist, I want an atomic long-form log of events, so that I
can add new metrics without changing the schema.

**Acceptance Criteria:**
1. <a name="1.1"></a>The system SHALL persist events in a single table ...
2. <a name="1.2"></a>The system SHALL store the canonical scalar measurement in `value` ...
```

Requirements state observable system behaviour and constraints — never an implementation.
"WHEN \<trigger\>, THE SYSTEM SHALL \<action\>" is the canonical event-driven form; plain
"The system SHALL \<action\>" covers invariants. Reference units and domain rules
explicitly (Medata is metric-only — glucose in mmol/L, never mg/dL).

## 7. Stateful task ledgering and execution

Tasks are a **programmatic, version-controlled ledger**, not prose and not throwaway
chat-driven TODOs. `tasks.md` is managed with the `rune` CLI so state lives in the file and
moves with the repo.

```bash
rune create specs/<feature>/tasks.md --title "<Feature>"   # scaffold
rune add    specs/<feature>/tasks.md --title "..." --phase "Phase 1"
rune next   specs/<feature>/tasks.md                        # next ready task
rune progress specs/<feature>/tasks.md 1.2                  # mark in-progress
rune complete specs/<feature>/tasks.md 1.2.1                # mark done
rune list   specs/<feature>/tasks.md --filter pending
```

Update the ledger as work happens — set a task in-progress when you start it and complete
it in the same commit that lands its code, so the ledger and the tree never drift. A task
should name the requirement(s) it satisfies and the file(s) it touches. Iterative work (§5)
omits the ledger; its state lives in the targets and the decision log instead.

Day-to-day, a single developer executes the ledger through `make-it-so` / `next-task` (§4) —
no orchestrator required.

**Orchestration (`orbit`).** The repo carries an `.orbit.yaml` for driving a coding agent
over the ledger. `rune`'s streams/owner model and `orbit` exist to run **parallel** agents
across independent tasks. We still use it, but reach for it only when a spec has genuinely
parallel, independent task streams (e.g. a platform port where Android bindings and a
shared-core refactor proceed at once), not by default. We do **not** require moving every
change through an orchestrator; the requirement is that task *state* is tracked in `rune`, not
how the tasks are executed. **Treat any persisted `.orbit/` run state as disposable:** it can
reference task formats, IDs, and names from before the domain migration (§3). The `rune`
ledger is authoritative — regenerate orbit state against it rather than trusting stale
`.orbit/` contents.

## 8. Keeping spec and code aligned (SSOT enforcement)

The spec stays authoritative through the **review gate**, not through tooling that guesses
at meaning. A change is done only when:

- every task in `tasks.md` is `[x]`;
- the code matches `requirements.md` (behaviour) and `design.md` (structure/maths) — the
  reviewer checks this directly, the same separation-of-concerns the documents were
  written along;
- new load-bearing choices are in `decision_log.md`, and `OVERVIEW.md` reflects the spec's
  status.

> **Why no pre-commit "alignment" hook.** A git hook that truly judged whether changed code
> still satisfies the requirements/design would need a language model in the commit path:
> slow, non-deterministic, and adversarial to a solo developer's commit loop. Structural
> checks a hook *could* do deterministically (folder well-formed, OVERVIEW in sync) are low
> value relative to that friction. We deliberately enforce alignment at the review gate
> instead. If lightweight structural linting is ever wanted, run it in CI as a non-blocking
> check — not as a commit-blocking hook.

## 9. Scaling the process for the roadmap

The roadmap is the reason the process must be mature now. Two expansions are anticipated;
each has a defined shape so it does not force an ad-hoc reorganisation later.

**New data input streams (biometrics, blood glucose, …).** Each new stream is a **new
sibling spec** under `specs/`, not an edit to `estimation/pipeline/`. The persistence layer already
anticipates this: the event-log schema stores any metric as a new `event_type` with no
schema change (`specs/data/event-log-schema/`). A new stream's spec owns its ingestion,
validation, units, and how it relates to existing events. The carb-estimation core
(`estimation/pipeline/`) stays focused; correlation features (e.g. glucose-vs-meal) are their own
specs that depend on both.

**Android port.** The estimation pipeline is already specified to be **platform-agnostic at
the algorithm layer** — `estimation/pipeline/` design §8 (Portability Notes) and Req 18 (Portable
Pipeline Contracts) define the seam between portable algorithms and platform bindings
(ARKit, Metal, SwiftUI). When Android work begins, the split is along that existing seam: a
platform-agnostic core spec (algorithms, data models, maths, contracts — reused verbatim)
and a per-platform binding spec (capture, depth, compute, UI). Do not duplicate the maths
into a second monolith.

### The authoritative spec set and iterative merge

Intent must not be branch-local. **Every branch carries the `specs/` tree** (the
`requirements.md` files at minimum), so a line of work never holds the only copy of *why* it
exists. A feature branch may add its own `specs/<domain>/<capability>/` long before its code
is portable or merged — **intent lands first, code follows**.

One branch is the **authoritative spec set** that aggregates all of them — for Medata today
that is `research`, which is intended to merge to `main` and supersede it. Specs converge
onto it **iteratively, one capability at a time**, not in a single big-bang:

```mermaid
flowchart LR
    b1[branch: ui work] -->|specs/ui/*| auth[(authoritative<br/>spec set)]
    b2[branch: android] -->|specs/platform/*| auth
    b3[branch: data stream] -->|specs/data/*| auth
    auth -->|regenerate OVERVIEW · reconcile DECISIONS| main[(main)]
```

The per-capability folder layout (§3) is what makes this safe: independent efforts touch
**disjoint folders**, so spec merges are additive and conflict-free. Only three files are
shared, and each has a rule that avoids hand-merging:

- **`OVERVIEW.md`** is a generated index — regenerate it from the folders after a merge
  (the `/specs-overview` skill), never resolve it by hand.
- **`DECISIONS.md`** is a synthesis; on conflict the per-spec `decision_log.md` wins (it
  already says so). Reconcile the meta log after the capability has landed.
- **`PROCESS.md`** changes rarely and is reviewed on its own.

So bringing another branch's intent in (e.g. a new data-stream or Android-binding spec)
is the *expected* path, not an exception: copy the `specs/<domain>/<capability>/` folders
onto the authoritative branch, regenerate `OVERVIEW.md`, reconcile `DECISIONS.md`. The code
can follow on its own schedule.

## 10. Decomposing a monolithic spec

A large spec earns a split when separate concerns within it acquire **separate owners,
separate platforms, or separate change-cadences** — the same seams as §2 and §9. Splitting
earlier is premature: it scatters cross-references (`§9`, `Decision 43`, σ-maths that span
sections) for no current benefit and makes the spec *harder* to keep coherent. Splitting
later, once a forcing function exists, pays for the churn.

**Pattern when the time comes:** keep the root spec as the canonical overview (shared maths,
modelling assumptions, the cross-cutting decision log) and extract self-contained concerns
into child specs that link back up; rewrite cross-references in the same pass; carry each
extracted decision's history with it.

**`estimation/pipeline/` — verdict (2026-06-25).** `estimation/pipeline/` is monolithic (23 requirement areas, a
large design, a large decision log) and is a candidate for decomposition. Applying the
criterion above, it is **not split yet**, because no forcing function is active: there is
one developer, one platform, and the internal portability seam (§8 / Req 18) already
isolates the future Android boundary on paper. The split becomes worthwhile — and should
follow the pattern above — when **either** the Android port starts (extract the
platform-agnostic core from the iOS bindings) **or** a concern inside it gains an
independent owner. The most self-contained extraction candidate, when triggered, is the
density + macronutrient concern (Req 11–12): pure data and arithmetic, platform-independent,
and the natural attachment point for blood-glucose correlation work. Until then `estimation/pipeline/`
stays cohesive by design, not by neglect.

## 11. Quick checklist

Before opening a change for review:

- [ ] Boundary checked (new spec vs extension, §3); lives at `specs/<domain>/<capability>/`
  named for the capability — not the layer, effort, or "feature".
- [ ] Right mode chosen (full / smol / iterative, §5).
- [ ] `requirements.md` in EARS, criteria anchored; no implementation leaked in — or, in
  iterative mode, the target and acceptance band are stated and measurable where possible.
- [ ] `design.md` cites sources / records maths where relevant; no requirements restated.
- [ ] `tasks.md` exists in `rune`, tasks map to requirements, state is current — *unless*
  iterative mode, where the converge-on-target loop and decision log carry the state.
- [ ] Code matches requirements + design; refusal/units/safety paths honoured.
- [ ] `decision_log.md` has any load-bearing decisions (Enhanced Nygard ADR format).
- [ ] `OVERVIEW.md` updated (status + links); `DECISIONS.md` updated if cross-cutting.
