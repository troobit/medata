# Prerequisites for Model Production

These are the human/data-gated stages a coding agent cannot perform — they need a dataset download, a GPU, a Mac with Xcode, a physical iPhone, or weighed meals. The code-actionable work lives in `tasks.md`; these stages produce the artefacts and verifications those tasks (and the MVP gate, Req 6.3) depend on. Stage numbers refer to the design §2.1 process table.

> **Operational runbook:** [`docs/mvp-unblock-runbook.md`](../../../docs/mvp-unblock-runbook.md) turns this checklist into ordered, time-boxed steps with go/no-go gates. Use it to actually run the work; use this file as the authoritative stage-by-stage checklist behind it.

## The only thing left for a real MVP estimate

Every surrounding subsystem is code-complete: the capture → segment → volume → macros pipeline runs end-to-end against a dev-stub segmenter, and the model-production tasks (loader on `Bundle.module`, build lineage, `modelVersion` derivation, the `export.py` equivalence/parity/channel/budget/metadata gates, validation IoU + export-eligibility reporting, and the palette↔DB edition bake lock) implement everything an agent can do. What no agent can produce is the trained model itself and the on-device proof that it runs. The MVP — the app showing a **real** carbohydrate number instead of the dev-stub — is blocked on exactly the human-gated chain below.

**Ordered path to the MVP gate (each step gates the next):**

1. **Stage 0 — Acquire FoodSeg103** (download). → unblocks the automated remap + split (Stages 1–2, already scripted).
2. **Stage 3 — GPU training run** → `build/checkpoint.pt`. Export-eligible only if validation mIoU ≥ 0.60 mean **and** ≥ 0.50 for every carb-priority class.
3. **Export (automated, gated)** — run `export.py` on macOS; the task 6/7 gates (equivalence, parity, channel order, ≤ 10 MB budget, metadata stamp) run automatically and bundle `segmenter.mlpackage`. No new human judgement, but needs a Mac + the checkpoint.
4. **Stage 7 — On-device verification** on the iPhone 13 Pro Max (ANE residency + a real capture). **This is the MVP gate (Req 6.3).**

**Off the critical path (deferred past the MVP gate):** β_c gravimetric calibration (Stages 9–10). The MVP ships every class at β = 1.0 / `uncalibrated_unity`; calibration only tightens accuracy later and is not required to ship.

The detailed runbook for each stage (commands, flags, acceptance bars) is in [`docs/ml-training.md`](../../../docs/ml-training.md); this file is the human-gated checklist that runbook feeds into.

## Dataset (Stage 0)

- [ ] **Acquire FoodSeg103** (Apache 2.0, https://xiongweiwu.github.io/foodseg103.html). Needed: the raw dataset on disk for the automated remap (`build_class_mapping.py`) and fixed-seed split (`prepare_dataset.py`). Record the source version / archive SHA so it can be written into `build/lineage.json` (`foodseg103_source`). Satisfies **Req 2.4**; feeds Req 1.3 lineage.

## Training (Stage 3)

- [ ] **Palette class-list lock — blocks the training run.** Before starting the GPU job, confirm the palette is locked at the final v1: `ClassPalette.v1Standard` redefined in place with the eight coarse liquid classes (water, coffee, tea, milk, fruit_juice, soup, beer, wine), giving 24 solid + 8 liquid + 3 special = 35 channels — the enumerated ordered list in `MedataCore/Sources/Segmentation/ClassPalette.swift` / `tools/food_db/generate.py` FOOD_DATA — and that the FoodSeg103 remap (`class_mapping_foodseg103_v1.json`) targets it. The trained checkpoint's output-channel count must match the shipped palette; training on the pre-liquid layout forces a full retrain. Recorded per `specs/estimation/nutrition5k-calibration/` Req 9.4 (Decisions 22–23 of that spec).
- [ ] **Run the GPU transfer-learning job** (`tools/segmenter/train.py`): DeepLabV3 + MobileNetV3-Large @ 513×513 → `build/checkpoint.pt`. Needs: the remapped dataset and a CUDA GPU. The checkpoint is **export-eligible only if** the validation harness (task 9) reports mean IoU ≥ 0.60 on the held-out split **and** every carb-priority class (white_rice, brown_rice, pasta, bread_white, bread_wholemeal, potato_boiled, potato_mashed, chips_fries) ≥ 0.50; a sub-bar run records its shortfall in `lineage.metrics` and does not proceed to export. Satisfies **Req 3.1**; produces the bars asserted by **Req 3.2, 3.5** (and the per-class report, Req 3.3). The per-class floor / set may be tuned against this first real run (Req 3.5/3.6).

## On-Device Verification (Stage 7 — the MVP gate)

- [ ] **Verify Apple Neural Engine residency** for the exported `segmenter.mlpackage` in Xcode's Core ML performance report. Needs: a Mac + Xcode and the bundled artefact. Satisfies **Req 6.1**; required before the MVP gate is met.
- [ ] **Run a device capture** with the bundled Core ML segmenter on the v1 hardware floor (**iPhone 13 Pro Max**). Assert: `estimate.end success=true` (DEBUG-only signpost, `Pipeline.swift:468-473`), `segmenterSource = coreml_<…>` (not the dev-stub tag), a finite carbohydrate value **> 0**, and a non-degenerate food mask whose coverage is plausible for the captured plate (a deployment-distribution sanity check, distinct from the FoodSeg103 mIoU bar). Satisfies **Req 6.2**. This is also where the UI honesty surface (task 10) is verified by build + on-device per the testing-minimal posture.

## β_c Calibration Execution (Stages 9–10 — deferred past the MVP gate)

- [ ] **Acquire ≥ 30 gravimetric meals per class** — calibrated kitchen scale, per-item weighing, matched capture per meal. This is the **single largest project risk** (Decision 5): until it exists every class ships with β = 1.0 / `uncalibrated_unity` and the v1 accuracy bar cannot be measured. Satisfies **Req 8.2**.
- [ ] **Run calibrate + bake** once the meals exist: `make_fixtures.py` (SHA-256-stamped, checkpoint-pinned) → `HarnessCLI calibrate` → `build/beta.json` → `tools/food_db/generate.py` bake into `cofid_db.sqlite`. The harness code and the palette↔DB bake lock (tasks 11–12) are already in place; only the data and the run are missing. On calibration a class flips `uncalibrated_unity` → `calibrated`, the honesty surface stops flagging it, and the v1 accuracy bar (MAPE < 20%, MAE ≤ 25 g) becomes measurable for that class. Satisfies **Req 8.3** (and exercises the Req 8.4 lock). See `docs/ml-training.md` §§8–9; commands are not duplicated here.

## Notes

- The MVP gate (**Req 6.3**) is a composite: it is met only when the export-eligibility gates (Req 3.2, 3.5, 4.2, 4.3), bundling (Req 5.2), ANE residency (Req 6.1), and the on-device run (Req 6.2) all hold. It does **not** require β_c calibration or the v1 numeric-accuracy bar.
- Dataset-prep stages 1–2 (class mapping, fixed-seed splits) are automated and already scripted — they are not listed here, but they cannot run until Stage 0 provides the dataset.
