---
references:
    - specs/ui/wireframe-library/requirements.md
    - specs/ui/wireframe-library/design.md
    - specs/ui/wireframe-library/decision_log.md
    - specs/ui/wireframe-library/prerequisites.md
---
# Wireframe Library

## Phase 1 — The catalogue

- [x] 1. Populate design-system/surfaces.md, one row per surface x state
  - 418 state rows across 67 distinct surfaces, grouped as Shell / Home / Capture / Review / Records / Trends / Entry / Settings / Shared chrome / Notifications / Widgets
  - Row schema per design.md "Row schema": id, surface, file, kind, state, state source, view-model, data, direction, archive, status
  - Seven rows (every dose-notification/*) are keyed on the construction site — App/DoseScheduleModel.swift and App/LocalReminderScheduler.swift — because a local notification has no renderable type
  - Scope is the iOS app on research: App/ and MeData/MeDataWidgets/. The SvelteKit screens on main are preserved by capture, not as live rows
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.7](requirements.md#1.7), [1.8](requirements.md#1.8), [1.11](requirements.md#1.11)

- [x] 2. Record the UI-to-data join in the view-model, data and direction columns
  - data names the MedataCore product and type by name only — "Persistence · DoseOccurrence" — and records the intended binding, never the imports actually present, or the catalogue would ratify today's layering as though it were the design
  - view-model takes the opposite rule and records what is actually there, so a dash reads as a to-do rather than as a claim
  - Documentation join only: no import, no generated binding, no build-time coupling. specs/PROCESS.md prescribes the same mechanism for cross-domain capability, which "references the other domains' specs rather than duplicating them"
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3), [2.4](requirements.md#2.4), [2.5](requirements.md#2.5), [2.6](requirements.md#2.6)

- [x] 3. Write the Exemptions section, a reason beside every exempted type
  - 33 entries covering row data, .sheet(item:) identity wrappers, decoding shims, and metric and formatting helpers
  - Silence is not permitted: the check treats an unexplained declared type as a missing row, so an exemption cannot lose its justification
  - Requirements: [1.9](requirements.md#1.9)

- [x] 4. Catalogue the harness-only surfaces with the harness condition visible
  - app-shell/harness-launch carries state source `UITestSupport.isActive` under `#if DEBUG` beside app-shell/launch
  - Its archive cell is n/a, not pending: a surface reachable only under the UI-test harness cannot be photographed on a normal install (prerequisites.md, "Screenshot capture — ios-v0")
  - Requirements: [1.10](requirements.md#1.10)

- [x] 5. State the catalogue's own coverage figures in a Coverage section
  - Surfaces, state rows, files covered, renderable types with a row, exemptions, rows by status, rows by archive cell, PNGs captured, plus a closed-enum coverage table naming the rows each enum's cases land on
  - The point is that a reader sees what is not covered without running anything
  - Requirements: [1.12](requirements.md#1.12)

- [x] 6. Add rows for the two nested Shapes in App/MedataLoadingSymbol.swift <!-- id:d18pyx0 -->
  - The rows existed; they named the wrong type. symbol-bowl/path, symbol-bar/path and symbol-dot/path said MedataLoadingSymbol.Bowl / .Bar / .Dot, while the declarations are inside enum MedataSymbolGeometry at App/MedataLoadingSymbol.swift:130, :145 and :156
  - Surface cells corrected to the qualified name the check emits, and each state source now names its own path maths rather than the bare namespace
  - Requirements: [1.1](requirements.md#1.1), [7.2](requirements.md#7.2)

- [x] 7. Write MealRoute.overview and MealRoute.result into their rows' state source cells <!-- id:d18pyx1 -->
  - meal-overview/photo-with-mask now reads "pushed by `MealRoute.overview`; artefact decodes" and result/hero-original "pushed by `MealRoute.result`; no correction, no pending adjustment" — both true of App/MealRouting.swift's mealRouteDestination
  - Stage 2 matches on `<Enum>.<case>` in the state source cell, so prose alone was invisible to it
  - This was a catalogue-side defect, not a reason to soften the check
  - Requirements: [1.6](requirements.md#1.6), [7.3](requirements.md#7.3)

- [x] 8. Reconcile the exemption grammar so the written exemptions are read <!-- id:d18pyx2 -->
  - Fixed on the script side, because the catalogue's table form is the readable one: check_surfaces.sh now normalises markers before matching — backticks stripped, the space after the colon dropped, comma lists expanded to one marker per name — and the reason is required in the same row
  - The name boundary excludes `.` so `exempt: ResultView.FoodRow` is not read as a reasonless exemption of ResultView
  - Blanking still happens after normalisation, so `exempt: ChipFlow` cannot excuse itself; both branches were exercised against a fixture catalogue via SURFACES_CATALOGUE
  - exempt=0 is the correct reading, not a miss: none of the 33 entries conforms to a scanned protocol
  - Requirements: [1.9](requirements.md#1.9), [7.2](requirements.md#7.2)

- [x] 9. Verify id uniqueness and reconcile the Coverage figures with what the check prints <!-- id:d18pyx3 -->
  - All 418 ids are unique and match `<surface>/<state>` in kebab-case, checked mechanically over the file
  - "renderable types with a row … 62 of 62" was wrong in both halves: the true figure is 63 of 63 — 61 structs under the six protocols the check scans, plus MedataApp: App and MeDataWidgetBundle: WidgetBundle, which the check does not scan
  - No row describes an intention, so rows at status planned stays 0
  - Requirements: [1.3](requirements.md#1.3), [1.12](requirements.md#1.12), [1.13](requirements.md#1.13)

- [x] 10. Declare the zone vocabulary, once per surface, in design-system/surfaces.md
  - 23 surfaces declare zones, across 19 distinct lists — the five row-* record rows share one. Most surfaces declare none, which is correct: a 76 pt shutter button, a confidence pill, a widget family variant and a notification action have nothing to point at that a state row does not already name
  - Declared as prose under the section heading that owns the surface, not as a twelfth table column: zones are per surface, the table is per surface x state
  - Names are harvested, not invented — MealReviewView's photoSection / totalRow / primaryAction / scaleControl / accessoryLine / foodRow, the "Layout zones" blocks in design-system/pages/meal-review.md and design-system/pages/capture.md, and the order specs/data/insulin-dosing/design-direction.md §2 fixes: "photo (40%) / totalRow / primaryAction / scale control / 1px divider / scrolling rows"
  - The canonical list is meal-review — `photo` · `total-row` · `primary-action` · `scale-control` · `accessory-line` · `food-rows` — and it is the list every option under design-system/wireframes/insulin-dose/ marks with data-zone
  - The web-v0 half declares none: zones exist so options can be pointed at, and no options are being generated for a frozen app
  - Zones generate no code and tools/check_surfaces.sh does not read them
  - Requirements: [8.1](requirements.md#8.1), [8.2](requirements.md#8.2), [8.4](requirements.md#8.4), [8.10](requirements.md#8.10)

## Phase 2 — The frozen archive

- [ ] 11. Freeze the 14 prose pages verbatim as design-system/archive/pages-v0/ <!-- id:d18pywy -->
  - Copy design-system/pages/ byte for byte. No edits, no reformatting, no spelling pass
  - Add design-system/archive/README.md stating the two rules: write-once, and superseded only by a new -vN generation, never updated in place
  - N is a generation counter, not a version number — everything stays v0 until main (docs/agent-notes/device-build-and-test.md, "Everything stays v0 until main")
  - The same bytes stop rotting the moment they stop claiming to describe the present
  - Requirements: [3.3](requirements.md#3.3), [3.4](requirements.md#3.4), [3.5](requirements.md#3.5)

- [ ] 12. FLAG: EXPIRING — capture the SvelteKit screens on main as archive/web-v0/ before research merges to main
  - This is the only part of the work with an expiry date. CLAUDE.md: the cycle "currently runs along the 'research' branch, with intent to merge to main when the MVP work is done". Do this first in this phase
  - main is the SvelteKit app at adc3b56, committed 2026-03-18; its package.json asks for @sveltejs/kit ^2.15.0, vite ^6.0.0 and svelte ^5.0.0, resolved in pnpm-lock.yaml to 2.50.2, 6.4.1 and 5.49.2, against node v26.7.0 and pnpm 11.22.0 on this machine, and nothing has verified that the install and dev server still resolve
  - Running it also wants backend configuration: .env.example lists AZURE_COSMOS_CONNECTION_STRING and AZURE_BLOB_STORAGE_URL, and RECOGNITION_MOCK_MODE=true mocks recognition only, not persistence
  - 28 surfaces and 101 state rows across 22 source files by the catalogue's web-v0 half — 4 route files, 1 layout, 1 document template and 16 components — roughly an afternoon. The Svelte source survives in git either way; what expires is the ability to run it and photograph the screens
  - It leaves nothing behind on research — no Node, no node_modules, no build step
  - If the window closes first, record those surfaces as unarchivable rather than leaving pending rows that will never resolve
  - Requirements: [3.2](requirements.md#3.2), [1.11](requirements.md#1.11)

- [ ] 13. Capture the shipped iOS surfaces as archive/ios-v0/<id>.png
  - 378 rows carry `archive: pending` and 40 carry n/a; no PNG exists yet
  - Filename is the catalogue id with the slash flattened — capture/tracking-lost becomes archive/ios-v0/capture-tracking-lost.png — so a screenshot and a row are found by the same key
  - make deploy-device for non-capture UI, make deploy-release-stub for anything in the capture flow: a Debug build cannot arm the shutter. Match the launch buildStamp before trusting a frame (docs/agent-notes/device-build-and-test.md)
  - Frames are taken at the phone and copied off by hand. No scripted capture path exists and none is being built
  - This serves the baseline goal — define the app as it is — and is not claimed to help generate options, because it does not: App/*.swift is already the canonical answer for anything shipped
  - Requirements: [3.1](requirements.md#3.1), [3.4](requirements.md#3.4)

- [ ] 14. Stop maintaining design-system/pages/ as a live reference <!-- id:d18pywz -->
  - Once pages-v0 is frozen, the catalogue and the archive together are the reference for how the app looks and behaves today
  - Say so at the top of design-system/pages/ and in design-system/MASTER.md. Freezing a copy is not deleting the originals
  - The evidence for retiring them: three pages — meals-tab.md, photo-tab.md and data.md — all claim part of what is now App/RecordsView.swift, and are named after two screens (MealsTabView, DataView) that no longer exist in the tree
  - Blocked-by: d18pywy (Freeze the 14 prose pages verbatim as design-system/archive/pages-v0/)
  - Requirements: [3.6](requirements.md#3.6), [3.7](requirements.md#3.7)

## Phase 3 — Tokens and wireframes

- [x] 15. tools/design_tokens/tokens_to_css.py — the one-directional token generator
  - Python 3 stdlib only, run from the repository root, matching tools/food_db/generate.py and tools/segmenter/export.py; must keep working on the stock macOS interpreter (3.9.6 here)
  - Naming is mechanical with no per-token exception: `static let <name>` becomes `--medata-<kebab(name)>`, so medataAccent becomes --medata-medata-accent. An ugly name beats a carve-out every wireframe author has to remember
  - Color(uiColor: .systemX) has no fixed sRGB value, so each is emitted at its documented dark-appearance value and marked approx in a comment beside the property — visible in the output rather than hidden in it
  - --check mode exits non-zero when the on-disk CSS is stale and writes nothing
  - It reads App/Colors.swift and never writes under App/. A diff from this work touching App/ is a defect
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2), [5.3](requirements.md#5.3), [5.4](requirements.md#5.4), [5.5](requirements.md#5.5), [5.8](requirements.md#5.8)

- [x] 16. Commit the generated design-system/tokens.css
  - Output reports `tokens=22 approx=13 alias=3 groups=6`; all 22 static let tokens in App/Colors.swift round-trip
  - That includes the four the hand-copied snippet in design-system/MASTER.md is missing — bandActivity, seriesActivity, seriesInsulinBasal, seriesInsulinBolus
  - The file declares that it is generated, names App/Colors.swift as its source, and names the command that regenerates it
  - Requirements: [5.3](requirements.md#5.3), [5.4](requirements.md#5.4)

- [x] 17. design-system/wireframe.css at true iPhone 16 Pro metrics
  - --device-w: 402px and --device-h: 874px — iPhone 16 Pro logical points at 1pt = 1px, so a value measured in a wireframe is the value written in Swift
  - The MASTER.md spacing scale as --space-1..6 (4/8/16/24/32/48), type roles as variables (--type-total: 44px is MealReviewView's 44pt heavy mono), --control-h: 48px and --radius-control: 12px
  - --status-band and --home-band are labelled in the stylesheet as drawn chrome strips, not a claim about UIKit safe-area insets
  - It makes 40 token references across 16 distinct --medata-* tokens and names no hue App/Colors.swift does not define. What it names outside the tokens is neutrals: the three greys of the furniture drawn around the device (--frame-page, --frame-edge, --frame-note), the striped fill standing in for a photo, and white at various opacities — the app's own OLED chrome convention rather than a token set
  - It must never introduce the MASTER.md anti-patterns — shadows, blur behind chrome, a second accent colour, gradients as control fills
  - Requirements: [4.2](requirements.md#4.2), [4.4](requirements.md#4.4)

- [x] 18. Three options under design-system/wireframes/insulin-dose/, one per insulin-dosing attempt
  - attempt-1.html, attempt-2.html and attempt-3.html — 104, 100 and 160 lines, 364 in total, against the 3,122 inserted lines of Swift the same three options cost as App-layer branches. Attempt 3 is longer because it renders two surfaces to make its argument
  - Each opens with a comment naming its catalogue id, its attempt number and branch, the one thing it is testing, and the zones it marks. Two renderings with no stated difference is a mood board
  - Each marks the six meal-review zones with data-zone, using the names declared in design-system/surfaces.md. Attempt 3's second frame is a different surface with no declared vocabulary yet, so it is deliberately unmarked rather than inventing names
  - Each links ../../tokens.css then ../../wireframe.css and fetches nothing else, so a browser opens them as files with no local server
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3), [4.8](requirements.md#4.8), [8.3](requirements.md#8.3)

- [x] 19. Rewrite design-system/wireframes/README.md for the disposable lifecycle
  - The four steps, ending in deletion: author two or more attempts, decide and record why in the owning spec's decision_log.md, implement, then delete the folder, render the winner into archive/ios-v0/ and flip the catalogue row to shipped
  - Attempt numbering matches the on-device convention — "One tag per attempt: <surface>-attempt-N" (docs/agent-notes/device-build-and-test.md, "Comparing UI attempts on the phone")
  - It states what a wireframe does not settle: decomposition, state models, settings keys, and anything about Dynamic Type, safe areas or ViewThatFits
  - design-handoff-00/ stays where it is as a frozen historical bundle
  - Requirements: [4.5](requirements.md#4.5), [4.6](requirements.md#4.6), [4.7](requirements.md#4.7), [4.9](requirements.md#4.9)

- [ ] 20. Replace MASTER.md's hand-copied Swift token snippet with a pointer to App/Colors.swift
  - The snippet carries 18 static let lines against the 22 in App/Colors.swift — the measured drift this requirement exists to kill
  - Replace it with a pointer to App/Colors.swift as the authority, to design-system/tokens.css as the generated wireframe copy, and to the command that regenerates it
  - After this the design system carries no second hand-maintained copy of the token set
  - Requirements: [5.6](requirements.md#5.6)

- [ ] 21. Confirm the token pipeline adds no SwiftPM target and changes nothing make build or make test compiles
  - Run make build and make test and confirm both totals are unchanged — CLAUDE.md requires reporting both the XCTest and the swift-testing slice
  - A shared Tokens target was proven not to build: Makefile build: is swift build on the macOS host, Package.swift declares .macOS(.v14), and 12 of the 22 tokens use Color(uiColor:), which does not exist on macOS
  - Confirm git diff shows nothing under App/
  - Requirements: [5.7](requirements.md#5.7), [5.2](requirements.md#5.2)

- [x] 22. design-system/wireframes/insulin-dose/compare.html — every option for one surface in one page <!-- id:d18pyx8 -->
  - 538 lines of self-contained HTML that opens by double-clicking. No server, no build step, no framework — this is the artifact that answers the complaint, because before it the options could only be seen one at a time, across a git checkout and a make deploy-device each
  - Whole screens first: all three options in one strip at 402x874, unscaled
  - Per-zone view: one button per declared zone, putting that region of every option beside itself. Each button carries the question that zone decides — for total-row, "Attempt 1 appends one segment to the line that already ships; attempt 2 appends two, carrying the divisor at every meal; attempt 3 appends none"
  - Outline zones (z) draws each data-zone boundary with its name; fit to window (f) scales the strip to 0.72x and is labelled "not true metrics", because a scaled screen is no longer evidence about size
  - It carries its own copy of each option's screen markup, because a file:// page cannot read its siblings. That duplication is unchecked and is the known cost — the folder is deleted whole, so it lives for days
  - Requirements: [8.5](requirements.md#8.5), [8.6](requirements.md#8.6), [4.2](requirements.md#4.2), [4.4](requirements.md#4.4)

- [x] 23. design-system/wireframes/insulin-dose/composition.md — the zone-choice record <!-- id:d18pyx9 -->
  - 89 lines. A six-row table — zone, taken from, reason — over the three real options: photo, primary-action, scale-control and accessory-line from attempt 1, total-row from attempt 2, food-rows from attempt 3
  - That table is the description of what you want to see next: short, unambiguous, and directly buildable as attempt-4.html or as the SwiftUI. A composed option is an ordinary option — it takes the next attempt number and goes back into compare.html and then onto the phone
  - It writes down what the table deliberately cannot say and where each goes instead: a change to the set of surfaces belongs in the surface-delta table, and decomposition (inline versus extracted) belongs in the decision
  - It is a worked example of the record, not a ruling on the insulin-dosing readout. That decision is the developer's
  - Requirements: [8.7](requirements.md#8.7), [8.8](requirements.md#8.8), [8.11](requirements.md#8.11)

## Phase 4 — The check and the Make target

- [x] 24. tools/check_surfaces.sh — four stages over the catalogue and the code
  - Stage 1, fails: every struct in App/ and MeData/MeDataWidgets/ conforming to View, Shape, Layout, UIViewRepresentable, UIViewControllerRepresentable or Widget has a row or an exemption with a reason. The wide conformance list is the point — a `struct .*: View` grep is blind to ChipFlow: Layout, the private component an attempt silently deleted
  - Nested types get a brace-depth qualified name, with comments and string literals blanked first so a brace in prose cannot shift the depth
  - Stage 2, fails: for each named state enum the cases are parsed out of Swift at check time and never hard-coded; cases are collected only at the enum body's own brace depth, and associated-value lists are stripped before splitting on commas
  - Stage 4, report-only: lists App/*View.swift and App/*Sheet.swift importing a MedataCore module, reading the module list off MedataCore/Sources/ at run time so it cannot rot
  - Output is compact key=value lines with no narration; a failure names the struct, enum case or count with its file and line
  - Written for system bash 3.2.57 — no newer shell
  - It reads no zones and checks nothing about them. Nothing about a zone is mechanically checkable, and a check that pretended otherwise would report on a naming convention as though it were a build artifact
  - Requirements: [7.1](requirements.md#7.1), [7.2](requirements.md#7.2), [7.3](requirements.md#7.3), [7.7](requirements.md#7.7), [7.8](requirements.md#7.8), [7.10](requirements.md#7.10), [7.11](requirements.md#7.11)

- [x] 25. Wire make surfaces in the repository Makefile
  - Same shape as make spell to tools/check_spelling.sh; listed in make help
  - Non-zero exit on a failing stage, verified
  - Requirements: [7.1](requirements.md#7.1)

- [x] 26. tools/surfaces_baseline.txt, starting at covered_min=0
  - A struct counts as covered only when one of its rows has status shipped. A row alone is not coverage
  - Starting at 0 keeps the check honest from the first commit rather than aspirational: a green boolean over a table of planned rows would be worse than today's visibly absent file
  - The file carries the comment explaining what the number means and when to raise it
  - Requirements: [7.4](requirements.md#7.4), [7.5](requirements.md#7.5)

- [x] 27. Raise the ratchet once the catalogue gaps close <!-- id:d18pyx4 -->
  - Done after tasks 6–9 closed. The run now reports `structs=61 missing=0 exempt=0`, `enum_cases=30 missing=0`, `covered=61 total=61 baseline=61`, and tools/surfaces_baseline.txt reads covered_min=61
  - Raised only because real rows earned it. Raising a baseline to quiet a red check locks in a lie
  - Blocked-by: d18pyx0 (Add rows for the two nested Shapes in App/MedataLoadingSymbol.swift), d18pyx1 (Write MealRoute.overview and MealRoute.result into their rows' state source cells), d18pyx2 (Reconcile the exemption grammar so the written exemptions are read), d18pyx3 (Verify id uniqueness and reconcile the Coverage figures with what the check prints)
  - Requirements: [7.4](requirements.md#7.4), [7.6](requirements.md#7.6)

- [ ] 28. Confirm the check stays off the commit path and out of the test targets
  - No new test target and no new test scaffolding — CLAUDE.md: "do not add new test scaffolding unless explicitly asked"
  - specs/PROCESS.md puts alignment "at the review gate instead" and structural checks in CI as non-blocking, "not as a commit-blocking hook"
  - Confirm no git hook, no Package.swift target and no Xcode build phase invokes it
  - Requirements: [7.9](requirements.md#7.9)

## Phase 5 — The surface-delta contract

- [ ] 29. Document the surface-delta contract in specs/PROCESS.md <!-- id:d18pyx5 -->
  - A four-column table — surface, change, catalogue id, note — in every UI-touching spec's requirements.md, because it states what must be true of the finished work rather than how it is built
  - change is one of add, modify, delete, consolidate; a dash marks a surface deliberately named as out of scope, which is the row that says "this must survive unchanged"
  - Written before implementation, at the gate specs/PROCESS.md already describes — "Do not start design before requirements are agreed, or code before its plan exists"
  - Where a spec changes no surface the table says so explicitly, so an absent table is always a defect and never a claim
  - Rows cite catalogue ids and quote the state; a spec adding a surface states the id it will take. Never a row number, a table position or a screen title
  - Requirements: [6.1](requirements.md#6.1), [6.2](requirements.md#6.2), [6.3](requirements.md#6.3), [6.7](requirements.md#6.7), [6.8](requirements.md#6.8), [1.4](requirements.md#1.4), [1.5](requirements.md#1.5)

- [ ] 30. Document how an attempt branch is checked against the table
  - The job is composition, not policing. Comparing an attempt's actual surface set against the table is what lets two options be compared and combined at the level of the surface set — "attempt 3's consolidation with attempt 2's readout" is a thing two tables can express together
  - Record every surface an attempt adds, deletes or consolidates that the table does not carry, and every surface the table carries that the attempt omits — attempt 1 building no activity surfaces at all, where attempts 2 and 3 both did, is a real difference between the options and belongs in the comparison
  - Several options for one surface is the expected shape of UI work here and is never a defect. What the record is for is the difference nobody intended, which falls out of writing the proposition down rather than being the reason to write it
  - This is a human step at the review gate. Nothing mechanically forces it, and no hook or CI rule is proposed
  - Requirements: [6.4](requirements.md#6.4), [6.5](requirements.md#6.5), [6.6](requirements.md#6.6)

- [ ] 31. Apply the contract to one live spec — specs/data/insulin-dosing/requirements.md <!-- id:d18pyx6 -->
  - The worked table in design.md is the starting point: meal-review/dose-suggestion modify, activity/entry add, intake/sheet-new-entry modify, insulin-dose/bolus modify, and chip-flow/single-line plus chip-flow/wrapped named out of scope
  - Check it against the three attempt branches and write down what it catches: the absent activity surfaces on insulin-dosing-ui-1-on-research, the unauthorised consolidation into App/LogSheet.swift on attempt 3, and the incidental removal of private struct ChipFlow: Layout from App/TrendsView.swift
  - One live spec, not all of them. The contract earns its place by catching something real once
  - Blocked-by: d18pyx5 (Document the surface-delta contract in specs/PROCESS.md)
  - Requirements: [6.1](requirements.md#6.1), [6.8](requirements.md#6.8)

## Phase 6 — Adoption

- [ ] 32. Rewrite docs/agent-notes/wireframe-intake.md for the new pipeline
  - The note today describes pasted Claude artifacts landing as numbered design-handoff-NN/ bundles that become design-system pages plus requirements. That is the pipeline being replaced
  - The new loop: catalogue id, then a surface-delta table, then two or more HTML attempts under design-system/wireframes/<surface>/, then a decision recorded in the owning spec's decision_log.md, then Swift, then delete the folder, screenshot into archive/ios-v0/ and flip the row to shipped
  - Keep the bulk-folder archive rule for anything that still arrives as a handoff bundle, and keep design-handoff-00/ readable — its MANIFEST.md is cited as evidence in requirements.md
  - Say plainly what the pipeline cannot catch: the manifest attributes its own deviations to "user direction after seeing the implementation", the design changing after the phone showed it
  - Requirements: [4.5](requirements.md#4.5), [4.9](requirements.md#4.9), [3.1](requirements.md#3.1)

- [x] 33. Index the spec in specs/OVERVIEW.md
  - Add the ui/wireframe-library row with its status and its file list, per the index's existing shape
  - The OVERVIEW entry for the design handoff still says "Graph is the launch root" via Decision 20 with the superseding note attached; leave that history intact and let the catalogue carry the current answer, which is App/AppRoot.swift presenting HomeView

- [ ] 34. Run the loop for real on the insulin-dosing decision <!-- id:d18pyx7 -->
  - The first genuine exercise, end to end: surface-delta table first, two or more HTML attempts, look at them, pick one, record why in specs/data/insulin-dosing/decision_log.md — the wireframe that showed it is about to be deleted
  - Then Swift, tagged <surface>-attempt-N only where the remaining question is one HTML cannot answer: decomposition, state models and settings keys are still decided in Swift
  - Then delete design-system/wireframes/insulin-dose/, capture archive/ios-v0/meal-review-dose-suggestion.png, and flip that row to shipped
  - The gate does not move: a person looking at the screen of an iPhone 16 Pro. This work moves the choice earlier, nothing else
  - Blocked-by: d18pyx6 (Apply the contract to one live spec — specs/data/insulin-dosing/requirements.md)
  - Requirements: [4.1](requirements.md#4.1), [4.5](requirements.md#4.5), [4.9](requirements.md#4.9), [6.1](requirements.md#6.1)

- [x] 35. Run make spell over the new documents and strings
  - UK spelling throughout — colour, behaviour, organise, recognise, catalogue. CLAUDE.md: "Always run make spell before committing docs or strings"
  - Covers the spec folder, design-system/surfaces.md, the READMEs, the generated tokens.css header and the wireframe comments

- [ ] 36. Move the composition table into the owning spec's decision_log.md when the implementation lands
  - The option files are disposable; this record is not. In a year the question is why the total row looks like that, and the answer is in the reasons column
  - Write it as an Enhanced Nygard entry in specs/data/insulin-dosing/decision_log.md, where the alternatives considered are the zones not taken — a rare case of that field writing itself
  - Then the chosen render goes to design-system/archive/ios-v0/meal-review-dose-suggestion.png, the catalogue row for meal-review/dose-suggestion flips to shipped, and design-system/wireframes/insulin-dose/ is deleted, composition.md included
  - Blocked-by: d18pyx7 (Run the loop for real on the insulin-dosing decision)
  - Requirements: [8.9](requirements.md#8.9), [4.5](requirements.md#4.5), [4.9](requirements.md#4.9)
