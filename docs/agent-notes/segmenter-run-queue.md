# Segmenter run queue — serial training on the local Mac

How multi-hour training runs are queued, run and read on the one MPS machine.
Recipe history and verdicts live in
`specs/estimation/estimation-quality/tasks-segmenter-training-pipeline.md`;
this note is the mechanics and the reading rules.

## Mechanics

- `tools/segmenter/run_queue.sh` runs every `tools/segmenter/queue/NN-<name>.sh`
  in name order, one at a time. Launch from the repo root, detached:
  `nohup caffeinate -is tools/segmenter/run_queue.sh >/dev/null 2>&1 &`
- State is under `tools/segmenter/build/queue/` (gitignored): `runner.log`,
  `runner.pid`, `<entry>.log` (the entry's own output), `done/<entry>` holding
  the exit code and finish time. Train and validation logs land beside the
  historical ones in `tools/segmenter/build/` as `train_<name>_<date>.log`,
  `validate_<name>_leakfree_v2anchor.log`, `lineage-<name>.json`,
  `checkpoint_<name>.pt`.
- An entry is three lines: source `lib.sh`, call
  `run_variant <name> [--epochs N] -- <recipe flags>`. `lib.sh` supplies the
  fixed envelope (merged corpus, 36 classes, 513, batch 16, lr 1e-3) and runs
  the leak-free anchor validation after training. Its exit code is the
  validation's; 1 means below the 0.48 gate and is expected today.
- `PAUSE` in the state dir holds the runner between entries; `STOP` makes it
  exit after the current one. Both are plain files. The runner re-globs the
  queue dir before each entry, so appending a new entry while it runs is fine.
- The runner execs a copy of itself from the state dir, so editing
  `run_queue.sh` while it is live is safe. `lib.sh` and the entries are read
  when their run starts — only append, never edit a live one.
- Dry run: `MEDATA_QUEUE_DIR=<scratch queue> MEDATA_QUEUE_STATE=<scratch state>
  tools/segmenter/run_queue.sh` with entries that just echo and exit.

## Never edit train.py while a run is live

DataLoader workers spawn each epoch and re-import `train.py` from disk. New
code against the old pickled dataset object crashes the run mid-training. Land
trainer changes only in a `PAUSE` window: touch `PAUSE`, wait for the current
entry's `done/` marker, edit, test (`tools/segmenter/.venv/bin/python -m pytest
tools/segmenter/tests -q`), commit, remove `PAUSE`.

## Reading a run

- The anchor is `data/foodseg103_remapped_v2` split `heldout_leakfree`, 182
  images. `run_validation.py` writes `mean_iou` and `per_class_iou` into the
  run's lineage file; compare two runs with a few lines of Python over their
  `metrics.per_class_iou`.
- Three classes have zero held-out truth pixels (bread_wholemeal, brown_rice,
  potato_mashed) and so do beer, milk and water. A run that never predicts one
  of them shows it as absent and drops it from the mean; a run that predicts it
  anywhere scores 0.0 and the mean falls. Compare means on the common scored
  set as well as the tool's number, or a false-positive class masquerades as a
  recipe effect (R6 lost 0.04 of its 0.064 gap this way; R7 gained 0.009).
- Noise, measured by R7 (an unseeded exact repeat of R3, 2026-09-26): the
  mean is stable to 0.001 on the common set; single classes swing by up to
  0.45 (soup +0.45, apple -0.40) and staples by 0.05. A single-run tail-class
  reading means nothing. The seeded block R8/R9/R10 (task 13) measures how
  much of that seeding removes and sets the per-staple tolerance.
- The in-run val split over-reports: R6 trailed R3 by 0.03 there and by 0.064
  on the anchor; R4/R5 showed the same. Never judge on the training log.

## Seeds

`--seed` pins the Python/torch RNGs, the shuffle order (own generator) and each
worker's augmentation stream, and is recorded in lineage `train_config.seed`
(absent = unseeded, every run before 2026-09-26). MPS kernels are not all
deterministic; whether two same-seed runs agree on the anchor is R9's question.
Every queued variant uses seed 1 and is read against R8 (seed 1).

## Boundary weight

`--boundary-weight W [--boundary-band-px K]` (2026-09-27) makes the train
Dataset return `(image, mask, weights)` instead of `(image, mask)`; the val
Dataset never does. The train loop indexes the batch by position for that
reason — any new consumer of the train loader must not unpack two values.
The map is built in the worker from the augmented mask (pure numpy,
`loss_config.boundary_weight_map`), so workers must re-import `loss_config`
by name, which is why train.py imports it via `sys.path`, not
`spec_from_file_location`. The reduction is `sum(w * ce) / sum(w)`; under
`--class-weighting sqrt_inverse` the denominator also carries the target-class
weight, so an all-ones map reproduces `nn.CrossEntropyLoss(weight=...)`
exactly (test_train_boundary.py checks this for every loss). Both flags are
recorded in lineage and drift-checked on resume; absent = off.
