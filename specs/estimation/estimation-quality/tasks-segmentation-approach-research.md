---
references:
    - prd.md
---
# MVP estimation quality — Segmentation approach research

## Research

- [ ] 1. Diagnose why held-out food-class mIoU plateaus at ~0.40 — cite the concrete factors in train.py (unweighted CrossEntropyLoss, geometry-only augmentation, MobileNetV3-Large capacity, ~5.5k train images, 35-class imbalance) and the per-class IoU shortfalls in build/lineage.json / model-production.md

- [ ] 2. Connect the linear-stripes-of-spots symptom to missing class-imbalance handling + missing spatial regularisation, consistent with the prior model-quality-not-format-bug conclusion

- [ ] 3. Recommend a prioritised set of training-recipe + algorithmic changes (weighted CE / focal / dice-Tversky / combined loss, class balancing/sampling, photometric augmentation, >=1 architecture/backbone alternative vs the 24 MiB weight budget + ANE residency) — each ranked highest-IoU-per-effort with the files it would touch

- [ ] 4. Recommend carb-reading-consistency + beta coverage levers without new hand-measured data where possible; route data-gated beta work to specs/estimation/cross-dataset-calibration and specs/estimation/nutrition5k-calibration rather than editing them here

- [ ] 5. Define a lightweight offline metric to compare recipe variants using run_validation.py held-out IoU + per-staple IoU, and state the improvement threshold that justifies a device deploy

- [ ] 6. Write the analysis to docs/agent-notes/segmenter-improvement-research.md, cross-link from docs/ml-training.md section 11, and run make spell clean
