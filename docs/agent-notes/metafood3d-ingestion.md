# MetaFood3D ingestion (tools/metafood3d/)

Stream 1 of the cross-dataset-calibration spec: mapping artifact +
render + `ingest.py` bridging MetaFood3D single-food meshes into
`.fixture` files (single-class **mixture** rows, Decision 11).

## Palette target (Decision 15 — load-bearing)

The spec was planned against palette v1 but everything here targets the
**v2 content list** (`ClassPalette.v2Standard`: 25 solids with `cereal`
at index 24, 8 liquids). β is keyed by class NAME end-to-end (fixture
GT-mass map, `MixtureBetaCalibrator` dicts, `generate.py`
UPDATE-by-class_id), so channel ordering only matters for probability
tensors — which mixture fixtures never carry. `mapping.py` parses the
`v2Standard` marker (same scoping pattern as `generate.py`'s lock);
fixtures are stamped `palette_version="v2"`.

## Layout

- `mapping.py` — loader for `mapping_metafood3d_to_palette.json`; fails
  loudly on palette-content mismatch. Categories are compared in
  normalised snake_case (`normalise_category`) because the gated
  dataset's exact folder spellings are unverified.
- `build_mapping.py` — curated category→class rules. **Curated-only
  artifact**: MetaFood3D has no public category enumeration, so the
  committed artifact's universe is the rules themselves
  (`categories_source: "curated_rules_only"`). Regenerate with
  `--categories-file` when the dataset lands — that enables the
  stale-rule abort and records the enumeration SHA-256. Ingest tolerates
  partial snapshots: artifact-unknown categories are excluded + counted
  (Req 1.4), never aborted on.
- `render.py` — CPU ray-cast (trimesh pure-numpy intersector, Decision
  12). Camera at origin, +z = depth axis; **z-depth**, not ray length
  (intrinsics unprojection assumes z-depth); Float32 LE mm, 0 = miss.
  Pinned config = N5k D435 nominal 640x480, plane 385 mm.
- `derive_metadata.py` — stdlib-only (zipfile + ElementTree, no
  openpyxl) workbook → `metadata.csv` derivation. RIGID (Decision 19):
  accepts exactly the known nine-column v2 header, aborts showing
  found-vs-expected otherwise. Column names are inverted:
  `Object_name` = category, `Food_Type` = object. Weights pass through
  verbatim — ingest judges malformedness.
- `ingest.py` — seats each mesh in its most probable
  `compute_stable_poses` pose, flips it under the camera (rotation about
  x, so no reflection), renders, composites misses to the plane, emits
  via the shared `make_fixtures.build_fixture_bytes`. Writes
  `run_summary.json` + `metafood3d_truth.json` ({fixture_id:
  mesh_volume_mm3}, for the Req 2.3 volume-fit diagnostic).

## Rigid snapshot layout (Decision 19)

The required `--mf3d-dir` layout is the shipped mesh archive extracted
verbatim plus the derived metadata — nothing rearranged:

    <mf3d-dir>/3D_Mesh/<Category>/<object>/   # exactly ONE mesh file
                                              # (.obj|.ply|.glb|.off);
                                              # .mtl/texture siblings OK
    <mf3d-dir>/metadata.csv                   # derive_metadata.py output

Structural deviations (stray files at category/object level, 0 or >1
mesh files in an object dir, missing/mis-headed metadata.csv) are HARD
errors that print the expected tree + the exact fix commands — never
silent skips, never tolerant discovery. Object identity is the directory
pair: object dir names repeat across categories in the real snapshot
(`almond_3` under both `Almond(bowl)` and `Almonds`), so every emitted
id (fixture filename, skip lists, truth sidecar) is
`<Category>__<object>` in raw on-disk names.

## Contracts stream 2 consumes

*(Corrected 2026-08-09, Decision 17 — the earlier version of this table
listed `snapshot_identifier` and a bare-`width`/`height` render_config,
which the Swift decoder never read; that stale shape is superseded.)*

- Fixtures: `estimator_path="mixture"`, sha `"no_segmenter"`, no probs,
  single-entry `ground_truth_class_mass_g`, `source_dataset=
  "metafood3d@<12-hex snapshot>"`, gravity (0,0,-1).
- `run_summary.json` — canonical keys are what
  `CalibrateRun.loadIngestSummary` decodes, and it EXITS 1 when any is
  missing on a metafood3d summary: `snapshot`, `mapping_version` (first
  12 hex of the mapping artifact's SHA-256), `licence`, and
  `render_config: {plane_depth_mm, intrinsics_model, image_width,
  image_height, seating_rule}` (plus `noise: noise_free_render`,
  Req 2.5). `authored_support_plane` (plane_depth_mm 385 + frame
  convention) rides the summary for the Decision 13 injected-plane
  branch — the fixture proto has NO support-plane field. Exclusions:
  `unmapped_excluded`/`ambiguous_excluded` {category: [ids]} + counts.
  The contract is pinned by the emitter-generated committed fixture
  `tests/fixtures/run_summary_contract.json` (regenerate with
  `tests/make_contract_fixture.py`): pytest diffs it against
  `ingest._summary_doc`, and `EndToEndCalibrateBakeTests` feeds the same
  file to the built HarnessCLI — change any key and one side goes red.
- Metric-scale gates (Decision 14) abort BEFORE emitting: unit-sanity
  (median bbox max extent in [20, 600] mm) and weight plausibility
  (implied bbox density in [0.05, 2.0] g/cm³); the failure block lands
  in `run_summary.json` under `scale_check_failed`.

## Dataset facts (verified 2026-08-10, real snapshot)

- Access **obtained 2026-08-10** (request-gated: Google Form + password)
  at <https://lorenz.ecn.purdue.edu/~food3d/> (TLS cert of that host
  fails verification — fetch with care). Licence is **CC BY-NC 4.0
  (non-commercial)**; commercial use governed by Decision 18 (research
  βs free; commercial ship = NC-free re-bake or commercial licence).
- The v2 nutrition workbook holds **637 objects / 108 categories** —
  the site's claimed counts, not the arXiv paper's 743/131. The
  workbook IS the category enumeration `build_mapping.py
  --categories-file` needs.
- Real category names carry parentheses and case (`Almond(bowl)`);
  `normalise_category` keeps parens (`almond(bowl)`), so curated rules
  written without them won't match those categories until the mapping is
  regenerated against the real enumeration.
- Downloads live in gitignored `data/` (never committed, Req 1.2):
  mesh + point-cloud tarballs, the v2 workbook, `_MetaFood3D_Readme.txt`.
  Only meshes + workbook + readme have consumers; renders/videos/point
  clouds are unused.
- Meshes assumed millimetres; a metre/centimetre snapshot trips
  unit-sanity and the conversion belongs in `derive_metadata.py`.

## Gotchas

- **Module/test name collisions.** File names deliberately mirror
  `tools/nutrition5k/` (design parity table), so the tool dir must NOT
  go on `sys.path` (the tests' conftest doesn't add it — unlike n5k's);
  tool modules import each other and are imported by tests via unique
  `metafood3d_<name>` sys.modules keys (`mf3d_testkit.load_tool`).
  Test basenames are `test_mf3d_*.py` for the same reason.
- **Venv:** `tools/metafood3d/.venv` (gitignored; requirements.txt has
  trimesh/scipy/rtree/hypothesis). Mapping tests run on system python;
  render/ingest tests `importorskip("trimesh")` and skip there — run the
  full set with `tools/metafood3d/.venv/bin/python -m pytest
  tools/metafood3d/tests`.
- **Pre-existing red (not this stream):**
  `tools/nutrition5k/tests/test_mapping.py::TestArtifactContent::
  test_palette_class_list_preserves_food_data_channel_order` fails on
  the base branch — the committed n5k artifact still carries the v1
  content list while `generate.py` FOOD_DATA moved to v2 (cereal).
  Fixing it means retargeting n5k's `parse_palette` to `v2Standard` and
  regenerating its artifact from the gitignored ingredients CSV (main
  checkout only).
- `generate.py` persists the cross-dataset meta dicts
  (`calibration_contributing_datasets_per_class`,
  `calibration_single_source_classes`) for APPLIED classes only — a
  reference-skipped β is not baked, so its provenance is not recorded as
  if it were. Pinned by
  `tools/food_db/tests/test_cross_dataset_persistence.py` (task 21) and
  end-to-end by `EndToEndCalibrateBakeTests` (task 23).
