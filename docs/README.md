# MeData documentation

MeData is a native iOS app that estimates the carbohydrate content of a meal from one or
two photographs using on-device computer vision (no LLM, no network in the estimation
path). Start with the project [`README.md`](../README.md) for structure and build commands.

## Documents

| Document | Purpose |
|---|---|
| [`architecture.md`](architecture.md) | **Start here.** Layers, modules, abstractions, and Swift/SwiftUI conventions — written for developers joining the project. Links to the specs for detail. |
| [`ios-device-setup.md`](ios-device-setup.md) | Build, sign, and side-load the iOS app to a developer iPhone. |
| [`agent-notes/`](agent-notes/) | Implementation-progress notes: what was built, gotchas found, and module-level details captured during tasks. |

## How these relate to the specs

Design intent lives in [`specs/`](../specs/) — one subfolder per feature, each with
`requirements.md`, `design.md`, `decision_log.md`, `tasks.md`, and `prerequisites.md`.
`architecture.md` is the evergreen overview that ties the modules together and points into
those specs; it does not duplicate the requirements or the maths.

- `specs/research/` — the on-device estimation pipeline (the core).
- `specs/ui/` — the SwiftUI capture-flow shell.

## Architecture vs agent-notes

These two are deliberately distinct:

- **`architecture.md`** — evergreen. *How the system is shaped and why.* Read it to
  understand the layering and conventions before changing code.
- **`agent-notes/`** — incremental. *What happened during implementation, and the
  non-obvious traps.* Read the relevant note before working in a module; update it after.
</content>
