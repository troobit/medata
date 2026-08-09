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
- `ingest.py` — seats each mesh in its most probable
  `compute_stable_poses` pose, flips it under the camera (rotation about
  x, so no reflection), renders, composites misses to the plane, emits
  via the shared `make_fixtures.build_fixture_bytes`. Writes
  `run_summary.json` + `metafood3d_truth.json` ({fixture_id:
  mesh_volume_mm3}, for the Req 2.3 volume-fit diagnostic).

## Contracts stream 2 consumes

- Fixtures: `estimator_path="mixture"`, sha `"no_segmenter"`, no probs,
  single-entry `ground_truth_class_mass_g`, `source_dataset=
  "metafood3d@<12-hex snapshot>"`, gravity (0,0,-1).
- `run_summary.json`: `authored_support_plane` (plane_depth_mm 385 +
  frame convention) for the Decision 13 injected-plane branch — the
  fixture proto has NO support-plane field, so the plane rides the
  summary. Also `render_config` (incl. `noise: noise_free_render`,
  Req 2.5), `unmapped_excluded`/`ambiguous_excluded` {category: [ids]} +
  counts, `licence`, `snapshot_identifier`.
- Metric-scale gates (Decision 14) abort BEFORE emitting: unit-sanity
  (median bbox max extent in [20, 600] mm) and weight plausibility
  (implied bbox density in [0.05, 2.0] g/cm³); the failure block lands
  in `run_summary.json` under `scale_check_failed`.

## Dataset facts (verified 2026-08-09)

- Access is **request-gated** (Google Form + password) at
  <https://lorenz.ecn.purdue.edu/~food3d/> (TLS cert of that host fails
  verification — fetch with care). Licence is **CC BY-NC 4.0
  (non-commercial)** — unlike N5k's CC BY 4.0; recorded in the run
  summary, and worth a user-level decision before any commercial ship.
- The site says 637 objects / 108 categories; the arXiv v-latest
  (2409.01966) says 743 / 131. No public category list exists — hence
  the curated-only mapping artifact.
- Expected local layout (documented in ingest.py, reconcile on first
  contact): `meshes/<category>/<object_id>.obj|ply|glb|off` +
  `metadata.csv` (object_id, category, weight_g). Meshes assumed
  millimetres; a metre/centimetre snapshot trips unit-sanity and the
  conversion belongs in the metadata derivation step.

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
- `generate.py` persistence of the cross-dataset meta dicts is
  test-pinned (`tools/food_db/tests/test_cross_dataset_persistence.py`,
  red) but NOT implemented: task 21 waits on the stream-2
  CalibrationArtifact schema (task 11) for the artifact key spellings.
