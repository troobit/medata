# Wireframes — options, cheap to make and easy to compare

A wireframe here exists **only while a surface is being designed**. It is deleted when the
implementation lands. That is the whole maintenance strategy: a file that does not outlive its
decision cannot go stale.

The job it does while it lives is narrower and more useful than "a picture of a screen". It makes
options for one surface **cheap to produce**, **cheap to look at**, **visible side by side**, and
**reusable as the description of what you want to see next**.

## Layout

```
wireframes/<surface>/<attempt>.html      one option — a whole screen at device metrics
wireframes/<surface>/compare.html        every option for that surface, adjacent, plus a per-zone view
wireframes/<surface>/composition.md      the zone-choice record: which parts came from which option
wireframes/view-mode.css                 the fragment view modes compare.html drives the options with
wireframes/design-handoff-00/            frozen historical bundle — see below
```

Each option is self-contained HTML at true iPhone 16 Pro metrics (402x874pt), linking
`../../tokens.css`, `../../wireframe.css` and `../view-mode.css`. It opens with an HTML comment
naming its catalogue id, its attempt number, the one thing it is testing, and the zones it marks.

`tokens.css` is generated from `App/Colors.swift` by `tools/design_tokens/tokens_to_css.py`. Every hue in
a wireframe comes from a `--medata-*` token or it is wrong. Neutrals are the exception: black, white and
white-at-opacity are the app's OLED chrome convention rather than a token set, and the greys around the
device are furniture, not design.

## Zones — how a part of a screen gets a name

A **zone** is a named region of a surface: the thing a person actually points at when comparing
options. For `meal-review` they are `photo`, `total`, `primary-action`, `scale-control`, `accessory`,
`foods`.

- Zone names are declared **once per surface** in `design-system/surfaces.md`, and every option for
  that surface reuses them. An option never invents a name; if a surface has no declared vocabulary
  yet, its frame carries no zone marks (see the `log-sheet` frame in
  `insulin-dose/attempt-3.html`).
- **A zone names a region by its role, never by its present geometry.** `total`, not `total-row`:
  the moment an option makes the total something other than a row — and `insulin-dose/attempt-3.html`
  is already close — a name that says "row" is a name that lies. This is the rule ARIA landmark
  regions and Drupal theme regions have both settled on, and the reason seven geometry-shaped names
  across the catalogue were renamed on 2026-09-25, while exactly one composition table existed:

  | was | is | surface |
  |---|---|---|
  | `total-row` | `total` | `meal-review`, `meal-overview` |
  | `accessory-line` | `accessory` | `meal-review` |
  | `food-rows` | `foods` | `meal-review`, `meal-overview` |
  | `bottom-row` | `bottom` | `capture` |
  | `value-line` | `value` | the five shared `row-*` surfaces |
  | `time-line` | `time` | the five shared `row-*` surfaces |
  | `row-list` | `rows` | `records` |

  Three of the seven — `total`, `accessory`, `foods` — are `meal-review`'s, so they are the three
  this folder's files carry. The other four are elsewhere in `design-system/surfaces.md`, which is
  the register: it holds the renames with the reasoning, and it is where an eighth one gets written
  down. Renaming a zone is a breaking change to every wireframe and composition table citing it,
  which is why doing it while one table existed was the cheap moment.
- In the markup a zone is one attribute: `<section data-zone="total"> … </section>`.
- `compare.html` outlines and labels them on demand, so the parts being compared are visible **as
  parts**.
- Zones are a naming convention for regions, **not a code construct**. Nothing is generated from
  them, and nothing checks that an implementation respects the boundaries its wireframe declared.

What the names buy is that *"attempt 2's total row with attempt 1's plate control"* becomes something
you can write down and hand over, instead of a sentence that has to describe the whole screen again.

## `compare.html` — the point of the exercise

Options are only useful if you can look at them together. Before this page, each option had to be
checked out and deployed to be seen at all, one at a time, so comparison happened from memory across
rebuilds.

`compare.html` puts every option for a surface in one page, at true device metrics, side by side. It
opens by double-clicking — no server, no build step, no framework — and it does three things:

1. **Whole screens**, adjacent. What a person judges first.
2. **Outline zones**, on a toggle (`z`). The regions get dashed boundaries and labels.
3. **One zone, all three.** Pick `total` and the total rows of every option land beside each other,
   each in the 16pt gutter its own screen gives it. That is a two-second judgement instead of a
   memory exercise.

There is also **fit to window** (`f`) at 0.72x. It is labelled *not true metrics* on the page,
because a scaled screen is no longer evidence about size — use it to see the set, not to decide
whether something is big enough.

**Each column is an `<iframe>` pointed at the option's own file.** This page holds no copy of any
option's markup, so nothing on it can disagree with an option. Adding a fourth option is one
`<article>` in `compare.html` and one `attempt-4.html` beside it.

### What `file://` does and does not allow

The three facts this page is built on, each run as an experiment against Google Chrome 154.0.8037.58
on 2026-09-26 — a `file://` parent with a sibling `file://` child — rather than assumed:

- **An `<iframe>` displays a sibling `file://` page.** The parent renders it normally, at the size
  the parent gives it.
- **The parent cannot read the child.** A local file is an opaque origin, so displaying and reading
  are different permissions and only the second is denied. Two accessors, two different failures, and
  the difference matters:
  - `frame.contentDocument` returns **`null`**. It does *not* throw, so a bare `if (doc)` passes
    silently and the bug shows up as nothing happening.
  - `frame.contentWindow.document` throws **`SecurityError`**.
  - `frame.contentWindow` itself is a usable `WindowProxy`. That is what makes `compare.html`'s
    height listener work: it matches the message's `event.source` against each frame's
    `contentWindow` by identity, because an opaque origin posts with `origin` `"null"` and there is
    nothing else to match on.
- **ES module scripts do not load from `file://` at all.** A `<script type="module" src="…">` beside
  the page never runs. Every script in this folder is therefore a classic inline `<script>` — no
  `type="module"`, no `import`, in the options or in `compare.html`.

Those three together decide the design. Because the parent cannot reach in, it drives each option
through the **URL fragment**, which the option reads with the 43-line classic script at the end of
its body: `attempt-1.html#frame` hides the page furniture, `#frame,zones` adds the outlines,
`#frame,zone=total` hides everything but that one region. `view-mode.css` holds the tokens and the
CSS each one turns on. Traffic the other way is one `postMessage` per option, carrying the height it
ended up at, because the parent cannot measure a document it cannot read.

Opening an option directly is unaffected: with no fragment none of the modes are on, and the file is
the page it always was. That is what the 56 extra lines per option buy — 104, 100 and 160 lines as
first written, 160, 156 and 216 now, the difference being one stylesheet link and the shared
view-mode block. `compare.html` went from 538 lines to 425 over the same change, because it stopped
carrying three transcriptions of screens that already existed.

**Safari is untested.** Its `file://` subresource policy is stricter than Chrome's and nothing here
has been checked against it. If a column comes up blank in Safari, open `compare.html` in Chrome
before assuming the page is broken.

## `make wireshot` — seeing what you just wrote

Options became cheap to write long before they became cheap to look at, and "costly to compare" is
one of the three costs this library exists to remove. `tools/wireshot.sh` closes that half:

```
make wireshot SURFACE=insulin-dose               # every attempt-*.html for that surface
make wireshot SURFACE=insulin-dose ATTEMPT=2     # just attempt-2.html
```

It renders each option with headless Google Chrome at `--force-device-scale-factor=3` into
`tmp/wireshot/<surface>/`, so the phone inside the page is 1206x2622 device pixels — the frame an
iPhone 16 Pro screenshot produces. A distance measured on the device frame and divided by 3 is the
value to write in Swift. It needs Chrome and nothing else: no Node, no npm, no server.

What it is for is the author. An agent or a person writing an option can now see the option before
handing it over, which is the difference between "I wrote some HTML" and "I looked at it".

**It does not move the gate.** The gate for UI work in this project is a person looking at the screen
of an iPhone 16 Pro, and a PNG from headless Chrome says nothing about Dynamic Type, safe-area insets
or `ViewThatFits`. It says only that the layout and the hierarchy are what you meant. Treat every
metric in it as a starting position to check on the phone.

**Why it reaps the browser rather than waiting for it.** Measured 2026-09-26 against Google Chrome
154.0.8037.58: the PNG is complete on disk one second after launch, and the browser process is still
alive ninety seconds later. Waiting on it hung the whole run after the first render, with the file
already written. `tools/wireshot.sh` now backgrounds each render, polls until the PNG exists and has
stopped growing, then kills the browser; `TIMEOUT` (default 60s) is the per-render ceiling and a
render that never settles is a failure, not a stall. `make wireshot SURFACE=insulin-dose` completes
unattended in about six seconds for all three options.

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
   several renderings, not one — and at roughly 100 lines of screen markup each, several is
   affordable.
2. **Render them.** `make wireshot SURFACE=<surface>` and look at the PNGs. This is the step that
   catches the option that does not survive contact with a layout engine, before anyone else spends
   attention on it.
3. **Compare.** Open `compare.html`, outline the zones, step through them.
4. **Compose, if the answer is parts of each.** Fill in `composition.md`, and build `attempt-4.html`
   from it if it needs to be seen before it is built.
5. **Decide**, and record the zone-choice table with its reasons in the owning spec's
   `decision_log.md`.
6. **Implement**, following the existing `<surface>-attempt-N` tag convention in
   `docs/agent-notes/device-build-and-test.md`, "Comparing UI attempts on the phone".
7. **Delete the folder.** Render the winner to `design-system/archive/ios-v0/<id>.png` and flip that
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
- HTML can **lie** about Dynamic Type, safe areas and `ViewThatFits`, and so can a wireshot PNG of
  it. Treat every metric here as a starting position to check on the phone, not as a result.
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
