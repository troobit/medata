# MetaFood3D ingestion (tools/metafood3d/)

Stream 1 of the cross-dataset-calibration spec: mapping artifact +
render + `ingest.py` bridging MetaFood3D single-food meshes into
`.fixture` files (single-class **mixture** rows, Decision 11).

## Palette target (Decision 15 — load-bearing)

The spec predates the cereal class but everything here targets the
**current content list** (`ClassPalette.standard`: 25 solids with `cereal`
at index 24, 8 liquids). β is keyed by class NAME end-to-end (fixture
GT-mass map, `MixtureBetaCalibrator` dicts, `generate.py`
UPDATE-by-class_id), so channel ordering only matters for probability
tensors — which mixture fixtures never carry. `mapping.py` parses the
`static let standard` marker (same scoping pattern as `generate.py`'s lock);
fixtures are stamped `palette_version="v0"` (pipeline Decision 50).

## Layout

- `mapping.py` — loader for `mapping_metafood3d_to_palette.json`; fails
  loudly on palette-content mismatch. Categories are compared in
  normalised snake_case (`normalise_category`; parens survive:
  `Almond(bowl)` → `almond(bowl)`).
- `build_mapping.py` — curated category→class rules, written against the
  **real 108-category enumeration** since Decision 20. The committed
  artifact is built in enumerated mode (`--categories-file
  data/metafood3d/categories.txt`): `categories_source` = enumeration
  SHA-256, all 108 categories recorded, stale-rule abort armed. Coverage
  is **13 rules → 11 classes, 80 objects** (apple, banana, beef,
  broccoli, carrot, chicken, chips_fries, egg, pork, potato_mashed,
  tomato); `Rice`/`Yeast_bread` ambiguous; 93 categories unmapped
  (composites, battered, desserts). The dataset does NOT cover the
  thin-sample carb staples (no plain pasta, no lentils, no cereal-type
  category) — the spec's motivating gap stays open. Ingest tolerates
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
  `normalise_category` keeps parens (`almond(bowl)`). The mapping is
  regenerated against the real enumeration (Decision 20) — the workbook's
  distinct `Object_name` values, via `derive_metadata.py` →
  `categories.txt`.
- Downloads live in gitignored `data/` (never committed, Req 1.2):
  mesh + point-cloud tarballs, the v2 workbook, `_MetaFood3D_Readme.txt`,
  and since 2026-08-13/14 the Blender renders and both RGBD video
  components. Only meshes + workbook + readme have consumers; point clouds,
  renders and videos are unused — see the component audit below.

## Component audit for segmenter training (2026-08-14, Decision 33)

The renders and RGBD videos were collected as candidate segmenter training
corpora and **rejected**. The facts below are measured, not inferred, so a
future revisit does not have to re-run the spike.

- **Layouts.** Renders:
  `Blender_render_images/<Category>/<instance>/<Instance>/{Original,Depth,Normal}/`,
  **200 viewpoints** per instance (not the ~60 the task text assumed).
  Videos: `RGBD_videos/<Category>/<object>/{original,masks,depth,segmented}/`,
  200 frames each, 1:1 across modalities, plus a stray `.mp4` per object.
- **Masks exist on both routes.** Render `Original` is **RGBA with a real
  alpha matte** — no need to infer from `Depth` at all. Alpha `>127` and
  "depth != background" agree at **IoU 0.9985-0.9989**, so Decision 31's
  depth inference is confirmed. Video `masks/*.jpg` are lossy-stored but
  effectively binary: 16 grey levels, all `<=10` or `>=245`, **zero**
  mid-tone pixels, so `>128` thresholds exactly.
- **The container problem is real, per-object, and systematic across frames.**
  Video masks include the plate/boat/carton for many container-served
  objects: `Mashed_Potato/mash1` covers the whole dark plate at 15.0-21.3 %
  of frame across every sampled frame, against 2.2-4.2 % for the other three
  `Mashed_Potato` objects — a 4-8x coverage signature, not a one-frame
  glitch. `French_Fry/fries_1` (7.0-9.4 %) labels the paper plate,
  `new_fries_3` the boat, `new_waffle_fry_2` the entire carton. Bare foods
  are tight — all six `Apple` objects sit at 3.4-12.9 % with no container.
  **The `new_` prefix is not a discriminator**: `new_fries_4` and
  `new_waffle_fry_1` are clean while `new_fries_3` and `new_waffle_fry_2`
  are not. For `(bowl)` categories the scanned mesh *is* the bowl, so the
  renders inherit it there too.
- **Some frames contain no food at all.** `French_Fry/fries_2` holds
  0.09-0.30 % mask coverage across sampled frames — the camera is pointed at
  bare tablecloth — yet the frames are still shipped under the category. A
  frame-coverage floor would be mandatory in any build.
- **Scale is 80 objects, not 16,000 images.** The 13 mapped categories cover
  80 physical objects over 11 palette classes — `potato_mashed` 4, `beef` 4,
  `egg` 5, `pork` 5, `chips_fries` 6, `carrot` 12. The 200 views per object
  are near-duplicates of one specimen on one black studio tablecloth, so any
  honest split must be **object-disjoint**, which leaves n=1 heldout objects
  for the thin classes.
- **Render photometry is viewpoint-dependent and wrong.** `Mashed_Potato`
  food-pixel mean luminance runs L=44-158 across viewpoints against L=137-181
  for the same objects in the real captures. Renders also have no background
  (transparent), 3-6 % frame coverage, and sub-horizon viewpoints the capture
  path never sees.
- **The staple premise that motivated it was stale.** "Three zero-image
  staples" is a **FoodSeg103-only** fact from Decision 21. In the live merged
  corpus `potato_mashed` has 150 images / 10.77 M train pixels, `brown_rice`
  131 / 11.37 M, `bread_wholemeal` 2,546 / 229.24 M. The only zero-train-pixel
  class is `beans_baked`, which MetaFood3D does not cover. The real gap is
  that those staples are absent from **heldout**, which MetaFood3D cannot fix
  because `heldout_leakfree` is deliberately real-image FoodSeg103 only.
- **Cost of a pass.** The archives are gzip, not seekable. Streaming to the
  `M` categories took ~3.5 min for the 137 GiB render archive with a
  `tarfile` `r|gz` filter that extracts only matching members, so a full pass
  is roughly 6 min. Filter and stop early rather than extracting wholesale.
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
- **The former pre-existing red is fixed** (2026-08-10,
  `specs/bugfixes/n5k-mapping-artifact-stale-v1-palette/`): n5k's
  `parse_palette` targets the standard declaration, its artifact is regenerated
  against the current content list, and its ingest stamps
  `palette_version="v0"` (pipeline Decision 50).
- `generate.py` persists the cross-dataset meta dicts
  (`calibration_contributing_datasets_per_class`,
  `calibration_single_source_classes`) for APPLIED classes only — a
  reference-skipped β is not baked, so its provenance is not recorded as
  if it were. Pinned by
  `tools/food_db/tests/test_cross_dataset_persistence.py` (task 21) and
  end-to-end by `EndToEndCalibrateBakeTests` (task 23).
