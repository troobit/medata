# MVP gap analysis — current state

**As of 2026-10-03** (branch `research`). Replaces the June note, whose single
blocker — no trained segmenter — closed in July: the bundled model is
`coreml_ab812dc3aa9d` (`model-production.md`). The MVP is: 1–2 photos of a
plate → a recorded carbohydrate estimate → a suggested insulin dose from it.

Classes used below: **(a)** desk-fixable code gap, **(b)** needs the phone (a
look or a sensor), **(c)** needs hardware or data we do not have yet.

## The path, hop by hop

| Hop | Code | State | Outstanding |
|---|---|---|---|
| 1. Capture | `App/Pages/Capture/`, `CaptureKit` | Proven on device (single-view LiDAR, Release) | (b) two-view well-aimed trail (`bugfixes/two-view-carve-no-volume` 1), two-view refit round (`two-view-trust` 21.2), sesame roll end to end (`unknown-food-nameable` 8). (c) a non-LiDAR phone, or the oblique-band capture, for the no-depth path |
| 2. Estimate | `Pipeline` | Proven: single-view reads the weighed 104 g roll at −13 % / +8 % (±11 % run to run). No-depth two-view refuses (`noSupportPlaneWithoutDepth`) | (b) weighed plate on the promoted plane (`support-plane-reference` 27), capture pass + ANE residency (`myfoodrepo-bridge` 7, 8). (c) β calibration and the benchmark campaign |
| 3. Persist | `GRDBPersistenceStore`, outcome rows, bundles | Proven (pulls, outcome rows, bundle replay) | (b) meal-review Req 9.4 / 9.10 durability checks |
| 4. Review | `MealReviewView` / `MealReviewModel` | Proven: layout, one-tap Record, reject, field notes. Relabel never exercised on device | (b) `mass-readout` 4, `manual-carb-intake` 19, `unknown-food-nameable` 8, swap-loop attempt choice |
| 5. Records / total | `RecordsModel`, `TrendsModel`, `ResultView` | Corrected total read everywhere | (b) meal-review Req 8.7 (corrected name and figures in history) |
| 6. Dose | `Dosing`, `DoseComputation`, `DosePill`, `DoseWorkingSheet` | Arithmetic proven by `make test`; never seen seeding the sheet on device | (b) `insulin-dosing` 18, 37. (c) 19 retrospective, 20, 22–26 fat programme |
| 7. Dose sheet + schedule | `AppRoot`, `LogSheet`, `DoseScheduleModel` | Desk-complete | (b) `dose-schedule` 21–25, `settings-information-architecture` 3. (c) `dose-schedule` 26 |

No (a) item is left open on this path after the fixes below.

## Fixed at the desk on 2026-10-03 (built, not yet seen on the phone)

1. **The dose sheet was never seeded from a meal.** `.environment(doseSeeds)`
   sat inside AppRoot's cover and sheet modifiers, so the holder was nil in
   the Capture and Intake covers and every `arm(_:)` did nothing. Moved
   outermost. (`insulin-dose-ui.md`)
2. **Reminder Adjust** opened unlinked when it raced the foreground refresh,
   inherited the last meal seed, and captioned the nominal amount `last basal`.
   It now resolves its own occurrence and reads `scheduled basal`. (dose-schedule
   Q1, Q2)
3. **Review buttons dead after a screen lock.** The AR interruption moved the
   state off `.showingResult`; Record, Retake and Delete were gated on it. A
   cover dismissed mid-review now also clears the stale review. (meal-review Q1)
4. **Amounts under a plate scale were scaled twice** (½: typing 100 g showed
   50 g). (meal-review Q2)
5. **Review dose pill could land behind its total** — now `.task(id:)`.
6. **History after a relabel or an added food** priced rows at the predicted
   food, showed a renamed Unknown food at 0 g, and dropped the relabel and
   added foods from the total at the first stepper tap. (meal-review Q3)

## Desk-complete, never confirmed on the phone

- The outstanding-dose gear pushing Settings › Insulin and scrolling to the
  schedule (`settings-information-architecture` 3).
- The reminder: firing, repeating, stopping, lock-screen Log, stale follow-up
  writing nothing, refused authorisation (`dose-schedule` 21–24).
- Relabel, Add a food and the two swap-loop attempts on a real capture.
- The dose working sheet's arithmetic lines on a real meal.

## One-sitting device checklist

Ordered by what each step unlocks. `make dev` (Release + model), then match
`event=launch buildStamp=…` to the commit before trusting anything.

1. [ ] **Capture → Record → Dose.** Single-view a plate. The review shows a
       dose pill; tap it, the working's lines sum. Record, close Capture, tap
       Home › Dose: the sheet opens at the suggested units under
       `from N g at R g/U`. Save.
       *Unlocks insulin-dosing 18 (main bullets) and 37; proves fix 1.*
2. [ ] **Records → that meal.** The pill shows the same dose and a `given` line
       pairs the bolus just saved. *insulin-dosing 37.*
3. [ ] **Relabel and add.** Capture again; relabel one food (sheet or chip),
       Add a food, tap ½, then step one row: the row shows what was stepped
       and the pill follows the total. Record. In Records the meal names the
       corrected food; open it: rows show the corrected food in its own unit,
       the added food is listed, and tapping + then − leaves the hero total
       where it was. *Fixes 4–6; meal-review Req 8.7; unknown-food-nameable 8
       if the plate is the sesame roll.*
4. [ ] **Lock mid-review.** Capture, lock the phone on the review, unlock, tap
       Record: it leaves. *Fix 3.*
5. [ ] **Reminder.** Settings › Insulin: set Repeat every 5 min, Add a
       schedule entry two minutes ahead (allow notifications); lock the phone. When it fires: tap **Adjust** — the sheet
       opens at the nominal amount under `scheduled basal`; save; the Home card
       clears and no repeat arrives. Add another, tap **Log** from the lock
       screen: the app never appears, and Records shows the dose. *Fix 2;
       dose-schedule 21, 22.*
6. [ ] **Stale follow-up.** With a third entry, log it in-app from the Home card,
       then tap the next repeat's Log: nothing new in Records. *dose-schedule 23.*
7. [ ] **Gear.** With an entry outstanding, the Home card's gear lands on the
       schedule, not the Settings top. *settings-information-architecture 3.*
8. [ ] **Quick-add.** Review › ⋯ › Save as quick-add, name it; Intake shows the
       tile; tapping it then Home › Dose opens seeded. *manual-carb-intake 19;
       insulin-dosing 18 bullet 3.*
9. [ ] **Looks.** Mass line on the review and Records (`mass-readout` 4); the
       dark theme acceptance band (`unified-dark-theme` 5).
10. [ ] **Durability.** Relabel, force-quit before Record, reopen: Records shows
        the correction (meal-review 9.4). Delete that meal: the corpus row
        survives (9.10).

Remove the test schedule entries afterwards (swipe in Settings › Insulin).

## Needs hardware or data

- **β calibration and the accuracy bar.** Every class ships at unity β; the
  MAPE < 20 % bar (MD-25) needs ≥ 30 weighed meals per class, and the SNAQ
  comparison needs the ≥ 20-meal benchmark campaign (`snaq-parity`). One
  weighed object exists (the 104 g roll).
- **The no-depth two-view path.** It refuses before fitting a plane; the
  oblique-band capture (Developer › Oblique tilt unlocked) or a non-LiDAR phone
  decides it (`two-view-trust` Decision 8, task 20).
- **Dose evidence.** `insulin-dosing` 19–20 need an exported database with weeks
  of CGM, meals and boluses; 22–23 need a weighed fat reference and CGM history;
  `dose-schedule` 26 needs weeks of due/logged pairs to set I and K.
- **Segmenter.** Training levers are exhausted against a 13-class-readable
  anchor; enlarging the held-out set is the next ML action
  (`segmenter-run-queue.md`).

## Seen, left alone (not on the path or not a defect)

- The review shows the calibration banner over `dev_stub` figures where
  ResultView suppresses it; meal-review design keeps the placeholder chip off
  the review. Stub builds only.
- ResultView's `Protein — soon` / `Fat — soon` placeholders, although fat and
  protein are computed and stored (insulin-dosing Req 8 keeps them out of the
  dose).
- `.tint(.medataAccent)` on AppRoot does not reach the covers either; changing
  it is a look decision.
- A pipeline that finishes after Capture was closed still pushes its review on
  the next Capture, whenever that is; Record then arms a fresh seed for the old
  meal.
