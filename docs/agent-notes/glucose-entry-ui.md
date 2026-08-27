# Glucose entry UI (App/)

`specs/data/fingerprick-glucose`, app half. Blood readings reach the record two
ways: a Contour meter through Apple Health (no app interaction, see
`glucose-ingestion.md`), and a hand-entered reading through the surfaces here.
The store API (`recordBloodBsl`, `BloodBslReading`, the provenance decode) is in
MedataCore — see `persistence.md`. The Lock Screen side is in
`widget-extension.md`.

## Architecture

- **`GlucoseEntrySheet` + `GlucoseEntryModel`** are the entry surface, and are
  deliberately **not a fourth `LogSheet` mode** even though `LogSheet` exists
  precisely to stop a fourth entry sheet being written (see
  `insulin-dose-ui.md`). Two reasons, and only the second is decisive: it has
  no kind to name, and it opens with the numeric keypad already up, so it sits
  at the LARGE detent where the other three modes are fixed-height compositions
  at the medium one. Folding it in would have made one sheet present at two
  heights depending on mode. It still uses `EntryChrome`'s `EntryTimeRow` and
  `EntrySaveButton`, so the back-dating control and the commit button are the
  shared ones.
- **Presentation** is `AppRoot`'s, alongside the insulin and activity sheets,
  with the same `pendingDeepLink` dismiss-and-resume sequencing — that is what
  makes "from any app state" true, including with another sheet or a
  full-screen cover up. Three sheets now, so each one's `onDismiss` switch
  resumes the other four targets.
- **Deep link** `medata://glucose/add`, handled in `handleDeepLink` beside the
  other three. Every other case had to learn to dismiss `showGlucoseSheet`
  first; that combinatorial edit is the standing cost of the sheet-over-sheet
  rule (presenting over a sheet that is animating out is silently dropped).
- **Home**: the BSL control shares the Dose row, accent-prominent in the
  TRAILING slot — `ingestRow` with the treatments inverted, so the column keeps
  one accent per row. With dose-schedule attempt 2 active,
  `OutstandingDoseControl` occupies the Dose slot beside it. The glucose header
  is now a `Button` routing to Graph (Decision 5, redefining home-router
  Req 4.8), not the page's one display-only element.

## The pad, and why it is shaped like that

Req 2.3 is the whole design: any value in 1.0–30.0 must be reachable and
recorded within FOUR interactions of the surface appearing. That excludes both
obvious controls — the insulin sheet's 0.1-step stepper needs 51 taps for
7.0 → 12.1, and a `decimalPad` field with a typed point costs five.

So digits shift in from the RIGHT with an implicit tenths place: `1`, `2`, `1`
is 12.1. Nothing in range needs more than three digits.

- The numeral **is** the text field. A full-size `TextField` with
  `.foregroundStyle(.clear)` and `.tint(.clear)` (the latter hides the caret)
  sits under a `Text` of the formatted value. A separate visible field would put
  two numbers on screen and make the implicit point something to reconcile
  between them.
- The field binds to RAW DIGITS, never to the formatted string. Binding it to
  `displayValue` looks tempting and does not work: the keyboard edits at the
  cursor, so "12.1" + "1" is "12.11", which filters to 1211 and is rejected.
- `setDigits` is the whole contract, and lives on the model so it is one
  testable place: digits only; leading zeros dropped (so `0` `8` `4` and `8` `4`
  both read 8.4); and anything that would exceed 30.0 refused. That last rule
  caps the length at three without a separate check — a fourth digit always
  exceeds the range — and is what makes an out-of-range entry **unreachable**
  rather than merely refused. The store's `bloodGlucoseOutOfRange` guard is then
  a backstop for a deep link or a future caller, not something the developer
  meets.
- The delete key needs no case of its own: it hands back a shorter string.
- **Autofocus needs one run-loop hop.** A focus request in the same cycle as the
  sheet's presentation is dropped (the field is not in the hierarchy yet) and
  the keypad then costs a tap — which Req 2.3's budget cannot spare. `.task`
  with a ~60 ms sleep before setting `@FocusState`.
- Saves as `source_id = "manual"` with NO native id, so hand entries are never
  deduplicated: two fingersticks a minute apart are two readings, and a double
  tap on Save is two rows (Decision 10).

## The deletion seam (Req 6.2)

Deleting the displayed reading leaves the recomputed snapshot carrying an OLDER
`readingDate` than the stored one, which every case of the monotonic guard
rejects — so without this the widget goes on rendering a reading that no longer
exists. The `eventsDidChange` tick cannot fix it: it knows a row went away but
not which one.

`RecordsModel` is the seam, not `RecordsView`. There are three delete call sites
in the view (swipe, bulk confirm, date-range purge) and they funnel through
`delete(_:)` and `deleteBulk(_:)` here, so a fourth added later inherits the
route. Both collect the removed `bsl` timestamps and call
`GlucoseWidgetPublisher.publishRemoval(of:)`, which passes them as
`replacingDeleted:`. Deletions carrying no glucose row pass nothing and behave
exactly as before.

The publisher reaches `RecordsModel` by plain injection —
`App.swift → AppRoot → RecordsView → RecordsModel`, the same shape
`glucoseConnections` already takes. It is optional because the UI-test harness
returns before the publisher is built.

Both writes converge whichever order the actor runs them in: if the tick lands
first it is dropped as not-newer and `publishRemoval` then writes; if
`publishRemoval` lands first the tick finds nothing changed and skips.

## Settings

- **Apple Health writers** (`GlucoseConnectionsView`) is what makes the Contour
  classification settable **without a rebuild** — no Contour bundle identifier
  is hard-coded anywhere in this repo, by design. The section is empty until a
  sample has actually arrived, because a writer is recorded when it contributes
  one and there is no way to enumerate writers ahead of time.
  - `Unset` is a distinct picker state from `Sensor`. Both ingest as sensor
    readings, but only one of them is a decision somebody made.
  - The list is mirrored on `GlucoseConnectionsModel`, not read from
    `UserDefaults` in the view body — a defaults read there is invisible to
    `@Observable` tracking and the picker would not move. Same rule as
    `connectedSourceIDs`. It refreshes off the coordinator's state tick, so a
    sample landing while Settings is open makes its writer appear.
  - Classifying takes effect on SUBSEQUENTLY arriving samples only. Existing
    rows keep the provenance they were written with and are correctable only by
    deletion (Decision 2).
- **Hold window**: a `Stepper` in 5-minute steps over a key stored in seconds
  (`medata.glucose.holdWindowSeconds`). Above 15 minutes a second row states the
  age at which the staleness ladder takes over — the ladder measures from the
  reading's own instant and knows nothing of the hold, so past that point a held
  reading renders stale while still holding (Decision 3). Shown only where the
  two numbers diverge, and stated as a number: a fact about the render, not
  disclaimer copy.

## Graph and Records

- **The `LineMark` runs over SENSOR readings alone.** That is what draws the
  trace unbroken across a blood instant (Req 4.2) — splicing a fingerstick in as
  a vertex would break the trace at exactly the moment the requirement asks it
  to stay continuous. Blood is a separate `PointMark` series at true instants in
  every range, unbucketed even on week and month, because a fingerstick is a
  discrete event like an insulin dose.
- Nothing is filtered out of `TrendsModel.glucose` itself, so the stat cards
  still see every reading (Req 4.1). The auto y-scale takes BOTH series, or a
  blood reading above the trace's peak plots off the top.
- `Color.seriesGlucoseBlood` is `systemBrown`, the system's deep low-chroma
  orange: the same quantity measured another way must read as a member of the
  glucose series, not as a fifth metric beside carbs, insulin and activity. The
  Records glyph uses the same two colours so a marker and a row are
  recognisably the same reading.
- Records labels BOTH provenances and touches neither the ordering, the swipe
  gesture nor the bulk actions — Req 6.1 needed no code at all.
