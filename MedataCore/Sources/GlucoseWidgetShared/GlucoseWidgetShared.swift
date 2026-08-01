// GlucoseWidgetShared — the contract between the MeData app and the
// MeDataWidgets extension's glucose kind (specs/ui/glucose-lock-widget).
//
// Two hard boundaries hold this module in place, both because `Persistence`
// depends on it and therefore anything imported here reaches `Pipeline` and the
// macOS `HarnessCLI`:
//
//   1. Zero package dependencies (Decision 10) — asserted by the dump-package
//      check in GlucoseWidgetSharedTests, so the widget's link closure cannot
//      pick up GRDB.
//   2. No `import WidgetKit`, ever (Decision 12). `TimelineEntry` and
//      `TimelineReloadPolicy` live in the extension; this module speaks in
//      `GlucoseRender` and `Date?`. The dump-package check cannot catch a
//      framework import — system frameworks never appear as package edges — so
//      that boundary is held by review.
//
// Foundation only.
