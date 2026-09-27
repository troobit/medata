#!/bin/bash
# R16: R8 recipe at target size 641 instead of 513 — boundary F is resolution-limited; the anchor is scored at the checkpoint's own size, so the comparison is on the same images; read against R8 on the mask-quality block.
source "$(dirname "$0")/lib.sh"
run_variant r16_size641_seed1 -- --loss combined --class-weighting none --photometric-augment --target-size 641 --seed 1
