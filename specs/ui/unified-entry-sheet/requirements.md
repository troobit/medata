# Requirements: Unified Entry Sheet

**Status:** Approved 2026-08-28 — implementation in progress.

Manual entry of a blood-glucose reading and manual entry of an insulin dose are the same job with
two different interfaces. Glucose is keypad-first in its own sheet; insulin is a pair of ±1 U
circular steppers inside `LogSheet`. This spec makes them one control in one sheet.

Full spec rather than a smolspec (`specs/PROCESS.md` §5): the change touches clinical safety — the
default value of an insulin dose entry — and spans more than three files.

The arbitrating UI/UX review is `specs/general/UI-IMPROVEMENTS.md`, "Review 2026-08-28 — unifying
the glucose and dose numeric-entry surfaces".

## 1. One Numeric Control

**User Story:** As the developer-user, I want every hand-entered quantity to behave the same way, so
that I do not have to remember which surface I am on before I start typing.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL enter every hand-typed quantity by shifting digits in from the
   right against a fixed number of decimal places, such that the decimal point is never typed and is
   rendered live — one decimal place for glucose, none for insulin units.
2. <a name="1.2"></a>The system SHALL draw the value as the numeral itself, with the field that takes
   the keystrokes laid underneath at full size and drawn clear, so no surface shows a quantity twice.
3. <a name="1.3"></a>The system SHALL make an out-of-range value unreachable rather than refused: a
   keystroke that would carry the value past its range SHALL be discarded, so the store's own bound
   is a backstop for a deep link and never something the developer meets.
4. <a name="1.4"></a>The system SHALL NOT present a stepper, arrow, or any other relative-adjustment
   control alongside the keypad on any surface that shares this control. *(The keypad sets the value
   absolutely and the displayed numeral is a render of a digit buffer; a relative control mutates the
   value without the buffer, so the two disagree about what the number is after any mixed sequence —
   see Decision 1.)*
5. <a name="1.5"></a>WHERE a surface has meaningful named values to offer, the system SHALL offer
   them as chips that set the value absolutely, never as relative adjustments.

## 2. One Sheet

**User Story:** As the developer-user, I want one manual-entry surface, so that a fourth kind of
event has one obvious place to land.

**Acceptance Criteria:**

1. <a name="2.1"></a>Glucose SHALL be a mode of `LogSheet` alongside insulin, activity and
   carbohydrate, and the separate glucose sheet SHALL be deleted rather than retained in parallel.
2. <a name="2.2"></a>Every entry point SHALL open `LogSheet` directly in its own mode — including
   `medata://glucose/add`, the glucose widget, and the home-page BSL control — so the mode selector
   remains a way out of a wrong turn and never a step on the way in.
3. <a name="2.3"></a>Each mode SHALL present at the same detent, so the sheet's height does not
   depend on which mode is showing.
4. <a name="2.4"></a>The system SHALL preserve the four-interaction budget of
   `specs/data/fingerprick-glucose` [Req 2.3](../../data/fingerprick-glucose/requirements.md#2.3):
   any glucose value from 1.0 to 30.0 SHALL be reachable and recorded within four interactions of the
   surface appearing, back-dating excluded.

## 3. Remembered Dose Defaults

**User Story:** As the developer-user, I want a repeating dose to be one tap, so that logging the
same basal every night is not four taps of arithmetic.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL remember the last saved dose SEPARATELY PER KIND and SHALL
   open each kind at its own remembered value; a basal SHALL NEVER seed a bolus, nor a bolus a basal.
2. <a name="3.2"></a>WHERE a dose suggestion is armed from a meal, that suggestion SHALL take
   precedence over the remembered value.
3. <a name="3.3"></a>WHERE neither a suggestion nor a remembered value exists for a kind, the system
   SHALL open at the fixed default of 10 U.
4. <a name="3.4"></a>The system SHALL name the provenance of the opening value beneath the numeral —
   which of suggestion, remembered value, or fixed default it came from — and SHALL replace that
   caption with the plain unit label on the first edit, permanently for that presentation.
   *(Mandatory, not optional: a variable default that does not say where it came from is a number the
   user did not choose, arrived at silently, on a surface that saves in two taps.)*
5. <a name="3.5"></a>Changing kind SHALL load that kind's own remembered value and restore its
   caption, because the opening value for the newly selected kind has not yet been edited.
6. <a name="3.6"></a>The remembered value SHALL survive app termination.
