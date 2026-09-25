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
  - Scope is the iOS app on research: App/ and MeData/MeDataWidgets/ — 418 rows. This bullet used to say the SvelteKit screens on main were "preserved by capture, not as live rows"; the file contradicts that by 101 rows. The web-v0 half is catalogued too, and task 37 carries it
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

- [x] 12. FLAG: EXPIRING — capture the SvelteKit screens on main as archive/web-v0/ before research merges to main
  - Captured 2026-09-25 from `origin/main` (adc3b56, committed 2026-03-18) and committed at design-system/archive/web-v0/: 97 PNG and 97 static HTML across 28 surface directories, plus `_assets/` — 202 files
  - 402x874 CSS px at deviceScaleFactor 3, i.e. 1206x2622 device pixels: the frame an iPhone 16 Pro screenshot produces, so a distance measured in the archive and divided by 3 is the value to write in Swift
  - HTML beside every PNG, because a PNG records what a screen looked like and cannot be measured, and a hex value cannot be recovered from one. Scripts stripped and same-origin images inlined as data URIs, so each opens by double-clicking with no server and no requests
  - No Azure credentials were needed. The app's API calls were intercepted in the browser and fulfilled from fixtures before the request left, and anything unstubbed was failed with a 500 so a missing fixture shows as an error state rather than silently reaching a real service. The clock was frozen at 2026-03-18T12:10:00Z
  - The Node toolchain lived in a /tmp `git archive` extract of main and went with it: no Node, no node_modules, no build step reaches research. Four of the 28 surfaces are routes; the other 24 are components no URL reaches, rendered through a throwaway harness that went the same way
  - Also archived under `_assets/`, because a screenshot cannot recover a hex value: app.css — whose `@theme` block carries `--color-brand-accent: #63ff00`, `--color-brand-background: #064e3b` and `--color-primary-background: #0a0a0a`, and #064e3b exists nowhere else in the repo — plus icon.svg, manifest.json and four favicon files (favicon.ico and three .svg variants, two of them unreferenced alternates on main)
  - 4 of the 101 rows are not captured because they cannot render on main: in each case a flag exists in the script block and never reaches the template. design-system/archive/README.md names each one with its file:line and records it as unrenderable rather than pending, because a pending row implies a frame somebody still owes
  - Two things the frames are not evidence about, written into the README rather than left to be assumed: they were rendered in Chromium, not in Safari on a real iPhone, which is where the web app actually ran; and a component photographed on its own is photographed without AppShell
  - Requirements: [3.2](requirements.md#3.2), [1.11](requirements.md#1.11), [3.4](requirements.md#3.4)

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

- [x] 21. Confirm the token pipeline adds no SwiftPM target and changes nothing make build compiles
  - `make build` completes in 1.95 s on this worktree, and `git diff origin/research...HEAD -- App/ MedataCore/ MeData/` is empty. This spec changes no Swift, which is the claim the task exists to check
  - A shared Tokens target was proven not to build: Makefile `build:` is `swift build` on the macOS host, Package.swift declares .macOS(.v14), and 12 of the 22 tokens use Color(uiColor:), which does not exist on macOS
  - The `make test` half is split out as task 43 rather than quietly dropped. CLAUDE.md asks for both totals — XCTest and swift-testing — and there is no suite to read them from: MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift:7228 and :14336 fail to compile with "unable to type-check this expression in reasonable time". Ticking this box on a suite that never ran is the defect task 35 had
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

- [ ] 35. Run make spell over the new documents and strings
  - Reopened. It was ticked on a run that cannot have read the prose: tools/check_spelling.sh scans `*.swift` under MedataCore/Sources, HarnessCore, HarnessCLI and App, plus `App/*.xcstrings`. No `.md` file is in SCAN_TARGETS, so the spec folder, design-system/surfaces.md, the READMEs, the generated tokens.css header and the wireframe comments were never read by it
  - `make spell` does report clean, and that reading is true of everything it scans. The bullet claiming it covered those documents was not
  - UK spelling throughout — colour, behaviour, organise, recognise, catalogue. CLAUDE.md: "Always run make spell before committing docs or strings"
  - Closes when task 42 gives the target that reach and a run over the prose comes back clean
  - Blocked-by: d18pyxa (Extend make spell's reach to the prose, or stop claiming it covers it)

- [ ] 36. Move the composition table into the owning spec's decision_log.md when the implementation lands
  - The option files are disposable; this record is not. In a year the question is why the total row looks like that, and the answer is in the reasons column
  - Write it as an Enhanced Nygard entry in specs/data/insulin-dosing/decision_log.md, where the alternatives considered are the zones not taken — a rare case of that field writing itself
  - Then the chosen render goes to design-system/archive/ios-v0/meal-review-dose-suggestion.png, the catalogue row for meal-review/dose-suggestion flips to shipped, and design-system/wireframes/insulin-dose/ is deleted, composition.md included
  - Blocked-by: d18pyx7 (Run the loop for real on the insulin-dosing decision)
  - Requirements: [8.9](requirements.md#8.9), [4.5](requirements.md#4.5), [4.9](requirements.md#4.9)

## Phase 7 — The research pass, applied

- [x] 37. Catalogue the SvelteKit web-v0 half — 101 rows, 28 surfaces, and the successor mapping
  - Phase 1 work the ledger never carried. design-system/surfaces.md lines 766–1021 hold 101 `web/` state rows across 28 surfaces over 22 files of `main:src/**` — 4 route files, 1 layout, 1 document template and 16 components — every row at `status: web-v0`, under a section with its own Coverage block and its own freeze rule: "Nothing here is ratcheted, and no number moves unless the freeze is corrected against `main`"
  - The Successor mapping subsection carries one entry per web surface, 28 of them, 8 of which have no iOS successor at all. That mapping is what decides which dropped capability gets taken back into iOS, so an over-claim in it mis-prices a future feature, and a citation in it that resolves to nothing is invisible: `grep web tools/check_surfaces.sh` returns nothing, so the web half is validated by nothing at all (task 41)
  - Task 1's bullet said the SvelteKit screens were "preserved by capture, not as live rows". 101 rows say otherwise. The bullet is corrected rather than the rows removed: a frozen row and a live row differ by `status`, not by existing
  - Requirement 1.11 still reads the way that bullet did — a web row "only where that surface is being taken forward as a design input". Widening it to authorise the 101 rows that exist is the requirements document's edit, not this task's
  - Requirements: [1.11](requirements.md#1.11), [1.12](requirements.md#1.12), [3.2](requirements.md#3.2)

- [x] 38. make wireshot — render an option to a PNG without a device build
  - tools/wireshot.sh, 104 lines of bash written for system bash 3.2.57, driving Google Chrome `--headless --window-size --force-device-scale-factor=3 --screenshot`. No Node, no npm, and Chrome is checked for before it runs
  - `make wireshot SURFACE=insulin-dose [ATTEMPT=2] [OUT_DIR=tmp/wireshot]` renders every attempt-*.html for a surface, or one of them
  - The window is sized to the page; the `.device` inside it stays at 402x874 CSS px, which at scale 3 is 1206x2622 device pixels — the frame an iPhone 16 Pro screenshot produces. A distance measured on the device frame and divided by 3 is the value to write in Swift
  - The gap it closes: moving option-making from Swift to HTML made options roughly four times cheaper to write and did nothing to make them cheaper to look at, while "costly to compare" is one of the three costs this spec exists to remove. Nothing in the spec previously gave the *author* of an option any way to see it
  - It does not move the gate and does not judge. A PNG from headless Chrome says nothing about Dynamic Type, safe-area insets or ViewThatFits ([L4](requirements.md#L4)); it says the layout and the hierarchy are what you meant
  - Requirements: [4.10](requirements.md#4.10), [4.2](requirements.md#4.2)

- [x] 39. The token generator refuses a `static let` it cannot parse
  - tools/design_tokens/tokens_to_css.py counts the `static let` declarations it saw against the tokens it parsed, and raises naming the missed names when the two differ
  - The failure that closes: a declaration wrapped across two lines previously produced no token, no error and exit 0 — the one failure mode giving a wrong-but-green run, in a generator whose whole justification is that it cannot drift
  - Silence was the bug, and the fix is the rule the catalogue check already follows: an unparsed form names itself, the way an unexplained declared type is treated as a missing row
  - Requirements: [5.3](requirements.md#5.3), [5.1](requirements.md#5.1)

- [x] 40. make surfaces also runs the token --check
  - The `surfaces:` target now runs `bash tools/check_surfaces.sh` and then `python3 tools/design_tokens/tokens_to_css.py --check`. design.md advertised the flag and nothing outside specs/ called it
  - A tokens.css stale against App/Colors.swift now fails the same target that catches a missing catalogue row. One command answers one question: is the design system still true of the code
  - --check writes nothing and exits non-zero, so the target reports drift rather than quietly repairing it
  - Requirements: [5.4](requirements.md#5.4), [7.1](requirements.md#7.1)

- [ ] 41. Strengthen tools/check_surfaces.sh so more than 61 of 418 rows are load-bearing
  - The measured hole: the ratchet counts *structs*, and tools/surfaces_baseline.txt holds only `covered_min=61`. Deleting all 7 dose-notification/* rows, or 29 of the 30 meal-review/* rows, leaves the run green at `covered=61 total=61 baseline=61`. 357 of the 418 rows are unprotected
  - Accept `struct|enum|class|actor` at the declaration scan (tools/check_surfaces.sh:125 gates on `kind == "struct"`, so the 194-line extension-declared Settings section in App/DoseScheduleSettingsSection.swift:14-79 and its 8 dose-schedule-settings/* rows have no mechanical protection)
  - Extend CONFORMANCES (line 36) with `ViewModifier|App|Scene|WidgetBundle` and the style protocols. `App` and `Scene` are live misses — MedataApp and MeDataWidgetBundle are the two types task 9 had to count by hand; `ViewModifier` is latent, there are none in the tree yet
  - Add `rows_min` to tools/surfaces_baseline.txt beside `covered_min`, so deleting rows fails the check rather than moving a number nobody reads
  - Restrict the coverage match to the `surface` and `file` columns. Check 1 (line 199) matches a name anywhere in a row, so share-sheet/activity-items is deletable purely because `ShareSheet` appears in two other rows' prose
  - Parse the state-enum list from the catalogue's own closed-enum coverage table rather than the STATE_ENUMS shell variable: the variable names 10 enums, the table names 25, so 15 are checked by eye only
  - Add a check that every catalogue id in the successor mapping's `catalogue id` column resolves to a real row id. Nothing validates the web half today, which is how eight broken citations across four surface keys survived
  - Add the zone-pointer check — collect every `data-zone` in design-system/wireframes/**/*.html and every zone named in a composition.md, and fail on a name design-system/surfaces.md does not declare. This contradicts requirement 7.11 and Decision 4, which list "the checker does not read them" as a virtue on the same page as "nothing checks for the dangling reference" as a cost; those are one fact with two signs. The requirement and the decision have to move first, and neither is this task's to move
  - Requirements: [7.2](requirements.md#7.2), [7.4](requirements.md#7.4), [7.5](requirements.md#7.5), [1.3](requirements.md#1.3)

- [ ] 42. Extend make spell's reach to the prose, or stop claiming it covers it <!-- id:d18pyxa -->
  - tools/check_spelling.sh's SCAN_TARGETS are MedataCore/Sources, HarnessCore, HarnessCLI and App, matched with `--include="*.swift"`, plus `App/*.xcstrings`. No `.md` file is scanned by any target
  - CLAUDE.md says "Always run `make spell` before committing docs or strings". For strings that is enforced; for docs it is unenforceable, and this spec is almost entirely docs
  - Either extend SCAN_TARGETS to specs/, design-system/ and docs/ for `*.md`, with the allowance the wireframe and token files need — `color`, `center`, `color-mix`, `theme-color`, `border-color`, `align-items` are CSS identifiers, not American spellings — or rewrite task 35's claim to say the prose was read by eye and say who read it
  - An allowance list that silences a real misspelling is worse than no scan, so whichever way this goes, name the trade in the decision rather than in a commit message
  - Unblocks task 35

- [ ] 43. Report both test totals — split from task 21, and blocked on a MedataCore compile failure
  - CLAUDE.md: "`make test` prints TWO totals — XCTest and swift-testing. Always report both". Neither can be read today: MedataCore/Tests/SupportPlaneTests/SupportPlaneCorpusMeasurementTests.swift:7228 and :14336 fail with "unable to type-check this expression in reasonable time" on multi-segment `print` interpolations, so the suite does not compile
  - Pre-existing, and not this spec's defect to fix: this branch changes no Swift (`git diff origin/research...HEAD -- App/ MedataCore/ MeData/` is empty). It is filed as specs/BACKLOG.md item 32 rather than left to silently block a wireframe task — note that specs/BACKLOG.md is untracked, so that entry lives in the working checkout and not on this branch
  - The fix is to break those two interpolations into separate statements. Closing this task means running `make test` and writing both totals here
  - Requirements: [5.7](requirements.md#5.7)

- [ ] 44. Add a pattern column to design-system/surfaces.md and derive a by-pattern index
  - The one thing an interface inventory buys that a surface x state cut cannot: carb-entry, insulin-dose, activity and preset-edit are four separate sheets, each declaring the same zones and each solving the same save-and-dismiss problem, and the catalogue today gives no way to see that they are one pattern with four instances
  - One column and one derived index, not a new document. The index is generated from the column so it cannot disagree with it
  - The value is in redesign, not in enforcement: when one of those four sheets changes, the pattern index is what says which other three now look wrong, which is exactly the recombination question the three insulin-dosing branches could not answer
  - Five record rows already share one zone list by assertion (task 10). A pattern column makes that a stated fact instead of a coincidence in the prose
  - Requirements: [8.1](requirements.md#8.1), [8.4](requirements.md#8.4), [1.12](requirements.md#1.12)

- [ ] 45. Consider #Preview as a verification mirror — not as the library
  - Decision 2 rejected Xcode previews as the catalogue, and that rejection holds: a preview is not enumerable, not diffable and not readable without Xcode. What it does not settle is the other leg
  - Limit L4 concedes that HTML lies about Dynamic Type, safe-area insets and ViewThatFits, and nothing in the spec currently covers that leg. It is the exact reason a SwiftUI attempt looks wrong on the phone after the wireframe looked right
  - Leaf surfaces needing no mock store first — ChipFlow, MedataLoadingSymbol, the confidence pills, the record rows — because those are the ones where a preview costs a fixture-free block and nothing else
  - The cost is recurring and real: previews across App/ are a maintenance bill design.md deliberately refuses to schedule. Adopting this changes what the wireframes are *for* (option generation only, SwiftUI verification handled elsewhere); declining it leaves L4 open with nothing covering it. Either way it is a decision entry, not a silent drift
  - This is the developer's call, not an agent's: it is the one item here that adds standing work to every future UI change
  - Requirements: [4.1](requirements.md#4.1)
