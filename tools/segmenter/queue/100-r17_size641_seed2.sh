#!/bin/bash
# R17: exact R16 recipe (R8 at target size 641) with seed 2 — the 641 noise band. R16 is a single run read against a 513 band; this says whether its region-IoU lead (0.5107 vs 0.4808–0.5029) survives a second draw at the same size. Read against R16 on the readable-13 mean and the mask block, both scored at 641.
source "$(dirname "$0")/lib.sh"
run_variant r17_size641_seed2 -- --loss combined --class-weighting none --photometric-augment --target-size 641 --seed 2
