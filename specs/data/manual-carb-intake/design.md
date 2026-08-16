# Design: Manual Carb/Macro Intake

## Overview

Adds a manual carb-logging path alongside the photo pipeline: a carb-entry sheet (insulin-dose sheet pattern), flat quick-add presets, and an edit/delete list — all reachable from `IntakeView`, which this feature replaces wholesale (home-router Decision 12). Manual entries are a new `EventType.intake` row (mirroring `EventType.insulin`); quick-add presets are a new SQLite table.

Req 8 adds a second origin for a preset — a successful capture — without adding a second mechanism: the meal's displayed carbohydrate total and a name derived from its detected foods pre-fill the *existing* preset sheet, and the *existing* one-tap quick-add is the replay. See "Preset from a captured meal".

## Architecture

### Event type and storage (Req 6.1–6.3)

A manual carb entry is one `events` row, `event_type = EventType.intake`, following the same shape as insulin (`persistence.md`'s convention): `value` = carbohydrate grams (REAL), `timestamp` = the user-set time, `metadata` = a JSON object carrying the subtype and optional macros.

```
EventType.intake = "intake"

metadata = {
  "subtype": "carb",              // Decision 14 taxonomy; only "carb" shipped here
  "schema_version": 1,
  "protein_g": 12.0,               // omitted key, not null, when absent (Req 2.3)
  "fat_g": 8.0,                    // omitted key when absent
  "fibre_g": 3.0,                  // omitted key when absent
  "source": "manual" | "quickadd", // Req 6.1 distinguishability; quickadd also
                                    // carries "preset_id" for provenance
  "preset_id": "<uuid>"            // present only when source = "quickadd"
}
```

`value` (carbs) is always present and non-optional, matching Req 1.4's 1–999 g floor/ceiling — enforced at the store layer the same way `insulinUnitsOutOfRange` gates units, returning a new `PersistenceError.intakeCarbsOutOfRange(Double)`.

`preset_id` is a point-in-time provenance stamp, not a live reference: a quick-add entry's carb/macro values are copied from the preset *at save time* into the entry's own `metadata`, so later editing that preset (Req 4.2) never retroactively changes already-written entries — each entry is a snapshot, matching the immutability the rest of the event log already assumes for meals. Deleting the source preset leaves `preset_id` pointing at a row that no longer exists; this is accepted and inert, because nothing dereferences `preset_id` at read time — `IntakeRecord`/`CarbEntrySheet(editing:)` render entirely from the entry's own stored fields, never by looking the preset back up. `preset_id` exists only so a future feature could group/filter by originating preset if wanted; this spec writes it and never reads it back.

`source`/`presetID` pairing (`presetID` set iff `source == .quickadd`) is a convention enforced by call-site discipline, not by the store: `IntakeEntry.init` accepts any combination, and `saveIntakeEntry` validates only the carb range. This matches the project's existing permissiveness elsewhere (e.g. `InsulinDose.note` has no store-side shape validation beyond presence) — a deliberate choice to keep the store layer's validation surface small, not an oversight.

This reuses the existing `events` table and `eventsDidChange` broadcaster verbatim — no new table for entries themselves, only for presets (below). Editing an entry (Req 7.2) is an `UPDATE` on the same row (manual intake has no correction/append-only model — home-router Decision 4 established this freedom for records this spec owns); deleting is a `DELETE ... WHERE event_type = 'intake'`, gated the same way `deleteInsulinEvent` is.

### PersistenceStore additions

```swift
// New in EventType (Persistence)
public enum EventType {
    ...
    public static let intake = "intake"
}

public enum IntakeSubtype: String, Sendable, Equatable {
    case carb
    // "alcohol" etc. arrive in a later feature (home-router Decision 14);
    // this spec ships only .carb.
}

public struct IntakeMacros: Sendable, Equatable {
    public var proteinG: Double?
    public var fatG: Double?
    public var fibreG: Double?
    public init(proteinG: Double? = nil, fatG: Double? = nil, fibreG: Double? = nil)
}

public enum IntakeSource: String, Sendable, Equatable {
    case manual
    case quickadd
}

public struct IntakeEntry: Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let carbsG: Double
    public let subtype: IntakeSubtype
    public let macros: IntakeMacros
    public let source: IntakeSource
    public let presetID: UUID?   // set iff source == .quickadd
    public init(id: UUID = UUID(), timestamp: Date, carbsG: Double,
                subtype: IntakeSubtype = .carb, macros: IntakeMacros = .init(),
                source: IntakeSource, presetID: UUID? = nil)
}

extension PersistenceStore {
    // Writes one `intake` event row. Throws `intakeCarbsOutOfRange` outside
    // 1...999. Notifies `eventsDidChange` once (Req 6.3, 3.2).
    func saveIntakeEntry(_ entry: IntakeEntry) async throws

    // Req 7.2: in-place update, same row id, re-validates the 1...999 range.
    // Notifies `eventsDidChange` once (Req 7.4).
    func updateIntakeEntry(_ entry: IntakeEntry) async throws

    // Req 7.3: gated on event_type = intake. Notifies `eventsDidChange` once (Req 7.4).
    func deleteIntakeEntry(id: UUID) async throws
}
```

Req 7.1's "recent manual entries" list needs no new store accessor: `IntakeModel` reuses the existing `events(in:type:)` with `RecordsModel`'s own all-time sentinel (`.distantPast...Date.distantFuture`, already established for exactly this "no natural window" case), decodes each `Event` into an `IntakeEntry`, and sorts/truncates in Swift. This is the same shape `RecordsModel.loadInsulin()`/`loadGlucose()` already use — no bespoke SQL, no second way to query the same table.

**Decode ownership**: home-router's Decision 13 deliberately keeps insulin/glucose decoders private and duplicated per model (`TrendsModel.insulinEntry(from:)`, `RecordsModel.insulinEntry(from:)`) rather than sharing one, specifically to avoid churning the perf-sensitive `TrendsModel`. This design follows the same convention: `intakeEntry(from event: Event) -> IntakeEntry?` is written twice, privately, once in `IntakeModel` and once in `RecordsModel` — not exposed as a public cross-module helper. Both decode the same three-key metadata shape (`subtype`, macro keys, `source`/`preset_id`), so the two copies are a few lines each and carry no shared-file coupling risk.

### Quick-add presets — new table (Req 3, 4)

Presets are structured (name + 4 numeric fields) and CRUD'd independently of any entry, so they get their own table rather than reusing `events` or `UserDefaults` (`SettingsKeys.swift` is reserved for scalar app settings, not user-authored records).

```sql
CREATE TABLE IF NOT EXISTS quick_presets (
    id          TEXT PRIMARY KEY,
    name        TEXT NOT NULL,
    carbs_g     REAL NOT NULL,
    protein_g   REAL,             -- NULL = absent (Req 2.3 applies to presets too)
    fat_g       REAL,
    fibre_g     REAL,
    sort_order  INTEGER NOT NULL  -- insertion order; flat list (Decision 6)
);
```

Schema version bumps 4 → 5; `createSchema` gains the table (`CREATE TABLE IF NOT EXISTS`, retrofits existing DBs), `migrate` re-stamps `schema_version = '5'`, matching the `processed_images`/v4 precedent exactly. First-launch seeding writes the three authored defaults (Req 3.3 — "A pint" 17 g, "Bagel" 45 g, "Chips" 40 g) once, gated on `quick_presets` being empty at store-init time (same idempotent-seed shape as `INSERT OR IGNORE`).

```swift
public struct QuickPreset: Sendable, Equatable, Identifiable {
    public let id: UUID
    public var name: String
    public var carbsG: Double
    public var macros: IntakeMacros
    public var sortOrder: Int
}

extension PersistenceStore {
    func quickPresets() async throws -> [QuickPreset]           // sort_order ASC
    func saveQuickPreset(_ preset: QuickPreset) async throws     // insert or replace by id
    func deleteQuickPreset(id: UUID) async throws
}
```

No `eventsDidChange` notification on preset CRUD — presets are not `events` rows and nothing outside the Intake surface reads them; `IntakeView` reloads its own preset list after a local mutation (create/edit/delete all originate from that surface, so no cross-view subscription is needed). *(Amended by Req 8: a preset can now also be created from a result surface. That surface presents `QuickPresetEditSheet` and then leaves — it holds no preset list to refresh, and `IntakeView` reloads on its own next appearance, so the no-notification stance is unchanged.)*

### Preset from a captured meal (Req 8)

A capture-born preset is the *same row* as a hand-authored one with one extra provenance column. Nothing about the quick-add tap, the tile, or the edit path changes — the amendment is an additional **origin**, and the existing quick-add path is the **replay** (Req 8.6, 8.7).

#### The flattening, and what survives it

A `MealRecord` decomposes into `macros.perClass: [String: PbPerClassMacros]` — per class a `volumeCm3`, `massG`, `carbsG`, `betaUsed`, `betaStatus`, `densitySource`, `coefficientSource`, `isLiquid`, `deviceVerified`. A `QuickPreset` is four flat numbers and a name. The decomposition is therefore **dropped**, not stored, and it is not recoverable from the preset (Decision 7). Two things survive it:

- **The number** — one carbohydrate total (below).
- **The name** — the decomposition's only durable trace. The pre-filled name is built from the meal's own rows: active (non-rejected) foods in the surface's existing carbs-descending order, each class id run through the existing `MealReviewModel.prettify(_:)` (`_` → space, first letter capitalised), the first two joined with `" + "`, and `" +N"` appended when `N` further foods remain. A three-food plate pre-fills as `"Rice + Chicken breast +1"`. It is a starting point, not a label the user is stuck with — Req 8.2 requires it editable, and the realistic edit is a place name ("Nando's half chicken").

The name is empty only when every row has been rejected; `QuickPresetEditSheet.canSave` already requires a non-empty trimmed name, so that case simply waits for the user to type one. No new validation.

#### Which number is frozen (Req 8.3)

The value carried is **what the surface is showing**, which on both surfaces is already a computed property:

| Surface | Displayed total |
|---|---|
| `MealReviewView` (post-capture) | `MealReviewModel.pendingTotalCarbsG` — the stored total plus per-row deltas, i.e. corrections included |
| `ResultView` (from records) | `heroCarbsG` — `adjustmentPending ? pendingTotalCarbsG : (correctedTotal ?? record.macros.totalCarbsG)` |

Neither is `record.macros.totalCarbsG` once the user has corrected anything, and the corrected figure is the better one to freeze (Decision 8). Both are `Double`/`Float` grams; the preset takes `Double(displayed.rounded())`, clamped into the existing `CarbEntryModel.minCarbs...maxCarbs` (1...999) window by the same `clampedDigits` sanitiser `QuickPresetEditSheet` already applies to typed input. A meal rounding to 0 g opens the sheet with an empty carb field and Save disabled — the existing `canSave` rule, no new branch.

Protein, fat, and fibre are **not** carried (Req 8.4, Decision 9), even though `record.macros.clinicalTotals` holds all three: they are computed-but-deliberately-unsurfaced (`ClinicalMacros.proto`: *"Computed but not surfaced in v1 per Req 12.6"*), and the preset sheet's macro fields are user-editable, so pre-filling them would surface unvalidated pipeline figures as if the user had asserted them. The macro disclosure opens collapsed exactly as it does for a blank preset.

#### Schema: `quick_presets.source_meal_id` (Req 8.8, 8.9)

```sql
-- createSchema's CREATE TABLE gains the column; migrate adds it to existing DBs
source_meal_id TEXT          -- MealRecord.id.uuidString; NULL = hand-authored
```

`QuickPreset` gains `public var sourceMealID: UUID?`.

Semantics are **exactly** the `preset_id` stamp on an intake entry (see "Event type and storage" above): a point-in-time provenance mark, written once, **never dereferenced at read time**. Nothing looks the meal back up; a preset renders entirely from its own columns. Deleting the originating meal — which the review surface's Retake and Delete both do — leaves `source_meal_id` dangling, and that is accepted and inert, satisfying Req 8.8 by construction rather than by cascade rules. The column's use is future: once β calibration lands, a non-NULL `source_meal_id` is the handle that identifies which presets froze an uncalibrated estimate (Decision 11). This spec writes it and never reads it back.

Schema version bumps **8 → 9**. This is the first *additive DDL on an existing table* in the store — versions 5–8 each added a whole table under `CREATE TABLE IF NOT EXISTS`, which retrofits itself. `ADD COLUMN` does not: SQLite throws `duplicate column name` on a second run, so `migrate` must read the stored `schema_version` before re-stamping and apply the `ALTER TABLE quick_presets ADD COLUMN source_meal_id TEXT` only when it is below 9. That turns `migrate` from an unconditional one-line re-stamp into a read-then-act pair (Decision 10); it stays non-destructive, so event-log-schema Decision 10's "no destructive DDL ships" holds.

**Gotcha — the round-trip.** `QuickPresetEditSheet.init` destructures the preset it is given (`presetID`, `sortOrder`, plus text state) and *reconstructs* a `QuickPreset` on save; `saveQuickPreset` is `INSERT OR REPLACE` by id. So an edit of a capture-born preset silently drops `source_meal_id` unless the sheet captures it too — a `private let sourceMealID: UUID?` alongside `presetID`/`sortOrder`, carried through untouched. That is what Req 8.9 exists to pin.

#### The action on the two result surfaces (Req 8.1, 8.5)

Both surfaces already own an overflow `Menu`; the action is one `Button` in each, reusing the string `CarbEntrySheet` already ships so the vocabulary stays single:

| Surface | Attach point | Existing items |
|---|---|---|
| `MealReviewView` | `ToolbarItem(placement: .topBarTrailing)` menu | `Retake`, `Delete` |
| `ResultView` | `actionRow`'s ellipsis `Menu` | `Delete` |

Label: **"Save as quick-add"** (identical to `CarbEntrySheet.swift`'s secondary action); accessibility identifiers `review.saveAsQuickAdd` and `result.saveAsQuickAdd`. It is not a destructive role and sits above the destructive items.

No confidence, calibration, or placeholder gate (Req 8.5, Decision 12): a refusal never reaches either surface, so everything reachable here is by definition a completed estimate, and the one build the developer exercises on device is the Debug stub build — gating on `segmenterSource == "dev_stub"` would hide the action precisely where it gets tested.

Presentation is local to each view, not a new injected callback: both already hold `store` (`ResultView.store`, `MealReviewModel.store`), so each gets `@State private var presetDraft: QuickPreset?` and `.sheet(item: $presetDraft) { QuickPresetEditSheet(store: store, preset: $0, isNew: true) }` — the same construction `CarbEntrySheet` uses. The menu action builds the draft and assigns it; dismissal does nothing further (the result surface holds no preset list). Cancelling creates no preset and rolls nothing back, matching the Req 4.4 flow.

Building the draft needs a `sortOrder`, and neither result surface loads presets. Rather than a third copy of `IntakeModel.nextSortOrder`'s expression, that one line moves to Persistence as a static on the type that owns it:

```swift
extension QuickPreset {
    // Append-at-end ordering (Decision 6's flat list): max + 1, -1 + 1 = 0 when empty.
    public static func nextSortOrder(after presets: [QuickPreset]) -> Int
}
```

`IntakeModel.nextSortOrder` is rewritten to call it; the result surfaces call `store.quickPresets()` once inside the menu action and pass the result in. One fetch on an explicit user tap of a table with a handful of rows — not a load-path cost.

The draft builder itself (record → `QuickPreset`) is shared rather than written twice, because unlike the per-model event decoders (see "Decode ownership" above, where duplication avoided coupling a perf-sensitive model) both call sites want byte-identical naming and clamping. It lands in `App/MealRouting.swift`, the existing home for App-layer meal plumbing shared across surfaces, so no new file and no `project.pbxproj` registration:

```swift
// App/MealRouting.swift — shared by MealReviewView and ResultView.
@MainActor
func quickPresetDraft(
    displayedCarbsG: Double,      // the surface's own displayed total (Req 8.3)
    foodNames: [String],          // active foods, carbs-descending, already prettified
    sourceMealID: UUID,
    existingPresets: [QuickPreset]
) -> QuickPreset
```

Each surface supplies its own displayed total and its own row order — `MealReviewModel.activeFoods.map { prettify($0.currentClassId) }` on review, `ResultView`'s existing rows (already `prettify`-ed and carbs-sorted) from records — so neither has to re-derive the other's correction model.

### Carb totals and graph series (Req 6.2)

`TrendsModel.carbBars` is built solely from `store.allMeals()` today (`TrendsModel.swift:114,122-123`, `carbTotal(_:MealRecord)`). Synthesizing a fake `MealRecord` for a typed-in number is the wrong shape — `MealRecord` requires `capturePath`, `calibration`, `volumes`, `confidence`, all photo-pipeline fields with no meaning for a manual entry. Instead, `TrendsModel.reload()` additionally fetches `.intake` events in range (same call shape as the existing `.insulin`/`.bsl` fetches) and folds their carbs into the same `carbBars` series:

```swift
// TrendsModel.reload() — additive, same pattern as the existing insulin/bsl fetch.
// intakeCarbs keeps (timestamp, value) pairs — a bare [Double] cannot feed
// either Day's per-entry TrendsChartPoint or Week/Month's dailyBuckets, both
// of which need a date per sample.
private(set) var intakeCarbs: [DatedValue] = []
...
let intakeEvents = (try? await store.events(in: iv.start...iv.end, type: EventType.intake)) ?? []
intakeCarbs = intakeEvents.compactMap { event in
    event.value.map { DatedValue(date: event.timestamp, value: $0) }
}
```

`recomputeSeries` folds `meals` and `intakeCarbs` into one series per range:
- **Day**: `carbBars = meals.map { TrendsChartPoint(date: $0.createdAt, value: carbTotal($0)) } + intakeCarbs.map { TrendsChartPoint(date: $0.date, value: $0.value) }` — one bar per entry regardless of source, same as today's per-meal bars.
- **Week/Month**: `let carbSamples = meals.map { DatedValue(date: $0.createdAt, value: carbTotal($0)) } + intakeCarbs`, then the existing single `TrendsMath.dailyBuckets(carbSamples, ...)` call — meal and intake samples are combined *before* bucketing, so a day's bucket total is one number regardless of how many sources contributed to it.

This is one series, not two, so Req 6.2's "same carb series" holds structurally. `carbTotal(_:)` stays meal-only (it takes a `MealRecord`); intake rows are read via `Event.value` directly, which is already the validated carb figure written at save time — no separate helper needed beyond the `DatedValue` mapping above. This adds a fourth `events(in:type:)` call to `reload()` (alongside the existing meal/bsl/insulin fetches) — the same per-tick cost class as the insulin fetch already pays, not a new query pattern.

### Records integration (Req 6.1, 7.3 seam)

Per home-router Decision 12/14, `RecordRow` gains `.intake(IntakeRecord)` — owned by this spec. `IntakeRecord` wraps `IntakeEntry` plus the display contract home-router's `RecordsView` needs (a display value and type label), so home-router's row renderer stays agnostic to intake's category set:

```swift
// RecordRow (MealRouting.swift) — additive case + its two switch arms, owned
// by this spec. RecordRow.id is String (not UUID — the enum's existing
// contract), so the new arm converts.
enum RecordRow: Identifiable {
    case meal(DisplayMeal)
    case insulin(InsulinEntry)
    case glucose(GlucoseRow)
    case intake(IntakeRecord)   // added by this spec

    var timestamp: Date {
        switch self {
        ...                              // existing arms unchanged
        case .intake(let record): record.timestamp
        }
    }
    var id: String {
        switch self {
        ...                              // existing arms unchanged
        case .intake(let record): record.id.uuidString
        }
    }
}

struct IntakeRecord: Identifiable, Equatable {
    let entry: IntakeEntry
    var id: UUID { entry.id }
    var timestamp: Date { entry.timestamp }
    var displayValue: String { "\(Int(entry.carbsG.rounded())) g" }
    // Only .carb ships in this spec (Decision 6 / home-router Decision 14),
    // so the label is a plain constant, not a branch pre-guessing a subtype
    // ("alcohol") this spec does not implement.
    var typeLabel: String { "Carbs" }
}
```

`RecordsModel.reload()` gets one additive merge line (`loadIntake()` alongside `loadMeals()`/`loadInsulin()`/`loadGlucose()`, same `events(in: Self.allTime, type: EventType.intake)` shape as `loadInsulin`, decoded via `RecordsModel`'s own private `intakeEntry(from:)` — see Decode ownership above), and `RecordsModel.delete(_:)` gets one additive case calling `store.deleteIntakeEntry(id:)`. This makes manually-added entries deletable from Records (satisfying the "delete reachable" half of Req 7.3 through the surface home-router already built) — but Req 7.1–7.2's edit list and inline edit/delete affordance (Req 7.5) are this spec's own surface, not Records; Records' delete-only stance (home-router Decision 4) does not extend edit capability, so the dedicated list below is where editing actually lives.

Both touch points are files this spec already owns changes in (`MealRouting.swift`, `RecordsModel.swift`) per home-router's stated low-collision seam. One home-router file is necessarily touched after all: `RecordsView.swift`'s row renderer switches exhaustively over `RecordRow`, so adding the `.intake` case forces a rendering arm there (and Req 6.1 needs a visible row anyway) — a small additive arm, not a reworking of the surface. *(Amended at implementation: the original "no home-router file changes" claim was wrong on this point.)*

### Views (Req 1, 2, 3, 4, 5, 7)

`IntakeView.swift` is replaced wholesale (home-router Decision 12 already documents this). New files, following the `InsulinDoseModel`/`InsulinDoseSheet` split exactly:

| File | Role |
|---|---|
| `App/IntakeView.swift` | Replaced. Hosts a quick-add grid — one button per preset, labelled with the preset's `name` (Req 3.1) — plus an "Enter amount" affordance opening `CarbEntrySheet` and the recent-entries list (Req 5.1). `NavigationStack` + `CloseCoverButton`, same shell as today's placeholder. |
| `App/IntakeModel.swift` | `@Observable @MainActor`. Loads/reloads presets and recent entries, owns quick-add tap → save, owns delete. |
| `App/CarbEntrySheet.swift` | The manual-entry sheet (Req 1, 2). Mirrors `InsulinDoseSheet`: plain `.sheet(.medium)`, `NavigationStack`, `CloseCoverButton`-free (sheets drag-dismiss per the insulin precedent). |
| `App/CarbEntryModel.swift` | `@Observable @MainActor`. Owns the sheet's amount/macros/timestamp state and save/update. Reused for both "new entry" and "edit entry" (Req 7.2) via an optional `editing: IntakeEntry?` init param. |
| `App/QuickPresetEditSheet.swift` | Create/edit a preset (Req 4.1, 4.2, 4.4). Same field set as `CarbEntrySheet` minus the timestamp, plus a name field. |

**Carb-entry sheet input affordance (Req 1.1, 1.4):** the insulin sheet uses a +/− stepper because 1–60 U is a narrow range where single-unit taps make sense. 1–999 g is two orders of magnitude wider — a stepper would need ~200 taps to reach a typical 180 g meal. `CarbEntrySheet` uses a numeric keypad field (`TextField` with `.keyboardType(.numberPad)`), matching Req 1.1's "input affordance suited to the carbohydrate range rather than the insulin stepper." Save is disabled below 1 g and the field clamps entry to 999 (Req 1.4); no stepper controls.

**Timestamp (Req 1.2):** reuses `InsulinDoseSheet.timeRow`'s exact `DatePicker(selection:in: ...Date(), displayedComponents: [.date, .hourAndMinute])` pattern — defaults to `Date()`, back-dateable, no future dates.

**Macro disclosure (Req 2.1, 2.2, 2.4):** three optional fields behind a `DisclosureGroup`. For a *new* entry it starts collapsed (Req 2.1's default path). For an *edit* (`CarbEntrySheet(editing:)`), `CarbEntryModel.init` sets the disclosure's initial expanded state to `editing.macros != IntakeMacros()` — an entry that already has any macro opens with the disclosure expanded, so Req 2.4 ("captured macros SHALL display in the entry's detail/edit view") is satisfied on open, not hidden behind a collapsed control the user must know to tap. Each field is a `TextField(.numberPad)`; empty text maps to `nil` in `IntakeMacros`, not `0` (Req 2.3) — the model reads `Double(text)` only when `text` is non-empty.

**Quick-add tap (Req 3.2):** `IntakeModel.tapPreset(_:)` calls `store.saveIntakeEntry` directly with `source: .quickadd, presetID: preset.id`, no sheet, no confirmation — a single async call from the button action.

**Save-as-preset (Req 4.4):** `CarbEntrySheet` gains a secondary action, "Save as quick-add," visible after a successful save (or as a menu item alongside Save) that opens `QuickPresetEditSheet` pre-filled with the just-entered values and prompts for a name. The two saves are independent: the entry (Req 1.3) is already committed by the time this sub-sheet opens, so cancelling `QuickPresetEditSheet` leaves the entry as-is and simply creates no preset — nothing to roll back. Preset names are not unique-constrained (the `quick_presets` table above has no `UNIQUE` on `name`); the design accepts duplicate preset names rather than adding collision UI, consistent with Decision 6's flat/minimal bias.

**Recent-entries list + inline edit/delete (Req 7.1, 7.5):** a `List` section in `IntakeView` below the quick-add grid, `.swipeActions` for delete (same interaction as `RecordsView`/home-router Decision 8 — no confirmation dialog) and a tap-to-edit that opens `CarbEntrySheet(editing: entry)`. `IntakeModel.recentEntries` reloads after any local mutation (own writes) — no `eventsDidChange` subscription needed since this view is the only writer of intake rows during a session, but subscribing costs nothing and keeps parity with `RecordsModel`/`MealHistoryModel` if a future surface also writes intake rows; **decision: subscribe**, for consistency with every other App-layer model in the codebase rather than as a special case.

### Home-router seam (Req 5.2)

Home-router already presents `IntakeView()` from `ActiveSheet.intake` (`AppRoot.swift:102-103`) — no changes needed there; this spec only replaces the body of `IntakeView.swift`. Since home-router has already landed on this branch (unlike the "temporary entry point" the requirements anticipated for the parallel-development case), Req 5.2's fallback clause is moot: the `intake` route already exists.

## Data Models

Summarised above: `EventType.intake`, `IntakeEntry`, `IntakeMacros`, `IntakeSource`, `IntakeSubtype` (Persistence module); `QuickPreset` (Persistence module, new `quick_presets` table) — extended by Req 8 with `sourceMealID: UUID?` / `source_meal_id TEXT` and the `QuickPreset.nextSortOrder(after:)` static; `IntakeRecord` (App layer, `MealRouting.swift`, wraps `IntakeEntry` for the `RecordRow.intake` case), joined there by the shared `quickPresetDraft(...)` builder.

## Error Handling

`PersistenceError.intakeCarbsOutOfRange(Double)` — new case, thrown by `saveIntakeEntry`/`updateIntakeEntry` for `carbsG` outside `1.0...999.0` (Req 1.4), mirroring `insulinUnitsOutOfRange`. The UI never triggers this in practice because `CarbEntryModel` disables Save below 1 g and clamps text entry at 999, but the store validates independently (same belt-and-braces the insulin store keeps despite the UI's own floor).

No new failure modes for presets or Records integration — preset CRUD failures are best-effort/silent on the write path (matching `MealHistoryModel.delete`'s "best-effort, next tick corrects" pattern), and the `RecordRow.intake` merge reuses `RecordsModel`'s existing `(try? …) ?? []` fallback shape.

Req 8 adds none either: the `store.quickPresets()` fetch behind the save-as-preset action uses the same `(try? …) ?? []` fallback (an empty list yields `sortOrder` 0, which is wrong only in ordering, never in correctness), and the preset write itself is `QuickPresetEditSheet`'s existing save path with its existing error text.

## Testing Strategy

Per the MVP test gate (build + on-device; no app-target test scaffolding — `docs/agent-notes/ui-capture-flow.md`, `testing-mvp-minimal`). `saveIntakeEntry`/`updateIntakeEntry`/`deleteIntakeEntry`/`quickPresets` CRUD land in `MedataCore/Sources/Persistence`, which the committed `make test` suite does cover for its existing store methods (`insulinUnitsOutOfRange` etc. have XCTest/swift-testing coverage today) — new store-layer methods should get the same treatment as a natural extension of that existing, executed suite. Everything in `App/` (views, `IntakeModel`, `CarbEntryModel`) is verified by build + on-device per the project convention; no new UITest-target files.

**On-device verification checklist:** Intake opens from Home (5.1); quick-add tap writes instantly, no sheet (3.2); manual sheet keypad accepts 1–999, rejects outside that range, Save disabled <1 g (1.4); macro disclosure starts collapsed for a new entry and expanded when editing an entry that has macros, empty fields save as absent not zero (2.1–2.3); never in Graph/totals; default presets present on first launch (3.3); create/edit/delete a preset, persists across relaunch (4.1–4.3); "save as preset" from a manual entry prompts for a name (4.4); recent-entries list supports inline swipe-delete and tap-to-edit with no intermediate screen (7.1, 7.5); editing an entry's amount/macros/timestamp persists and Graph + totals refresh (7.4); manual and quick-add entries appear in Records as `.intake` rows and are deletable there too (6.1, home-router seam); manual carbs sum into the same Graph carb bars as photo meals, Day and Week/Month (6.2).

**On-device verification checklist (Req 8):** "Save as quick-add" appears in the post-capture review menu and in the Result menu from records (8.1, 8.5 — including on a very-low-confidence and on a stub-segmenter result); the sheet opens pre-filled with the total the surface was showing and with a name built from the detected foods, both editable (8.2); correct a row or change the plate fraction first and confirm the *corrected* total is what pre-fills, not the original estimate (8.3); the macro disclosure opens collapsed and empty (8.4); the new tile appears on Intake next time it opens, and one tap on it writes an intake row with no sheet and no meal record (8.6, 8.7); delete the originating meal from Records and confirm the preset and its value are untouched (8.8); edit that preset's name, relaunch, and confirm it still carries its `source_meal_id` — check with `sqlite3` against the on-device DB, since nothing surfaces it (8.9); a DB carried over from a schema-8 build gains the column and its presets survive with `source_meal_id` NULL.

**PBT candidate, not built:** `TrendsModel`'s merge of `meals` + intake carbs into one bucketed series has a real invariant (bucket totals equal the sum of all contributing samples regardless of source), but it lives in the App-layer `TrendsModel`, which no harness executes — same accepted gap as home-router's Records-merge note. Recorded here for the same reason.
