# On-device model scoping: masks and volume (2026-09)

Research for backlog item 33 (MD-29). Two jobs, both fully on the phone: (A) better food
masks than `deeplab_mnv3` inside the segmenter budget, (B) a height bound for the non-LiDAR
two-view carve (two-view-trust D8: the carve over-reads 2–3x because no allowed tilt closes the
hull). Constraints: iPhone 16 Pro floor, iOS 26.5, Core ML, no network in the estimation
path, segmenter ≤ 24 MiB FP16, ANE-resident, ≤ 250 ms per view, deterministic.

"Verified" below means read from the primary source cited; "derived" means computed from a
published parameter count at 2 bytes/parameter; "claimed" means the vendor's own number.

## Job A: masks

| Candidate | Params / FP16 | Core ML / ANE evidence | Licence | Fit |
|---|---|---|---|---|
| `deeplab_mnv3` (current) | 22.1 MB (measured) | ANE-resident today | BSD (torchvision) | baseline; 0.42 class-mean IoU on the anchor |
| **EdgeTAM** (Meta, CVPR 2025) | RepViT-M1 encoder; Core ML packages published: encoder ~9.6 MB + prompt ~2 MB + decoder ~8 MB ≈ 19.6 MB (verified, vendor) | 16 FPS on iPhone 15 Pro Max, coremltools, "CPU and NPU", iOS 18.1 (verified, paper) | Apache-2.0 (verified) | **inside budget; strongest candidate** |
| MobileSAM | 9.66 M (5 M TinyViT + 3.9 M decoder) ≈ 19.3 MB derived | RepViT-SAM paper: OOM on iPhone 12 at 1024² via Core ML Tools; no ANE report found | Apache-2.0 | inside budget; ANE unproven |
| EdgeSAM | 9.6 M ≈ 19 MB derived | 38.7 FPS on iPhone 14 (claimed; compute unit not stated) | **S-Lab 1.0: non-commercial; commercial use needs the authors' permission** | rejected on licence |
| RepViT-SAM | RepViT-M2.3 encoder (~23 M) + decoder ≈ 27 M ≈ 54 MB derived | 48.9 ms on iPhone 12 at 1024² (verified, paper) | Apache-2.0 | over budget 2x |
| EfficientSAM-Ti / -S | 10 M / 25 M ≈ 20 / 50 MB derived | none found (ViT encoder at 1024²) | Apache-2.0 | Ti fits on size; ANE unknown |
| EfficientViT-SAM L0 / XL0 | 34.8 M / 117 M ≈ 70 / 234 MB derived | ONNX + TensorRT only | Apache-2.0 | over budget |
| SAM 2.1 tiny / small | 38.9 M / 46 M; Apple's Core ML repos are 79.7 / 93.9 MB (verified) | Apple-converted FP16; no latency published | Apache-2.0 | over budget 3–4x |
| Vision `GenerateForegroundInstanceMaskRequest` | 0 bytes in the app | OS-managed, iOS 18+ (verified) | OS API | free baseline; salient-object instances, no prompts |
| Vision `GenerateIterativeSegmentationRequest` (tap/box/scribble) | 0 bytes in the app | **iOS 27.0+** (verified); model fetched by `downloadAssets()` | OS API | above the 26.5 floor; asset download is a network step |
| Lightweight semantic (SeaFormer 8.6 M, TopFormer, PP-MobileSeg) | ≈ 17 MB derived | ARM-CPU papers; no Core ML | Apache-2.0 | same family SegFormer-B0 lost in; no food pretraining |

Notes.

- **EdgeTAM is the only promptable model with vendor-published Core ML packages that sum
  under 24 MiB and an Apache licence.** It is SAM 2 distilled for video; used image-only
  (no memory bank) it is a box/point-prompted SAM. Accuracy cost: SA-23 1-click 55.5 mIoU vs
  SAM 2 58.9; 5-click 81.7 vs 81.7. On food the relevant number is unknown until measured.
- MobileSAM is the fallback if EdgeTAM's decoder falls off the ANE; the iPhone 12 OOM was at
  1024² on a 4 GB device and is not evidence against an 8 GB iPhone 16 Pro, but there is no
  positive ANE report either.
- Apple's own subject lifting (foreground instance mask, iOS 18) costs nothing and should be
  the first row in any comparison. It cannot be prompted on iOS 26; the promptable request
  arrives with iOS 27 and pulls its model over the network on first use, which the offline
  invariant would need to absorb as a one-time install step.
- **Class production for a class-agnostic mask.** Two options. (i) Keep `deeplab_mnv3` and
  pool its per-pixel logits inside each promptable mask for the ranked shortlist: no new
  training, but ~42 MB across two models, so a budget decision. (ii) Replace deeplab with a
  MobileNetV3-Small crop classifier (~2.5 M ≈ 5 MB) trained on the same corpus, giving
  EdgeTAM + classifier ≈ 25 MB — marginally over 24 MiB. Option (i) first for measurement.
- **Prompting without a user.** The pipeline is automatic. Candidate prompts are: instance
  boxes from the Vision foreground request, connected components of deeplab's non-background
  argmax (one box each), or a grid of points. The anchor evaluation must use the same
  prompt source the app would.
- **Evaluation on the 182-image anchor**, class-agnostic: union of all food channels vs
  background (food IoU), per-region IoU where GT regions are connected components of the
  argmax label map, and boundary F-score. Run once with oracle GT boxes (upper bound) and once
  with the app's prompt source. Shortlist hit rate: GT class in the pooled top-3. EdgeTAM and
  MobileSAM run in PyTorch on the Mac; the Vision request runs on macOS 15+, so the existing
  harness host can score it.

## Job B: volume and height

The non-LiDAR path already has a metric support plane: `CardPoseSolver` gives the ID-1 card's
pose from the intrinsics and `CardOnlyPlaneFitter` back-projects silhouette edges at card
scale. What is missing is any height above that plane.

| Candidate | Params / FP16 | Core ML / ANE evidence | Licence | Metric claim | Fit |
|---|---|---|---|---|---|
| **Depth Anything V2 Small (relative)** | 24.8 M / 49.8 MB FP16 (verified, Apple card) | Apple-converted; 33.9 ms iPhone 15 Pro Max, 31.1 ms iPhone 12 Pro Max (verified card; compute unit not stated) | Apache-2.0 (Small only) | affine-invariant inverse depth; scale and shift unknown | **spike candidate** with card-plane fit |
| Depth Anything V2 Metric-Indoor-Small | 24.8 M ≈ 49.8 MB | same architecture; no published conversion | Apache-2.0 (Small) | NYU AbsRel 0.073, δ1 0.961 (verified, paper Table 4a, ViT-S) | 7 % of 40 cm ≈ 3 cm, the size of the food; absolute depth alone cannot give height |
| MoGe-2 ViT-S | 35 M ≈ 70 MB derived | ONNX docs only | MIT | metric point map | plausible second candidate; no mobile evidence |
| Metric3D v2 ViT-S | not published (DINOv2 ViT-S + decoder) | ONNX only | BSD-2 | NYU AbsRel 0.045 (giant); small not quoted | no mobile evidence |
| Apple Depth Pro | 504 M ≈ 1 GB | community PR converts at 1024² | Apple licence: personal, non-commercial | sharp metric | out on size and licence |
| Depth Anything 3 | no small metric model; Metric-Large 0.35 B | none | Apache (S/B/Metric-L), CC-BY-NC (L/G) | metric via focal | out on size |
| UniDepthV2 | ViT-S variant exists | none | **CC BY-NC 4.0** | metric | out on licence |
| ZoeDepth | 345 M (BEiT-L) / 112 M (B) | none | MIT | metric | out on size |
| DPT-hybrid (MiDaS) | ~123 M | none | Apache-2.0 | relative | out on size |
| Marigold | SD2 diffusion, multi-step | none | Apache-2.0 | relative | out on latency |

The decisive point: **no monocular model's absolute error at 20–60 cm is small compared with
a 2–5 cm food height.** The usable signal is relative shape. Fit the model's inverse depth to
the card-known plane on the plate and table pixels (two unknowns, scale and shift, solved by
least squares over hundreds of pixels), then read food pixels' residual above the plane as
height. That converts a 50 MB relative model into a height map whose accuracy is set by the
model's local consistency, not its global metric calibration — and it is measurable today
against LiDAR height fields on the existing bundles.

A depth model is a separate budget: ~50 MB FP16 and ~35 ms at 518×392, against a segmenter
budget of 24 MiB. That is a new decision, not a stretch of the existing one; 6-bit palettised
variants exist (Apple ships F32 and F16; coremltools palettisation would roughly halve F16
at an accuracy cost to be measured).

Cheaper priors, no model:

- **Food-class height prior.** MetaFood3D (743 scanned meshes, 131 categories, weights) and
  Nutrition5k's overhead depth (already a spec in this repo) yield per-class height
  percentiles offline. Cap the voxel grid at the class P90 instead of the shipped 120 mm.
  Zero bytes, deterministic, and the swap-a-food loop fixes the cap along with the label.
  D8's own cap sweep shows why it matters: 24 mm → 238 cm³, 48 → 460, 120 → 927.
- **Plate rim.** A card-scaled rim ellipse gives a diameter check and a population prior
  (~25 cm, used by the Implicit-Scale benchmark); it bounds height only for foods below the
  rim (~2–3 cm). Weak on its own, useful as a floor for shallow foods.
- **ARKit and AVFoundation on non-LiDAR iPhones.** `sceneDepth` needs LiDAR;
  `personSegmentationWithDepth` returns depth only on person pixels; `AVCaptureDepthDataOutput`
  gives disparity on dual-camera phones (iPhone 16/16 Plus) but not on the single-camera
  16e, and Apple describes it as relative and photo-effects grade. World tracking (already
  used by `ARKitCaptureEngine`) gives metric camera poses and horizontal planes on every
  device; `rawFeaturePoints` on textured food might bound height sparsely. Unverified; cheap
  to log since the session already runs. Nothing in iOS 26 adds non-LiDAR scene depth.

## Ranked recommendation

1. **Class height prior into the carve (Job B, no model).** Cheapest and directly attacks the
   number the product cannot recover. Derive per-class heights from MetaFood3D, replay the
   five `carve-audit` bundles with the class cap, compare with the LiDAR height-field.
2. **Depth Anything V2 Small + card-plane fit (Job B, model).** Vendor-converted Core ML,
   Apache, ~35 ms. Settles whether a relative depth model can bound height on this hardware.
   Needs a budget decision if it works.
3. **EdgeTAM image-mode vs Vision foreground mask vs deeplab (Job A).** Class-agnostic IoU
   on the anchor. Only worth doing after (1) and (2), unless the mask spike is what produces
   the plate/table pixels the depth fit needs; then run it alongside (2).
4. MobileSAM only if EdgeTAM fails the ANE report. Everything else is out on size or licence.

## Replacement for the 0.48 class-mean gate

Three bars, all on the existing anchor and weighed plates, replacing segmenter-foundation D5:

- **Mask bar.** Class-agnostic food IoU (union food vs background) and per-region IoU on the
  182-image anchor; boundary F-score at a 2-pixel tolerance. Numeric thresholds are set after
  the first measurement of `deeplab_mnv3` on the same metrics (unknown today); a candidate
  must beat deeplab by ≥ 0.05 food IoU and not lose boundary F.
- **Shortlist bar.** GT class in the top-3 shortlist for ≥ 80 % of anchor regions.
- **Volume bar.** On weighed plates, median |V_est − V_true| / V_true ≤ 25 % and P90 ≤ 50 %;
  two-view vs single-view LiDAR ratio on the same roll ≤ 1.3 (D9's hull bias is 1.05–1.17).
  Three weighed plates is not enough; a kitchen-scale sitting is a prerequisite.
- **Runtime bar unchanged.** ≤ 250 ms per view, ANE residency confirmed by the Xcode
  performance report on the iPhone 16 Pro, total FP16 within whatever budget the decision
  sets.

## Risks

- **ANE fallback.** Both SAM-family decoders and DINOv2 ViT encoders carry attention; Apple's
  DA-V2 latency table and EdgeTAM's "CPU and NPU" note are the only on-device numbers, and
  neither states residency per layer. The Xcode report is the gate.
- **Licence.** EdgeSAM (S-Lab), UniDepth (NC), DA-V2 Base and larger (NC), Depth Pro (Apple
  personal licence) are out for a shipped app. EdgeTAM, MobileSAM, DA-V2 Small, MoGe-2 are
  clean.
- **Size.** SAM 2.1, EfficientViT-SAM, RepViT-SAM exceed the segmenter budget 2–4x. Any depth
  model is ~50 MB and needs its own decision.
- **OS floor.** The promptable Vision request is iOS 27; adopting it moves the floor and adds
  a first-use asset download.
- **Metric depth is not height.** Absolute depth error at tabletop range equals the food
  height; only the plane-fitted relative approach is credible, and it is untested on food.

## One-day experiments

- **Height prior:** script over MetaFood3D meshes → per-class P50/P90 height; replay the five
  carve-audit bundles with the class cap; pass if the two-view/LiDAR ratio drops under 1.3 on
  ≥ 4 of 5.
- **Depth fit:** run Apple's `DepthAnythingV2SmallF16` on the nadir frame of each LiDAR
  bundle (Mac or phone), fit scale/shift on support-plane pixels using the known card pose,
  compare P98 food height with the LiDAR height field; pass if within ±25 % on ≥ 4 of 5.
- **Masks:** EdgeTAM (PyTorch) with deeplab-component boxes and with oracle boxes over the
  182 anchors, plus the Vision foreground request on the Mac; report food IoU, per-region
  IoU, boundary F against deeplab; pass if EdgeTAM beats deeplab by ≥ 0.05 with app prompts.

## Sources

- EdgeTAM paper: https://arxiv.org/html/2501.07256v1 ; repo and Core ML sizes: https://github.com/facebookresearch/EdgeTAM
- EdgeSAM repo: https://github.com/chongzhou96/EdgeSAM ; licence: https://github.com/chongzhou96/EdgeSAM/blob/master/LICENSE
- MobileSAM: https://github.com/ChaoningZhang/MobileSAM
- RepViT-SAM paper: https://arxiv.org/html/2312.05760v2 ; repo: https://github.com/THU-MIG/RepViT
- EfficientSAM: https://github.com/yformer/EfficientSAM ; paper: https://arxiv.org/abs/2312.00863
- EfficientViT-SAM: https://github.com/mit-han-lab/efficientvit/blob/master/applications/efficientvit_sam/README.md
- SAM 2.1 sizes and licence: https://github.com/facebookresearch/sam2 ; Apple Core ML: https://huggingface.co/apple/coreml-sam2.1-tiny , https://huggingface.co/apple/coreml-sam2.1-small
- Vision foreground mask: https://developer.apple.com/documentation/vision/generateforegroundinstancemaskrequest
- Vision iterative segmentation (iOS 27): https://developer.apple.com/documentation/vision/generateiterativesegmentationrequest ; WWDC26 session 237: https://developer.apple.com/videos/play/wwdc2026/237/
- SeaFormer: https://arxiv.org/abs/2301.13156 ; PP-MobileSeg: https://arxiv.org/pdf/2304.05152
- Depth Anything V2 Core ML (Apple): https://huggingface.co/apple/coreml-depth-anything-v2-small ; paper: https://arxiv.org/html/2406.09414v1 ; repo and licences: https://github.com/DepthAnything/Depth-Anything-V2 ; metric small: https://huggingface.co/depth-anything/Depth-Anything-V2-Metric-Indoor-Small-hf
- Depth Pro: https://github.com/apple/ml-depth-pro ; licence: https://github.com/apple/ml-depth-pro/blob/main/LICENSE ; Core ML PR: https://github.com/apple/ml-depth-pro/pull/45
- Metric3D v2: https://github.com/YvanYin/Metric3D ; paper: https://arxiv.org/abs/2404.15506
- UniDepthV2: https://github.com/lpiccinelli-eth/unidepth ; paper: https://arxiv.org/abs/2502.20110
- MoGe-2: https://github.com/microsoft/MoGe ; paper: https://arxiv.org/abs/2507.02546
- Depth Anything 3: https://github.com/ByteDance-Seed/Depth-Anything-3
- ZoeDepth: https://github.com/isl-org/ZoeDepth ; DPT-hybrid: https://huggingface.co/Intel/dpt-hybrid-midas ; Marigold: https://arxiv.org/abs/2312.02145
- ARKit sceneDepth (LiDAR only): https://developer.apple.com/documentation/arkit/arframe/scenedepth ; estimatedDepth thread: https://developer.apple.com/forums/thread/654208 ; AVCaptureDepthDataOutput: https://developer.apple.com/documentation/avfoundation/avcapturedepthdataoutput ; WWDC22 depth session: https://developer.apple.com/videos/play/wwdc2022/110429/
- Apple, transformers on the ANE: https://machinelearning.apple.com/research/neural-engine-transformers ; vision transformers on the ANE: https://github.com/apple/ml-vision-transformers-ane
- MetaFood3D: https://arxiv.org/abs/2409.01966 ; dataset: https://lorenz.ecn.purdue.edu/~food3d/
- Implicit-Scale multi-food benchmark (plate priors): https://arxiv.org/abs/2602.13041 ; MonoBite: https://link.springer.com/chapter/10.1007/978-981-95-5737-0_3
- FoodSAM: https://arxiv.org/abs/2308.05938
- Repo: `specs/DECISIONS.md` MD-29; `specs/estimation/two-view-trust/decision_log.md` D8, D9; `docs/agent-notes/segmenter-improvement-research.md` §4.6.

All web sources accessed 2026-09-27.
