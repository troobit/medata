# UI/UX Improvements

Heuristic usability review (Nielsen's heuristics, iOS HIG, WCAG 1.4.3 contrast) of the surfaces
changed by the last five commits on `research` (`2c63bd6` insulin-dosing synthesis, `0953f80` +
`c43b5ca` unified-dark-theme, `214297b` shared-meal-components, `3d31983` capture-born quick-add).
Review was conducted by reading the code against the governing design documents; no simulator or
device pass was available, so every finding cites file and line. Contrast ratios are computed from
the token values in `App/Colors.swift` with fills alpha-composited over `#000000`.

Recommendations respect the standing constraints: developer-phase copy rule (no reassurance or
disclaimer text), one accent per screen, the dose suggestion is never a control and never
accent-coloured, and `specs/ui/meal-review` Req 6.6 — "The scale control SHALL be visible without
scrolling when the surface first appears" — nothing proposed here adds height above the review fold.

## Summary

The dose-suggestion readout is a faithful, careful implementation of
`specs/data/insulin-dosing/design-direction.md`: the derived register, the middle-dot grammar, the
absence-is-absence rule and the forbidden list are all honoured, and the shared serving rows and
readouts genuinely eliminate cross-surface drift. The forced dark theme lands cleanly because the
grouped tokens were already semantic.

The findings cluster in three areas. First, **contrast**: the design system's own budget
(`design-system/MASTER.md`: "Text contrast ≥4.5:1") is broken by white text on the accent-green and
orange confidence-pill fills and on the orange banner cards — failures of 1.9:1 to 2.8:1 that the
unified dark theme now carries app-wide. Second, **the accent register**: the app's structural claim
that "accent means this button writes a row" — the very mechanism that lets a dose suggestion read
as not-a-command without disclaimer copy — is contradicted by accent-filled `Done` and `Full result`
buttons that write nothing. Third, **spoken output**: every dose line hands VoiceOver raw unit
abbreviations ("12 U", "5 g/U") that are read as letters, not quantities. Everything else is
polish-level.

## Critical Issues

### Issue: White text on High/Moderate confidence pill fills fails WCAG contrast

**Current State**: `App/ConfidencePill.swift:24-28` renders `Color.captureChromeText` (pure white)
label text over `level.colour.opacity(0.85)` in a capsule. For `.high` the fill is `medataAccent`
`#63FF00` (`App/Colors.swift:36`), for `.moderate` it is `systemOrange` (`App/Colors.swift:37`).
The pill appears on MealReviewView (`App/MealReviewView.swift:398`), ResultView
(`App/ResultView.swift:367`) and MealOverviewView (`App/MealOverviewView.swift:111`).

**Problem**: White on `#63FF00` at 85% over black computes to roughly **1.9:1**; white on dark-mode
`systemOrange` at 85% to roughly **2.8:1**. Both fail WCAG 1.4.3 for any text size (large-text
threshold is 3:1; `design-system/MASTER.md`'s own pre-delivery checklist demands ≥4.5:1). The two
*good* tiers — the ones a user should be able to read at a glance — are the two illegible ones. The
Low (white on red, ~4.6:1) and Very Low (white on grey, ~8.6:1) tiers pass.

**Recommendation**: Flip the label colour to `Color.captureBackground` (black) for `.high` and
`.moderate`, keeping white for `.low` and `.veryLow` — exactly the treatment `EntrySaveButton`
(`App/EntryChrome.swift:53-56`) and the `Record` button (`App/MealReviewView.swift:441-442`) already
use on accent fills (black on full `medataAccent` is ~15.8:1; black on the orange fill ~7.4:1).
Alternatively drop the fill to a low-alpha tint with the tier colour as text, but the black-on-fill
fix is one line per tier and matches existing precedent.

**Impact**: Restores legibility of the app's primary trust signal at every meal surface and brings
the pill inside the design system's stated contrast budget.

**Implementation Notes**: Add a `labelColour` computed property beside `colour` in the
`ConfidenceLevel` extension in `App/ResultView.swift:33-40` / `App/ConfidencePill.swift`. No layout
change; the icon + text `color-not-only` rule is unaffected.

### Issue: White caption text on the orange banner cards fails contrast

**Current State**: Three surfaces put white `caption.weight(.semibold)` text on
`Color.confidenceModerate.opacity(0.85)`: the review accessory line
(`App/MealReviewView.swift:582-585`), the calibration banner card
(`App/ResultView.swift:753-756`) and the liquid over-estimate flag
(`App/ResultView.swift:764-775`).

**Problem**: ~**2.8:1** for caption-size (small) text, which needs 4.5:1. These cards carry the
functional accuracy signals (uncalibrated, liquid over-estimate) that CLAUDE.md explicitly keeps —
so their copy is load-bearing and currently the hardest text on the screen to read.

**Recommendation**: Switch the card foreground to black (`Color.placeholderFG` or
`Color.captureBackground`) — the same pairing the yellow placeholder chip already uses
(`App/ResultView.swift:728-735`, black on `systemYellow`), so the "honesty surfaces" family becomes
visually and mechanically consistent: dark text on a warm fill.

**Impact**: The estimate-accuracy warnings become readable at caption size; no copy, height or
layout changes, so meal-review Req 6.6 is untouched (the accessory line is below the divider
anyway).

**Implementation Notes**: One `foregroundStyle` change per site
(`App/MealReviewView.swift:582`, `App/ResultView.swift:753`, `App/ResultView.swift:772`). The
chevron and SF Symbols on the cards inherit the same style and stay paired with text.

## High Priority Improvements

### Issue: VoiceOver reads dose lines as letters, not quantities

**Current State**: `MealTotalSecondLine.spokenLabel` (`App/DoseReadoutLine.swift:104-107`) speaks
"…12 units at 5 g/U." — the ratio is passed through as the visual `ratioLabel`. The history
readout `RecordedSuggestion.line` (`App/MealReadouts.swift:96-105`) is rendered as a plain `Text`
with no spoken override at `App/ResultView.swift:443-448`, `App/MealOverviewView.swift:113-121`,
so VoiceOver reads "suggested 12 U · 5 g/U · given 12 U" literally. The carb-entry segment
(`App/CarbEntrySheet.swift:87-99`) likewise exposes " · 12 U" raw.

**Problem**: VoiceOver pronounces "U" as the letter ("twelve you") and "g/U" as "g slash u". The
review surface got a spoken-label clause precisely because design-direction §2.6 says "VoiceOver
has no adjacency to read the relationship from" — but the clause itself is half-unintelligible, and
the other three dose surfaces got no clause at all.

**Recommendation**: Add one shared spoken formatter beside the visual ones in `DoseReadout`
(`App/DoseSuggestionModel.swift:48-79`) — e.g. `spokenUnits` → "12 units", `spokenRatio` → "5 grams
per unit" — and use it in `spokenLabel`, plus `.accessibilityLabel` on the two history `Text`s
("suggested 12 units, 5 grams per unit, given 12 units") and on the carb-entry segment ("12
units"). Naming a number in a spoken label is labelling, not counsel (design-direction §2.6), so
the copy rule is intact.

**Impact**: Every dose readout becomes intelligible to VoiceOver users; the register system's
"structural, not editorial" distinction finally survives the spoken modality.

**Implementation Notes**: Keep the visual strings byte-identical — only accessibility labels
change. The middle dot in a spoken string should become a comma pause.

### Issue: Accent-filled buttons that write nothing undermine the accent register

**Current State**: `MealOverviewView.actionRow` fills `Full result` — a navigation push — with
`medataAccent` (`App/MealOverviewView.swift:157-168`). `ResultView.actionRow` fills `Done` — a
pop — with `medataAccent` (`App/ResultView.swift:789-800`), and while an adjustment is pending the
accent `Log N g` pill (`App/ResultView.swift:581-594`) is on screen *simultaneously* with accent
`Done`.

**Problem**: The entire no-disclaimer dose design rests on one structural claim, stated in
`App/DoseReadoutLine.swift:8-10` and design-direction §1: "on these screens the accent colour
already means 'this button writes a row', so a number that is not accent-coloured visibly cannot be
an instruction." `Full result` and `Done` write no row, and the pending-adjustment state shows two
accent controls on one screen — against MASTER.md's "Single primary CTA per screen" and "One accent
colour per screen" checklist items. `ResultView`'s own comment concedes the rule
(`App/ResultView.swift:498`: "the accent stays reserved for the log pill").

**Recommendation**: On ResultView, demote `Done` to the neutral chrome treatment the adjacent `⋯`
button uses (`captureChromeBG` fill, white text) — or at minimum demote it only while
`adjustmentPending` is true, so `Log N g` is the sole accent. On MealOverviewView, restyle
`Full result` as a stroked or elevated neutral button; it is the screen's primary *navigation*, not
its primary *commitment*.

**Impact**: The accent again reliably means "writes a row" everywhere the dose suggestion appears,
which is the mechanism keeping the suggestion legible as not-a-command; the Records → overview →
result chain stops presenting two different meanings of the same colour two taps apart.

**Implementation Notes**: Cosmetic only — no behaviour change. If a fully neutral `Done` feels too
quiet on device, this is a good candidate for the repo's two-attempt tag convention
(`result-done-attempt-N`).

### Issue: MealTotalSecondLine's shed order contradicts its own documented rule

**Current State**: The comment at `App/DoseReadoutLine.swift:68-72` states "the ratio is the FIRST
thing dropped when the line tightens, so at any width where it does not fit the line is
byte-identical to design.md's `≈ 214 g on plate · 12 U`". The actual `ViewThatFits` candidates
(`App/DoseReadoutLine.swift:120-127`) are: full + ratio, `≈ N g` + dose + ratio, `N g` + dose +
ratio, full + dose, `≈ N g` + dose, `N g` + dose, dose only.

**Problem**: Candidates 2 and 3 shed the words "on plate" and "≈" while *keeping* the ratio, so at
those widths the line is `≈ 214 g · 12 U · 5 g/U` — neither byte-identical to a design.md form nor
consistent with "ratio drops first". design-direction §2.3's order ("shed in this order, so the
line loses language before it loses information: 1. `on plate` … 3. the mass segment entirely")
was written for the ratio-less line; §10 explicitly left the ratio branch to "decide once, on
device". The code took the data-forward branch but its fallback ladder doesn't match either the
comment or an extended §2.3.

**Recommendation**: Decide the shed order and make code and comment agree. If the ratio is "the
least certain number" that should go first (the comment's claim), the ladder is: full + ratio,
full + dose, `≈ N g` + dose, `N g` + dose, dose — i.e. delete candidates 2 and 3. If words should
still shed before any number (§2.3's principle), rewrite the comment and add the missing
`≈ N g on plate · 12 U · ratio` intermediate reasoning to design-direction §10 when the on-device
decision lands.

**Impact**: The tightest line in the app degrades predictably at large Dynamic Type sizes, and the
next person reading the file isn't misled about what ships.

**Implementation Notes**: Removing two `line(...)` candidates is the whole code change for option
one. Either way this is a design-direction §10 follow-up: the open question is now half-answered in
code and should be closed in the spec.

## Medium Priority Enhancements

### Issue: LogSheet mode menu — small hit target and single subtle affordance

**Current State**: The sheet's title is a `Menu` labelled by the mode name plus a `caption2`
chevron (`App/LogSheet.swift:137-159`), placed as the `.principal` toolbar item. The
`contentShape(Rectangle())` covers only the HStack's natural bounds — one `headline` line, roughly
22pt tall.

**Problem**: The one affordance for mode-switching is a very small chevron, and the tappable area
is well under the 44pt HIG minimum (MASTER.md asks ≥48pt). The pattern itself is sound — every
entry point pre-selects its mode, so the menu is "a way out of a wrong turn" — but a wrong turn is
exactly when a user is least primed to discover a novel control, and a fumbled tap on a small
target compounds it.

**Recommendation**: Give the label `.frame(minHeight: 44)` (and a little horizontal padding)
inside the `contentShape` so the whole title band is tappable. Consider nudging the chevron to
`caption.weight(.semibold)` — still quiet, slightly more visible against the drag indicator above
it.

**Impact**: The only recovery control on the consolidated sheet becomes reliably hittable; zero
change to the two-tap happy paths.

**Implementation Notes**: `App/LogSheet.swift:147-155`. The `accessibilityLabel("Entry mode, …")`
is good; the `Menu` supplies the popup trait itself.

### Issue: Carbs-mode asymmetry — "Save as quick-add" both hides in one mode and hides a side effect

**Current State**: Only the carbs mode carries a second, non-committing action
(`App/CarbEntrySheet.swift:125-143`); tapping it *first commits the carb entry save*
(`model.save()` at line 128) and then opens the preset sheet, whose dismissal always closes the
entry sheet (`App/CarbEntrySheet.swift:66`).

**Problem**: The label "Save as quick-add" doesn't say the entry is logged too. A user who typed
62 g intending only to create a reusable preset has silently written an intake row; cancelling the
name sheet rolls back nothing (by design — the code comment at lines 25-29 is honest about it).
That is a "visibility of system status" gap: the row lands with no signal distinguishable from the
preset save. This behaviour is specified (`specs/data/manual-carb-intake` Req 4.4: "commits the
entry save first, then prompts for a preset name"), so **this is flagged as worth a spec
amendment**, not as an implementation error.

**Recommendation**: Amend Req 4.4 so the secondary action reads "Log & save quick-add" (names both
writes, same grammar as `Save 62 g` naming its value — labelling, not disclaimer), or decouple
preset creation from logging. The label fix is the cheaper amendment and keeps the one-save-path
model.

**Impact**: The commit-labelling principle from `App/EntryChrome.swift:32-34` ("Its label always
names the value it is about to write, which is why no confirmation surface exists") extends to the
one button that currently writes more than it names.

**Implementation Notes**: String-only change if the amendment is accepted; `saveLabel`'s
value-naming precedent (`App/CarbEntrySheet.swift:118-121`) shows the pattern.

### Issue: Serving-row step buttons and fraction stops are mute or small for assistive users

**Current State**: `ServingStepButton` (`App/ServingRows.swift:180-198`) has an
`accessibilityIdentifier` but no `accessibilityLabel` — VoiceOver announces the bare SF Symbol
name. `PlateFractionButton` (`App/ServingRows.swift:204-234`) never exposes selection state, unlike
its sibling `EntryChip` which sets `.isSelected` (`App/EntryChrome.swift:87`). ResultView's
fraction stops are 30×26pt (`App/ResultView.swift:501-521`); review's are 44×34
(`App/MealReviewView.swift:456-468`).

**Problem**: A VoiceOver user stepping a food row hears "minus, button" with no object; a fraction
stop gives no feedback about which stop is active; and the result-surface stops are half the HIG
44pt minimum in both axes. shared-meal-components Req 1.4 converged the *step* buttons on 44pt but
left the fraction stops divergent and small on one surface.

**Recommendation**: Add `accessibilityLabel("Decrease amount")` / `("Increase amount")` to
`ServingStepButton` (the row container already names the food); add
`.accessibilityAddTraits(isActive ? [.isSelected] : [])` to `PlateFractionButton`; give the result
fraction stops a 44pt hit area via padding/`contentShape` inside the label while keeping the 26pt
visual (MASTER.md's own `hitSlop` guidance).

**Impact**: The adjustment surfaces — the core interaction on both meal screens — become fully
legible to VoiceOver and reliably hittable, with no visual change above or below any fold.

**Implementation Notes**: All three changes live in `App/ServingRows.swift`, so both consuming
surfaces inherit them at once — the whole point of the extraction.

### Issue: Carb-entry dose segment ignores Reduce Motion

**Current State**: The suggestion segment on the carb sheet applies
`.contentTransition(.numericText())` and `.animation(.smooth, value: readout)` unconditionally
(`App/CarbEntrySheet.swift:95-96`).

**Problem**: design-direction §2.4 requires the motion "gated on `accessibilityReduceMotion`, with
the ternary written the same way as the four existing sites in the file". `MiddleDotLine` does this
(`App/DoseReadoutLine.swift:46-47`); the carb sheet's hand-rolled segment does not — the one
deviation of its kind on the changed surfaces.

**Recommendation**: Add `@Environment(\.accessibilityReduceMotion)` to `CarbEntryContent` and write
the two modifiers with the standard ternary.

**Impact**: Motion-sensitive users get the same respect on the manual path as on the capture path;
spec conformance.

**Implementation Notes**: Two-line change. Alternatively render the segment *via* `MiddleDotLine`
with grouped-palette colours — one grammar implementation instead of two (the concatenated-`Text`
construction here is exactly what `App/DoseReadoutLine.swift:16-19` argues against).

### Issue: Records row grammar drifts from the page it was written down in

**Current State**: `design-system/pages/records.md` (added in `c43b5ca`, whose commit message is
"the written design system says what the app now does") specifies the meal value line as
"`47 g carbs · ≈ 214 g`" and the intake row as "Display value + type label (manual / quick add)".
The code renders the meal line as two texts with plain 6pt spacing and no middle dot
(`App/RecordsView.swift:253-261`), and the intake type label is the constant `"Carbs"`
(`App/MealRouting.swift:131-136`).

**Problem**: The commit that claims doc/code convergence shipped two divergences. The missing
middle dot is the same grammar every other multi-segment readout uses (overview per-class rows,
`App/MealOverviewView.swift:141`, do use `·`), so the timeline's meal row is the odd one out. The
intake label "Carbs" also duplicates the `carrot` glyph's meaning while the doc's "Quick add /
manual" would carry provenance the row currently drops.

**Recommendation**: Decide per element and align: add `Text(" · ")` (or a joined string) to the
meal row to match the documented grammar, and either render the doc's provenance label or amend
records.md to say `Carbs`. Given `IntakeEntry` knows whether a preset produced it, the provenance
label is the more informative choice and costs no height.

**Impact**: The design-system pages stay trustworthy as the single written source for these
surfaces — the stated purpose of the c43b5ca commit.

**Implementation Notes**: Meal row: `App/RecordsView.swift:254-260`. Intake label:
`App/MealRouting.swift:135` (`typeLabel`); the comment there explains why it is a constant today,
so this is a deliberate decision to revisit, not an accident.

### Issue: Insulin and activity modes have no scroll fallback at accessibility type sizes

**Current State**: `LogSheet` gives only the carbs mode a `ScrollView`
(`App/LogSheet.swift:109-131`, `App/CarbEntrySheet.swift:33`); insulin and activity are
"fixed-height compositions" inside a `.medium` detent (`App/LogSheet.swift:102`).

**Problem**: At AX Dynamic Type sizes the 56-72pt numerals, kind chips (which wrap to more lines
as text grows — `ChipFlow` at `App/EntryChrome.swift:99`), date row and save button can exceed the
medium detent's height with no way to reach the save button. MASTER.md's checklist requires
"Dynamic Type respected up to AX5".

**Recommendation**: Wrap all three modes' content in one `ScrollView` at the `LogSheet.content`
level (and remove the carbs-local one), or add `.presentationDetents([.medium, .large])` so the
user can pull the sheet up when content overflows.

**Impact**: The commit button — the whole point of the sheet — stays reachable at every type size;
as a bonus the carbs-mode asymmetry the code comments call "the first honest seam"
(`App/LogSheet.swift:106-110`) narrows.

**Implementation Notes**: Verify on device that the insulin stepper's drag gestures still feel
right inside a scroll container before committing to the ScrollView route.

### Issue: Capture-born preset names inherit database comma descriptors

**Current State**: `quickPresetDraft` (`App/MealRouting.swift:161-183`) joins the first two
prettified class names with " + " and appends " +N": with real CoFID-style display names this
yields drafts like "Pasta, cooked + Potato, boiled +1".

**Problem**: The generated name mixes two levels of punctuation (comma-as-descriptor and
plus-as-join), reads as four items instead of three, and spends the quick-add grid's limited label
width on cooking-state descriptors that don't help re-recognition. The name is editable, but the
default is the value most users will keep.

**Recommendation**: Trim each food name at its first comma before joining
(`"Pasta, cooked"` → `"Pasta"`), producing "Pasta + Potato +1". Keep the full names in the sheet
only if the user types them.

**Impact**: Cleaner defaults on the quick-add grid where the preset is consumed
(`App/IntakeView.swift` preset buttons), less editing friction in the name sheet.

**Implementation Notes**: One `prefix(while:)`/`split` in `quickPresetDraft`; both surfaces
inherit it since the builder is shared (that was Req 8's point). The empty-name path
(no foods → `""` → Save disabled by `QuickPresetEditSheet.canSave`,
`App/QuickPresetEditSheet.swift:55-57`) is correct as designed.

## Low Priority Suggestions

### Issue: Menu-buried "Save as quick-add" has no discovery scent — spec-conformant, noted only

**Current State**: The action lives in the `⋯` menu on both surfaces
(`App/MealReviewView.swift:151-164`, `App/ResultView.swift:806-817`), exactly as
`specs/data/manual-carb-intake` tasks 16/17 specify ("One non-destructive Button in the existing
ToolbarItem… Menu, above Retake and Delete").

**Problem**: An ellipsis menu whose other occupants are destructive (Retake/Delete) is where users
least expect a constructive shortcut, so Req 8's feature will mostly be found by accident.

**Recommendation**: **No change now** — the placement is specified and correct for a
developer-phase feature that must not add chrome to the capture path. This is explicitly *not*
flagged as worth a spec amendment at this time; if on-device use shows the feature going unused,
the amendment to consider is surfacing it once as a post-`Record` affordance, never a new button
above the review fold (Req 6.6).

**Impact**: Documented trade-off, revisit with usage evidence.

**Implementation Notes**: None.

### Issue: Token hygiene stragglers under the forced dark theme

**Current State**: `App/GlucoseImportView.swift:88` uses `.foregroundStyle(.orange)` inline;
`App/LidarForkSheetView.swift:95` uses `Color.black` for badge text on `medataAccent`;
`App/Colors.swift:64-65` still says `seriesActivity` is "Also the selected-chip fill on the
activity entry sheet" but the activity chips use the shared `EntryChip` with a `textPrimary` fill
(`App/EntryChrome.swift:80`, `App/ActivitySheet.swift:55`); `App/RecordsView.swift:294-295` says
glucose rows have "no delete" though records-deletion made them deletable (the code right above it
says so).

**Problem**: All render correctly today, but the inline colours bypass the token file the
`ColourTokenUsageTests` comment (`App/Colors.swift:4-6`) claims is guarded, and the stale comments
misdirect the next reader — exactly what c43b5ca set out to eliminate.

**Recommendation**: `.orange` → `Color.seriesGlucose`; `Color.black` → `Color.captureBackground`;
delete the stale sentence in Colors.swift; update the GlucoseRecordRow comment.

**Impact**: Documentation and single-source-of-truth hygiene; zero visual change.

**Implementation Notes**: Four one-line edits.

### Issue: Fixed dimensions that ignore Dynamic Type

**Current State**: The 56pt carb keypad numeral (`App/CarbEntrySheet.swift:232`), the 52pt-wide
gram field (`App/ServingRows.swift:147`), and the 120pt-wide very-low buttons
(`App/MealReviewView.swift:492,501`) are all fixed.

**Problem**: Fixed `.system(size:)` fonts don't scale, and fixed frames clip scaled content — a
4-digit gram value at large type sizes can overflow 52pt; "Keep as-is" can truncate at 120pt. The
hero numeral already has a clamp precedent (`ResultViewLayout.displayPoints`,
`App/ResultView.swift:166-183`).

**Recommendation**: Use `minWidth:`/`minHeight:` instead of fixed frames for the buttons and gram
field; consider a small clamp table for the 56pt field mirroring `ResultViewLayout`.

**Impact**: Graceful behaviour at accessibility type sizes on the entry and review paths.

**Implementation Notes**: Low-risk; verify the review fold (Req 6.6) is unaffected — the very-low
surface already legitimately owns the fold when shown.

### Issue: Preset sheet opened with an empty name gives no cue why Save is dead

**Current State**: A capture-born draft with no food names, or the blank create path
(`App/IntakeView.swift:96`), opens `QuickPresetEditSheet` with an empty name and a disabled
`Save preset` (`App/QuickPresetEditSheet.swift:55-57,110-119`); nothing focuses the name field.

**Problem**: The name-required rule is enforced silently. Validation copy is rightly off the table
(developer-phase rule; design-direction §5: "A rejected entry reverts on commit and shows
nothing"), which makes *focus* the only legitimate cue available — and it isn't used.

**Recommendation**: Auto-focus the name field via `@FocusState` when `isNew && name.isEmpty` on
appear, so the keyboard itself says what's missing.

**Impact**: The empty-name flow self-explains without a word of copy.

**Implementation Notes**: `App/QuickPresetEditSheet.swift:83-90`; standard
`.focused($nameFocused)` + `.onAppear`/`.defaultFocus`.

## Positive Observations

- **The dose readout is the design-direction, faithfully.** The derived register (same font,
  colour, size as the mass segment — `App/DoseReadoutLine.swift:44-47`), the semibold-not-colour
  emphasis, the `U+00B7` separator as a `Text` run at 0.45 opacity, the no-verbs grammar
  (`DoseReadout.unitsLabel`, `App/DoseSuggestionModel.swift:54`), and the absence-is-absence rule
  (`App/DoseReadoutLine.swift:135-144` renders today's exact line when no readout exists) all match
  §1, §2.2 and §2.5. Nothing from the §8 forbidden list appears anywhere on the changed surfaces:
  no orange card, no accent, no second primary control, no icon beside the dose figure.
- **Req 6.6 is genuinely honoured**: the suggestion adds zero height above the review fold — it is
  seven-plus characters appended to an existing line (`App/MealReviewView.swift:407-410`), and the
  `ViewThatFits` ladder guarantees the line never wraps.
- **The rationale comments are exemplary.** `App/DoseReadoutLine.swift:13-19` explains *why* the
  HStack-of-runs construction exists (per-run `numericText` + per-run opacity are mutually
  exclusive with the alternatives); `App/LogSheet.swift:106-110` names its own weakest seam.
- **The shared-component extraction did its job**: serving rows, readouts, formatters and the
  timeline row are each written once with parameterised accessibility prefixes preserving both
  surfaces' identifiers byte-for-byte (`App/ServingRows.swift:7-12`), and the 44pt step-button hit
  target converged upward, not downward (Req 1.4).
- **The forced dark theme was done at the right layer**: `MeData/Info.plist:62-63` with semantic
  tokens kept adaptive (`App/Colors.swift:20-27`) means no sheet or UIKit-hosted surface can miss a
  root modifier, and a future light theme is a one-line revert.
- **Reduce Motion gating is near-universal** on the changed surfaces (`MiddleDotLine`,
  `CarbAmountText`, serving rows, review animations) — the one gap is filed above.
- **The review photo's VoiceOver shadow layer** (`App/MealReviewView.swift:323-339`) gives each
  detected food a contour-shaped accessibility element with a button trait — considerably better
  than bounding-box hit areas.
- **DisplayMeal folding corrections into an `Equatable` row struct**
  (`App/MealRouting.swift:186-207`) is a correct, documented fix for the SwiftUI diffing trap where
  a value-identical refetch would never invalidate the row.

## Disposition (2026-08-25, same session)

Applied in code, verified by `make build-app` + `make spell`:

- **Confidence pill contrast** — dark-on-fill for High/Moderate/Low, white kept
  only on Very Low's grey (`App/ConfidencePill.swift`).
- **Orange banner cards** — captions now `captureBackground` on the
  `confidenceModerate` fill at all three sites (review accessory line,
  calibration banner, liquid flag).
- **VoiceOver dose quantities** — `DoseReadout.spokenUnits`/`spokenRatio` and
  `RecordedSuggestion.spokenLine` feed accessibility labels on the review
  line, both history readouts, and the carb-entry segment.
- **Shed order** — `MealTotalSecondLine`'s `ViewThatFits` candidates reordered
  so the ratio genuinely sheds first; the comment and code now agree with
  design-direction §2.3/§10.
- **LogSheet mode menu** — 44 pt minimum tappable frame behind the compact title.
- **Serving rows** — step buttons gain spoken labels; fraction stops carry
  `.isSelected`.
- **Carb-entry dose segment** — Reduce Motion gating per design-direction §2.4.

Deferred to the on-device pass or a spec amendment, deliberately:

- **Accent register on `Done` / `Full result`** — changing shipped
  design-handoff-00 controls is a design decision for the device sitting, not
  a drive-by; the finding stands.
- **ResultView fraction-stop size, AX-size scroll fallback, Dynamic Type fixed
  dimensions** — layout changes to judge on the phone.
- **"Log & save quick-add" relabel, preset-name comma trimming, records.md
  grammar drift, empty-name cue** — copy/spec-amendment candidates for the
  manual-carb-intake device checklist (task 18).
