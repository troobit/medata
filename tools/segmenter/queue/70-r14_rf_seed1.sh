#!/bin/bash
# R14: R8 recipe plus LVIS repeat-factor sampling at T = 0.02 (task 15) — the ten classes under 2 % image frequency get r = 1.1–2.6, everything else r = 1; read against R8.
source "$(dirname "$0")/lib.sh"
run_variant r14_rf_seed1 -- --loss combined --class-weighting none --photometric-augment --repeat-factor-threshold 0.02 --seed 1
