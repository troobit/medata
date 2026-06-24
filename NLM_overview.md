# NLM Overview — a reading overview for the human in the loop

> Orientation, not the source of truth. It frames what this work is and where the
> detail lives, so you can hold the shape of it in your head before going deeper.
> The authoritative recipe — every command and contract — is in
> [`docs/ml-training.md`](docs/ml-training.md); when this overview disagrees with
> it or with the code, those win. Reflects the `research` branch.

## Frame this correctly first

MeData is a **native iOS app** that estimates a meal's carbohydrates from one or
two photos using deterministic geometry plus a **27-class food segmenter**, all
**on-device**. There is **no cloud inference, no server, no Azure in the
estimation path** — so the usual cloud/SRE deployment model does not apply here:

- "Shipping the model" means producing one file, `segmenter.mlpackage`, and
  bundling it into the app binary — not deploying a service or endpoint.
- Training is the only off-device step; it runs once on a GPU box, offline.
- The whole pipeline already runs on a phone today behind a **development stub**.
  The single missing piece is the trained `segmenter.mlpackage`. Produce it and
  the pipeline goes live.

## Where to go for the detail

| When you need | Read |
|---|---|
| **The recipe** (env → data → train → validate → export → bundle) — the source of truth | [`docs/ml-training.md`](docs/ml-training.md), start at §1 |
| System shape, layers, conventions | [`docs/architecture.md`](docs/architecture.md) |
| Requirements / design / decisions | [`specs/research/`](specs/research/) |
| What's built vs what the model unblocks | [`docs/agent-notes/pipeline-wiring-status.md`](docs/agent-notes/pipeline-wiring-status.md) |
| Project intro, build, phase plan | [`README.md`](README.md) |

## Mental model

```
RawFrame (BGRA8)                         ← CaptureKit (ARKit)
   │  CoreMLSegmenter.segment(_:)        ← Segmentation module
   │    pre-process → engine.runInference → post-process
   ▼
ProbabilityTensor (27 channels)          ← your model's output contract
   │  Pipeline.estimate(...)             ← geometry · macros · confidence
   ▼
MealRecord (carb total)
```

The model plugs in at **`engine.runInference`** — today a stub, in Release a
Core ML model loaded from `segmenter.mlpackage`.

## The parts that matter

So you know what each piece is when it comes up — not to work in them directly:

- **The seam** — `MedataCore/Sources/Pipeline/PipelineFactory.swift`: where the
  app decides to load the real model (Release) or the stub (Debug).
- **Segmentation module** — `MedataCore/Sources/Segmentation/`: the wrapper
  around the model, the input/output transforms training must match, the
  27-channel class definition, and the stub running today.
- **Offline tooling** — `tools/segmenter/export.py` (turns a trained checkpoint
  into `segmenter.mlpackage`), `tools/food_db/generate.py` (food database + the
  canonical class order), `HarnessCLI` (the mIoU pass/fail gate).
- **One thing that bites silently:** the class order is hand-synced between the
  training side and the app and must never be reordered — `docs/ml-training.md`
  §2 explains why.

## Current state

- **Now:** full pipeline on device with a dev stub; carb numbers are placeholders.
- **The one blocker:** train + export `segmenter.mlpackage`.
- **Already resolved — don't re-investigate:** BGRA8 capture conversion, the real
  `Pipeline` factory, `VisionCardDetector`.
- **Deferred (out of MVP scope):** β_c calibration + end-to-end accuracy (need
  gravimetric data no public dataset has).
- **Cross-platform:** one PyTorch checkpoint exports to both Core ML (iOS) and
  TFLite (future Android) — Decision 28; Android re-exports the same checkpoint.

## First move

Open [`docs/ml-training.md`](docs/ml-training.md) and start at §1.
