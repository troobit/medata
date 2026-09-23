# Unified Entry Sheet

## Shared control

- [x] 1. Extract DigitEntry — the digit-shift rule, generalised by decimals and range
  - Lifts GlucoseEntryModel's setDigits verbatim: digits only, strip leading zeros, discard anything exceeding the range
  - Adds set(value:) so a remembered or suggested number becomes a digit buffer the first keystroke replaces
  - Req 1.1, 1.3

- [x] 2. Extract NumericEntryPad — the numeral that is its own field
  - Clear TextField at 72pt under the drawn numeral, unit caption beneath; focus stays with the caller
  - Req 1.2

- [x] 3. Move GlucoseEntryModel onto DigitEntry, leaving save() untouched
  - The manual route provenance, the no-deduplication rule and the store's range guard do not change

## The fold

- [x] 4. Give the insulin sheet the keypad and delete the steppers
  - Deletes stepControl, beginHold, endHold, repeatSteps and the hold-acceleration schedule
  - Req 1.4 — a relative control cannot coexist with the digit buffer (Decision 1)

- [x] 5. Add the chip row for named values, from the existing EntryChip and ChipFlow
  - Armed suggestion where one exists; the kind's remembered value. Chips set absolutely
  - Req 1.5

- [x] 6. Remember the last saved dose per kind, with the caption naming its provenance
  - UserDefaults, one key per kind; suggestion outranks remembered outranks fixed 10 U
  - Caption is mandatory and consumed on first edit; changing kind reloads that kind's value
  - Req 3.1 to 3.6 (Decision 2)

- [x] 7. Add LogSheet.Mode.glucose and route AppRoot to it
  - Every mode presents at .large; GlucoseEntrySheet.swift is deleted
  - Deep link, widget URL and home control keep their targets — only what the target builds changes
  - Req 2.1 to 2.3 (Decision 3)

## Verify

- [-] 8. Build, deploy, and confirm the four-interaction budget on device
  - Any glucose value 1.0 to 30.0 within four interactions of the surface appearing, back-dating excluded
  - Req 2.4 — the one requirement a device pass can falsify and a build cannot
  - Debug build green, zero warnings. Deployed 2026-08-28 for the device pass.
