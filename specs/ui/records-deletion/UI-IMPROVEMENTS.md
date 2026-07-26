# UI/UX Improvements

## Summary

Review of the Records surface (`App/RecordsView.swift`, full-screen cover from
the home router): one chronological List of meal, insulin, glucose, and manual
intake rows. Deletion today is inconsistent per row type — swipe-to-delete
exists for meals/insulin/intake, glucose rows are delete-disabled, and the
discoverable meal-deletion path is buried two levels deep (row → meal overview
→ toolbar menu → confirm). There is no bulk deletion and no date-range purge,
so clearing developer/test data means dozens of individual swipes.

Reviewed 2026-07-26 against the iOS Human Interface Guidelines (edit mode,
swipe actions, destructive confirmation) and Nielsen heuristics (user control,
consistency, efficiency of use).

## Critical Issues

### Issue: No bulk or date-range deletion for records

**Current State**: Every deletion is one row at a time; glucose rows cannot be
deleted at all. A LibreLinkUp import session can add thousands of glucose
rows.
**Problem**: Efficiency-of-use failure — purging a day of test data takes
dozens of swipes; purging imported glucose is impossible from the UI.
**Recommendation**: Standard iOS edit-mode multi-select (the Mail/Photos
pattern): an Edit button in the navigation bar enters `EditMode.active` with
row checkmarks; a bottom bar offers Select All / Deselect All and a
destructive Delete (n) with a confirmation dialogue. Add a toolbar menu item
"Delete by Date…" opening a small sheet with From/To date pickers, a live
count of affected records, and a confirmed destructive delete.
**Impact**: Bulk purge drops from O(rows) interactions to 3–4 taps.
**Implementation Notes**: Needs a batched store delete (single transaction,
one `eventsDidChange` tick) — a per-row loop would trigger one list reload per
row across thousands of rows.

### Issue: Glucose rows are delete-disabled

**Current State**: `.deleteDisabled(true)` per home-router Req 3.5
("import-sourced, reappears on next import").
**Problem**: Inconsistency across row types (same list, different affordances)
and a dead end for the user who wants the data gone.
**Recommendation**: Enable deletion for glucose rows (swipe + edit-mode +
range purge) via a new `deleteBslEvent` store method, superseding Req 3.5.
**Impact**: One consistent deletion model across every row type.
**Implementation Notes**: A reading deleted inside the live LibreLinkUp
polling window may be re-ingested by the keep-first merge on the next poll —
acceptable; the primary use case is clearing history, not suppressing a
single live reading. No UI messaging about this (developer-phase copy rule).

## High Priority Improvements

### Issue: Meal deletion is buried in the overview menu

**Current State**: Row → MealOverviewView → ellipsis Menu → Delete → confirm
(four interactions, two screens deep).
**Problem**: The list already supports swipe-to-delete for meals, but the
discoverable path (the menu) is the deep one; the user perceives deletion as
"having to go through the menu".
**Recommendation**: Keep the overview menu path as a secondary route, but make
the list the primary surface: swipe-to-delete stays, and edit-mode
multi-select makes deletion visible at the top of the screen (Edit button).
Swipe delete follows standard practice (the revealed Delete button is the
deliberate second step; no extra dialogue). Bulk and range deletes confirm
via dialogue because they are not individually reversible gestures.
**Impact**: Deletion is discoverable in one tap from the list.

## Medium Priority Enhancements

- Deleting from edit mode should clear the selection and exit edit mode after
  the confirmed delete, returning the list to browse state (Mail behaviour).
- The date-range sheet should default From to the earliest record and To to
  now, so "everything" is two taps (Select All in edit mode covers the same
  case; the range default just avoids date spinner fiddling).

## Low Priority Suggestions

- Long-press context menu ("Delete") on rows as a tertiary affordance —
  standard but redundant next to swipe + edit mode; skip unless requested
  again.
- Section headers per day would make date-range deletion previewable in
  place; defer to a future Records information-architecture pass.

## Positive Observations

- The single chronological timeline with per-type icons and monospaced-digit
  values is clean and scannable.
- Swipe-to-delete where present follows the platform convention exactly
  (`.onDelete`, destructive role, no superfluous confirmation).
- `eventsDidChange`-driven reload means deletions propagate to Trends and
  History without manual refresh plumbing.
