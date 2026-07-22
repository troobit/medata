# SNAQ benchmark — operationalising "comparable to SNAQ"

User mandate (2026-07-16): iterate on estimation until carb accuracy is comparable to
SNAQ while staying locally runnable. This note pins that phrase to published figures so
the target is measurable. Researched 2026-07-16 (web, multi-source verified; single-sourced
items flagged). Sister note: `estimation-improvement-avenues.md` (the levers).

## The target

**Per-meal carbohydrate MAE ≤ ~13 g (≈44% relative), matching SNAQ's real-world
shipping-app performance** (Baumgartner 2024), and clearly better than unaided T1D
self-estimation (~15–21 g). Stretch band: SNAQ's preclinical 5.5 g / dietitian-from-photo
~15 g. Report carb MAE in **grams AND percent**, plus the **proportion of meals within
±10 g** (the clinical band the SNAQ/GoCARB studies use) so results line up directly.

Scope honesty: SNAQ studies publish carb-gram error only. End-to-end carb error is the
head-to-head metric; segmentation mIoU stays our internal gate with exactly one external
reference point (SNAQ preclinical per-item IoU 71.8%, different metric and meal set — NOT
comparable to our FoodSeg103 35-class mIoU). A defensible "comparable" claim needs the
same ground-truth protocol: weighed items + food-composition DB. All source studies are
small-N single-site — treat ~13 g as an order-of-magnitude bar, not a precise one.

## Lineages — do not conflate

- **GoCARB** — academic predecessor (ARTORG, University of Bern; Mougiakakou group).
  Single RGB image + reference card. 2015–2018 papers.
- **SNAQ** — commercial app (SNAQ AG, Zurich; same Bern milieu). Depth hardware
  (TrueDepth/LiDAR) + volumetry. The direct comparator.

## Verified figures

| System | Study | N | Ground truth | Result |
|---|---|---|---|---|
| SNAQ (tech) | Herzig 2020, JMIR mHealth (preclinical, iPhone X) | 48 meals / 128 items | weighed 0.1 g + Swiss FCDB | **carb MAE 5.5 ± 5.1 g (14.8 ± 10.9%)**; weight err 14.0%; per-item IoU 71.8%; 5.5% items hand-fixed; 22.9 s on-device — [PMC7142738](https://pmc.ncbi.nlm.nih.gov/articles/PMC7142738/) |
| SNAQ (app) | Baumgartner 2024, J Diabetes Sci Technol (real-world) | 53 T1D; 26 meals × 3 portions | weight × recipe DB | **SNAQ 13.1 ± 11.3 g (44.3%)** vs Calorie Mama 24 g (81%) vs patients 21 g (71%); differences NOT significant (p > .05) — [PubMed 39058316](https://pubmed.ncbi.nlm.nih.gov/39058316/) |
| SNAQ (app) | Bally group RCT 2025, eClinicalMedicine | 44 T1D on AID, 3-wk crossover | glycaemic outcomes | TIR **+6.6 pp** (p < 0.001); users accepted SNAQ's carb suggestion only **19.2%** of the time — [PMC12538901](https://pmc.ncbi.nlm.nih.gov/articles/PMC12538901/) |
| GoCARB | Rhyner 2016, JMIR | 19 T1D / 24 meals | weighed + USDA | GoCARB **12.28 ± 9.56 g** vs patient self-estimate 27.89 g (p = .001) — [PMC4880742](https://pmc.ncbi.nlm.nih.gov/articles/PMC4880742/) |
| GoCARB | Vasiloglou 2018, Nutrients | 54 meals / 6 dietitians | weighed + USDA | GoCARB **14.8 g** ≈ dietitians **14.9 g** (p = .93); within ±10 g: 37.0% vs 35.2% — [PMC6024682](https://pmc.ncbi.nlm.nih.gov/articles/PMC6024682/) |

Human anchors: adults with T1D in real life **15.4 ± 7.8 g (20.9%)** per ~72 g meal, 63%
of meals underestimated (Brazeau 2013); dietitians from photos ~15 g with only ~35%
within ±10 g; adolescents 42% within ±10 g / 86% within ±20 g (review,
[PMC11279647](https://pmc.ncbi.nlm.nih.gov/articles/PMC11279647/)).

## Strategic notes

- The 5.5 g figure is lab conditions; **13.1 g is the honest shipping-app number**.
- The shipping SNAQ app is **almost certainly cloud-based** (researched 2026-07-18): its
  privacy policy has users "upload photos" retained for 10 years and names AWS as a
  processing/storage provider; snaq.ai states an internet connection is often required and
  offline functionality is limited; an Android version exists (io.snaq.app) with no
  LiDAR/ANE stack; and on non-LiDAR phones SNAQ falls back to **default portion sizes**
  (no volumetry). Only the 2020 Herzig prototype is documented on-device (22.9 s, iPhone X).
  MeData's no-network/no-LLM estimation path is therefore a genuine differentiator, and
  SNAQ's recognition breadth likely rests on a server-side model plus a user-photo data
  flywheel (250k+ users) that an offline 35-class model cannot copy — parity means carb-MAE
  parity on the staple palette, not open-world recognition parity.
- The 19.2% suggestion-acceptance figure in the RCT says UX trust matters as much as
  accuracy — the estimate must be inspectable/adjustable (snaqui portion adjustment is
  the right instinct).
- Single-sourced items: the 71.8% IoU figure and the adolescent bands.
