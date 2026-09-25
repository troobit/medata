# Wireframe intake — how a UI change gets designed before it is written

This note is the loop. The reference documents are `specs/ui/wireframe-library/` (why it
is shaped this way) and `design-system/wireframes/README.md` (what a wireframe folder
contains). Read this one first; it is short and it tells you the order.

The thing being replaced was one-way: a Claude artifact was pasted in, archived as a
numbered `design-handoff-NN/` bundle, translated into a `design-system/pages/<screen>.md`
page plus EARS requirements, and then implemented. One design in, one implementation out,
no comparison anywhere. That is still how a *handoff bundle* is filed (below), but it is
no longer how a surface gets designed.

## The loop

1. **Name the surface.** Find or add its rows in `design-system/surfaces.md`. The
   catalogue id — `<surface>/<state>`, kebab-case, e.g. `meal-review/dose-suggestion` —
   is the citation key shared by the catalogue row, the wireframe filenames, the archive
   filename and the decision entry. One key, everywhere. If the surface has no declared
   zone vocabulary yet, declare one now; a surface nobody can point at a region of is the
   problem this whole loop exists to fix (Decision 1, Decision 4).

2. **Write the surface-delta table** in the owning spec's `requirements.md`: which
   surfaces this change adds, removes, merges or retitles. A zone table cannot express
   "these three sheets become one", and that move is exactly the kind a prose spec loses.
   A spec that changes no surface says so explicitly rather than omitting the table, so an
   absent table is always a defect and never a claim (requirement 6.7, Decision 14).

3. **Write two or more attempts** as `design-system/wireframes/<surface>/attempt-N.html`
   — self-contained HTML at 402x874pt, linking `../../tokens.css` and `../../wireframe.css`,
   opening with a comment naming the catalogue id, the attempt number, the one thing it is
   testing, and the zones it marks. One attempt is a draft, not a decision. The three
   `insulin-dose` attempts are 104, 100 and 160 lines. The three Swift attempts at the
   same readout cost 542 + 1,565 + 1,015 = 3,122 inserted lines between them (tags
   `insulin-dosing-ui-attempt-{1,2,3}-on-research`).

4. **Look at them.** `make wireshot SURFACE=<surface> [ATTEMPT=N]` renders each attempt to
   a PNG under `tmp/wireshot/` through headless Chrome at
   `--window-size=402,874 --force-device-scale-factor=3`, so the agent that wrote the
   attempt can see it before the developer is asked to. `compare.html` in the same folder
   puts every attempt side by side, outlines the zones on a toggle, and shows one zone
   across all attempts in its own gutter. Neither replaces the phone.

5. **Compose, if the answer is parts of each.** Fill in `composition.md` — zone, which
   attempt it comes from, one line of reason — and build `attempt-4.html` from it if it
   needs to be seen before it is built. A composed attempt is an ordinary attempt.

6. **Decide, in the owning spec's `decision_log.md`.** Enhanced Nygard, per
   `rules/references/decision-log-format.md`. The zone-choice table with its reasons goes
   in the entry: the wireframes are about to be deleted, and in a year the question is why
   the total row looks like that. Zones not taken write the Alternatives Considered field
   for you.

7. **Implement in Swift**, tagged `<surface>-attempt-N` on a clean tree only where a
   question remains that HTML cannot answer — decomposition, state models, settings keys
   and anything touching Dynamic Type, safe areas or `ViewThatFits`. The convention and
   its three shapes are in `docs/agent-notes/device-build-and-test.md`, "Comparing UI
   attempts on the phone".

8. **Delete the folder.** Whole of `design-system/wireframes/<surface>/`, `composition.md`
   included. Screenshot the shipped surface to
   `design-system/archive/ios-v0/<surface>-<state>.png` and flip that catalogue row to
   `shipped`. A file that does not outlive its decision cannot go stale — that is the
   entire maintenance strategy (Decision 6).

The gate does not move. It is still a person looking at the screen of an iPhone 16 Pro.
The loop moves the *choice* earlier and makes it cheaper to have more than one option to
choose between; it does not replace the device.

## Handoff bundles still arrive, and are still archived whole

There is no claude.ai connector in the CLI session, so an artifact designed on the web
arrives by paste. When it arrives as a coherent bundle — wireframes plus scaffold plus its
own README, with internal cross-references that only make sense together — it is committed
verbatim as `design-system/wireframes/design-handoff-NN/` with a `MANIFEST.md` recording
the handoff id, the date received, the source, and the list of behavioural deviations the
adopting spec makes. No commit-SHA field:
`git log -- design-system/wireframes/design-handoff-NN/` answers that for free.

These folders are **inert reference inputs**. Nothing imports them, they carry no target
membership, and they are not disposable wireframe folders — they do not get deleted when
an implementation lands. Future handoffs increment the number.

`design-handoff-00/` stays readable, and its `MANIFEST.md` is cited as evidence in both
`specs/ui/wireframe-library/requirements.md` and that spec's `decision_log.md`. Read it for
provenance; do not edit it, do not extend it, and do not trust its statements about the
current app — its manifest still calls Graph the launch root while `App/AppRoot.swift:102`
presents `HomeView`.

A single pasted screen is not a bundle. It goes straight into step 3 as an `attempt-N.html`
under the surface it is an attempt at.

## Reconciling a web artifact to this app

- Web idioms map to iOS ones: hover to touch and press states, `px` to points, web fonts
  to SF/system type, `#hex` to a `Color` token.
- Every hue in a wireframe comes from a `--medata-*` token in `design-system/tokens.css`
  or it is wrong. That file is **generated** from `App/Colors.swift` by
  `tools/design_tokens/tokens_to_css.py`; the Swift owns the palette and nothing edits the
  CSS by hand. A colour with no token is either mapped to the nearest one or raised as a
  proposed token addition in the owning spec's decision log — never hard-coded silently.
  Neutrals are the exception: black, white and white-at-opacity are the OLED chrome
  convention rather than a token set.
- Glassmorphism, neumorphism and heavy shadow are anti-patterns here
  (`design-system/MASTER.md`, "Style"). Note the intent they were expressing and realise it
  with the flat/OLED/exaggerated-minimalism layers instead.
- Developer-phase copy rule: no reassurance or disclaimer messaging anywhere. An artifact
  drawn by someone who does not know that will carry it.

## What this loop cannot catch

`design-system/wireframes/design-handoff-00/MANIFEST.md` attributes rows 10 and 11 of its
own deviation table (`MANIFEST.md:36-37`) to user direction after seeing the
implementation: full-screen covers instead of sheets over Capture, and Graph as the launch
root instead of the camera-first launch the handoff drew, because "camera-first launch was
unwanted in developer use". That is the design changing **after** the phone showed it,
which is the dominant historical cause of the handoff going stale — and **no
forward-only wireframe-to-code flow
catches it**, this one included. Wireframes make the option cheaper to produce and the
choice earlier; they cannot make the developer's reaction to a running build predictable.

What the catalogue and the surface-delta table can do is make the resulting change cheap to
write down, so the next reader finds the change recorded instead of inferring it from a
diff. What they cannot do is make the change unnecessary.

Two smaller limits worth saying out loud:

- Nothing mechanically forces a wireframe to precede the implementation. That stays a
  habit, held up by wireframing being the cheaper way to get an option, not by a rule.
- HTML lies about Dynamic Type, safe areas and `ViewThatFits`. Every metric in a wireframe
  is a starting position to check on the phone, never a result.

## External design tools are rejected, not deferred

Figma, Penpot, Supernova, Tokens Studio, Storybook and the design-token platforms were all
assessed and rejected in `specs/ui/wireframe-library/decision_log.md` Decision 2. The
structural reasons are that the source of truth leaves git and a GUI step enters an
agent-authored workflow; the token platforms additionally cannot represent an OS-resolved
colour, which is more than half of `App/Colors.swift`. Do not re-propose one without
reading that entry first.
