# Estimation improvement avenues — verified research survey (2026-07-15)

Deep-research sweep commissioned by the user ("research ALL avenues to improve; near
enough isn't good enough"), run 2026-07-15 against the **iPhone 16 Pro hardware floor**
(segmenter-foundation Decision 22: A18 Pro ANE, budgets ≤ 24 MiB FP16 / ≤ 250 ms —
the 13 Pro Max is out of scope). Baseline context: honest leak-free heldout mean
food-class IoU ≈ 0.3776 (Decision 21) against the 0.48 gate / 0.45 staple floors;
three staples (brown_rice, bread_wholemeal, potato_mashed) have zero FoodSeg103 images.

**Method**: 5 search angles → 23 sources fetched → 108 claims extracted → every claim
adversarially verified by 3 independent refutation votes (2/3 refutes kills). 22 claims
confirmed, 3 killed, 11 findings after synthesis. Votes are recorded per finding.
Refuted claims and verification-coverage gaps are listed at the end — **silence on an
avenue means verification attrition, not evidence of absence.**

This document seeds the next improvement spec's research foundation, the way
`model-foundation-research.md` seeded segmenter-foundation.

## 1. Architecture: the current pairing is dominated (highest-confidence avenue)

The strongest verified result is that DeepLabV3+MobileNetV3-Large is Pareto-dominated
by 2022–2024 mobile segmentation designs — including SegFormer-B0, the current spike
candidate.

- **EfficientViT** (ReLU linear attention, ICCV 2023; [arXiv:2205.14756](https://arxiv.org/pdf/2205.14756), votes 3-0/3-0/3-0, high confidence).
  B0 matches/beats a DeepLabV3+MobileNet-class model on Cityscapes (75.7 vs 75.2 mIoU)
  at ~21× fewer parameters (0.7M) and ~126× fewer MACs. B1 (4.8M params) beats
  SegFormer-B1 by +0.6 mIoU on ADE20K with 5.2× fewer MACs and up to 3.5× lower GPU
  latency — **Pareto-dominating the SegFormer family the spike targets**. The core
  operator avoids softmax and large-kernel convolutions (the usual ANE-fallback
  triggers), so clean Core ML/ANE conversion is plausible but UNVERIFIED.
- **SeaFormer** (squeeze-enhanced axial attention, ICLR 2023/IJCV 2025; [arXiv:2301.13156](https://arxiv.org/html/2301.13156), votes 3-0/3-0, high confidence).
  B++ surpasses a MobileNetV3-based segmenter by +8.3 mIoU on ADE20K (41.4 vs 33.1)
  while ~16% faster on a Snapdragon 865 CPU. O(HW) attention from convolution-friendly
  ops. Caveats: the paper's baseline decoder is LR-ASPP, so headroom vs a DeepLabV3
  head is plausibly ~5–7 mIoU; **Large (14M ≈ 28 MB FP16) BUSTS the 24 MiB budget**
  (that claim was refuted 0-3) — Tiny/Small/Base fit.
- **PP-MobileSeg** (Baidu tech report, not peer-reviewed; [arXiv:2304.05152](https://arxiv.org/pdf/2304.05152), votes 3-0/3-0, high confidence).
  Base: 41.57 mIoU on ADE20K at 5.71M params (~11.4 MB FP16), beating SeaFormer-Base
  while 42.3% faster (Snapdragon 855 CPU). Tiny (1.44M, MobileNetV3 blocks + strided
  SEA attention): 36.39 mIoU, +3.13 over a MobileNetV3 MobileSeg baseline, 45% faster,
  49.5% smaller.
- **RepViT** (backbone only; [arXiv:2307.09283](https://arxiv.org/abs/2307.09283), [GitHub](https://github.com/THU-MIG/RepViT); core claim 3-0, medium confidence).
  First lightweight model over 80% ImageNet top-1 at ~1 ms Core ML latency on an
  iPhone 12 (M1.0: 6.8M params). Two companion claims REFUTED (0-3): "ANE-friendly by
  construction" is not demonstrated, and the full family does NOT fit the budget
  (M2.3 ≈ 46 MB FP16). The 1 ms figure is 224×224 classification, not segmentation.
  Treat as a backbone-spike candidate needing its own conversion verification.

**Recommendation**: extend the SegFormer-B0 spike (task 20) into a 3–4 candidate
conversion bake-off — EfficientViT-B0/B1, SeaFormer-Base, PP-MobileSeg-Base — using
the same four stop-on-fail criteria. Every ANE/Core ML feasibility statement above is
**inferred, never measured**: all surviving benchmarks report NVIDIA GPU or Snapdragon
CPU latency. The 16 Pro re-derating (Decision 22) plus the §4 upsample finding below
gives borderline candidates real headroom.

## 2. Deployment: the upsample+argmax tail may cost half the latency

([arXiv:2304.05152](https://arxiv.org/pdf/2304.05152), vote 3-0, high confidence.)
The final bilinear-interpolate + argmax stage accounted for **more than half of total
mobile segmentation latency** in PP-MobileSeg's profiling; their Valid Interpolate
Module (upsample only classes present in the prediction) cut end-to-end latency 49.5%
(465.6 → 234.6 ms) in ablation. Architecture-agnostic: profile MeData's own Core ML
tail (SegmenterPreProcessor → model → argmax path) before buying a new backbone —
any saving here funds a larger backbone within the 250 ms budget. Caveats: VIM
activates above a 30-class threshold (the 35-class palette clears it narrowly); the
interpolate/argmax share may differ on ANE vs Snapdragon CPU.

## 3. Data: the FoodSeg103 ceiling is hard; MyFoodRepo-273 is the verified way out

- **FoodSeg103's supervised ceiling** ([arXiv:2105.05409](https://arxiv.org/abs/2105.05409), votes 2-1/2-1, medium confidence):
  9,490 images total including the FoodSeg154 extension, only 7,118 usable in
  FoodSeg103 proper. Classes with zero annotated images are unrecoverable from this
  dataset regardless of training technique — **external sourcing for the three absent
  staples is mandatory, not optional** (matches Decision 21's ground truth).
- **MyFoodRepo-273 / AIcrowd Food Recognition Benchmark** ([Frontiers in Nutrition 2022](https://www.frontiersin.org/journals/nutrition/articles/10.3389/fnut.2022.875143/full), [arXiv:2106.14977](https://arxiv.org/abs/2106.14977), vote 3-0, high confidence):
  24,119 images / 39,325 segmented polygons / 273 food categories with
  instance-segmentation annotations — ~3.4× FoodSeg103's usable count. The Swiss
  menuCH ontology (and the 498-class Food Recognition 2022 successor) includes
  bread-white, **bread-wholemeal**, rice, potatoes-steamed. Dedicated brown-rice and
  mashed-potato classes were NOT confirmed — check the class list before committing.

**Recommendation**: a dataset-bridging spec (MyFoodRepo-273 → 35-class palette remap,
CoFID-wins-style merge with FoodSeg103) is the highest-leverage data move; it attacks
both the absent-staple gap and the small-set ceiling at once.

## 4. Training technique: co-occurrence source matters; init beats SSL recipe

- **Ingredient co-occurrence loss** ([Springer, J Food Meas Charact 2025](https://link.springer.com/article/10.1007/s11694-025-03647-2), votes 3-0/3-0/3-0, medium confidence):
  on FoodSeg103 itself, up to +3.72% mIoU (U-Net, matrix from FoodSeg103), rising to
  up to **16.54% mIoU improvement when the matrix is derived from Recipe1M+** instead,
  and a 755% relative gain on the least-frequent 10% of classes (near-zero baseline).
  Directly relevant: the co_occurrence loss builds its matrix from
  FoodSeg103 (`co_stats`) — **deriving it from Recipe1M+ is a cheap, verified
  upgrade path**. Caveats: single unreplicated study, mid-tier journal, ambiguous
  relative-vs-absolute reporting; transfer from U-Net/EfficientNet-b7 to a compact
  mobile model is unproven.
  **Outcome (2026-07-16, Decision 24):** the FoodSeg103-internal run completed
  and was REJECTED — same-set leak-free 0.3253 vs the pinned model's 0.3776,
  with four staples regressing beyond tolerance while dead tail classes
  recovered from ~0 (milk/tea/soup/fish_white/apple). The mechanism works on
  the tail; its cost model on the staples is the problem — consistent with
  this paper's finding that the statistics source matters, so the Recipe1M+
  question stands. Nothing was exported (bundled model remains
  `24e0b022241a`); a combined-loss fallback run (weighting-vs-co-term
  attribution) is in flight.
- **Initialisation beats SSL machinery** (UniMatch V2, TPAMI 2025; [arXiv:2410.10777](https://arxiv.org/html/2410.10777v2), votes 3-0/3-0, high confidence):
  SSL delivers big gains under label scarcity (+5.7 mIoU on ADE20K at 1/32 labels),
  but the paper's own ablations attribute most of the headline improvement to the
  backbone swap (DINOv2), not the SSL recipe — supporting the in-flight init upgrade
  as the cheaper first move. Expected SSL gains at MeData's scale/backbone are well
  below the headline deltas.
- **Food-domain self-supervised pretraining** (FeaSC, ACM MM 2023; [arXiv:2308.03272](https://arxiv.org/pdf/2308.03272), votes 3-0 ×4, high confidence):
  Food2K-pretrained FeaSC improves FoodSeg103 fine-tuned mIoU by ~4 points over plain
  SSL baselines (BYOL 31.72 → 36.22) and edges supervised Food2K pretraining by +0.85.
  Cost: ~12 V100-days ≈ 1–2+ weeks on a single Apple-silicon machine — **high-cost
  avenue for the local setup**; park unless a GPU box appears.
- **Loss sweep is cheap but non-transferable** ([arXiv:2312.05391](https://arxiv.org/html/2312.05391v1), vote 2-1, medium confidence):
  >6-point DSC spread from loss choice alone on medical CT (Jaccard 80.85 vs Dice
  74.23, TransUNet). The survey's own conclusion: rankings do not transfer across
  domains. Predicts "run a Jaccard/Tversky/compound sweep", not a specific food gain.

## 5. Refuted claims (do not cite these)

- SeaFormer-Large fits the 24 MiB FP16 budget — **refuted 0-3** (14M params ≈ 28 MB).
- RepViT is "ANE-friendly by construction" because of its benchmarking — **refuted 0-3**.
- The full RepViT family fits the budget with latency headroom — **refuted 0-3**.

## 6. Coverage gaps — avenues where nothing survived verification

No claims survived adversarial verification for: TTA within the latency budget,
CRF/boundary refinement on ANE, ensemble-free calibration, monocular-depth+LiDAR
fusion for volume, learned volume correction, and per-class density/carb-factor
sources beyond Nutrition5k/MetaFood3D. These need targeted follow-up passes, not
dismissal. Unverified leads fetched under the volume/density angle:
[FAO/INFOODS density database v2](https://www.fao.org/fileadmin/templates/food_composition/documents/density_DB_v2_0_01.pdf),
[USDA FNDDS](https://www.ars.usda.gov/northeast-area/beltsville-md-bhnrc/beltsville-human-nutrition-research-center/food-surveys-research-group/docs/fndds-download-databases/),
[arXiv:2409.01966](https://arxiv.org/abs/2409.01966), [arXiv:2411.10492](https://arxiv.org/html/2411.10492v1),
[JMIR mHealth 2020](https://mhealth.jmir.org/2020/3/e15294/).

## 7. Open questions for the next spec

1. Core ML/ANE bake-off: do EfficientViT-B0/B1, SeaFormer-Base, PP-MobileSeg convert
   cleanly and stay ANE-resident within budget? Does ReLU linear attention actually
   avoid fallback in practice?
2. Does MyFoodRepo-273 (or Food Recognition 2022, 498 classes) have usable brown-rice
   and mashed-potato coverage, and how does menuCH remap onto the 35-class palette?
3. Does the Recipe1M+-derived co-occurrence matrix advantage transfer to a compact
   mobile architecture on the 35-class remap (and are the paper's percentages
   relative or absolute)?
4. Targeted follow-ups for the §6 coverage gaps.

## Ranked recommendation (as of 2026-07-15)

1. **Profile the upsample/argmax tail** (§2) — days of work, potentially halves
   latency, funds everything else.
2. **Architecture bake-off spike** (§1) — extend task 20's method to 3–4 candidates;
   EfficientViT first.
3. **MyFoodRepo-273 dataset bridge** (§3) — the only verified fix for the absent
   staples and the data ceiling.
4. **Recipe1M+ co-occurrence matrix** (§4) — small change to an already-landed
   mechanism.
5. Loss sweep (§4) — cheap, run opportunistically alongside other retrains.
6. Park: food-domain SSL pretraining (cost), full SSL pipeline (init dominates),
   until the above are exhausted or hardware changes.
