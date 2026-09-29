#!/bin/bash
# R13: R8 on an 18-epoch schedule — R3 was still climbing at epoch 12 (0.4335 -> 0.4510 on merged val); R5 answered this for plain CE only.
source "$(dirname "$0")/lib.sh"
run_variant r13_18ep_seed1 --epochs 18 -- --loss combined --class-weighting none --photometric-augment --seed 1
