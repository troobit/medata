# Decision Log: Serving-Based Portion Adjustment

## Decision 1: Meal review supersedes the plate-fraction card, the confirm pill and the no-new-schema non-goal

**Date**: 2026-08-09
**Status**: accepted

### Context

`specs/ui/meal-review/` merges the post-capture segmentation-review and result screens into one review surface with relabelling, rejection and a per-food correction corpus. Its supersession register names three parts of this PRD: §iOS app item 2 (the plate-fraction control), §iOS app item 4 (the confirm pill and the edit-by-exception persistence rule), and the non-goal "no new correction mechanism, event types, or schema changes".

### Decision

The text of §iOS app items 2 and 4 is removed from `prd.md`, each replaced by a one-line removal marker so item numbering stays stable, and the no-new-schema non-goal is deleted. Items 1, 3 and 5 remain in force and are cited, not restated, by meal-review Req 6.1 (with the gram-stepper increment held unchanged by its Req 6.2).

### Rationale

Item 2's whole-meal scale control survives as a control, but meal-review Req 6.3–6.5 restates its stops (fractions at or below one) and its base (each row's currently derived amount, so it composes with relabels and never compounds); two normative statements of one control would drift. Item 4 contradicts meal-review directly: corrections now apply live and are retained at the moment they are made (its Req 7.4, 9.4), and unchanged foods are kept as records rather than written off by exception (its Req 9.1). The non-goal forbade exactly the correction schema meal-review Req 9 requires — one carrying class identity, correction kind, palette version and lineage — so keeping it would leave the spec set contradicting itself. Superseded text is edited out of the document that holds it, per the practice in meal-review's supersession register, with this entry as the trail.

### Alternatives Considered

- **Annotate the superseded items in place, keeping the text**: More visible history - Rejected because the spec set must hold one answer per surface; the removal markers plus this entry preserve the trail without a second live statement.
- **Retain the confirm pill on the merged surface**: Familiar edit-then-commit pattern - Rejected by meal-review Req 7.4 (its Decision 6): a confirmation step between the primary action and the meal being recorded is precisely what that spec removes.

### Consequences

**Positive:**
- One owner each for the scale control and the persistence rule.
- Items 1, 3 and 5 stay binding without restatement, so the serving data model, gram path and retired correction screen are untouched.

**Negative:**
- The PRD no longer reads standalone; understanding the current adjustment surface requires following the pointer to `specs/ui/meal-review/`.
- The removed non-goal's restraint survives only as the `estimation/pipeline` Req 14.3/14.4 obligations meal-review takes on, which is a less visible guard than a stated non-goal.

---
