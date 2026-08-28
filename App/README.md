# App target — the iOS app, by screen

Restructured 2026-08-28. Every file used to sit flat in this directory, 82 of
them, and nothing told you which ones made up a screen. Now the folder IS the
answer: open `Pages/MealReview/` and you have the meal-review screen, all of it.

**`App/` is a synchronised group in Xcode.** Add a file to a folder here and it
is in the build — there is nothing to register, no project file to edit. Create
a folder and it appears in the navigator. (Until 2026-08-28 each file needed
four separate entries in `project.pbxproj`; that whole ritual is gone, along
with `tools/pbx_add_app_file.py`.)

## Where to look

| Folder | What it is |
|---|---|
| `Design/` | **Start here to change how the app looks and feels.** Colours, motion, haptics, sizes — see [`Design/README.md`](Design/README.md) |
| `Shell/` | Launch, routing, `medata://` deep links. Not a screen |
| `Pages/` | One folder per screen, named as a user would name it. A page's view, its model and its own subviews live together |
| `Shared/` | Used by two or more pages. If only one page uses it, it belongs in that page |
| `Shared/FieldLoop/` | The `#if FIELD_LOOP` developer note-taking instrument, compiled out of product builds |

## The pages

| Page | What it is |
|---|---|
| `Pages/Home/` | The landing screen: latest reading, and the row of actions |
| `Pages/Capture/` | The camera: AR preview, aiming guides, shutter, refusals |
| `Pages/MealReview/` | What was captured, before it is recorded — corrections and the plate scale |
| `Pages/MealDetail/` | A recorded meal, opened from Records or the Graph |
| `Pages/LogEntry/` | The one manual-entry sheet: insulin, glucose, activity, carbohydrate |
| `Pages/Intake/` | Quick-add carbohydrate presets |
| `Pages/Records/` | The list of everything recorded |
| `Pages/Graph/` | Glucose, carbohydrate, insulin and activity over time |
| `Pages/Settings/` | Ratios, connections, schedules, developer tools |
| `Pages/GlucoseConnections/` | Which sources may write glucose readings |
| `Pages/GlucoseImport/` | Reading glucose out of LibreLink screenshots |
| `Pages/EstimationLog/` | What the estimator did, per capture |
| `Pages/Benchmark/` | Weighed meals to measure the estimator against |
| `Pages/About/` | Licences and attribution — the only legal surface |

## Conventions

- A page is a **view** plus its **model**. Behaviour lives in the model (an
  `@Observable @MainActor` type); the view is composition only.
- A file moves to `Shared/` when a **second** page needs it, not in
  anticipation of one.
- Long header comments are deliberate. They record why a thing is the way it
  is, which is the part that is expensive to rediscover.

See [`docs/agent-notes/ui-capture-flow.md`](../docs/agent-notes/ui-capture-flow.md)
for module-level gotchas and [`docs/architecture.md`](../docs/architecture.md) §4
for the wider architecture.

## File counts, as built

| Folder | Swift files |
|---|---|
| `App/Design/` | 3 |
| `App/Pages/About/` | 1 |
| `App/Pages/Benchmark/` | 1 |
| `App/Pages/Capture/` | 19 |
| `App/Pages/EstimationLog/` | 1 |
| `App/Pages/GlucoseConnections/` | 2 |
| `App/Pages/GlucoseImport/` | 2 |
| `App/Pages/Graph/` | 3 |
| `App/Pages/Home/` | 4 |
| `App/Pages/Intake/` | 2 |
| `App/Pages/LogEntry/` | 11 |
| `App/Pages/MealDetail/` | 1 |
| `App/Pages/MealReview/` | 2 |
| `App/Pages/Records/` | 2 |
| `App/Pages/Settings/` | 2 |
| `App/Shared/` | 14 |
| `App/Shared/DoseSchedule/` | 4 |
| `App/Shared/FieldLoop/` | 8 |
| `App/Shell/` | 3 |
