# Review Swap Loop — Fewer Taps From Wrong Food To Recorded Meal

## Overview
`specs/DECISIONS.md` MD-29 (2026-09-27) puts the review screen's swap-a-food
and Record loop second only to volume correctness: the user, not the model,
picks the right food, so a wrong class must cost one or two taps. The
shipped relabel path (`specs/ui/meal-review` Req 3, 5) is already two taps
on the shortlist, but a survey of `App/Pages/MealReview/` found six
frictions, each verified against the code:

- `RelabelSheet` lists "Not in the database" FIRST, then the shortlist, then
  "All foods" with an in-list `TextField` filter that scrolls away.
- `openAlternatives` presents the sheet and only then awaits the recency
  read, so the shortlist pops in late and the list reflows under the thumb.
- `eligibleFoods` filters out the predicted class, so reverting a mis-swap
  (Req 3.11, `reverseRelabel`) is unreachable from the sheet.
- Under `recency_plus_candidates` the section is headed "Recent" even when
  every entry is candidate evidence the user never chose.
- Where a relabel is refused (`canRelabel` false, meal-review Decision 14)
  every candidate is disabled with no explanation.
- There is no way to add a food the segmenter missed.

Two attempts ship in one build, per `docs/agent-notes/device-build-and-test.md`
"Comparing UI attempts on the phone" (shape 1): attempt 1 fixes the sheet;
attempt 2 adds inline chips behind a developer-phase switch and an
"Add a food" row.

## Requirements

### Attempt 1 — the sheet (tag `review-swap-attempt-1`)
- The shortlist section MUST come first, "All foods" second, "Not in the
  database" last (Req 5.1 still offers it from both lists — it stays on the
  sheet, it just stops being the first thing under the thumb).
- The shortlist header MUST be honest: "Recent" only when the ordering is
  the pure recency source AND the recency read returned at least one entry;
  otherwise "Suggested". No score or tier is shown (Req 3.2, candidates
  Req 7.7).
- The model MUST build every row's shortlist during `start()` so the sheet
  opens populated; `openAlternatives` uses the prepared list and keeps the
  lazy build as the fallback for a row it has not prepared.
- WHEN the row is currently relabelled, a "Keep <predicted display name>" row
  MUST sit at the top of the shortlist section and call the existing
  `reverseRelabel` path (Req 3.11). It is never disabled.
- The in-list filter MUST become `.searchable` on the sheet's list, pinned
  (`navigationBarDrawer(displayMode: .always)`) and clearable. While the
  search text is non-empty the shortlist section is hidden and "All foods"
  is filtered; "Not in the database" keeps carrying the typed text as its
  query (Req 5.2).
- WHEN `canRelabel` is false, the sheet MUST show one line explaining that
  the record has no usable volume to re-derive from, above the still-disabled
  candidates. Functional, not a disclaimer (developer-phase copy rule).
- No layout change outside the sheet.

### Attempt 2 — chips and add-a-food (tag `review-swap-attempt-2`)
- Settings › Developer › Review gains **Inline food chips**
  (`DeveloperFlags.inlineFoodChipsKey`, `#if FIELD_LOOP`, default OFF), so
  both attempts coexist and are compared by toggling.
- WITH the switch on, every active, relabel-able row MUST render a chip line
  under its name: the predicted food first, then the top three prepared
  shortlist entries. The chip matching the row's current class is drawn
  selected. Tapping an alternative chip relabels in one tap (shortlist rank =
  its position in the prepared list); tapping the predicted chip reverses.
  The ⇄ button still opens the full sheet. Chips are hidden where
  `canRelabel` is false.
- An **Add a food** row MUST follow the active rows. It opens a searchable
  list of every solid the database can derive (the same eligibility as
  Req 3.8); picking one inserts a volume-less row keyed `added_<n>` whose
  predicted side is empty (zero volume, mass and carbohydrate, unity β,
  `classIndex` = the palette's `unknown_food`) and whose corrected side is the
  chosen food at one serving or 100 g, user-set. The row opens its gram
  editor (`ServingGramEditor`) so the amount is typed at once. Persistence is
  the ordinary `persist(_:)` upsert; `adoptStoredRows` restores added rows on
  a re-push so the display and the corpus row keep agreeing.
- The Add a food row is not behind the switch: it is a row appended to the
  list, not a competing layout.

## Implementation Approach
- **`App/Pages/MealReview/MealReviewModel.swift`** — `PreparedShortlist`
  (candidates + `fromRecency`) cached per class in `preparedShortlists`;
  `prepareShortlists()` called first thing in `start()`; `shortlistHeader`
  set beside `shortlist` by `openAlternatives`; `eligibleCandidates(isLiquid:
  excluding:)` shared by `eligibleFoods(for:)` and the new `addableFoods`;
  `chipCandidates(for:)` (predicted + top 3); `addFood(_:)` builds the
  `ReviewFood` and persists it; `adoptStoredRows` appends stored `added_`
  rows it does not already hold. `ReviewFood.isAdded` and `addedPrefix`.
- **`App/Pages/MealReview/MealReviewView.swift`** — `RelabelSheet` reordered
  with `.searchable`, the Keep row and the refused line; `chipLine(_:)` in
  `foodRow` gated on the flag; `addFoodRow` + `AddFoodSheet`; `nameLine`
  shows an added row's chosen name with an "added" caption instead of a
  struck-through synthetic predicted name.
- **`App/Shared/DeveloperFlags.swift`, `App/Pages/Settings/DeveloperSettingsView.swift`**
  — the key and the toggle, matching `reviewPhotoFillsWidthKey`.
- **Out of scope:** history (`ResultView`) rows for added foods — its rows
  come from `record.macros.perClass`, so an added food counts in the
  corrected total and the dose but is not listed per row there; the corpus
  representation of added foods beyond the `added_` prefix (a full spec
  should own it if the row survives the comparison); any change to
  `ShortlistOrdering` or the recency query.

## Risks and Assumptions
- **Risk:** `tools/shortlist_hit_rate.py` treats every `class_corrected` row
  as a relabel; an added row (rank 0) reads as a shortlist miss. Its adjacency
  pass already maps an unknown class name to `unknown`. Filter on the
  `added_` prefix there when the row is kept.
- **Risk:** focusing the gram field straight after the add sheet dismisses
  may not take on every iOS build; the row's amount button is the fallback
  and costs one more tap.
- **Assumption:** the app-target build plus the on-device look is the gate
  (CLAUDE.md); no MedataCore change, so `make test` is untouched.
- **Assumption:** tap counts after attempt 1 — shortlist swap 2, search swap
  3 plus typing, record as-is 1, swap then record 3. After attempt 2 with
  chips on — shortlist swap 1, search swap 3 plus typing, record as-is 1,
  swap then record 2; add a food 2 plus typing.
