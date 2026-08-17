# meal-review/dose-suggestion — composition record

Three options exist for this surface, which was the intention: the repo's own convention, in
`docs/agent-notes/device-build-and-test.md` under "Comparing UI attempts on the phone", is that
"Nothing merges until a person looks at all three and picks one". This file is what "picks one"
writes down when the answer is *parts of each*.

**A composition is a table of zone choices.** It is short, it is unambiguous, and it is directly
buildable — as `attempt-4.html`, or as the SwiftUI. It replaces the paragraph of prose that would
otherwise have to carry the same instruction, and unlike the paragraph it names regions that exist in
the markup and can be pointed at in `compare.html`.

- **Surface:** `meal-review`
- **Catalogue id under decision:** `meal-review/dose-suggestion`
- **Owning spec:** `specs/data/insulin-dosing/` — look at `design-direction.md` for the register
  rules and `design-system/pages/meal-review.md` for the layout order
- **Options compared:** `attempt-1.html`, `attempt-2.html`, `attempt-3.html`, together in
  `compare.html`
- **Worked figure throughout:** a 60 g-carbohydrate meal on a 214 g plate, 60 g ÷ 5.0 g/U = 12.0 U

## The zone vocabulary

Declared once for `meal-review` in `design-system/surfaces.md` and reused by every option for this
surface, in the layout order fixed by `design-system/pages/meal-review.md` ("Layout zones") and by
`specs/data/insulin-dosing/design-direction.md` §2, which states that the order "is fixed and must
not change".

| zone | what it is |
|---|---|
| `photo` | preview plus class outlines, ~40% of height, fixed |
| `total-row` | the carbohydrate figure, the confidence pill and the middle-dot second line |
| `primary-action` | `Record 60 g` — the one accent-filled control on the screen |
| `scale-control` | `PLATE` label and the fraction capsules, above the fold |
| `accessory-line` | calibration and estimate signals, one expandable line |
| `food-rows` | the scrolling per-food rows |

## The composition — `attempt-4`

| zone | taken from | reason |
|---|---|---|
| `photo` | attempt-1 | Identical in all three; taken from the option that changed nothing. |
| `total-row` | attempt-2 | The extracted middle-dot line. The divisor is the parameter the feature exists to measure, and it sheds first, so at any width where it does not fit the line is byte-identical to attempt 1's. |
| `primary-action` | attempt-1 | Unchanged `Record 60 g`. No option proposed anything else, and the screen's single accent budget is spent here. |
| `scale-control` | attempt-1 | 44x34 capsules kept where they are, because `specs/ui/meal-review/requirements.md` says "The scale control SHALL be visible without scrolling when the surface first appears." |
| `accessory-line` | attempt-1 | One expandable line, unchanged; nothing in the three options touched it. |
| `food-rows` | attempt-3 | Its chip and commit treatments, which `App/EntryChrome.swift` on `insulin-dosing-ui-3-on-research` describes as "the plate-fraction control's, moved to the grouped palette" — so the row affordances and the manual-entry sheets stop drifting apart. That file exists only on that branch; it is not in the `research` tree. |

Six lines, and the next artifact is unambiguous. Build it as `attempt-4.html` and it sits in
`compare.html` beside the other three on exactly the same terms: **a composed option is an ordinary
option**, and it still has to be looked at on the phone before it is a decision.

## What this table cannot say, and where that goes instead

- **Attempt 3's actual proposition is not a zone choice.** Its move is that this surface carries no
  dose readout at all and that three manual-entry sheets become one — `App/LogSheet.swift` calls
  itself "ONE manual-entry surface, three modes … This is that third sheet refusing to exist", and
  `git diff --name-only research...insulin-dosing-ui-3-on-research` does not list
  `App/MealReviewView.swift`. A zone table describes regions *within* a surface; it has no row for
  "this surface, and two others, become one". That belongs in the surface-delta table in the owning
  spec's `requirements.md` as a `consolidate` row naming the ids involved. The two artifacts are
  complementary: zones compose *within* a surface, the delta table records changes *to the set of*
  surfaces.
- **A zone choice does not settle decomposition.** Attempts 1 and 2 render the second line
  identically in places; attempt 1 built it inline in `App/MealReviewView.swift` and attempt 2
  extracted `App/DoseReadoutLine.swift`. Zones say what a region looks like, never how it is factored
  in Swift. If the factoring matters, write it in the decision, not in the table.
- **Nothing enforces the boundaries.** No check verifies that an implementation respects the zones its
  wireframe declared. Zones are a naming convention for regions; two people could agree this table and
  still build different things inside a zone.

## This record outlives the wireframes

The option files here are disposable — the folder is deleted when the SwiftUI lands. This table is
not. On implementation:

1. The table above, with its reasons, moves into the owning spec's `decision_log.md` as an Enhanced
   Nygard entry, where the alternatives are the zones *not* taken.
2. The chosen render goes to `design-system/archive/ios-v0/meal-review-dose-suggestion.png`.
3. The catalogue row for `meal-review/dose-suggestion` in `design-system/surfaces.md` flips to
   `shipped`.
4. `design-system/wireframes/insulin-dose/` is deleted, this file included.

That is what makes the choice reviewable in a year without keeping the options alive to rot: the
reasoning is preserved in the spec, the appearance is preserved as a picture, and the HTML — which
was only ever a way of looking — is gone.

**Status of this file:** it is a worked example of the record, written while the options are on the
table. It is not a ruling on the insulin-dosing readout; that decision is the developer's, made by
looking at `compare.html` and then at the phone.
