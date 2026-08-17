# Wireframes — options, cheap to make and easy to compare

A wireframe here exists **only while a surface is being designed**. It is deleted when the
implementation lands. That is the whole maintenance strategy: a file that does not outlive its
decision cannot go stale.

The job it does while it lives is narrower and more useful than "a picture of a screen". It makes
options for one surface **cheap to produce**, **visible side by side**, and **reusable as the
description of what you want to see next**.

## Layout

```
wireframes/<surface>/<attempt>.html      one option — a whole screen at device metrics
wireframes/<surface>/compare.html        every option for that surface, adjacent, plus a per-zone view
wireframes/<surface>/composition.md      the zone-choice record: which parts came from which option
wireframes/design-handoff-00/            frozen historical bundle — see below
```

Each option is self-contained HTML at true iPhone 16 Pro metrics (402x874pt), linking
`../../tokens.css` and `../../wireframe.css`. It opens with an HTML comment naming its catalogue id,
its attempt number, the one thing it is testing, and the zones it marks.

`tokens.css` is generated from `App/Colors.swift` by `tools/design_tokens/tokens_to_css.py`. Every hue in
a wireframe comes from a `--medata-*` token or it is wrong. Neutrals are the exception: black, white and
white-at-opacity are the app's OLED chrome convention rather than a token set, and the greys around the
device are furniture, not design.

## Zones — how a part of a screen gets a name

A **zone** is a named region of a surface: the thing a person actually points at when comparing
options. For `meal-review` they are `photo`, `total-row`, `primary-action`, `scale-control`,
`accessory-line`, `food-rows`.

- Zone names are declared **once per surface** in `design-system/surfaces.md`, and every option for
  that surface reuses them. An option never invents a name; if a surface has no declared vocabulary
  yet, its frame carries no zone marks (see the `log-sheet` frame in
  `insulin-dose/attempt-3.html`).
- In the markup a zone is one attribute: `<section data-zone="total-row"> … </section>`.
- `compare.html` outlines and labels them on demand, so the parts being compared are visible **as
  parts**.
- Zones are a naming convention for regions, **not a code construct**. Nothing is generated from
  them, no Swift type has to exist for them, and nothing checks that an implementation respects the
  boundaries its wireframe declared.

What the names buy is that *"attempt 2's total row with attempt 1's plate control"* becomes something
you can write down and hand over, instead of a sentence that has to describe the whole screen again.

## `compare.html` — the point of the exercise

Options are only useful if you can look at them together. Before this page, each option had to be
checked out and deployed to be seen at all, one at a time, so comparison happened from memory across
rebuilds.

`compare.html` puts every option for a surface in one page, at true device metrics, side by side. It
opens by double-clicking — no server, no build step, no framework — and it does three things:

1. **Whole screens**, adjacent. What a person judges first.
2. **Outline zones**, on a toggle. The regions get dashed boundaries and labels.
3. **One zone, all three.** Pick `total-row` and the total rows of every option land beside each
   other in their own device-width gutter. That is a two-second judgement instead of a memory
   exercise.

Because a `file://` page cannot read its sibling files, `compare.html` carries its own copy of each
option's screen markup. The duplication is deliberate and short-lived: the whole folder is deleted
together when the implementation lands.

## `composition.md` — the part that survives

Having looked, the useful output is often *parts of each*. That is written as a table of zone
choices — zone, which option it comes from, one line of reason — and that table **is** the brief for
the next option or for the SwiftUI. Composing zones produces `attempt-4`, written as a wireframe like
any other and compared on the same terms: **a composed option is an ordinary option, not a special
case**, and it still has to be looked at on the phone.

`insulin-dose/composition.md` is the worked example.

## The lifecycle

1. **Write two or more options.** One option is not a decision, it is a draft. The gate for UI work
   in this project is a person looking at a screen, so a surface worth deciding about ships as
   several renderings, not one — and at roughly 100 lines of HTML each (104, 100 and 160 for the
   three `insulin-dose` options), several is affordable.
2. **Compare.** Open `compare.html`, outline the zones, step through them.
3. **Compose, if the answer is parts of each.** Fill in `composition.md`, and build `attempt-4.html`
   from it if it needs to be seen before it is built.
4. **Decide**, and record the zone-choice table with its reasons in the owning spec's
   `decision_log.md`.
5. **Implement**, following the existing `<surface>-attempt-N` tag convention in
   `docs/agent-notes/device-build-and-test.md`, "Comparing UI attempts on the phone".
6. **Delete the folder.** Render the winner to `design-system/archive/ios-v0/<id>.png` and flip that
   row in `design-system/surfaces.md` to `shipped`.

The catalogue id — `<surface>/<state>`, kebab-case, e.g. `meal-review/dose-suggestion` — is the
citation key shared by the catalogue row, the wireframe filenames and the archive filename. One key,
everywhere.

## What a wireframe does not settle

Say this out loud rather than discovering it later:

- It does **not** settle decomposition, and neither does a zone choice. Attempts 1 and 2 of the dose
  readout render identically in places; one inlined the line in `App/MealReviewView.swift`, the other
  extracted `App/DoseReadoutLine.swift`. Zones say what a region looks like, never how it is factored
  in Swift.
- It does **not** settle state models or settings keys.
- A zone table cannot express a **surface-level** move — "this surface does not carry the readout, and
  three sheets become one". That is what the surface-delta table in each UI-touching spec's
  `requirements.md` records.
- HTML can **lie** about Dynamic Type, safe areas and `ViewThatFits`. Treat every metric here as a
  starting position to check on the phone, not as a result.
- Nothing mechanically forces a wireframe to precede the implementation. That stays a habit, held up
  by wireframing being the cheaper way to get an option — not by a rule.

The on-device gate is unchanged. Wireframes move the *choice* earlier; they do not replace the phone.

## `design-handoff-00/` is frozen

`design-handoff-00/` is the original design bundle and is **not** a disposable wireframe folder. It
stays as the historical record of where the app's look came from — JSX screens, the shared
`styles/wireframe.css` the current stylesheet borrows structure from, a `MANIFEST.md` and a parallel
SwiftUI sketch. Read it for provenance. Do not edit it, do not extend it, and do not trust its
statements about the current app: its manifest still calls the Graph the launch root, and `HomeView`
has been the launch root for some time. It is a snapshot, and snapshots are allowed to be old.
