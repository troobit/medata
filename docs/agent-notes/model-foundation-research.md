# Model-foundation research — findings (Track A)

**Date:** 2026-07-10
**Question:** Is DeepLabV3 + MobileNetV3-Large the best-in-class on-device food-segmentation
foundation for MeData in 2026, or do newer architectures / checkpoints / pretraining
strategies materially surpass it — and how do ImageNet-style tagging and a 1–2 word text
prompt fit? Grounded against the shipped model (0.40–0.43 heldout mIoU, below the 0.60 gate,
developer override) and the prior seefood-rejected / FoodSeg103 evaluation
(`docs/agent-notes/dataset-strategy.md`).

**Provenance.** Produced by the `deep-research` harness (fan-out search → fetch → 3-vote
adversarial verification). 70 primary-sourced claims extracted across 16 sources; 75
verification votes (11 refutes). The harness's final synthesis step returned a probe/test
artifact (empty), so this report is hand-synthesised from the verified claim set and the
refutation votes — the corrections below are the harness's, not added after the fact. This
is research input for `/starwave:creating-spec`, framed so findings can become requirements.

---

## Headline finding — the 0.60 gate is a dataset ceiling, not just a model choice

**FoodSeg103 SOTA is ~52% mIoU** (Swin-TUNA 50.56%, 2025, arXiv 2507.17347; HDF 52.25%,
2025, J. Food Meas. Charact. 10.1007/s11694-025-03647-2), and it takes **100M+ parameter
models** to get there (BEiT v2-L, 441M → 49.4%, arXiv 2306.09203). No published model — at
any size — clears 0.60 mIoU on FoodSeg103.

Implication for the spec: MeData's shipped 0.40–0.43 is genuinely low, but the **0.60 gate
(pipeline Decision 14) is very likely unattainable on FoodSeg103 regardless of backbone.**
A model-foundation spec must therefore decide one of: (a) revisit/re-derive the mIoU gate
against what is achievable, (b) improve the *data/taxonomy* (the real ceiling), and/or (c)
lean on the physics path's tolerance (β calibration already absorbs some segmenter error,
pipeline §6.9). "Wrong model" is at most half the story; "hard dataset + gate set above the
achievable frontier" is the other half. **This reframes the effort and should be Requirement 1.**

---

## Q1 — Backbone / architecture: do compact segmenters beat DeepLabV3+MobileNetV3-Large?

Several compact segmenters are *within budget* and report accuracy/efficiency gains over
MobileNetV3-DeepLab — **but every gain is on general scenes (ADE20K/Cityscapes), none on
FoodSeg103, and Core ML / ANE conversion feasibility is unverified for all of them.**

| Candidate | Size | Reported result | On-device caveat |
|---|---|---|---|
| **SegFormer-B0** (MiT encoder + all-MLP decoder, arXiv 2105.15203) | 3.8M params | 37.4% ADE20K; +3.4% mIoU & +7.4 FPS over DeepLabV3+ (MobileNetV2) | MiT attention → ANE/Core ML conversion **unverified**; no FoodSeg103 number |
| **PP-MobileSeg** (StrideFormer = MobileNetV3 blocks + strided SEA attention) | Tiny 1.44M / Base 5.71M | 36.4–41.6% ADE20K; +1.57% mIoU & −32.9% params & +42.3% speed vs SeaFormer-Base | Latency measured on **Snapdragon 855, not ANE**; no direct MobileNetV3-DeepLab comparison; no FoodSeg103 number |
| **LVT** (Lite Vision Transformer) | ~5.5M w/ head | 39.3% ADE20K; 74.8% ImageNet-1K top-1 (> MobileNetV2) | Custom conv/atrous self-attention ops → **conversion-feasibility questions**, unaddressed |
| **TopFormer** | tiny | "+5% mIoU over MobileNetV3, lower latency" (ADE20K) | **Refuted framing:** baseline is MobileNetV3+**LR-ASPP** (32.3% mIoU, a weak head), *not* DeepLabV3+MobileNetV3-Large — margin does **not** transfer to MeData's head |

Net: a backbone swap is *plausible* but **unproven for food and unproven on the ANE**. The
single biggest unknown across the whole search — nobody publishes Core ML / Apple Neural
Engine latencies for these — must be an explicit spike/prerequisite before any swap is
committed.

## Q2 — Pretraining / ImageNet / "plate" class

- **The real ImageNet lever is heavy self-supervised pretraining, not a bigger label set.**
  FoodSeg103 winners use **ImageNet-1K masked-image-modeling (MIM)** pretraining (e.g. BEiT
  v2, 1,600 epochs) + a UperNet decoder; transformer backbones pretrained with MIM transfer
  to food segmentation **better than plain conv backbones** (arXiv 2306.09203). "Heavy
  pretraining is the lever rather than food-specific pretraining." A BEiT v2 tokenizer
  trained on **Food-101** also learned useful food concepts (food-specific SSL data helps).
- **Training-recipe lever, architecture-agnostic, compatible with the *existing* segmenter:**
  a plug-and-play **co-occurrence-relationship loss** improves FoodSeg103 mIoU by **+3.72%**
  overall (up to **+16.54%** when the co-occurrence matrix is built from **Recipe1M+**), and
  specifically targets **class imbalance — MeData's exact failure mode** (collapsed
  carb-priority staples). (Corrected: the headline "755%" is *least-frequent-tail-class only*,
  a base-rate artifact; the honest overall figure is +3.72%.) Springer 10.1007/s11694-025-03647-2.
- **"plate" as a distinct class:** not directly answered by the sources. Deferred — plausibly
  useful for plate isolation/scale, but no evidence found; the spec should treat it as an
  open sub-question, not a settled win.

## Q3 — Text-conditioned / open-vocabulary ("1–2 word prompt")

Technically real and — importantly — **not an LLM** (a learned conditioning mechanism), so
it does not by itself break the no-LLM invariant. But it breaks the **budget** and the
**single-pass multi-class contract**:

- **CLIPSeg** (CVPR 2022): the "1.1M trainable params" figure is misleading — it ships a
  **frozen CLIP ViT-B/16 (~150M params, >100 MB fp16)**, ~10× over the ≤10 MB budget. It
  emits a **binary mask per prompt**, so covering the 35-class palette needs **one forward
  pass per class**, breaking the single-pass per-pixel class-probability contract that
  per-class voxel ownership (pipeline Decision 11) depends on. Accuracy 43–48% mIoU (below
  gate), and not food-trained.
- **SAM family** (MobileSAM, SAM3-distilled): class-agnostic *promptable* masks, **not**
  per-pixel food-class probabilities; even distilled, the SAM3 text encoder **alone** is
  42.5M params (~4× budget); no ANE claims; deployment target is edge GPUs, not a ≤10 MB ANE
  model.
- **VolE++ (2026):** text-guided food segmentation *does* exist and works, but it is a
  **Multi-View-Stereo volume pipeline**, not a drop-in compact segmenter, and reports no
  size/latency/ANE figures.

Verdict: **text-conditioning is a dead-end for MeData's on-device segmenter** under the
current budget + multi-class single-pass contract. Record as evaluated-and-rejected so it
isn't re-litigated. (The user's "1–2 word prompt" intuition is sound in the literature — it
just doesn't fit an offline ≤10 MB ANE segmenter.)

## Q4 — Newer food-specific checkpoints / datasets

- **FoodSeg103 remains the food-segmentation set of record** (confirmed across the 2023–2025
  SAM-era literature). Nothing displaces it as the training set — consistent with the prior
  `dataset-strategy.md` conclusion.
- **FoodSAM** (46.42% mIoU on FoodSeg103): a ViT-H (~636M param) SAM + semantic module +
  detector — **far outside budget**, a post-hoc mask-refinement scheme, no latency/size/ANE
  data. Not a foundation candidate.
- New **food-3D** datasets exist (MetaFood3D, FoodKit via VolE++) but they are volume/3D
  benchmarks, **not** pixel-accurate 2D masks remappable to the 35-class palette.

---

## Ranked candidate foundations (accuracy gain × on-device feasibility × conversion/licensing risk)

1. **Training-recipe upgrade on the *existing* DeepLabV3+MobileNetV3-Large** — MIM-pretrained
   backbone + the co-occurrence-relationship loss (Recipe1M+ priors) + class-imbalance
   handling. **Lowest risk, no conversion change, directly attacks the collapsed-staple
   failure mode.** Best value/risk. Recommended as the spec's primary lever.
2. **SegFormer-B0 backbone swap** — strong general-benchmark accuracy/efficiency, tiny
   (3.8M), permissive. Gated on an **ANE/Core ML conversion spike** and a FoodSeg103 retrain
   to prove the food-domain gain. Medium risk.
3. **PP-MobileSeg / LVT** — even smaller, MobileNetV3-lineage (PP-MobileSeg). Android-only
   latency, non-standard ops (LVT), no food benchmarks. Medium-high risk; fallback to (2).
4. **Dead-ends (record as rejected):** FoodSAM, MobileSAM / SAM3, CLIPSeg — each violates the
   ≤10 MB / ≤250 ms budget and/or the single-pass per-pixel multi-class-probability contract
   (Decision 11), and/or emits class-agnostic or binary masks.

## Invariant checks (flag where a candidate would break MeData's rules)

- **No-LLM / offline:** text-conditioned segmenters (CLIPSeg, SAM3-text) are *not* LLMs and
  can run offline — they fail on **budget** and the **multi-class contract**, not the no-LLM
  rule. None of the ranked (1)–(3) touch the no-LLM/offline invariants.
- **Single-pass per-pixel class probabilities (Decision 11):** binary-per-prompt (CLIPSeg)
  and class-agnostic (SAM) outputs break it. (1)–(3) all preserve it.
- **≤10 MB / ≤250 ms ANE:** (1)–(3) fit on *size*; **ANE latency is unverified for the
  transformer candidates** and is the gating unknown.

## What the spec must decide (requirements seeds)

1. **Re-derive the accuracy gate** against the FoodSeg103 achievable frontier (~0.52 SOTA),
   or justify keeping 0.60 with a data/taxonomy plan. (Headline finding.)
2. **Primary lever = training-recipe upgrade** on the current architecture (MIM pretraining +
   co-occurrence/imbalance loss); measure against the collapsed carb-staple IoUs specifically.
3. **Backbone swap (SegFormer-B0) as a parallel track gated on an ANE conversion spike** — do
   the Core ML/ANE feasibility + FoodSeg103 retrain before committing.
4. **Record text-conditioning and SAM/FoodSAM as evaluated-and-rejected** (budget + contract),
   so they are not re-opened.
5. **`plate`-class value = open sub-question**, not a committed change.

## Sources (primary)

- SegFormer — arXiv 2105.15203 · TopFormer — arXiv 2204.05525 (CVPR 2022) · PP-MobileSeg —
  ResearchGate 369946276 · FoodSeg103 SOTA/BEiT v2 — arXiv 2306.09203 · Swin-TUNA (50.56%) —
  arXiv 2507.17347 · HDF (52.25%) — PMC12897188 / Springer 10.1007/s11694-025-03647-2 ·
  FoodSAM — arXiv 2308.05938 · co-occurrence loss — Springer 10.1007/s11694-025-03647-2 ·
  CLIPSeg — CVPR 2022 (Lüddecke & Ecker) · MobileSAM — arXiv 2306.14289 · LVT — Lite Vision
  Transformer (CVPR 2022) · VolE++ / VolE — 2026 food-volume MVS.
