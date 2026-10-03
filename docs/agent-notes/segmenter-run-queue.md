# Segmenter run queue — serial training on the local Mac

How multi-hour training runs are queued, run and read on the one MPS machine.
Recipe history and verdicts live in
`specs/estimation/estimation-quality/tasks-segmenter-training-pipeline.md`;
this note is the mechanics and the reading rules.

## Research handoff after the decoder merge (2026-10-04)

`research` and `origin/research` both contain decoder merge `7c56f0d`; the
segmenter suite passed 339 tests during the merge. `../MODELRESUME.md` describes
the earlier recovery window and is now stale. Its watcher merged on **marker
presence**, although R17's marker says exit 124: the watchdog killed R17 after
epoch 7, leaving `checkpoint_r17_size641_seed2.pt.resume.pt`. R17 has no final
checkpoint, v3 validation, or verdict yet. Do not treat the merge as an R17
success or rerun the watcher.

The live serial runner started R18 (`110-r18_size769_seed1`) on 2026-10-03 at
19:36; it is a 769-pixel resolution measurement. A queued
`115-r17_resume_after_r18` resumes R17's sidecar with the identical 641-pixel
recipe and validates it on `heldout_leakfree_v3`. It runs between R18 and R19.
R19's entry checks successful R18 and R17 recovery markers before starting.
Either prerequisite failure creates `build/queue/PAUSE`. The queue must stay
serial: never launch another MPS trainer while R18 is active.

For a fresh human or agent session, check `git status --short --branch`,
`ps -axo pid,ppid,etime,command` (filter for `run_queue`, `train.py`),
`build/queue/runner.log`, `build/queue/done/`, and the latest train/validate
logs. Check whether `build/queue/PAUSE` exists. If R18 or the R17 recovery has
failed, diagnose its log and sidecar before releasing PAUSE; a `done/` file
with a nonzero code is a failure, not completion. Do not restart a trainer
without checking the process list and its final checkpoint first. An old
nonzero marker from R8–R16 can mean the former strict validation gate rejected
an otherwise valid measurement; read its train/validation log and lineage.

Once R17, R18 and R19 have final checkpoints and v3 lineage metrics, record
their results in the estimation-quality task file. Compare R17 to R16 at 641
to measure seed spread; compare R18 to that 641 pair to judge the extra
resolution and cost; compare R19 to R16 (same 641 size and seed) for the decoder
effect, with R17 as a second baseline. Use the readable-28 mean and mask block
on the **same v3 anchor**, with the prediction intervals below. Boundary F is
the decoder's primary metric, then region IoU and staples. Check for an actual
effect before considering export or a device run. Decoder adoption requires a
spec decision and an iPhone 16 Pro ANE latency measurement; R19 itself is only
an experiment. The currently bundled model is unchanged.

## Mechanics

- `tools/segmenter/run_queue.sh` runs every `tools/segmenter/queue/NN-<name>.sh`
  in name order, one at a time. Launch from the repo root, detached:
  `nohup caffeinate -is tools/segmenter/run_queue.sh >/dev/null 2>&1 &`
- State is under `tools/segmenter/build/queue/` (gitignored): `runner.log`,
  `runner.pid`, `<entry>.log` (the entry's own output), `done/<entry>` holding
  the exit code and finish time. Train and validation logs land beside the
  historical ones in `tools/segmenter/build/` as `train_<name>_<date>.log`,
  `validate_<name>_leakfree_v3anchor.log` (runs before 2026-10-03:
  `_leakfree_v2anchor.log`, the 182-image anchor), `lineage-<name>.json`,
  `checkpoint_<name>.pt`.
- An entry is three lines: source `lib.sh`, call
  `run_variant <name> [--epochs N] -- <recipe flags>`. `lib.sh` supplies the
  fixed envelope (merged corpus, 36 classes, 513, batch 16, lr 1e-3) and runs
  the leak-free anchor validation after training. Its exit code is the
  validation's. It echoes
  the validation's `mean food-class IoU`, `staple` and `mask ` lines into
  `runner.log`.
- `PAUSE` in the state dir holds the runner between entries; `STOP` makes it
  exit after the current one. Both are plain files. The runner re-globs the
  queue dir before each entry, so appending a new entry while it runs is fine.
- The runner execs a copy of itself from the state dir, so editing
  `run_queue.sh` while it is live is safe. `lib.sh` and the entries are read
  when their run starts — only append, never edit a live one.
- Dry run: `MEDATA_QUEUE_DIR=<scratch queue> MEDATA_QUEUE_STATE=<scratch state>
  tools/segmenter/run_queue.sh` with entries that just echo and exit.

## Stalls and sleep

2026-09-27: R11 showed no epoch for four hours (main thread on the Metal command
queue, workers idle) and was killed as a hang. It was not a hang: `pmset -g log`
shows the Mac asleep — lid closed, then "Low Power Sleep" on battery at 22:09 and
hibernation until the power button at 09:24 next morning. `caffeinate -is` does
not survive a lid close without an external display, nor a battery low-power
sleep. Training needs AC power and either the lid open or clamshell mode on the
hub (docs/ml-training.md §4 run hygiene). A run that stopped writing but whose
process is alive and whose CPU time is barely advancing is a sleeping Mac, not a
stalled trainer; it resumes on wake.

`lib.sh` keeps a watchdog for real stalls (no log line for `MEDATA_STALL_SECS`,
default 5400 s, then kill, exit 124) but measures from the later of the last log
line and `kern.waketime`, so time asleep never counts. To re-run an entry that
the watchdog killed: `rm build/queue/done/<entry>`, move its train log aside (a
fresh start appends), `rm PAUSE`. A `.resume.pt` sidecar means an epoch completed;
resume with identical flags instead of starting fresh.

2026-09-28 afternoon: the first sleep-aware watchdog had a parse bug (`.*sec = ` also
matches `usec = ` in `kern.waketime`'s `{ sec = N, usec = M }`), so it read the wake
time as microseconds, fell back to wall-clock, and killed R12 during a maintenance
DarkWake in a three-hour standby. Fixed (`\{ sec = N,`). A DarkWake counts as a wake
for this purpose: processes run during it, and `kern.waketime` moves, so the age
resets. R12 and R13 were re-run from scratch (neither had an epoch).

## Never edit train.py while a run is live

DataLoader workers spawn each epoch and re-import `train.py` from disk. New
code against the old pickled dataset object crashes the run mid-training. Land
trainer changes only in a `PAUSE` window: touch `PAUSE`, wait for the current
entry's `done/` marker, edit, test (`tools/segmenter/.venv/bin/python -m pytest
tools/segmenter/tests -q`), commit, remove `PAUSE`.

## R17 and the decoder merge watcher: moving the laptop

Historical recovery instructions below preceded the 2026-10-03 merge. The
watcher has finished and must not be restarted. Use the handoff above for the
current queued recovery.

Checked 2026-10-03: both processes are detached (parent PID 1), so quitting
Codex or its terminal does not stop them. Ordinary sleep suspends them; reopen
on AC power to continue. A reboot or terminated process needs a restart.
The R17 sidecar was readable at epoch 5/12; termination loses at most the
unfinished epoch. Resume restores weights and optimiser, not the full RNG
stream, so it is not a bit-identical continuation.

The existing local watcher is `tools/segmenter/build/queue/land-decoder.sh`
(gitignored, not launchd and not automatically started at login). It checks
every 120 seconds for `done/100-r17_size641_seed2`, waits another 30 seconds,
merges `staging/decoder` into the main checkout, runs segmenter pytest, pushes
`research`, then removes `PAUSE`. R18 then runs before R19. Its log is
`tools/segmenter/build/queue/land-decoder.log`. Keep the branch until it lands;
its linked worktree is not required. The watcher expects a clean main checkout
on `research`. It treats any done marker as completion, even a nonzero exit;
on pytest failure its existing rollback is `git reset --hard HEAD~1`. Do not
make concurrent edits during the merge/test window. A failed push is only
logged; the script still releases PAUSE.

Check before restarting; if the trainer, queue and watcher are still alive,
leave them alone:

```sh
cd /Users/r/repos/medata
pgrep -fl 'train.py|run_queue.live.sh|land-decoder.sh'
tail -n 8 tools/segmenter/build/train_r17_size641_seed2_*.log
tail -n 8 tools/segmenter/build/queue/land-decoder.log
```

**After a reboot, with all three processes absent and R17 still incomplete:**
the queue does not automatically add `--resume`. Run R17 through the existing
queue library explicitly, while the restarted serial runner waits on PAUSE.
This keeps the exact recipe, validation and lineage-copy steps. Confirm the
sidecar exists and research is clean before running the block. Do not use this
block once R17 has completed (its sidecar is removed on successful training).

```sh
cd /Users/r/repos/medata
git status --short --branch
ls -lh tools/segmenter/build/checkpoint_r17_size641_seed2.pt.resume.pt

touch tools/segmenter/build/queue/PAUSE
rm -f tools/segmenter/build/queue/STOP
rm -f tools/segmenter/build/queue/done/100-r17_size641_seed2

nohup caffeinate -is bash -c '
  source tools/segmenter/queue/lib.sh
  run_variant r17_size641_seed2 -- \
    --loss combined --class-weighting none --photometric-augment \
    --target-size 641 --seed 2 \
    --resume tools/segmenter/build/checkpoint_r17_size641_seed2.pt.resume.pt
  rc=$?
  if [ "$rc" -eq 0 ]; then
    printf "0 %s\n" "$(date)" > tools/segmenter/build/queue/done/100-r17_size641_seed2
  fi
  exit "$rc"
' >> tools/segmenter/build/queue/r17-resume.log 2>&1 < /dev/null &

nohup caffeinate -is tools/segmenter/run_queue.sh \
  >> tools/segmenter/build/queue/restart.log 2>&1 < /dev/null &
nohup bash tools/segmenter/build/queue/land-decoder.sh \
  >> tools/segmenter/build/queue/watcher-restart.log 2>&1 < /dev/null &
```

The recovery wrapper writes the completion marker only after training AND
validation succeed. On failure, inspect `r17-resume.log` and the train/validate
logs; PAUSE stays set. If training finished and only validation failed, the
sidecar will be gone: rerun validation against the final checkpoint instead
of restarting training. The normal queue writes markers even on failure and
skips every marked entry, which is why stale failure markers must be removed
before restarting the watcher.

If **only the watcher** has died and R17/queue remain alive, run only its
`nohup bash .../land-decoder.sh` command after confirming it is absent. If
only the queue has died, inspect R17 and its marker first; do not start a
second R17 trainer. These are local background processes, not session jobs.

## Reading a run

- The anchor (since 2026-10-03, backlog 35) is `data/merged_foodseg_foodrec2022`
  split `heldout_leakfree_v3`: 2,506 images, built by
  `tools/segmenter/build_anchor.py` from every merged-corpus image outside
  `train` — FoodSeg103 heldout 830 and val 687, Food Recognition 2022
  validation 989 — after a duplicate audit against all 45,515 train images.
  `manifest.json` beside `images/` holds the per-class and per-source counts,
  the audit and a sha256. `queue/lib.sh` validates every run on it into
  `validate_<name>_leakfree_v3anchor.log`. Rebuild (deterministic, about a
  minute): `tools/segmenter/.venv/bin/python tools/segmenter/build_anchor.py`.
- It contains the merged `val` split. That is held out only because `train.py`
  evaluates val in eval mode and saves the LAST epoch. A trainer change that
  selects a checkpoint on val would silently make the anchor a training-time
  split. The in-run val number still over-reports (different metric, different
  image set) — never judge on the training log.
- The audit: stems, SHA-256, then a 64-bit pHash screen (12 bits, eight
  rotations/mirrors) judged by at most 4 bits or aligned 64×64 thumbnail
  correlation of at least 0.85. A pHash alone does not work on food photos:
  among 45k plates a 6–8 bit match is routinely an unrelated dish, while a
  colour-filtered copy of a train photo correlates at only 0.85. It dropped 59
  of 2,565 (19 byte-identical to train, 36 near-duplicates, 4 within-pool).
  FoodSeg103 ships the same photo under two ids, so a stem check proves
  nothing. Three of the old 182-image anchor's images are train copies.
- Residual leak the hash cannot see: Food Recognition 2022 splits by image,
  not by user, so its val shares users and scenes with train (the audit caught
  several burst shots and one user's repeated water glass). It inflates
  absolute numbers on FR22-heavy classes (water, coffee, cheese,
  bread_wholemeal), not A/B comparisons.
- `run_validation.py` writes `mean_iou`, `per_class_iou` and
  `metrics.mask_quality` (`food_iou`, `region_iou`, `boundary_f2`,
  `shortlist_top3_hit`, `n_images`, `n_regions`, `scored_at`; MD-29) into the
  lineage file. To re-score an older run onto v3, copy its lineage to
  `lineage-<name>_v3anchor.json` and pass that, so the recorded reading
  survives (about 4.5 minutes on MPS, 5.5 at 641).
- Noise on v3, six identical-recipe runs (R3, R7, R8, R9, R10, R8b): 28
  classes readable at single-run resolution (at least 20 images and at most
  0.10 spread). Tea and milk sit at the image bar and miss (0.14, 0.18 over
  six). Cereal (14 images), beer, potato_mashed, brown_rice and beans_baked
  cannot be read. Median per-class spread 0.034, fruit_juice the widest
  readable (0.099). Readable-28 mean band 0.4593–0.4703: a class-mean effect
  under ~0.011 is not a result. Mask bands: food IoU 0.8369–0.8404, region IoU
  0.4807–0.4923, boundary F 0.3875–0.3921, top-3 hit 0.8177–0.8268. Staple
  spreads: potato_boiled 0.012, pasta 0.017, bread_white 0.023, white_rice
  0.024, chips_fries 0.071, bread_wholemeal 0.072.
- Judge a lever against a prediction interval, not the band edges. A seventh
  identical run lands outside a six-run min–max about 2 times in 7, so "just
  outside the band" is what noise does. Use z = (x − mean6) / (sd6 · √(7/6));
  |z| > 2.57 is outside the 95% interval for one new identical run. Expect
  about 1.4 of the 28 classes to fall outside it by chance. PI95 on v3:
  readable-28 mean 0.4552–0.4757, food IoU 0.8345–0.8424, region IoU
  0.4758–0.4997, boundary F 0.3838–0.3952, top-3 hit 0.8141–0.8335. A class
  with a tiny spread can show a large z on a small absolute move, so read the
  absolute difference beside z.
- Absolute levels differ by source and must not be compared across anchors.
  FR22's polygon-traced masks read food IoU ~0.78 and boundary F ~0.31 where
  FoodSeg103 reads ~0.88 and ~0.44 for the same checkpoint. Region IoU and
  top-3 are level across sources. A resolution lever shows up only on
  FoodSeg103 (FR22 photos are ~480 px, below the 513 input): R16 sits above
  the FoodSeg103 band on region IoU and boundary F, and inside or marginally
  below the FR22 one.
  `run_validation.py` reports only the whole-split block; for a per-source
  reading, group `mask_quality_over_loader`'s per-image scores by stem
  (`fr22_` prefix = FR22) and pass each group to `mask_quality.summarise`.
- Only beans_baked has no held-out truth on v3. A class with no truth scores
  0.0 whenever a run predicts it anywhere and is dropped from the tool's mean
  when it does not, so the tool's own `mean_iou` stays unusable for verdicts.
  Read the readable-28 mean and the mask block.
- The 182-image `foodseg103_remapped_v2/heldout_leakfree` anchor stays for
  checkpoints trained on the pre-merge seed-1234 carve (`0295ea61edd9`,
  `24e0b022241a`), for which v3's FoodSeg103 images are training data. Its
  six-run bands (readable-13 mean 0.4783–0.5031; mask 0.8792–0.8873 /
  0.4808–0.5029 / 0.4433–0.4596 / 0.8033–0.8244) and every R3–R16 verdict in
  estimation-quality task 13/14 were read there. On it, six classes have no
  truth at all and anything under 20 images swings up to 0.78 between
  identical runs.

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
