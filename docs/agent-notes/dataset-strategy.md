# Dataset strategy — verified facts and remediation priorities

**Date:** 2026-07-02
**Method:** three parallel review agents — (1) estimation specs (model-production,
nutrition5k-calibration, pipeline, siblings), (2) remaining specs + OVERVIEW + agent
notes, (3) web verification of Google mobile-food-segmenter-v1 and Nutrition5k against
primary sources. Findings below are remediation *routing*, not spec edits: per
`specs/PROCESS.md`, each item closes through a spec amendment, decision-log entry, or
new spec — never a direct change outside the gates.

Companion note: [mvp-gap-analysis.md](mvp-gap-analysis.md) (2026-06-28) still holds —
the MVP is blocked on the trained segmenter. This note adds the dataset-level facts
and corrections discovered since.

---

## 1. Verified facts (primary sources)

### Google mobile-food-segmenter-v1 ("seefood", Kaggle / ex-TF Hub)

Model card: `github.com/tensorflow/tfhub.dev` → `assets/docs/google/models/seefood/segmenter/mobile_food_segmenter_V1/1.md` (same card as the Kaggle page).

- **Architecture:** DeepLabV3 + **MobileNetV2** backbone, 513×513 RGB input scaled to [0,1].
- **Output:** NOT binary — **26 coarse category classes** (`SemanticPredictions` int64 mask + `SemanticProbabilities` [h,w,26]). Labelmap (live): `gstatic.com/aihub/tfhub/labelmaps/seefood_mobile_food_segmenter_V1_labelmap.csv`. Categories are USDA-guideline groups: one class each for `starches/grains|rice/grains/cereals`, `noodles/pasta`, `baked_goods`, `starchy_vegetables`; classes 23/24 are non-food (containers, dining tools).
- **Training data:** Google-internal ingredient-parsing dataset, not released. **`fine-tunable: false`.**
- **License:** Apache 2.0, with card caveat "if you intend to use it beyond permissible usage, please consult with the model owners". Card explicitly states it is only for "a coarse-grained guess of the major ingredients" and **"cannot be used for accurate nutrition tracking"**.
- **Format:** TF1 hub module + official TFLite variant (~10.4 MB, uint8 input). coremltools has **no TFLite importer**; the only Core ML path is the legacy TF1 hub-module → frozen graph → `ct.convert`, with known DeepLab resize-op fidelity risks. No published eval metrics or latency figures.

### Nutrition5k (github.com/google-research-datasets/Nutrition5k, CVPR 2021)

- **Contents:** 5,006 plates (README; paper says 5,066 — pin to README and record the actually-ingested count). Per plate: 4 rotating side-angle 1080p videos, per-ingredient gravimetric mass + fat/carb/protein, dish totals. **Overhead RealSense RGB-D exists for only ~3.5k of the ~5k dishes** ("when available"; paper: "3.5k out of the 5k").
- **No segmentation masks** (confirmed; the README points at the seefood segmenter as "related").
- **License:** **CC BY 4.0** — free for any use incl. commercial, attribution required.
- **Depth:** RealSense D435, 8-second averaged; **16-bit integer, units of 1e-4 m (10,000 units = 1 m)**; plate distances ≈ 0.4 m (~4,000 units). Nutrition values derived from USDA data; masses from a scale.
- **Size/hosting:** 181.4 GB full tarball; browsable at `gs://nutrition5k_dataset/nutrition5k_dataset/` — **`gsutil -m cp -r` per-directory is the intended partial-download mechanism**. The calibration spec needs only `imagery/realsense_overhead/` + `metadata/` + `dish_ids/splits/`; the side-angle videos are the bulk of the 181 GB.
- **Official train/test splits** ship in `dish_ids/splits/`.
- **Paper baselines (test set, MAE as % of mean):** carb — predict-the-mean 62.1%, RGB direct 31.9%, **RGB-D direct 23.8%**, RGB+volume-scalar 22.0%. Context for our MAPE < 20% target (reported, not gated — n5k-calibration D6): beating Google's direct-regression baseline is ambitious but our physics path (volume × density × β) is a different approach class.

---

## 2. mobile-food-segmenter-v1: assessment against our requirements

No spec or decision log anywhere in the repo mentions this model — it was never
evaluated. That evaluation should be durably recorded (ADR in
`estimation/model-production/decision_log.md`) whichever way it lands.

**As the shipped segmenter: recommend reject.** Four independent disqualifiers:

1. **Palette mismatch, not adaptable.** 26 coarse categories vs our 35-class v1 palette; all eight carb-priority staples (white_rice vs brown_rice, bread_white vs bread_wholemeal, potato_boiled vs potato_mashed, chips_fries) collapse into 2–3 seefood category classes, so model-production Req 3.5 (per-staple IoU ≥ 0.50; bars since re-derived to 0.48/0.45 — segmenter-foundation D5/D14) is unsatisfiable and the palette↔DB bake lock (Req 8.4) cannot hold. `fine-tunable: false` and no released training data closes the adaptation route.
2. **Fitness disclaimer.** The card states it cannot be used for accurate nutrition tracking — adverse for a carb-estimation product, both technically and for the Apache-2.0 "consult the owners beyond permissible usage" caveat.
3. **Conversion risk.** TF1 hub module is the only Core ML input; legacy tooling, DeepLab resize-op fidelity issues, int64 argmax output.
4. **No eval numbers** to trade off against our mIoU ≥ 0.60 bar (bars since re-derived to 0.48/0.45 — segmenter-foundation D5/D14).

**Candidate accepted uses (each optional; adopt via its own decision entry):**

- **Interim real-mask source for device verification (highest value).** The dev-stub's image-centred ellipse is what keeps two-view SfS aim-sensitive and the success path unobserved (mvp-gap-analysis P2). A converted seefood model collapsed to food/non-food (or mapped to `unknown_food`) would give real, pose-dependent masks months before the FoodSeg103 checkpoint, letting the two-view carve, success path, and ANE/latency behaviour be verified on device. Weigh against the cheaper alternative already noted in mvp-gap-analysis: a world-locked stub. If adopted, this is dev-tooling behind `DEV_STUB_SEGMENTER`-adjacent flags — it must *not* enter the Release bake-lock path.
- **N5k ingestion QA.** Food/non-food masks for sanity-checking single-dominant purity routing and plate isolation during ingestion. It cannot feed the β fit itself — n5k-calibration Req 5.1's masking guarantee requires the *device* masking path — so QA/diagnostics only.

**FoodSeg103 remains the correct training set.** Apache 2.0, pixel-accurate 103-class
masks, remappable to our palette — nothing verified here displaces it. There is no
other public Google food *segmentation* checkpoint (`aiy/vision/classifier/food_V1` is
a 2023-dish classifier, unsuitable).

---

## 3. Spec corrections needed (facts the specs get wrong or omit)

All in `specs/estimation/nutrition5k-calibration/` unless noted. Close via
requirements/design amendments + decision-log refinement entries through the normal
gates.

| # | Finding | Where | Correction |
|---|---|---|---|
| C1 | "5,006 plates with overhead RealSense RGB-D" — only ~3.5k dishes have RGB-D | requirements.md intro, design.md overview | State ~3.5k RGB-D coverage; re-check per-class effective-sample feasibility (Req 4.5 n ≥ 30) against the smaller pool |
| C2 | No license/attribution handling for N5k | requirements.md (absent) | CC BY 4.0: add attribution requirement (About/Legal screen alongside the existing OGL v3 attributions; provenance in lineage). Only derived β values ship, but attribution is cheap and unambiguous |
| C3 | Depth encoding not pinned — 10× scale-bug risk | design.md ingestion (`depthBytesMm` conversion) | Pin source format: 16-bit int, 1e-4 m units → mm = units / 10 |
| C4 | Fixed-seed own splits (Req 4.4/6.1) ignore the official `dish_ids/splits/` | requirements.md Req 4.4, 6.1 | Decision needed: adopt official test split for paper-comparable reporting, or record why cross-validation policy overrides it |
| C5 | Dish-count ambiguity (5,006 vs 5,066) | requirements.md intro | Pin to README figure; Req 1.4 already records release identifier — also record ingested count |
| C6 | N5k absent from `docs/ml-training.md` datasets table (§1) and from pipeline Req 20.2 dataset-overlap | docs/ml-training.md; estimation/pipeline requirements §20.2 | Pipeline alignment already tracked as n5k-calibration Req 9.1 — extend that task to sync ml-training.md too |

---

## 4. Prioritised remediation plan (MVP closeout)

Routing follows PROCESS.md §3 (extension vs new spec) and §5 (mode). Nothing here is a
direct spec edit; each item names the vehicle.

### P0 — act now (blocks or shapes work already in flight)

1. **Trim the in-progress N5k download.** If the full 181.4 GB tarball is being pulled, switch to `gsutil -m cp -r` of `imagery/realsense_overhead/` + `metadata/` + `dish_ids/splits/` only (side-angle video is the bulk and is future-work only per n5k-calibration D3). No spec change; record in the spec's prerequisites when created (P0-4).
2. **Palette v2 must be fixed before the FoodSeg103 training run.** The liquid classes (water/coffee/tea/milk/juice/soup/beer_lager/beer_stout/wine, n5k-calibration Req 7) change the segmenter's output-channel count and the remap in `build_class_mapping.py`. Training on v1 then adopting v2 forces a retrain; FoodSeg103 also has no lager/stout distinction, so sub-class supervision needs a stated source or a coarser trained class + runtime sub-resolution. **Vehicle:** cross-referenced decision entries in n5k-calibration + model-production decision logs; palette-version requirement amendment in model-production. This is the tightest sequencing coupling to the MVP critical path.
3. **ADR for mobile-food-segmenter-v1** (see §2). **Vehicle:** model-production decision_log entry (reject-as-shipped + explicitly scoped optional uses). If the interim device-verification use is adopted, it is its own small spec under `estimation/` (conversion tooling + stub-path integration exceeds smolspec's no-cross-cutting bar).
4. **Process hygiene on nutrition5k-calibration.** The spec is untracked in git (violates §9 "intent lands first — every branch carries the specs tree"): commit it to `research`. Regenerate OVERVIEW.md via `/specs-overview` (it's a generated index; currently missing this spec). The folder has requirements/design/decision_log but no `prerequisites.md` (expected for a large spec, §2) and no `tasks.md` — fine only if the design gate is still open; on approval run `/starwave:tasks`, and declare the mode (β_c tuning is PROCESS §5's named example of iterative work → likely `full ·iterative`).
5. **Apply the §3 factual corrections (C1–C5)** before ingestion code is written — C1 (sample pool) and C3 (depth scale) silently corrupt the calibration if wrong. **Vehicle:** requirements/design amendment + decision-log refinement entry in n5k-calibration.

### P1 — before calibration implementation starts

6. **β bounds reconciliation.** Mixture solver hard-codes [0.05, 1.5] (design §3) while pipeline Req 11.7 states β_c ∈ (0, 1]. Either document why mixture may exceed 1 or align the bounds. **Vehicle:** n5k-calibration design amendment + decision entry.
7. **Preprocessing parity for N5k fixtures.** Single-dominant fixtures must carry probabilities from the *same* letterbox/normalise path the device uses (Req 5.1 guarantee); ingestion at a different resize breaks it silently. **Vehicle:** new EARS criterion under n5k-calibration Req 3 or 5.
8. **Dataset-overlap doc sync (C6).** Extend the existing Req 9.1 alignment task to cover `docs/ml-training.md`.
9. **USDA license provenance.** Liquid values cite CoFID (OGL v3) / AFCD (OGL v3) / USDA (unstated). USDA FoodData Central is U.S.-government public domain — record it where the other two licenses are recorded. **Vehicle:** n5k-calibration Req 7 amendment.

### P2 — post-MVP hygiene (tracked, not scheduled)

10. Checkpoint artifact storage/retention policy (lineage records the SHA but not where checkpoints live) — model-production extension.
11. FoodSeg103 archive version pin (lineage example says "v1.0" without a source hash) — model-production prerequisites.
12. `deviceVerified` flag home (per-class? where stored? who writes it?) — belongs to the future device spot-check spec n5k-calibration D18 anticipates.
13. Palette-version check at app launch (bake lock verifies at bake time only; a stale bundled DB is undetected at runtime) — pipeline extension.
14. σ_tilt / confidence treatment for liquid depth-integration — n5k-calibration design gap.
15. Macro cross-check (Req 6.7) is flag-only — a flagged class still ships its β; record as a known limitation or add a bake-time gate.
16. Mixture-fit co-occurrence collinearity has SE reporting but no decoupling/regularisation mechanism — revisit with real N5k counts.

---

## 5. FoodSeg103 acquired locally (2026-07-04)

The dataset now sits at `data/foodseg103/` in the release layout
(`Images/img_dir/{train,test}` + `Images/ann_dir/{train,test}` +
`category_id.txt`), verified over all 7,118 pairs — counts, mask mode, and
class-id range all match the official release. Provenance, source URLs, and
SHA-256 hashes are in `data/foodseg103/SOURCE.md`.

- **Source of record: the HF parquet mirror** `EduardoPacheco/FoodSeg103`
  (original JPEG/PNG bytes + filenames embedded), reconstructed byte-for-byte.
  Chosen over the canonical zip (2026-07-04, user decision — the SMU server
  was 502-ing and the mirror was judged sufficient and preferable); the
  parquet SHA-256s in SOURCE.md are the release identifier. HF "validation" =
  official "test". The `justinsiow/FoodSeg103` HF mirror is **incomplete**
  (405 files) — only its raw `category_id.txt` was used.
- **EXIF gotcha:** 4 train JPEGs (00000273, 00002585, 00003969 — orientation 6;
  00006505 — orientation 8) carry EXIF rotation; their masks match the
  *rotated* image — an original-dataset quirk, not a mirror artefact. Plain
  `Image.open(...)` ignores EXIF, so those 4 samples would have trained with
  pixels/mask 90° apart — silent, because both are resized to 513×513.
  **Fixed 2026-07-04:** `ImageOps.exif_transpose` applied at all three image
  loads — `train.py` `__getitem__`, `export.reference_input` (shared by the
  export oracle and `make_fixtures.py` model input), and `make_fixtures.py`'s
  stored nadir PNG — keeping train/export/fixture parity. Masks are never
  transposed (PNGs carry no EXIF; annotation matches the rotated pixels).
  Verified: `reference_input` on train image 00000273 now equals the manually
  transposed load and its dims match the mask.
- **Palette lock verified engaged (2026-07-04).** `build_class_mapping.py`
  re-run against the real `category_id.txt`; the committed
  `class_mapping_foodseg103_v1.json` was regenerated (only diff: "French
  beans" capitalisation, routing identical). `verify_palette_lock` passes and
  both test suites are green — see the ticked Stage 0 / palette-lock entries
  in `specs/estimation/model-production/prerequisites.md`. P0-2 above is
  closed. §3c done (2026-07-04): `prepare_dataset.py --heldout-frac 0.12
  --seed 1234` → `data/foodseg103_remapped/` (train 5,553 / val 711 /
  held-out 854 of 7,118; provenance in its `splits.json`; ~1k-mask sample
  swept, all pixel values within channels 0–34). The `exif_transpose` loader
  fix is in (see the EXIF bullet above). Training venv:
  `tools/segmenter/.venv` (python3.13 — the full `requirements.txt` does not
  resolve on 3.14, tensorflow has no wheels; repo root has no venv). Stage 3
  one-liner for the local Mac (MPS auto-detected; `caffeinate` per
  `docs/ml-training.md` §4 run hygiene; resume sidecar lands at
  `<--out>.resume.pt`):

  ```sh
  caffeinate -is tools/segmenter/.venv/bin/python tools/segmenter/train.py \
      --data data/foodseg103_remapped --num-classes 35 --target-size 513 \
      --epochs 60 --batch-size 16 --lr 1e-3 --split-seed 1234 \
      --foodseg103-source "hf:EduardoPacheco/FoodSeg103 see data/foodseg103/SOURCE.md" \
      --out tools/segmenter/build/checkpoint.pt
  ```

  **Stage 3 done — two runs.** `checkpoint.pt` (square-resize recipe; shipped
  2026-07-05 as model `0295ea61edd9`, heldout mean food-class IoU 0.4259),
  then `checkpoint_letterbox.pt` (2026-07-06; letterbox preprocessing matching
  the runtime path, plus independent vertical flip augmentation; shipped as
  model `24e0b022241a`, heldout 0.4054 — slightly lower offline, but with
  train↔runtime parity that the offline bench cannot see, expected to improve
  real-device behaviour). Both below the strict gate; both shipped under
  Decision 11 developer-phase overrides. `docs/ml-training.md` §5 seg-bench
  was skipped in favour of `run_validation.py` (stage 9), which records the
  same gate quantity into lineage without the ~16 GB fixture bundle; §6 export
  is done — the bundled `segmenter.mlpackage` carries `24e0b022241a`. Details
  in [model-production.md](model-production.md).

- **Stratified re-cut executed (2026-07-15, segmenter-foundation task 17 /
  Decision 21).** `data/foodseg103_remapped/` was DELETED and regenerated at
  frozen seed **20260715** (same 5,553/711/854 counts; `splits.json` gains the
  stratification block, `co_stats.json` is `co_stats.v2`). Always `rm -rf` the
  out dir before re-cutting with a new seed — `write_split` only adds files, so
  a re-cut into a populated dir leaks images across splits. Three gotchas
  learned here: (1) **brown_rice, bread_wholemeal, potato_mashed have zero
  FoodSeg103 images** — the class mapping routes no source category to those
  channels, so no seed makes them measurable and `validation.shortfall` will
  always report them absent (strict gate unattainable on FoodSeg103 alone);
  (2) **re-measuring an OLD checkpoint on a re-cut heldout is
  train-contaminated** — `checkpoint_letterbox.pt` scored 0.7403 there because
  78.7% of the new heldout was in its seed-1234 train split; the honest anchor
  is the leak-free 182-image subset (mean 0.3776), reconstructable via
  `carve_splits(pairs, 0.12, 0.1, 1234, None)` and now materialised as
  `data/foodseg103_remapped/heldout_leakfree/` (gitignored symlinks); (3) the
  old carve is reproducible with `--no-stratify --seed 1234` since the
  plain-shuffle path is unchanged. Init history: the timm in21k adapter probe
  FAILED (Decision 19; the graphs diverge numerically despite matching
  shapes); the torchvision `IMAGENET1K_V2` fallback init was then empirically
  REJECTED at epoch 20 of the task-18 run (Decision 23) and the run relaunched
  on `DEFAULT` (COCO-seg) weights. That co-occurrence-recipe run completed and
  was REJECTED too (Decision 24: same-set leak-free 0.3253 vs the pinned
  model's 0.3776; four staples regressed beyond tolerance while dead tail
  classes recovered from ~0). The bundled model remains `24e0b022241a`; a
  combined-loss fallback run (weighting-vs-co-term attribution) is in flight —
  see [model-production.md](model-production.md).

## 6. MyFoodRepo-273 acquisition attempt — BLOCKED at auth wall (2026-07-25)

The myfoodrepo-bridge PRD (dataset-bridge context, task 1) attempted a
non-interactive acquisition of MyFoodRepo-273 (AIcrowd Food Recognition
Benchmark; 24,119 images / 39,325 polygons / 273 classes, licence CC BY 4.0
per the Frontiers paper 10.3389/fnut.2022.875143). **Every viable route to the
exact release requires an interactive login and terms acceptance**, so the
PRD's conditional STOP fired. Nothing was scraped, guessed, or substituted.

Findings, all verified 2026-07-25:

- **Release identity.** MyFoodRepo-273 is the `v0.4` release of the AIcrowd
  *Food Recognition Challenge* (round 3/4, 2020-21): `train-v0.4.tar.gz`
  (1.16 GB, 24,119 images / 39,325 annotations), `val-v0.4.tar.gz`
  (1,269 images / 2,053 annotations), `test_images-v0.4.tar.gz`. The
  2022 benchmark's `public_training_set_release_2.0/2.1` files are the
  **different, larger successor** (39,962 images / 498 classes, then
  54,392 / 323) — not what the PRD pins.
- **Canonical host is OAuth-gated.** Direct file URL
  `https://datasets.aicrowd.com/default/aicrowd-public-datasets/food-recognition-challenge/v0.4/train-v0.4.tar.gz`
  answers HTTP 302 → `datasets.aicrowd.com/login` → `www.aicrowd.com/oauth/authorize`.
  The listing page
  `https://www.aicrowd.com/challenges/food-recognition-challenge/dataset_files`
  is a login wall. Third-party confirmation (epfl-dlab/biased-bytes README):
  "It is necessary to log in, accept the Terms and conditions, and download
  the train-v0.4.tar.gz (1.16G) file."
- **Kaggle mirror is credential-gated.** `rohitmidha23/food-recognition-challenge`
  (announced on the AIcrowd forum) — anonymous Kaggle API access returns
  403 (`kagglehub` 1.0.2 confirmed); no Kaggle credentials exist on this
  machine (`~/.kaggle/` absent).
- **The old public Wasabi bucket predates the 273 release.**
  `s3.eu-central-1.wasabisys.com/aicrowd-public-datasets` lists only
  `myfoodrepo/round-1/` and `myfoodrepo/round-2/` (2019-20, top-40/top-61
  class phases) — no `v0.4` keys anywhere in the bucket.
- **No open mirror found.** HuggingFace (dataset search: no MyFoodRepo /
  273-class entry), Zenodo, archive.org, Academic Torrents: nothing.
  Dataset Ninja hosts only the 498-class *Food Recognition 2022* successor
  (Supervisely repack, licence metadata there says CC0 which conflicts with
  AIcrowd's CC BY 4.0 — treat as unreliable provenance); substituting the
  successor would change the PRD's 273-category audit/mapping contract and
  was not done.

**Steps a human must take** (either route, ~10 minutes + 1.2 GB download);
afterwards the bridge context can resume at task 1's verification step:

1. Create/log in to an AIcrowd account at <https://www.aicrowd.com>
   (Google/GitHub OAuth offered), open
   <https://www.aicrowd.com/challenges/food-recognition-challenge>,
   click Participate and accept the challenge terms.
2. Download from
   <https://www.aicrowd.com/challenges/food-recognition-challenge/dataset_files>:
   `train-v0.4.tar.gz` and `val-v0.4.tar.gz` (test images optional — no
   public annotations).
   CLI alternative once the account exists: `pip install aicrowd-cli`,
   `aicrowd login` (browser handshake or API key from
   <https://www.aicrowd.com/participants/me>), then
   `aicrowd dataset download --challenge food-recognition-challenge`.
3. Place the archives in `/Users/r/repos/medata/data/myfoodrepo273/raw/`
   (see `data/myfoodrepo273/ACQUISITION.md` in the main checkout). Keep the
   `.tar.gz` files — SOURCE.md will hash them as the release identifier.

### 6.1 Outcome — v0.4 unobtainable; substituted with the 2022 release (2026-07-26, MD-30)

The human steps above were completed 2026-07-25 (login, participation terms
v2, challenge rules v9 accepted on the user's account) and STILL failed:
`datasets.aicrowd.com` answers **HTTP 500 on every file path** — in-browser
(user-confirmed), via the redirect chain with an authenticated session, and
via `aicrowd-cli` — while `gitlab.aicrowd.com` (the paper's data-availability
pointer) answers 503. The auth handoff itself works (a `datasets.aicrowd.com`
session cookie is granted); the storage backend behind their proxy is broken.
The small `round-*-datasets.txt` entries download fine because they live on a
different store (`aicrowd-production` S3 presigned URLs).

A mirror sweep found **no copy of v0.4 anywhere**: the public Wasabi bucket
(`aicrowd-public-datasets`, all top-level prefixes enumerated) holds only
rounds 1–2; the one historical Kaggle mirror (`rohitmidha23/…`) is deleted;
Kaggle/HuggingFace/Dataset Ninja hold only 2022-successor releases; Superb AI
hosts an 8,367-image subset; the Wayback Machine never archived the tarballs;
GitHub code search for the literal filename yields only repos linking the dead
URLs; the HuggingFace `food_recognition_2022_processed` copy is bbox-only (no
polygons — unusable for segmentation).

**Decision MD-30**: substitute the Food Recognition Benchmark 2022 release
(same MyFoodRepo source, CC BY 4.0; its ontology covers cereal via
porridge/muesli/crunch-muesli/birchermuesli/flakes-oat plus rice-whole-grain,
bread-wholemeal, and mashed-potatoes-…-butter). Acquisition route: Kaggle
mirror `sainikhileshreddy/food-recognition-2022` (5.27 GB, needs a
user-supplied API key), landing in `/Users/r/repos/medata/data/foodrec2022/`.
A background retry watch on the v0.4 links continues; v0.4 would be an
additional source if it ever resurfaces, not a replacement.

## 7. Public-data posture (confirmed)

The stated preference — freely available public data, no repeated work — holds across
the plan with no gaps: FoodSeg103 (Apache 2.0) for training, Nutrition5k (CC BY 4.0)
for β calibration, CoFID/AFCD (OGL v3) + USDA (public domain) for composition. The
only non-public dependency left on the roadmap is the deferred ≥30 gravimetric
meals/class hand-measured set (post-MVP, per model-production prerequisites), and the
one paid/gated resource (GPU time for training) is unavoidable. Nothing in seefood's
weights substitutes for the FoodSeg103 training run.
