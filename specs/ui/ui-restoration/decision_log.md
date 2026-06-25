# Decision Log: UI Restoration (Figma Archive)

## Decision 1: Code is the source of truth, Figma is downstream

**Date**: 2026-06-04
**Status**: accepted

### Context

The MeData design system exists as SvelteKit code (brand tokens, a `Logo` component, an icon suite, UI primitives, and CSS/Svelte animations). A Figma file is wanted so the visual system is browsable and shareable by non-developers. Two-way authoring (editing Figma and code independently) inevitably drifts.

### Decision

The repository code is the canonical source of truth for the MeData visual identity. The Figma file is a downstream artifact generated from the code/`design-system.md`. Drift is reconciled by re-running the Figma authoring step from code, never by hand-editing code to match Figma.

### Rationale

The values that matter (SVG path data, colour hex values, animation timings, component variants) are already precise in code and version-controlled. Treating code as authoritative keeps a single owner for each value and makes reconciliation mechanical.

### Alternatives Considered

- **Figma as source of truth**: Designers author in Figma, developers re-implement - Rejected; the system already exists in code, and re-implementing from Figma would lose the exact values and add manual translation error.
- **Bidirectional sync**: Keep both in step manually - Rejected; no tooling enforces it, so it drifts.

### Consequences

**Positive:**
- One owner per value; reconciliation is re-export, not negotiation.
- `design-system.md` doubles as the authoring brief and the drift-check reference.

**Negative:**
- Designers cannot freely restyle in Figma; changes must flow back through code.

---

## Decision 2: Snapshot the pre-refocus design system from commit 3b5d54d

**Date**: 2026-06-08
**Status**: accepted

### Context

Commit `d062061` ("Development updates and MVP simplification (refocus)") deleted the entire `ui/` primitive suite, the `icons/` set, `motion.svelte.ts`, `PageTransition.svelte`, and several brand assets (`logo.png`, the `apple-touch-icon-*.png` set). The design system to be archived is the fuller pre-refocus one, not the current `HEAD`.

### Decision

The penultimate commit `3b5d54d` ("Fixes for previous round.") — the last commit before the refocus — is the asset and specification snapshot for this archive. All path data, colours, variants, and animation timings are read from that commit's tree via git history.

### Rationale

`3b5d54d` is the most recent state that still contains the complete design system (Logo variants, the 7-icon macro/drink suite, the UI primitives, and the animation set). It is reachable in git history, so no code needs to be restored to the working tree to read it.

### Alternatives Considered

- **Current `HEAD`**: Simpler to read - Rejected; the refocus stripped most of the design system, so `HEAD` no longer contains the material to archive.
- **Cherry-pick assets back to the working tree first**: - Rejected; unnecessary, and superseded by Decision 3 (no code restoration).

### Consequences

**Positive:**
- The complete system is captured without touching the current MVP code.

**Negative:**
- Contributors must use `git show 3b5d54d:<path>` to read sources, not the working tree.

---

## Decision 3: Reframe the spec as a pure Figma archive (no code restoration)

**Date**: 2026-06-08
**Status**: accepted (supersedes the code-restoration framing of `requirements.md` v0.3)

### Context

`requirements.md` v0.3 was written as a code-restoration spec: re-add `Logo.svelte`, `motion.svelte.ts`, and the touch icons to the working tree with vitest coverage, and document the rest. The stated goal has since changed to exporting the design system to Figma. The branch is named `ui-archive`.

### Decision

This spec's sole deliverable is the Figma archive plus the `design-system.md` documentation that drives it. No design-system code is restored to the working tree. The pre-refocus code remains the source of truth in git history (Decision 2) and is read from there.

### Rationale

The code already exists and is preserved in git; re-adding it to a working tree that has deliberately moved on to a slimmer MVP would reintroduce dead code and tests for components the app no longer renders. The value being sought is a browsable design archive, which the Figma file and `design-system.md` provide without that cost.

### Alternatives Considered

- **Keep both active** (restore code AND author Figma): - Rejected; reintroduces unused components/tests into the MVP for no runtime benefit.
- **Demote code restoration to deferred**: Keep the sections, mark them optional - Rejected; leaving inert requirements in the doc invites confusion about what is actually being built.

### Consequences

**Positive:**
- Smallest footprint; the MVP working tree is untouched.
- `requirements.md` becomes a clear, single-purpose Figma-export spec.

**Negative:**
- If the live app later needs these components, a separate restoration spec is required.
- `design-system.md` must be complete enough to author from, since there is no restored code in the tree to inspect.

---

## Decision 4: Figma authoring is in-scope (supersedes the prior Non-Goal)

**Date**: 2026-06-08
**Status**: accepted (supersedes the "Authoring the Figma file itself" Non-Goal in `requirements.md` v0.3)

### Context

`requirements.md` v0.3 listed "Authoring the Figma file itself" as a Non-Goal, deferring it to a designer. The current goal is to author that file directly using the Claude `/figma` plugin toolset.

### Decision

Authoring the Figma file is the primary in-scope activity, performed with the Claude `/figma` plugin skills (`figma-generate-library` for foundations and components, `figma-generate-design` for any composed example screens).

### Rationale

The `/figma` toolset can read `design-system.md` and the source code and build the Figma file directly with proper variables, styles, and component variants. This removes the manual designer hand-off the original Non-Goal assumed.

### Alternatives Considered

- **Hand off to a human designer**: - Rejected; the plugin produces a tokens-and-components-linked file directly from the source of truth, which a manual rebuild would not guarantee.
- **Figma REST/MCP server setup**: - Rejected; the Claude Figma plugin covers the need without separate server configuration.

### Consequences

**Positive:**
- The Figma file is generated from the source of truth, not re-drawn by hand.
- Components land as proper variant sets bound to design-token variables.

**Negative:**
- Output quality depends on the plugin's component/variant fidelity; some animation behaviour can only be approximated (see Decision 7).

---

## Decision 5: Export the full component and icon suite, including animations

**Date**: 2026-06-08
**Status**: accepted

### Context

The archive could cover just the Logo and brand tokens, or the whole system. The pre-refocus snapshot contains the Logo (3 variants, animated), a 7-icon macro/drink suite (`Alcohol`, `BSL`, `Carbs`, `Fat`, `Insulin`, `Meal`, `Protein`), 4 inline `BottomNav` icons, UI primitives (`Button`, `Input`, `EmptyState`, `ExpandableSection`, `LoadingSpinner`, `StorageError`), and a set of animations.

### Decision

The archive covers the full suite: brand tokens, the Logo, the icon suite, the UI primitives, and the animation set (Logo draw/undraw loop, `PageTransition` fade/slide, `Button` press/ripple/shimmer/shadow, `Input` float-label/focus-shimmer, `ExpandableSection` spring rotation + slide, spinner rotation).

### Rationale

A partial archive would leave the icon suite and interaction design — the parts hardest to reconstruct later — undocumented. Capturing everything once, while the snapshot is at hand, is cheaper than revisiting.

### Alternatives Considered

- **Logo + tokens + animations only**: - Rejected; omits the icon suite and primitives, the bulk of the reusable system.
- **Full suite, static only** (document animations but do not represent them in Figma): - Rejected; the interaction design is part of what is worth archiving (see Decision 7 for how it is represented).

### Consequences

**Positive:**
- Complete, single-pass capture of the visual and interaction system.

**Negative:**
- Larger authoring effort; some animations are documented rather than fully reproduced in Figma.

---

## Decision 6: Logo and icon variant naming — `colour`, not `pride`

**Date**: 2026-06-04
**Status**: accepted

### Context

The pre-refocus snapshot named the rainbow-gradient asset `apple-touch-icon-pride.png`. The `Logo` component's `variant` prop uses the value `colour` for the same gradient.

### Decision

The third variant is named `colour` everywhere in the archive (`Logo` variant value, Figma variant name, raster asset filename `apple-touch-icon-colour.png`). The `pride` filename is not carried forward.

### Rationale

Aligning the asset filename with the component's `variant` prop value removes the one place the system used two names for one thing, keeping the archive internally consistent.

### Alternatives Considered

- **Keep `pride`**: - Rejected; mismatches the `variant` prop value and the other two variant filenames (`default`, `contrast`).

### Consequences

**Positive:**
- One name per variant across code, assets, and Figma.

**Negative:**
- The archive's filename differs from the historical asset name in commit `3b5d54d`.

---

## Decision 7: Represent animation as Figma interactions where supported, documented otherwise

**Date**: 2026-06-08
**Status**: accepted

### Context

The source animations range from CSS keyframes (`PageTransition`, Logo `stroke-dashoffset` loop) to Svelte `Spring`-driven physics (`Button` press/ripple, `ExpandableSection` icon rotation). The Figma Plugin API cannot reproduce arbitrary CSS keyframes or spring physics exactly.

### Decision

Each animation is captured in `design-system.md`'s animation catalogue with its exact timing, easing, and keyframes. In the Figma file, animations are represented with Smart Animate / prototype interactions and component variant states (e.g. default/hover/pressed) where the API supports a faithful-enough approximation; where it does not, the variant end-states are authored and the motion is left documented-only in `design-system.md`.

### Rationale

The exact, reproducible specification belongs in `design-system.md` (the source of truth). Figma's role is to make the states and approximate motion browsable, not to be a pixel-exact runtime. Splitting responsibilities this way avoids over-investing in Figma prototype fidelity for physics it cannot match.

### Alternatives Considered

- **Reproduce every animation exactly in Figma**: - Rejected; infeasible for spring physics and custom keyframes via the Plugin API.
- **Skip animation entirely in Figma**: - Rejected; the state set (hover/pressed/expanded) is useful to browse even without motion.

### Consequences

**Positive:**
- Exact specs are preserved in one place; Figma stays a browsable approximation.

**Negative:**
- The Figma file is not a faithful motion prototype; consumers must read `design-system.md` for exact timings.

---

## Decision 8: Ship non-canonical SVG + mermaid placeholders while Figma authoring is quota-blocked

**Date**: 2026-06-09
**Status**: accepted

### Context

The Figma Starter plan caps MCP tool calls at 6 per month (per Figma's `rate-limits-access.md`); the June 2026 window was exhausted by the Foundations work (tasks 2-3) and earlier inspection calls. Two attempts on 2026-06-09 to author tasks 4-6 (Logo + icons) hit the cap with the file unchanged. The next quota window is 2026-07-01 at the earliest, leaving the spec stalled for ~3 weeks with no browseable representation of the Logo or icon work the spec is meant to deliver.

### Decision

Commit static SVG renders (3 Logo variants, 7 macro icons, 4 nav icons) plus mermaid diagrams (Figma file structure, Logo variant matrix, Button state machine) under `docs/agent-notes/ui-baseline/`, alongside an "Uplift to Figma" mapping that doubles as the next-quota-window authoring brief. These artifacts are explicitly **non-canonical**: the Figma file remains the source of truth once authored, and the SVGs are deleted or kept as a regression check after uplift — they are not maintained in parallel.

### Rationale

The spec's deliverable is the Figma archive, but the authoring step is blocked on a calendar window outside our control. A repo-local placeholder lets reviewers see what the Logo and icons look like, confirms the path data from design-system.md renders sensibly, and prepares an exact, machine-followable authoring brief — so the next quota-window session is mechanical, not interpretive. The cost is small (16 files, all generated from existing spec data) and the cleanup is mechanical (`rm -rf docs/agent-notes/ui-baseline/` after uplift).

### Alternatives Considered

- **Wait until July with no placeholders**: - Rejected; leaves the spec partially-archived with no way to see the Logo + icon work for ~3 weeks, and forces the next session to re-derive path data and authoring shape from scratch.
- **Render placeholders directly into Figma using a non-MCP path (e.g. manual upload)**: - Rejected; breaks Decision 1 (code is the source of truth, Figma is generated from it via the `/figma` plugin) and creates a hand-authored Figma layer that drifts.
- **Maintain SVGs and Figma in parallel after uplift**: - Rejected; bidirectional sync is exactly what Decision 1 forbids. The SVGs are a stopgap, not a parallel artifact stream.

### Consequences

**Positive:**
- The Logo + icon work is browseable today via `docs/agent-notes/ui-baseline/README.md`.
- The "Uplift to Figma" section makes the July session mechanical: one `use_figma` call, exact bindings spelled out.
- Path data is sanity-checked (we can see the SVGs render) before being pushed to Figma — bugs in the spec's path data would be caught locally.

**Negative:**
- A second non-canonical asset location exists temporarily; a reviewer could mistake it for source-of-truth. Mitigated by an explicit disclaimer at the top of the placeholder README and in `docs/agent-notes/figma-archive.md`.
- The settings-icon path was elided in `design-system.md` §7.2 and had to be re-read from the snapshot — same lookup will be needed in the Figma session; `design-system.md` §7.2 should be filled in before the next session.

### Impact

- `docs/agent-notes/ui-baseline/` (new directory, 16 files).
- `docs/agent-notes/figma-archive.md` (cross-references the placeholders).
- Rune tasks 4, 5, 6, 7 remain `Pending` — placeholders do **not** satisfy the spec's acceptance criteria, which are written against the Figma file.

---
