# Wireframe intake (Claude artifacts → UI spec)

How wireframes designed in Claude on the web get turned into a MeData UI spec.
There is no claude.ai connector in the CLI session, so artifacts arrive by paste.

## Why paste, not a live connector

Claude artifacts are self-contained HTML/React previews held in a claude.ai
conversation or project. This repo's CLI has the Figma and Google Drive MCPs
connected but **not** a claude.ai one, so the artifact source cannot be fetched
directly. The reliable path is: paste the artifact's code (or drop the file into
the repo / Google Drive) and translate it here.

## Landing zone

**Bulk-folder archive (current scheme — Decision 10, design-handoff-00).**
Each design handoff arrives as a coherent bundle (wireframes + scaffold + README)
whose internal cross-references must be preserved. Handoffs are committed verbatim
as numbered folders:

```
design-system/wireframes/design-handoff-NN/   # e.g. design-handoff-00/, design-handoff-01/
```

Each folder contains a `MANIFEST.md` recording the handoff id, date received,
source description, and the list of behavioural deviations the adopting spec makes.
No commit-SHA field — `git log -- design-system/wireframes/design-handoff-NN/`
answers that question for free.

These are **inert reference inputs**: nothing imports them, and they carry no target
membership. Future handoffs increment the number (01, 02, …) as new archive folders
alongside their own spec.

**Superseded (one-file-per-screen scheme).**
The earlier convention — one file per screen at
`design-system/wireframes/<screen-name>.<ext>` — is superseded by the bulk-folder
archive above. It is preserved here for history only.

## Translation pipeline (per screen)

Each wireframe becomes two kinds of spec output, never a direct code port:

1. **Design-system page file** — `design-system/pages/<screen>.md`, in the same
   shape as the existing `photo-tab.md` / `meals-tab.md`: layout, the tokens it
   uses (colour, type, spacing from `design-system/MASTER.md`), and any override
   of the master. Non-token values in the wireframe are reconciled to the master
   or flagged as a proposed token change.
2. **Requirements** — EARS acceptance criteria in the owning UI spec's
   `requirements.md` (a new `specs/ui/<capability>/` spec, or an addition to an
   existing one), describing observable behaviour, not markup.

The artifact's literal HTML/CSS/JSX is **not** copied into `App/*.swift`. It is a
picture of intent; the SwiftUI implementation follows the design-system page +
requirements, using existing components and tokens.

## Reconciliation rules

- Web artifacts use web idioms (hover, `px`, web fonts, `#hex`). Map these to the
  iOS equivalents: touch/press states, points, SF/system type, `Color` tokens.
- Any colour that is not already a MASTER.md token is either mapped to the nearest
  token or raised as a proposed token addition in the spec's decision log — never
  hard-coded silently.
- Glassmorphism / neumorphism / heavy shadow in a wireframe are anti-patterns here
  (MASTER.md "Style"); note the intent they were expressing and realise it with the
  approved flat/OLED/exaggerated-minimalism layers instead.

## Figma option (heavier, deferred)

If a living, editable design source is wanted later, the same artifacts can be
pushed into a Figma file via the Figma MCP and Code-Connected back to the SwiftUI
components. That is a separate, larger effort than the paste→spec path above and
is not required to seed a spec.
