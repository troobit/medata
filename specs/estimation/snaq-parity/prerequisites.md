# Prerequisites for SNAQ Parity

These tasks must be completed by the user before or during implementation. Training runs, on-device measurements, and model promotion are human-gated STOP points throughout.

## Before Starting

- [ ] Kitchen scale (±1 g) available for the weighed-meal protocol; until then, package weights are the marked lower-fidelity fallback (design lane B).
- [ ] Recipe1M+-style ingredient corpus: confirm availability and licence terms for local use. Blocks *running* task 22's tool on real data — the code itself is testable on the committed fixture corpus.
- [ ] `tools/segmenter/.venv` intact (torch/torchvision/coremltools per requirements.txt); avoid `brew upgrade` near runs — Homebrew has previously dropped python@3.13 from under the venv.

## During Implementation

- [ ] **Tail-profile capture session** (after task 15 is deployed to the 16 Pro): capture real meals so outcome records accumulate per-view sub-stage timings (Req 4.1), plus a one-off Xcode Core ML performance report for ANE residency. Then record the Req 4.2 budget derivation (250 ms − measured non-model share) in `decision_log.md` **before any bake-off verdict** — blocks acting on task 24's outputs.
- [ ] **Bake-off conversion runs + 16 Pro latency measurements** per candidate (after task 24): run `spike_convert.py` in the venv, measure each surviving `.mlpackage` via the Xcode performance report, complete each `build/spike_<candidate>.json` verdict.
- [ ] **Winner training run** (after task 18, and only for the top feasible candidate): detached-run hygiene per `docs/ml-training.md` §4 (nohup + caffeinate, lid open, never edit train.py mid-run); judge via `run_validation.py --split heldout_leakfree` against the 0.3776 anchor (Req 6.2, Decision 21 procedure).
- [ ] **External-matrix training run** (after task 22): same launch and judging procedure; lineage must show `source: recipe1m` and the mapping SHA.

## Before Testing

- [ ] **Benchmark meal set**: build to ≥ 20 weighed meals including the staple-floor foods via `BenchmarkView` (Req 1.6) — start with the foods on hand (lemons, cereal + milk, bread, basics). Known-weak staples are expected to refuse; capture them anyway (Req 1.5).
- [ ] **Model promotion** (Req 7.1/7.2) is human-executed: swap the bundled model only when a candidate beats the leak-free anchor AND the `promotionVerdict` gate passes on the re-run benchmark; record before/after figures with the decision.
- [ ] **Cycle completion** (Req 8.1/8.2): record each lever's verdict or explicit handoff — including the MyFoodRepo-273 bridge seeding if the ≤ 13 g target is unmet — in `decision_log.md`.
