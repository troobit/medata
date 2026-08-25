---
references:
    - specs/ui/shared-meal-components/requirements.md
    - specs/ui/shared-meal-components/design.md
    - specs/ui/shared-meal-components/decision_log.md
---
# Shared Meal Components

- [x] 1. ServingRows.swift — extract PlateFraction, amount button, gram editor, step logic; adopt in MealReviewView and ResultView <!-- id:6yhak35 -->
  - Requirements: [1.1](requirements.md#1.1), [1.2](requirements.md#1.2), [1.3](requirements.md#1.3), [1.4](requirements.md#1.4)

- [x] 2. MealReadouts.swift — CarbTotalBlock, CorrectedMarker, MealPhotoCard; adopt across the four marker sites and three total sites <!-- id:6yhak36 -->
  - Requirements: [3.1](requirements.md#3.1), [3.2](requirements.md#3.2), [3.3](requirements.md#3.3)

- [x] 3. SharedFormatting.swift — cached en_IE formatters, prettify, TimelineRow; adopt across six row/formatter sites <!-- id:6yhak37 -->
  - Requirements: [4.1](requirements.md#4.1), [4.2](requirements.md#4.2), [4.3](requirements.md#4.3)

- [x] 4. Carb-amount form unification — CarbAmountFields shared by LogSheet.CarbEntryContent and QuickPresetEditSheet <!-- id:6yhak38 -->
  - Cross-spec ordering: needs LogSheet from the insulin-dosing Decision 16 synthesis merge (specs/data/insulin-dosing tasks.md task 14) on research first
  - Requirements: [2.1](requirements.md#2.1), [2.2](requirements.md#2.2), [2.3](requirements.md#2.3)

- [x] 5. Entry-chrome adoption — QuickPresetEditSheet and DoseScheduleSettingsSection consume EntryTimeRow/EntrySaveButton; no private sheet chrome remains for consolidated modes <!-- id:6yhak39 -->
  - Cross-spec ordering: needs EntryChrome from the insulin-dosing Decision 16 synthesis merge (specs/data/insulin-dosing tasks.md task 14) on research first
  - Requirements: [5.1](requirements.md#5.1), [5.2](requirements.md#5.2)

- [x] 6. Remove MealHistoryModel.swift, its tests file and pbxproj entries <!-- id:6yhak3a -->
  - Requirements: [6.2](requirements.md#6.2)

- [ ] 7. Gate: make build-app, make test (both totals), make spell <!-- id:6yhak3b -->
  - Blocked-by: 6yhak35 (ServingRows.swift — extract PlateFraction, amount button, gram editor, step logic; adopt in MealReviewView and ResultView), 6yhak36 (MealReadouts.swift — CarbTotalBlock, CorrectedMarker, MealPhotoCard; adopt across the four marker sites and three total sites), 6yhak37 (SharedFormatting.swift — cached en_IE formatters, prettify, TimelineRow; adopt across six row/formatter sites), 6yhak38 (Carb-amount form unification — CarbAmountFields shared by LogSheet.CarbEntryContent and QuickPresetEditSheet), 6yhak39 (Entry-chrome adoption — QuickPresetEditSheet and DoseScheduleSettingsSection consume EntryTimeRow/EntrySaveButton; no private sheet chrome remains for consolidated modes), 6yhak3a (Remove MealHistoryModel.swift, its tests file and pbxproj entries)
  - Requirements: [6.1](requirements.md#6.1), [6.3](requirements.md#6.3)

- [ ] 8. STOP — device look: each surface renders as before, corrections persist identically <!-- id:6yhak3c -->
  - Blocked-by: 6yhak3b (Gate: make build-app, make test both totals, make spell)
  - Requirements: [6.1](requirements.md#6.1), [6.3](requirements.md#6.3)
