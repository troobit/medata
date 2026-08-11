# MeData documentation

MeData is a native iOS app that estimates the carbohydrate content of a meal from one or
two photographs using on-device computer vision (no LLM, no network in the estimation
path). Start with the project [`README.md`](../README.md) for structure, build commands,
and the **Phase 1 / 2 / 3 delivery plan**.

**Current state:** the full pipeline runs on the iPhone 16 Pro (hardware floor since
segmenter-foundation Decision 22). Debug builds still use the development stub in the segmenter
slot (`DEV_STUB_SEGMENTER`, `specs/estimation/pipeline/requirements.md` §23), but Release now
bundles a real model (`coreml_ab812dc3aa9d`, 36 channels). The MVP gate is the
on-device verification of that model — see [`roadmap.md`](roadmap.md).

## Documents

| Document | Purpose |
|---|---|
| [`roadmap.md`](roadmap.md) | **What to do next, in order.** The remaining path to MVP (one batched on-device session) and the capture → truth → error loop that makes accuracy improvable afterwards. |
| [`architecture.md`](architecture.md) | **Start here.** Layers, modules, abstractions, and Swift/SwiftUI conventions — written for developers joining the project. Links to the specs for detail. |
| [`ios-device-setup.md`](ios-device-setup.md) | Build, sign, and side-load the iOS app to the iPhone 16 Pro (or any LiDAR-equipped iPhone). |
| [`mvp-unblock-runbook.md`](mvp-unblock-runbook.md) | **Do this now to unblock the MVP.** Ordered, time-boxed operational steps and go/no-go gates for producing the on-device segmenter — the one human/GPU/device-gated task left. Links into `ml-training.md` for detail. |
| [`ml-training.md`](ml-training.md) | End-to-end training recipe for the Phase 3 segmenter + β_c calibration. |
| [`agent-notes/`](agent-notes/) | Implementation-progress notes: what was built, gotchas found, and module-level details captured during tasks. |

## How these relate to the specs

Design intent lives in [`specs/`](../specs/) — one subfolder per feature, each with
`requirements.md`, `design.md`, `decision_log.md`, `tasks.md`, and `prerequisites.md`.
`architecture.md` is the evergreen overview that ties the modules together and points into
those specs; it does not duplicate the requirements or the maths.

**[`specs/OVERVIEW.md`](../specs/OVERVIEW.md) is the spec index** — every feature and
bugfix spec, its status, summary and per-file links. Consult it first when looking for
prior design work on any topic. **[`specs/PROCESS.md`](../specs/PROCESS.md)** governs *how*
a spec is written, sized, tracked (`rune`), and reviewed — read it before starting a new
feature.

The two foundational specs the architecture sits on top of:

- `specs/estimation/pipeline/` — the on-device estimation pipeline (the core). §0 has the phase
  plan; §1.2 has the hardware floor; §23 covers the Phase 1 dev-stub.
- `specs/ui/iphone-experience/` — the SwiftUI capture-flow shell.

## Architecture vs agent-notes

These two are deliberately distinct:

- **`architecture.md`** — evergreen. *How the system is shaped and why.* Read it to
  understand the layering and conventions before changing code.
- **`agent-notes/`** — incremental. *What happened during implementation, and the
  non-obvious traps.* Read the relevant note before working in a module; update it after.
</content>
