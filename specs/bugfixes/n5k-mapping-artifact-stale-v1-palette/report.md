# Bugfix Report: n5k-mapping-artifact-stale-v1-palette

**Date:** 2026-08-10
**Status:** Fixed

## Description of the Issue

The committed Nutrition5k mapping artifact (`tools/nutrition5k/mapping_n5k_to_palette.json`) still carried the superseded palette **v1** content list (32 classes) while `tools/food_db/generate.py`'s `FOOD_DATA` had moved to **v2** (33 classes, `cereal` appended at solid index 24). The committed test `test_palette_class_list_preserves_food_data_channel_order` had been red on the branch since the v2 promotion — the one known-failing test in the repo. Root of the drift: `tools/nutrition5k/mapping.py::parse_palette` still scoped its regex to the retained `v1Standard` declaration in `ClassPalette.swift`, so even a regeneration would have rebuilt the stale list. A latent second defect rode along: `tools/nutrition5k/ingest.py` never passed `palette_version` to `build_fixture_bytes`, stamping every emitted fixture with the default `"v1"` — after the parser retarget, checkpoint-mode fixtures would have carried 36-class tensors under a v1 stamp, which the harness resolves to a 35-class palette (a mismatch, though now a *reported* one since `seg-bench-silently-drops-mis-sized-fixtures`).

**Reproduction steps:**
1. `python3 -m pytest tools/nutrition5k/tests/test_mapping.py -q` on the base branch.
2. Observe `test_palette_class_list_preserves_food_data_channel_order` fail: artifact index 24 is `water` (v1) where the live palette has `cereal` (v2).

**Impact:** the artifact's palette lock — the guard that keys β baking to the current palette content — was asserting the wrong palette. Any real N5k calibrate run would carry v1-locked lineage against a v2 food database. Flagged in the metafood3d-ingestion agent note as owned by the nutrition5k/myfoodrepo boundary; fixed here as the boundary's first free slot.

## Investigation Summary

- **Symptoms examined:** the failing assertion (artifact vs `FOOD_DATA` channel order vs hardcoded expected list).
- **Code inspected:** `tools/nutrition5k/mapping.py` (`parse_palette` scoping to `v1Standard`), `build_mapping.py` (rebuilds from the parser + gitignored `data/metadata/ingredients_metadata.csv`, present in this checkout), `ingest.py` (fixture emission, no `palette_version` argument), `tools/segmenter/make_fixtures.py` (default `palette_version="v1"`), and the sibling `tools/metafood3d/mapping.py` (already v2-scoped via a `PALETTE_MARKER` constant — the pattern to mirror).
- **Hypotheses tested:** whether `FOOD_DATA` also lacked cereal (no — the first assertion against `generate.py` passes once the artifact is v2; the residual failures were stale hardcoded test expectations).

## Discovered Root Cause

The v2 palette promotion updated `generate.py` and `ClassPalette.swift` but not the n5k tool chain: its parser stayed pinned to `v1Standard`, its committed artifact was never regenerated, and its fixture stamp was never introduced. Palette version was effectively duplicated across four sites with no single lock.

**Defect type:** stale generated artifact + parser targeting a superseded declaration (cross-tool version drift).

**Why it occurred:** `ClassPalette.swift` deliberately retains `v1Standard` for the persisted-meal migration, so a `v1Standard`-scoped regex keeps parsing successfully — nothing failed loudly at the tool level; only the committed cross-check test caught it.

**Contributing factors:** the artifact regeneration needs the gitignored ingredients CSV, so the fix could only land from a checkout holding the dataset — which let the red stand across sessions.

## Resolution for the Issue

**Changes made:**
- `tools/nutrition5k/mapping.py` — `PALETTE_MARKER = "v2Standard"` (mirroring `tools/metafood3d/mapping.py`); `parse_palette` and docstrings retargeted.
- `tools/nutrition5k/mapping_n5k_to_palette.json` — regenerated from `data/metadata/ingredients_metadata.csv`: 555 ingredients (90 mapped, 4 ambiguous, 461 unmapped), `palette_class_list` now the v2 33-class list. Mapping rules unchanged — only the palette lock moved.
- `tools/nutrition5k/ingest.py` — new `PALETTE_VERSION = "v2"` constant passed to `build_fixture_bytes`, so emitted fixtures carry the palette their tensors are sized for.
- Test expectations updated to v2: `EXPECTED_SOLIDS` gains `cereal` (test_mapping), the fixture stamp assertion reads `v2` (test_ingest), `NUM_CLASSES = 36` (test_routing).

**Approach rationale:** identical scoping pattern to the metafood3d tool, so both dataset bridges read the same declaration the same way; regeneration rather than hand-editing keeps the artifact a deterministic output of its inputs.

**Alternatives considered:**
- Hand-edit the committed artifact JSON to the v2 list — rejected: the artifact is a generated file; hand edits break the regeneration contract and would leave the parser still pointed at v1 for the next rebuild.
- Leave the ingest stamp at the `"v1"` default — rejected: after the parser retarget, checkpoint-mode fixtures would emit 36-class tensors under a 35-class stamp; the harness would (now loudly) skip every one.

## Regression Test

**Test file:** `tools/nutrition5k/tests/test_mapping.py`
**Test name:** `TestArtifactContent::test_palette_class_list_preserves_food_data_channel_order`

**What it verifies:** the committed artifact's `palette_class_list` equals `generate.py`'s `FOOD_DATA` channel order and the v2 expected list. This pre-existing committed test *was* the red — no new test was needed; the fix is complete when it passes.

**Run command:** `python3 -m pytest tools/nutrition5k/tests -q`

## Affected Files

| File | Change |
|------|--------|
| `tools/nutrition5k/mapping.py` | `PALETTE_MARKER = "v2Standard"`; parser retargeted |
| `tools/nutrition5k/mapping_n5k_to_palette.json` | Regenerated against palette v2 |
| `tools/nutrition5k/ingest.py` | `PALETTE_VERSION = "v2"` stamped into fixtures |
| `tools/nutrition5k/tests/{test_mapping,test_ingest,test_routing}.py` | Stale v1 expectations updated to v2 |
| `docs/agent-notes/metafood3d-ingestion.md` | Pre-existing-red gotcha resolved |

## Verification

**Automated:**
- [x] The formerly red test passes; full n5k suite 56/56.
- [x] Neighbouring suites green: `tools/food_db/tests`, `tools/metafood3d/tests` (67 in venv), `tools/segmenter/tests`.
- [x] `make spell` passes.
- No Swift-side run needed: nothing in MedataCore/HarnessCore reads the artifact or these tools; the harness receives `--mapping-version` as an opaque string.

**Manual verification:**
- Confirmed baked-DB lineage (`calibration_mapping_artifact_version = 909f19f575a6`) is historical provenance of the bake that produced it, not a live pin — the regenerated artifact hash applies to future runs only.

## Prevention

**Recommendations to avoid similar bugs:**
- The palette version now has one committed cross-check per dataset tool (this test; the mf3d equivalent) — keep that pattern for any future dataset bridge.
- When promoting a palette version, grep for the *old* marker (`v1Standard`) across `tools/` — the retained declaration means stale regexes keep working silently.

## Related

- `specs/estimation/cross-dataset-calibration/` Decision 15 — the mf3d palette v2 retarget this mirrors.
- `specs/bugfixes/app-palette-drift-after-v2-promotion/` — the app-side drift from the same promotion.
- `specs/bugfixes/seg-bench-silently-drops-mis-sized-fixtures/` — why a stamp/tensor mismatch is now a reported skip rather than a silent drop.

---

**Postscript (2026-08-10, pipeline Decision 50)**: the retained `v1Standard`
declaration this parser mis-scoped to has been expunged along with the whole
v1/v2 iteration; the palette is the single `ClassPalette.standard`, stamped
"v0" until the first main release. The retained learning: a tool that
regex-parses a source file must anchor on an unambiguous declaration marker
(`static let standard`), and artifacts must lock on palette *content*, not
labels — both now hold across food_db, nutrition5k, and metafood3d tooling.
