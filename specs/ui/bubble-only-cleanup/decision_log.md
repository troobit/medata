# Decision Log: Bubble-only Tilt Guide Cleanup

## Decision 1: Relocate and rename the shared state enum rather than delete it with the gauge file

**Date**: 2026-06-24
**Status**: accepted

### Context

The task brief said to delete `App/TiltAimGuide.swift` (the `.gauge` design). That file also defines `TiltAimGuideState`, the pure per-stage tilt logic (`target`, `toleranceDegrees`, `isAligned`, plus the gauge/dial-only `halfSpanDegrees`, `offsetFraction`, `correction`). `TiltBubbleGuide` — the design being kept — depends on `target`, `toleranceDegrees`, and `isAligned`, and the existing tests cover the enum directly. Deleting the file wholesale would break the build.

### Decision

Move the three members the bubble uses into `App/TiltBubbleGuide.swift`, drop the three gauge/dial-only members as dead code, and rename the enum `TiltAimGuideState` → `TiltGuideState`.

### Rationale

The bubble must retain its logic, so the enum has to survive the gauge file's deletion. Keeping the name `TiltAimGuideState` would leave a type named after a deleted design (`TiltAimGuide`) inside the surviving file — exactly the "stale scaffolding" this cleanup is meant to remove. The rename touches only three call sites and the test file, so the churn is trivial relative to the clarity gained.

### Alternatives Considered

- **Keep the name `TiltAimGuideState`**: Zero rename churn - rejected because it permanently mis-names the type after a removed design and contradicts the "no leftover scaffolding" goal.
- **Extract to a new standalone `TiltGuideState.swift` file**: Cleaner view/logic separation - rejected because it adds a new file (and a new `project.pbxproj` entry) for ~15 lines of shared logic; folding it into the sole consumer keeps the change self-contained.

### Consequences

**Positive:**
- The surviving file carries no reference to a deleted design.
- Dead gauge/dial-only logic (`halfSpanDegrees`, `offsetFraction`, `correction`) is removed.

**Negative:**
- The pure-logic enum now lives inside a view file rather than standing alone; acceptable for a single small consumer.

---

## Decision 2: Remove stale references in all surviving files, including comments

**Date**: 2026-06-24
**Status**: accepted

### Context

`TiltBubbleGuide.swift` and `CaptureFlowView.swift` describe the bubble as one of three competing prototypes selected via `tiltGuideStyle`. After the cleanup those designs and the selector no longer exist.

### Decision

Rewrite the header/inline comments in every surviving file (`CaptureFlowView.swift`, `TiltBubbleGuide.swift`) so none reference `TiltGuideStyle`, `tiltGuideStyle`, `.gauge`, `.dial`, `TiltAimGuide`, or `TiltDialGuide`. Rename the test file `TiltAimGuideTests.swift` → `TiltGuideStateTests.swift` to match the renamed type.

### Rationale

The cleanup's stated intent is to retain only the bubble with no leftover scaffolding. Dangling comments that point at deleted code are scaffolding too — they mislead the next reader and re-introduce the confusion the deletion removes.

### Alternatives Considered

- **Leave comments as-is**: Less edit surface - rejected because it leaves stale documentation referencing deleted symbols, defeating the cleanup's purpose.

### Consequences

**Positive:**
- No surviving file references a removed design, in code or prose.

**Negative:**
- Slightly larger diff in otherwise-untouched comment blocks.

---
