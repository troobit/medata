# SNAQ input study — flow map + gap analysis

Study of a collaborator's app (SNAQ) from 64 onboarding/UI screenshots in
`tmp/design/SNAQ onboarding flow images/` (IMG_0624–0688). Purpose: mimic SNAQ's UI and
flow where it serves Medata, keeping Medata's core offline, and identify which areas of
Medata a SNAQ-shaped build would touch. Classification done by four parallel sub-agents
(16 images each); this note is the consolidated, deduplicated result.

**Framing (from the mandate):** Medata is single-user, developer-phase, under clinical
supervision. The *suggestion* is the point — SNAQ's "not a medical device / not for insulin
dosing" disclaimers are explicitly **out of scope**. Glucose comes in live via a "connect
once, keep access" link; screenshot import is the fallback, not the goal. Barcode scanning is
de-prioritised; the text-description + lookup path and the fats/protein macro UI are in focus.

---

## Part 1 — Deduplicated flow map

64 images collapse to ~40 distinct screens. Two clusters: **onboarding/connection** and the
**live logging app**. Note the screenshots come from two accounts — one that connected a real
vendor CGM (FreeStyle Libre follower) and one that went pure Apple Health — so SNAQ supports
**both** glucose ingestion archetypes.

### A. Onboarding / device connection

| Step | Screens | What it does |
|---|---|---|
| Intended-use gate | 0624 | Legal disclaimer + "I will not use for insulin dosing" consent. **Medata rejects this.** |
| Country | 0628, 0627 (picker open) | Locale → drives units + which data sources are supported. |
| Glucose measurement type | 0625 | Branch: **CGM** / **BGM** / "I don't have a sensor". |
| CGM source picker | 0626 | dexcom, FreeStyle Libre, eversense, glooko, NIGHTSCOUT, Apple Health. |
| **Libre "connect once"** | 0629, 0630 | **Core pattern.** SNAQ generates a dummy identity (`snaq`/`snaq`/`libreNNNNN@snaq.io`, email copyable) that the user pastes into the Libre app → Connected Apps → LibreLinkUp as a follower. 0630 = "connecting… ~5 min, keep sharing on". 0634 is the public Notion help page reproducing this. |
| Apple Health glucose | 0640, 0641 | Alternative: read glucose from HealthKit (priming → OS sheet). |
| BGM routes | 0636 (Accu-Chek via MySugr→Health), 0637→0639→0638 (Contour Next One over BLE) | Secondary; not relevant to a Libre-first build. |
| **Sync hub checklist** | 0631, 0648, 0655 | **Backbone of onboarding.** Reusable vertical stepper: Glucose → Activity & Workouts → Weight → Nutrient Targets → Personalize Settings. Each step skippable via "Not now". Same screen, three progress states. |
| Activity/workouts import | 0642, 0632/0643 (priming) → 0644/0645 (OS Health sheet: Heart Rate, Steps, Workouts) | HealthKit read for exercise. |
| Birthdate | 0646 (picker), 0647 (set) | Personalisation input. |
| Weight import | 0649 (priming) → 0650/0651 (OS Health sheet: Weight, Body Fat) | HealthKit read for weight. |
| Nutrient targets | 0652 (loading, macro ring) → 0653 (plan: kcal + carb/protein/fat grams) → 0654 (adjust: kcal stepper + % sliders per macro) | Computes daily macro targets. **0654 is the fats/protein editing UI.** |
| Units personalisation | 0656 (mg/dl default), 0657/0660 (mmol/l), 0658/0659 (target-range editor) | mmol/l path matches Medata's metric-only invariant; mg/dl default is a US-account artefact to avoid. |

### B. Live logging app

| Surface | Screens | Notes |
|---|---|---|
| **Logbook (home/day view)** | 0661, 0662, 0686 (populated), 0687/0688 (empty days) | Launch surface. Week date-strip, three daily macro cards (Carbs/Protein/Fat + progress bars, 3-page carousel), and a reverse-chronological feed mixing **meals + glucose readings + weight** by timestamp. Search + calendar in header. |
| Bottom tab bar | (all logbook screens) | Logbook · Insights · centre "+" FAB · Coach · More. |
| Insights | 0663 | Nutrition analytics over 1W/1M/3M/6M: calories, macro %, and Carbs/Protein/Fat/Sugar/Fibre/Net-Carbs totals. Not a glucose line chart. |
| Quick-add sheet | 0664 | "+" FAB → Workout / Note / Weight / Glucose / Meal. Meal row has barcode + camera shortcut icons. |
| **Add-meal hub** | 0668, 0669/0671 (Custom empty), 0670 (Recent) | Text search ("Food, meal or brand") + 2×2 mode grid (Photo / Barcode / **Describe** / Saved Meals) + filter tabs **Frequent / Favourites / Custom / Recent**. Rows show emoji + name + serving + purple "C" carb badge. |
| **Describe (NL text)** | 0672 (placeholder), 0673 (typed "cheese sandwich"), 0674 (loading) | Free-text meal entry → parse → foods. The text-description path. |
| Results + suggestions | 0675, 0678 | Chosen food at top (carb "C" badge) + SUGGESTIONS list of related foods. Bottom bar: add-more search + barcode + camera. |
| Food detail | 0667 | Post barcode/lookup: emphasised Carbs + Weight cards, full macro list (Protein/Fat/Calories/Sugar/Fibre/Net-Carbs), serving stepper, **heart = favourite**, "+ Add". |
| Meal summary (3-panel carousel) | 0676/0679 (macros + Ingredients / Additional-Data chips), 0680/0681 (Eating tips + insulin-dosing consent checkbox) | Macro cards Carbs/Protein/Fat. "Additional Data" chips attach Glucose/Notes/Workouts to a meal. **Consent checkbox — Medata rejects.** |
| Meal name/time edit | 0677 | Rename + date/time. |
| Health write-back | 0682 (explainer) → 0683 (detail) → 0684 (OS sheet: Carbohydrates, Dietary Energy, Fibre) | Writes meal macros back to HealthKit. |
| Satisfaction modal | 0685 | Post-save "Are you satisfied with the summary?" Skip/No/Yes — estimate-quality feedback. |
| Label/barcode capture | 0665 (label), 0666 (barcode) | De-prioritised. |

### Duplicate clusters (safe to treat as one screen each)
0627≈0628 · 0629≈0634 (0634 is a help page) · 0638≈0639 · 0644≈0645 · 0646≈0647 ·
0648≈0655 (states of the hub) · 0650≈0651 · 0657≈0660 · 0658≈0659 · 0669≈0671 ·
0673≈0674 · 0675≈0678 · 0680≈0681 (checkbox state) · 0687≈0688.

### Design language to borrow
Bottom tab-bar navigation; card-based day view; **macro colour code Carbs=purple,
Protein=red, Fat=orange** (Sugar=dark-red, Fibre=green, Net-Carbs=magenta); per-item purple
"C" carb badge; the Add-meal hub as the single fan-out into every logging mode.

---

## Part 2 — Gap analysis (Medata today → SNAQ-shaped target)

Medata's current surfaces (all under `App/`): capture/estimation pipeline
(`CaptureFlowView`, `CapturePathDecider`, `PreShutterSegmenter`, `ARPreviewView`) →
results (`ResultView`, `SegmentationReviewView`, `ManualCorrectionView`, `ConfidencePill`)
→ records (`MealHistoryModel`, `MealOverviewView`, `DataView`, `InsulinDoseModel/Sheet`) →
Graph (`TrendsView/Model`) → glucose import (`GlucoseImportModel` — screenshot only) →
Settings/About. **No favourites/frequents surface exists.**

### 1. Glucose connection — the headline gap
**Today:** screenshot import only (`GlucoseImportModel` uses Photos/ImageIO to OCR a
LibreLink screenshot). **SNAQ:** live ingestion via (a) **LibreLinkUp follower** — the
"connect once, paste credentials, keep sharing on" pattern (0629/0630), or (b) **HealthKit
read** of glucose (0640/0641).

Central architectural decision (needs the user before a spec):
- **LibreLinkUp follower API** — matches the exact screens and the "connect once" ask; **requires network** for the sync, but is direct and works on any device the Libre app runs on.
- **HealthKit glucose read** — stays on-device (no network), but depends on the FreeStyle Libre app writing glucose to Apple Health (Libre 3 does). Also the natural mechanism for the later activity/weight reads (0642–0651).

**Invariant to respect:** "No network calls in the estimation path." A LibreLinkUp sync is
data *ingestion*, not estimation — allowed, but must be firewalled from the deterministic
estimation path. Worth stating explicitly in the spec.

**Touches:** new connection UI (a connect step + a Settings entry), a background sync/ingestion
service, `Persistence`/`GlucoseGraph` store (already exists), the Graph screen.
**Verdict:** its own spec-lane feature (`specs/data/` domain). Online for LibreLinkUp; the
offline core is untouched.

### 2. Favourites & frequents — net-new surface
**Today:** none. **SNAQ:** Frequent/Favourites/Custom/Recent filters on the Add-meal hub
(0668–0671), heart-toggle on food detail (0667), per-item carb badge. This is exactly the
user's "where a pint would go" — a saved quick-add.

**Overlaps existing work:** Track C `specs/data/manual-carb-intake` already scopes quicksets/
presets and an alcohol subtype (Decision 6 quicksets flat-vs-grouped is still open). The SNAQ
favourites/frequents model should fold into that spec rather than start a new one.
**Touches:** a saved-foods store (`Persistence`), the Add-meal/records UI, the intake taxonomy
(Track C). Fully offline. **Verdict:** extend Track C.

### 3. App recording / Logbook — mostly already in flight
**Today:** `MealHistoryModel`/`MealOverviewView`/`DataView`; Track B home-router already
scopes a unified Records timeline (spec complete). **SNAQ adds:** day-based navigation (week
strip), per-day macro totals, and glucose readings inline in the feed.
**Verdict:** feed the SNAQ day-view + daily-macro-totals patterns into Track B rather than a
new spec; the inline-glucose-in-feed idea depends on gap #1 landing. Offline.

### 4. Estimation pathways — additive text-lookup path
**Today:** photo/LiDAR carb estimation (deterministic CV). **SNAQ adds** three non-photo
entry modes: text search, **Describe (NL)**, and Saved Meals — all resolving against a food
database. Medata already bundles `cofid_db.sqlite` + `afcd_db.sqlite` locally.
- **Text search against the local DB** — straightforward, fully offline, high value. New entry
  path parallel to the camera; reuses the food DB. **In scope.**
- **NL "Describe" parse** — SNAQ parses free text into foods; Medata **cannot** use an LLM
  (hard invariant). A deterministic offline parser (quantity + food-name tokens → DB lookup)
  is possible but a real build effort. **Flag as a scoping decision**, likely a later spec;
  start with plain text search.
**Touches:** a new logging entry point, the food-DB query layer, the results/confirm UI.
**Verdict:** text search = its own small spec (offline); NL-describe deferred.

### 5. Fats/protein macro UI — data already present, display missing
**Today:** Medata is carb-focused. **SNAQ:** shows Carbs/Protein/Fat everywhere (day cards,
meal summary, food detail) with the colour code. The bundled DBs carry protein/fat/energy
columns, so this is a **display + record-model** change, not new estimation — protein/fat come
from DB lookup, not from CV. The estimation core stays carb-only.
**Touches:** the record model, `ResultView`/records UI, the design system's macro colours.
**Verdict:** folds into the Track B / records UI work. Offline.

### 6. UI / navigation shell
**SNAQ:** bottom tab-bar (Logbook/Insights/+/Coach/More), the "+" quick-add sheet, macro
colour coding, the Add-meal hub. Medata has its own `design-handoff-00` system and Track B is
defining the home/router. **Verdict:** borrow the tab-bar + quick-add-sheet + Add-meal-hub
patterns into Track B's router work; don't graft SNAQ's full chrome wholesale.

### Explicitly dropped (out of scope)
- All disclaimer/consent copy: intended-use gate (0624), the insulin-dosing checkbox
  (0680/0681). Contradicts the mandate **and** the developer-phase no-disclaimer rule.
- Privacy-reassurance copy ("we never share or sell your data") — same no-reassurance rule.
- Account/signup and paywall — none present; single-user.
- Heavy multi-step onboarding ceremony — "excessive handholding is overkill" for one developer.
  Keep the **glucose-connection step**; drop the rest of the checklist as gated onboarding.
- Barcode/label scanning (0665/0666) — de-prioritised by the mandate.
- BGM routes (Accu-Chek/Contour) — Libre-first.

### Future arc (user's longer goal, not this pass)
Read glucose + exercise + weight, combine with carb/insulin ratios, and suggest dosing
refinements. SNAQ already imports activity (workouts/HR/steps, 0642–0645) and weight/body-fat
(0649–0651) via HealthKit, and computes nutrient targets (0652–0654). If gap #1 chooses the
**HealthKit** route for glucose, the same bridge later covers activity + weight — a reason to
weigh HealthKit seriously now even though LibreLinkUp matches the screens more literally.

---

## User decisions (2026-07-10)
- **Glucose ingestion:** build a **connection abstraction** and spike both routes, but assume
  **HealthKit as the primary, extensible path** — device coverage grows as more CGMs write to
  Apple Health (e.g. FreeStyle Libre 3). The LibreLinkUp follower "connect once" pattern
  (0629/0630) is the complement/alternative for devices that don't yet write to HealthKit. The
  spec is explicitly expected to be **iterated upon** as device support expands.
- **Spec to open now:** `specs/data/cgm-connect` (new spec, ingestion/`data` domain). It is the
  **live-connection successor** to the existing `specs/data/libre-ingestion` (which is the
  *screenshot-OCR* import path, `GlucoseImportModel`) — creating-spec must set that boundary,
  not duplicate it. Firewall the (online) LibreLinkUp sync from the deterministic estimation
  path; HealthKit reads are on-device/offline.
- **Everything else folds into existing specs**, not new ones: favourites/frequents → Track C
  `manual-carb-intake`; day-view + daily macros + inline glucose + macro colours + tab-bar/Add-
  meal-hub shell → Track B `home-router`. Offline text-search lookup = a later standalone spec;
  NL-Describe stays deferred (no-LLM invariant).

## Routing recommendation (post-analysis)
The SNAQ build is not one feature — it fans into distinct pieces, most of which attach to
existing tracks:
1. **Live glucose connection** — new spec-lane feature (`specs/data/`), gated on the
   LibreLinkUp-vs-HealthKit decision. Highest-value, the true headline.
2. **Favourites/frequents ("where a pint goes")** — extend Track C `manual-carb-intake`.
3. **Day-view logbook + daily macro totals + inline glucose** — feed into Track B home-router.
4. **Text-search food lookup (offline)** — small standalone spec; NL-Describe deferred.
5. **Fats/protein display + macro colours** — folds into Track B / records UI.
6. **Tab-bar + Add-meal-hub navigation shell** — folds into Track B router work.
