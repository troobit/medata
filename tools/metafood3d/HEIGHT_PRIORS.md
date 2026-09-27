# Food height priors from MetaFood3D

`height_priors.py` measures every MetaFood3D mesh, seats it on its support
plane and reports per-palette-class height percentiles in `height_priors.json`
(schema `height_priors.v1`, mm) plus a per-item audit CSV
(`height_priors_items.csv`). Purpose: a class-conditioned vertical cap for the
two-view voxel carve, which has no height bound on non-LiDAR phones
(two-view-trust Decision 8) and today stops only at the shipped 120 mm grid.

Generated 2026-09-27 from the local snapshot (637 meshes, 108 categories;
`data/metafood3d/SOURCE.md`). Runtime: 18 min single-core CPU for the full
snapshot (`--limit N` for smoke runs). The meshes were extracted `.obj`-only
into `data/metafood3d/3D_Mesh/` (35 GB, gitignored):
`tar -xzf data/_MetaFood3D_new_3D_Mesh.tar.gz -C data/metafood3d --include='*.obj'`.

## Method

1. Load vertices and faces (`trimesh.exchange.obj.load_obj`, materials
   skipped; the meshes are authored in metres and scaled to mm — median max
   extent 106 mm, gated to the 20–600 mm band).
2. Seat on the base plane (rule below), z = 0 at the plane, food in +z.
3. Per item: max, P98, P90 and P50 of vertex height; a 2 mm top-surface
   height field (max z per xy cell — what a nadir depth sensor sees) giving
   `surface_p50`/`surface_p90` and the footprint; the closed volume (signed
   tetrahedra about a point on the base plane, so a mesh left open at its
   table cut is closed by the plane); the workbook's weight and `Volume`.
4. Per palette class via `mapping_metafood3d_to_palette.json` (strict
   `mapped` entries) plus two height-only extensions: `Rice` → both rice
   classes and `Yeast_bread` → both bread classes. The mapping marks those
   ambiguous because the mass fit needs the grain/flour split; a height prior
   does not. `n_items_strict_mapping` in the JSON keeps the strict count
   visible (0 for the four extended classes).

Workbook check: the closed mesh volume matches MetaFood3D's own `Volume`
column to within 0.3 % on 587 of 635 joined items (median ratio 1.000), so the
dataset's volume column is this same closed-mesh integral and the seat does
not disturb it. The 21 items off by more than 10 % are all unmapped flat foods
whose meshes are open or self-intersecting at the base (tortillas, pancakes,
fried eggs, bacon); none feed a palette class. Two workbook ids are typos
(`carrrot_8`, `new_edammame_4`) and are corrected in the script.

## Base-plane rule

**Largest convex-hull facet whose normal lies within 30° of the scanner's
vertical axis (raw ±z), rotated to face −z and translated to z = 0.**

Why this and not the alternatives tried:

- The scans are gravity-aligned but the sign is not consistent: on the 97
  mapped meshes the largest hull facet faces raw −z on 50, raw +z on 25, and
  sideways on 22. So "use the raw frame" is wrong for a quarter of them, and
  the seat has to be found, not assumed.
- An unconstrained largest-facet rule (no cone) seats a mesh on whichever
  side happens to have the biggest flat patch. It read `Chicken_breast/breast_3`
  at 112 mm (true 54), two rice bowls at 119 and 91 mm (true 55 and 51) and a
  tomato at 90 mm (true 65): 5 of 97 mapped items 1.4–2.2× too tall, which
  moves the P90 of exactly the classes the cap is for.
- `trimesh.compute_stable_poses` (what `ingest.py` uses for rendering) lands
  many meshes on a side pose (21 of 97 more than 30° from the scanner
  vertical) because a food's most probable resting pose on a frictionless
  plane is not the pose it was scanned in.
- Fitting a plane to the open boundary edges was tried and is not usable:
  the meshes are closed at the base (0 watertight, but the boundary loops are
  scattered micro-holes across the whole surface), so the boundary "plane"
  is the mesh centroid plane.

With the 30° cone the seated height agrees with the raw-frame extent to
within −7.2…+2.5 mm (P5–P95) on mapped items, and the residual cases are
meshes whose scan frame was itself tilted (`seat_tilt_deg` in the CSV). Three
meshes eyeballed by extents: `Apple/apple_4` 79 × 80 footprint, 78.4 mm tall
(an apple stands as tall as it is wide); `Steak/steak_3` 34.4 mm over 73 cm²;
`Banana/banana4` 41.0 mm tall, 83 cm² footprint lying flat.

## Per-class numbers (mm, palette classes with meshes)

| class | idx | n | max P50 | max P90 | P98 P50 | min–max | surface P50 | footprint cm² P50 | volume cm³ P50 | categories |
|---|---|---|---|---|---|---|---|---|---|---|
| white_rice | 0 | 8 | 52.9 | 77.7 | 51.4 | 26–84 | 45.0 | 103.7 | 207.7 | Rice (height-only) |
| brown_rice | 1 | 8 | 52.9 | 77.7 | 51.4 | 26–84 | 45.0 | 103.7 | 207.7 | Rice (height-only) |
| bread_white | 3 | 9 | 31.6 | 80.9 | 29.8 | 17–104 | 25.1 | 104.6 | 123.4 | Yeast_bread (height-only) |
| bread_wholemeal | 4 | 9 | 31.6 | 80.9 | 29.8 | 17–104 | 25.1 | 104.6 | 123.4 | Yeast_bread (height-only) |
| potato_mashed | 6 | 4 | 42.6 | 48.6 | 38.0 | 39–50 | 26.9 | 81.9 | 145.9 | Mashed_Potato |
| chips_fries | 7 | 6 | 68.6 | 122.6 | 59.6 | 15–144 | 47.4 | 112.8 | 279.8 | French_Fry |
| chicken | 8 | 10 | 53.5 | 70.4 | 50.4 | 32–71 | 41.3 | 77.8 | 193.6 | Chicken_breast, Chicken_thighs |
| beef | 9 | 4 | 29.3 | 33.6 | 27.7 | 23–34 | 23.9 | 73.3 | 130.9 | Steak |
| pork | 10 | 5 | 27.6 | 31.9 | 26.3 | 23–33 | 23.1 | 108.3 | 187.0 | Pork_Chop |
| egg | 12 | 5 | 43.2 | 44.3 | 41.9 | 41–45 | 36.9 | 21.1 | 53.2 | Egg |
| broccoli | 15 | 9 | 51.4 | 112.5 | 47.5 | 35–118 | 39.8 | 22.0 | 32.7 | Broccoli |
| carrot | 16 | 12 | 32.8 | 54.2 | 31.3 | 11–63 | 21.6 | 51.7 | 91.3 | Carrot |
| apple | 20 | 7 | 78.1 | 81.0 | 73.8 | 70–82 | 66.4 | 49.9 | 240.9 | Apple |
| banana | 21 | 7 | 41.0 | 45.9 | 39.7 | 33–46 | 32.4 | 83.2 | 197.8 | Banana |
| tomato | 22 | 11 | 41.6 | 61.5 | 40.7 | 9–65 | 33.6 | 27.8 | 74.2 | Tomato, Tomato_slice |

Global over all 637 meshes: max-height P50 41.0, P90 71.8, P98 117.5 mm.

No meshes: pasta, potato_boiled, fish_white,
cheese, salad_leaves, peas, beans_baked, lentils, mixed_vegetables, cereal,
and all eight liquid classes (`null` with a note in the JSON). MetaFood3D has
no plain pasta, lentil or cereal category; `Baked_Potato`, `Salmon_Grill`,
`Breaded_Fish`, `Fried_egg`, `Green_beans`, `Cauliflower` exist but are not
in the mapping and were not added here (a baked potato is not a boiled one,
salmon is not white fish; adding them is a mapping decision, not a script
default).

## Outliers and what the spread means

Classes fall into two kinds:

- **One form, tight spread** (P90/P50 < 1.15): apple, banana, egg, beef,
  pork, potato_mashed, chicken. A class cap at P90 is within ~5 mm of every
  item and the cap acts as a measurement, not just a ceiling.
- **Several forms in one category** (P90/P50 > 1.5): the height is set by
  which form is on the plate, and the class P90 is the tallest form.
  - `Yeast_bread` is three slices (16.7–19.7 mm), three rolls (31.3–31.9)
    and three whole loaves (74–104). P50 = a roll, P90 = a loaf.
  - `French_Fry` is 15–27 mm (a scattered handful, waffle fries) to 101–144
    (a full basket, `new_fries_4` 307 × 279 mm footprint). The 144 mm waffle
    basket is taller than the shipped 120 mm grid.
  - `Broccoli` is 35–56 mm florets and three whole heads at 108–118.
  - `Rice` runs 26 mm (a thin spread) to 84 mm (a domed bowl).
  - `Tomato` merges whole tomatoes (42–65) with slices (9–32).

Individual items worth knowing: `Broccoli/broccoli_5` reads 108 mm seated
against 132 mm in its raw frame (a head scanned leaning); `Mashed_Potato/
new_mashed_potato_3` 41 mm seated vs 61 raw (same); `Tomato_slice/
new_tomato_slice_1` 32 mm seated vs 42 raw (a slice scanned on edge). In each
case the seated number is the one a plate would show.

## The five carve-audit bundles

All five are bread rolls (`docs/agent-notes/two-view-geometry-audit.md` §7):
`1790318627741`, `1790315814452`, `1790310086654`, `1790325380366` reconciled
to `bread_wholemeal` (index 4), `1790315734391` to `bread_white` (index 3).
Both classes carry the same Yeast_bread prior:

| prior | mm | LiDAR max height on the five rolls (mm) |
|---|---|---|
| max P50 | 31.6 | 47.6, 50.7, 37.1, 33.8, 30.5 |
| P98 P50 | 29.8 | (P98: 47.3, 50.4, 36.0, 33.4, 30.2) |
| max P90 | 80.9 | |
| global P90 | 71.8 | |

So on these rolls a P90 cap (81 mm, 86 with the 5 mm margin) would have
bitten but not solved: D8's own cap sweep on `1790318627741` reads 927 cm³ at
120 mm, 756 at 86, 656 at 72 — a P90 cap takes 18 % off a 2.5× over-read. A
P50 cap (32 mm) would have clipped three of the five rolls (LiDAR max 47.6,
50.7 and 37.1 mm), because the category's median is a slightly flatter roll
than the ones photographed. The MetaFood3D rolls sit at 31–32 mm; the field
rolls at 30–51 mm.

## Recommended cap rule

`cap_mm = class max_height_p90_mm + margin`, with `margin` the shipped 5 mm,
and `cap_mm = global max_height_p90_mm (71.8) + margin` for any class with
`n_items` null or below 4. Never below one voxel layer above the shipped
minimum grid.

Reasoning:

- A cap must not clip real food. P90 of per-item max height is the loosest
  statistic that is still class-specific; on the tight classes it is a
  near-measurement (egg 44, apple 81, banana 46, beef 34, pork 32 mm), and on
  the mixed classes it is the tallest common form, which is the honest
  ceiling when the form is unknown.
- P50 or P98-of-P50 is not safe as a cap: on bread it clips three of the five
  audited rolls. Those percentiles are the right numbers for a different
  role — the height *estimate* the swap-and-record loop could seed — but not
  for the grid extent.
- The global P90 (72 mm) as fallback is below the shipped 120 mm for every
  unmapped class and above every MetaFood3D item outside the tall tail
  (loaves, fry baskets, whole broccoli heads), which are the items no
  single-plate estimate should assume.
- What the numbers say the cap cannot do: for bread, chips and broccoli the
  class P90 still leaves the two-view carve 1.5–2× over on a roll-sized
  object, because the hull does not close below ~74° of tilt (Decision 8)
  and the cap is the only bound. A form-level prior (slice / roll / loaf,
  handful / basket) would be tight for exactly these classes; the palette
  does not carry form, so that is a swap-and-record question, not a script
  one.

## Files

- `tools/metafood3d/height_priors.py` — the script (numpy + trimesh, CPU,
  deterministic).
- `tools/metafood3d/height_priors.json` — the prior, all 36 palette indices
  (33 classes + 3 sentinels), palette order.
- `tools/metafood3d/height_priors_items.csv` — one row per mesh with every
  measured column, the seat diagnostics and the workbook join.
