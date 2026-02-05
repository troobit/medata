# MeData Implementation Plan

**Status:** Not Started
**Last Updated:** 2026-02-05
**Requirements Version:** 1.2

---

## 1. MVP Definition

The Minimum Viable Product focuses on **food macro capture via photography** with a **clean, minimal UI**. This is the primary use case and must work well before expanding to other features.

### MVP Priorities

1. **Photo → Macro Estimation** — The core value proposition
2. **Clean, frictionless UI** — Mobile-first, minimal taps
3. **Save and review meals** — Persistent meal history
4. **Manual entry fallback** — Always able to log without AI
5. **Presets** — Quick logging of frequent meals
6. **Label scanning** — Accuracy for packaged foods

### MVP Out of Scope

These features are deferred until MVP is validated:

- Insulin logging
- BSL readings and CGM import
- Exercise tracking
- Alcohol tracking
- Visualisation/graphs
- Dose suggestions/modelling
- Profile management
- Data export

---

## 2. Implementation Phases

### Phase 1: Project Scaffold & Branding

**Goal:** Bootable SvelteKit app with clean UI shell and branding.

| Task | Requirements | Deliverable |
|------|--------------|-------------|
| SvelteKit 2.x + Svelte 5 setup | - | Working dev server |
| TypeScript strict mode | Constitution §6.4 | `tsconfig.json` |
| Tailwind CSS 4.x | Constitution §10 | Styling configured |
| **Integrate existing logo** | Constitution §10.2 | Logo in app shell header |
| **Configure favicons** | - | Link `static/favicon-default.svg` in `app.html` |
| **PWA manifest** | NF.5 | `manifest.json` with icon variants from `static/` |
| Clean app shell | 9.1, 9.2, 9.4 | Mobile-first layout with 44px tap targets |
| Home page with action buttons | Design §7.5 | Capture, Manual Entry, Presets buttons |
| Environment config | 11.1 | `.env.example` with AI provider keys |

**Static Assets Available:**
- `static/icon.svg` — Main logo (#63ff00 green "d")
- `static/favicon-default.svg` — Default favicon
- `static/favicon-colour.svg` — Rainbow gradient variant
- `static/favicon-contrast.svg` — High contrast variant
- `static/favicon.ico` — Binary fallback

**Exit Criteria:** `npm run dev` starts, app shell renders on mobile with logo, installable as PWA.

---

### Phase 2: Photo Capture & AI Recognition

**Goal:** Photograph food, get macro estimates with clean result display.

| Task | Requirements | Deliverable |
|------|--------------|-------------|
| Camera capture component | 1.1, 1.2, 1.5 | `CameraCapture.svelte` |
| Image preview with retake | 1.3, 1.4 | `ImagePreview.svelte` |
| Gallery upload fallback | 1.6 | File input for existing photos |
| AI provider interface | Constitution §11 | `IFoodRecognitionService` |
| Claude implementation | 2.1, 2.8 | `ClaudeFoodService.ts` |
| Fallback to manual on AI failure | 2.7, 2.10 | Error state → manual entry |
| Food recognition result UI | 2.2, 2.3, 2.4, 2.5 | `FoodRecognitionResult.svelte` |
| API route | Design §3.3 | `POST /api/ai/recognise` |

**Exit Criteria:** User photographs meal → sees itemised macro breakdown with confidence scores → can proceed to edit/save.

---

### Phase 3: Edit, Review & Save Flow

**Goal:** Frictionless editing of AI estimates and saving meals.

| Task | Requirements | Deliverable |
|------|--------------|-------------|
| Meal editor component | 3.6, 5.1, 5.2 | `MealEditor.svelte` |
| Food item cards with large tap targets | 3.7, 5.2, 9.2 | `FoodItemCard.svelte` |
| Add/remove food items | 3.2, 5.3, 5.4 | Item management UI |
| Auto-recalculate totals | 3.3, 5.5 | Derived totals on edit |
| Timestamp adjustment | 4.4, 4.5 | Default now, allow backdate |
| Save confirmation | 4.6, 9.3 | Toast: "Meal saved" |
| Zod validation schemas | 3.4, 10.3, 10.5 | `src/lib/schemas/` |

**Exit Criteria:** User can modify any AI estimate, add/remove items, and save in ≤3 actions.

---

### Phase 4: Meal Storage & History

**Goal:** Persist meals and display history in logbook.

**Research Tasks (before implementation):**
- **Cosmos DB partition strategy:** Validate day-based partition key performance for date range queries using Azure documentation
- **Image upload orchestration:** Research best practice for capture → upload → AI → save flow

| Task | Requirements | Deliverable |
|------|--------------|-------------|
| **Research: Cosmos DB partitioning** | Design §1.5 | Validated partition strategy |
| **Research: Image upload flow** | Design §1.5 | Documented sequence |
| Cosmos DB connection | Design §4.2 | Repository implementation |
| Meal repository | 4.1, 4.7, 4.8 | `IMealRepository` |
| Meal API endpoints | Design §4.4 | `POST/GET/PUT/DELETE /api/meals` |
| Server-side image upload | 4.3, 11.2 | `POST /api/images/upload` |
| Logbook list view | 8.1, 8.2 | `LogbookList.svelte` |
| Meal detail/expand | 8.3, 8.6 | `MealDetail.svelte` |
| Edit saved meals | 8.4 | Edit from logbook |
| Delete meals | 8.5 | Delete from logbook |
| Data integrity timestamps | 10.1, 10.2 | createdAt, updatedAt |

**Exit Criteria:** Meals persist to Cosmos DB, viewable in chronological logbook, editable after save. Design refined based on research findings.

---

### Phase 5: Manual Entry Mode

**Goal:** Standalone manual entry without requiring a photo.

| Task | Requirements | Deliverable |
|------|--------------|-------------|
| Manual entry form | 3.1, 3.5 | `ManualEntryForm.svelte` |
| Name + carbs + protein + fat fields | 3.1 | Minimal form |
| Multiple items per meal | 3.2 | Add items to meal |
| Direct save flow | 4.2 | source: 'manual' |

**Exit Criteria:** User can log a meal via manual entry without taking a photo.

---

### Phase 6: Meal Presets

**Goal:** Save and reuse frequent meals for quick logging.

| Task | Requirements | Deliverable |
|------|--------------|-------------|
| Preset repository | Design §3.3 | `IPresetRepository` |
| Preset API | Design §4.4 | `POST/GET/PUT/DELETE /api/presets` |
| Save meal as preset | 6.1, 6.2 | From meal editor |
| Preset list view | 6.3 | `PresetList.svelte` |
| Apply preset to new meal | 6.3, 6.8 | One-tap → meal editor |
| Edit/delete presets | 6.4, 6.5 | Preset management |

**Exit Criteria:** User can save "Morning Cereal" and log it in one action next time.

---

### Phase 7: Label Scanning (Unified Flow)

**Goal:** Improve accuracy for packaged foods via nutrition label context.

| Task | Requirements | Deliverable |
|------|--------------|-------------|
| "Add Label" button in capture | 7.1 | Optional label photo |
| Unified AI endpoint | 7.2, 7.4, 7.5 | Food + label → accurate macros |
| Serving estimation from food photo | 7.4 | AI estimates portions |
| Fallback on parse failure | 7.6 | → manual entry |

**Exit Criteria:** Photograph packaged food + label → accurate macros based on label data and portion estimate.

---

## 3. Post-MVP Phases

These are planned but not detailed until MVP is validated.

| Phase | Features | Spec Reference |
|-------|----------|----------------|
| **8** | Insulin logging (3-action flow) | spec FR-01 |
| **9** | BSL manual entry | spec FR-03 |
| **10** | CGM CSV import (Libre, Dexcom) | spec FR-20-24 |
| **11** | BSL visualisation | spec FR-40-44 |
| **12** | Exercise tracking | spec FR-04, FR-35 |
| **13** | Alcohol tracking | spec FR-05, FR-16-19 |
| **14** | User profile management | spec FR-45-48 |
| **15** | Modelling & dose suggestions | spec FR-50-62 |
| **16** | Data export | spec FR-72-76 |

---

## 4. Technical Decisions

| ID | Decision | Rationale | Status |
|----|----------|-----------|--------|
| D1 | SvelteKit 2.x + Svelte 5 | Modern reactive framework, runes syntax | Decided |
| D2 | TypeScript strict mode | Type safety, catch errors at compile time | Decided |
| D3 | Azure Cosmos DB | Flexible document model, good free tier | Decided |
| D4 | Azure Blob Storage | Server-side upload, 30-day TTL | Decided |
| D5 | Zod validation | Runtime validation at API boundaries | Decided |
| D6 | Multi-provider AI | User choice, provider redundancy | Decided |
| D7 | mmol/L only | Simplifies logic, Irish/UK standard | Decided |
| D8 | Repository pattern | Storage-agnostic, testable | Decided |
| D9 | Irish English | User localisation preference | Decided |
| D10 | Existing logo from static/ | Brand assets already designed | Decided |

---

## 5. Requirements Traceability

### Specification → Requirements Mapping

This table maps specification.md FR-* IDs to requirements.md sections for the MVP scope.

| Spec ID | Requirements Section | Description |
|---------|---------------------|-------------|
| FR-02 | 4.x (Meal Storage) | Record meals with macros |
| FR-10 | 2.1-2.10 (AI Recognition) | Photo → food identification |
| FR-11 | 2.3 | Confidence scores |
| FR-14 | 7.x (Label Scanning) | Nutrition label parsing |
| FR-30 | 6.1 | Save as preset |
| FR-31 | 6.2 | Preset categories |
| FR-33 | 6.3 | Apply preset |
| NF-01 | 9.3 | ≤3 actions to save |
| NF-02 | 9.1, 9.2, 9.4 | Mobile-first UI |
| NF-05 | (PWA) | Installable on mobile |

### Requirements → Phase Mapping

| Req Section | Phase | Notes |
|-------------|-------|-------|
| 1.x (Photo Capture) | Phase 2 | Camera, preview, gallery |
| 2.x (AI Recognition) | Phase 2 | AI service, results UI |
| 3.x (Manual Entry) | Phase 3, 5 | Edit flow + standalone |
| 4.x (Meal Storage) | Phase 4 | Persistence, timestamps |
| 5.x (Review/Edit) | Phase 3 | Inline editing |
| 6.x (Presets) | Phase 6 | Save/apply presets |
| 7.x (Label Scan) | Phase 7 | Unified capture flow |
| 8.x (Logbook) | Phase 4 | History view |
| 9.x (UI) | Phase 1, all | Mobile-first, clean |
| 10.x (Data Integrity) | Phase 4 | Timestamps, raw values |
| 11.x (Security) | Phase 1, 4 | Env vars, server-side |
| NF.x (Non-functional) | Phase 1 | PWA, performance |

---

## 6. Current Status

**Current Phase:** Not Started

| Phase | Status | Notes |
|-------|--------|-------|
| Phase 1: Scaffold & Branding | Not Started | Logo + PWA setup |
| Phase 2: Photo & AI Recognition | Not Started | Core value prop |
| Phase 3: Edit, Review & Save | Not Started | Frictionless UX |
| Phase 4: Storage & History | Not Started | Research + Persistence |
| Phase 5: Manual Entry | Not Started | AI fallback |
| Phase 6: Presets | Not Started | Quick logging |
| Phase 7: Label Scanning | Not Started | Packaged food accuracy |

---

## Revision History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| 2026-02-03 | 2.0 | Claude | Complete rewrite: food-first MVP, requirements traceability |
| 2026-02-05 | 2.1 | Claude | Added static asset integration, PWA manifest, fixed requirement references to use requirements.md numbering, added spec→requirements mapping, reordered phases to prioritise photo capture and clean UI |
| 2026-02-05 | 2.2 | Claude | Added research tasks for Cosmos DB partitioning and image upload orchestration to Phase 4 |
