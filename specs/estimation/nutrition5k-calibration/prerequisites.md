# Prerequisites for Nutrition5k Calibration

These are the inputs that gate the calibration *runs*, not the spec or the tooling. Per Ronan (2026-07-02), dataset downloads are **agent-executable** — implementation agents have dataset context and may fetch requisite files (gsutil / public-bucket HTTP via the available tooling) into the documented gitignored directory. The genuinely human-gated remainder shrinks to what needs hardware: the GPU training run and on-device verification (both owned by model-production). The code-actionable work will live in `tasks.md` once the design gate closes.

## Dataset acquisition (gates ingestion, Req 1) — agent-executable

- [x] **Acquired 2026-07-02** into the gitignored `data/` directory (repo root; `.gitignore` line covers `data/`) via the gcloud CLI. **Local layout differs from the bucket layout** — this is the layout Req 1.3 documents and the ingestion tool's `--n5k-dir` default should target:
  - `data/n5k/realsense_overhead/dish_<id>/{rgb.png, depth_raw.png, depth_color.png}` — **3,490 dish folders** present (≈ the full RGB-D subset)
  - `data/metadata/` — all three CSVs (`dish_metadata_cafe1.csv`, `dish_metadata_cafe2.csv`, `ingredients_metadata.csv`)
  - `data/dish_ids/splits/` — all four split files, including the load-bearing `depth_test_ids.txt`

  Ingestion (Req 1.2) must still run the required-files check against this tree; **implementation agents are authorised to fetch anything missing or corrupt** directly from `gs://nutrition5k_dataset/nutrition5k_dataset/` (gcloud/gsutil). The Req 1.4 release identifier (SHA-256 manifest of metadata + split files, plus download date 2026-07-02) is generated at first ingestion — a task, not a prerequisite.

- The original partial-download guidance, retained for re-fetches (CC BY 4.0 — attribution required, see Req 1.5): do **not** pull the full archive — `nutrition5k_dataset.tar.gz` is 181.4 GB, mostly side-angle video this spec does not use (future work per Decision 3). Fetch only:
  - `imagery/realsense_overhead/` — the overhead RGB-D captures, one `dish_<id>/` folder per dish (~3.5k of the ~5k dishes carry these; the rest have no depth and cannot be ingested). Ingestion consumes `rgb.png` and `depth_raw.png`; `depth_color.png` is a visualisation artifact, optional and not a "required file" for Req 1.2
  - `metadata/` — `dish_metadata_cafe1.csv`, `dish_metadata_cafe2.csv`, `ingredients_metadata.csv`
  - `dish_ids/` — including `splits/depth_train_ids.txt` and `splits/depth_test_ids.txt` (the **depth** split is the RGB-D one this spec uses; the `rgb_*` files split the video-derived imagery and hold mostly depth-less dishes — Req 4.4 pins `depth_test_ids.txt` as the held-out set reported per Req 6.8)

  via `gsutil -m cp -r` from `gs://nutrition5k_dataset/nutrition5k_dataset/<dir>` (verified 2026-07-02 via the bucket's public listing API: these are the only non-imagery directories besides `scripts/`, and the four split files are exactly `depth_train_ids.txt`, `depth_test_ids.txt`, `rgb_train_ids.txt`, `rgb_test_ids.txt` — re-confirm filenames at download time as part of Req 1.2's required-files check). The bucket is unversioned, so the "release identifier" for lineage (Req 1.4) is operational: a SHA-256 manifest of the fetched metadata + split files plus the download date.

- [ ] **Camera intrinsics are NOT in the dataset.** Verified 2026-07-02 against the full bucket listing and the GitHub repo: N5k publishes no RealSense calibration (no intrinsics file, nothing in the README). Req 3.3 therefore requires a documented, pinned nominal camera model (e.g. RealSense D435 factory intrinsics at the captured resolution) chosen at design time and recorded in lineage; the systematic volume-scale risk this introduces is folded into the population-transfer caveat (Req 9.3).

## Sequencing prerequisite owed to model-production (Decisions 22–23)

- [ ] **Lock the final palette class list — v1 redefined to include the coarse liquid classes (Req 7.1–7.2, Decisions 23–24) — before the FoodSeg103 GPU training run starts.** The trained checkpoint's output-channel count must match the shipped palette; training on the pre-liquid 24-class layout then adopting the final list forces a full retrain. This item must appear as a prerequisite in model-production's Stage 3 ordering — training is blocked on it. There is no "v2": the app has never shipped, so the liquid classes land in a redefined v1 (Decision 23).

## Checkpoint dependency (single-dominant path only)

- [ ] **Trained segmenter checkpoint** (model-production Bucket C: FoodSeg103 download → GPU training → export). The download is agent-executable; the training run and on-device verify remain human/hardware-gated. Required only for the **single-dominant** β path, whose Req 5.1 masking guarantee needs real segmenter probabilities. The **mixture** path is deliberately decoupled (Decision 17, sentinel SHA) and can be fitted and baked before the checkpoint exists.

## Notes

- Nothing here blocks writing `design.md` amendments or `tasks.md`; these gate the *runs*, not the spec or the tooling.
- Liquid carb output stays unvalidated in this spec regardless of the items above (Req 7.7, Decision 9) — N5k carries no standalone-liquid ground truth.
