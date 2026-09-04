
The gap was narrower than "no test data." All three attempts show their readout
  from carbohydrates + the seed ratios, and the seed ratios are compiled-in
  defaults — no glucose, no insulin history, no ledger rows are needed for
  anything to appear. The manual path (Intake → carb entry) and the dose sheet
  already work on an empty database. The one surface that only existed after a
  camera capture was the review screen — the very line attempts 1 and 2 disagree
  about — and every capture produced a different number, so the three builds
  could never be compared against the same figure.

  Two DEBUG-only affordances, 113 lines, all in App/, nothing in MedataCore
  (a1618ee):

  - App/SettingsView.swift — "Seed demo meal" beside the existing "Seed demo
  glucose", writing one fixed record (white_rice / chicken / broccoli, 56.0 g
  carbohydrate) through the ordinary save(_:artefacts:) path. 56.0 g is 11 U on
  the breakfast seed ratio and 6 U on the other three, so rounding is visible
  either way. Segmenter source is demo_seed, which MealReviewModel copies into
  every correction-corpus row it writes — the corpus is never pruned, so those
  rows stay filterable even after the meal is deleted.
  - App/MealRouting.swift + CaptureState.swift + MealOverviewView.swift — a
  MealRoute.review case and a "Review" item in the meal overview's ⋯ menu, so the
  post-capture review surface opens on any stored meal. Off the capture stack
  Retake means nothing, so it and Delete both delete and unwind.

  The review screen already handles a record with no artefacts (Req 1.6: rows and
  total render without the photo; never an error) — you get the fork.knife
  placeholder and no outlines, everything else is live.

  Replayed onto all three attempt branches, since without it the attempt builds
  have no seed button. Each make build-app clean, tagged on a clean tree:

  ┌─────┬───────────────────────────────────────────┬─────────┐
  │     │                    Tag                    │   Sha   │
  ├─────┼───────────────────────────────────────────┼─────────┤
  │ 1   │ insulin-dosing-ui-attempt-1-on-research-3 │ ff9d29f │
  ├─────┼───────────────────────────────────────────┼─────────┤
  │ 2   │ insulin-dosing-ui-attempt-2-on-research-3 │ e0373bd │
  ├─────┼───────────────────────────────────────────┼─────────┤
  │ 3   │ insulin-dosing-ui-attempt-3-on-research-3 │ 26af5f9 │
  └─────┴───────────────────────────────────────────┴─────────┘

  git checkout <tag> && make deploy-device, then seed → Records → the meal → ⋯ →
  Review → Record → open the dose sheet. Docs updated:
  docs/agent-notes/device-build-and-test.md (the mechanism), insulin-dose-ui.md
  (new tags + what to judge), and task 8 in specs/data/insulin-dosing/tasks.md.

  On the test suite: I didn't write one, deliberately. MeData/Tests/ and
  MeData/UITests/ are documentation contracts — no committed target runs them, so
  a suite here would be files that never execute while reading like coverage.
  The gate for this work is a person looking at the screen, and what that gate
  was missing was a repeatable meal, not assertions. MedataCore is untou
  Off the capture stack Retake means nothing, so it and Delete both
  delete and unwind.

  The review screen already handles a record with no artefacts (Req 1.6:
  rows and total render without the photo; never an error) — you get
  the fork.knife placeholder and no outlines, everything else is live.

  Replayed onto all three attempt branches, since without it the attempt
  builds have no seed button. Each make build-app clean, tagged on a
  clean tree:

  ┌─────┬───────────────────────────────────────────┬─────────┐
  │     │                    Tag                    │   Sha   │
  ├─────┼───────────────────────────────────────────┼─────────┤
  │ 1   │ insulin-dosing-ui-attempt-1-on-research-3 │ ff9d29f │
  ├─────┼───────────────────────────────────────────┼─────────┤
  │ 2   │ insulin-dosing-ui-attempt-2-on-research-3 │ e0373bd │
  ├─────┼───────────────────────────────────────────┼─────────┤
  │ 3   │ insulin-dosing-ui-attempt-3-on-research-3 │ 26af5f9 │
  └─────┴───────────────────────────────────────────┴─────────┘

  git checkout <tag> && make deploy-device, then seed → Records → the
  meal → ⋯ → Review → Record → open the dose sheet. Docs updated:
  docs/agent-notes/device-build-and-test.md (the mechanism),
  insulin-dose-ui.md (new tags + what to judge), and task 8 in

  git checkout <tag> && make deploy-device, then seed → Records → the meal → ⋯ → Review → Record → open the dose
  sheet. Docs updated: docs/agent-notes/device-build-and-test.md (the mechanism), insulin-dose-ui.md (new tags +
  what to judge), and task 8 in specs/data/insulin-dosing/tasks.md.

  On the test suite: I didn't write one, deliberately. MeData/Tests/ and MeData/UITests/ are documentation
  contracts — no committed target runs them, so a suite here would be files that never execute while reading like
  coverage. The gate for this work is a person looking at the screen, and what that gate was missing was a
  repeatable meal, not assertions. MedataCore is untouched, so make test is unaffected by this change; make spell
  and make build-app are clean.
