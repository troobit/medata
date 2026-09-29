#!/bin/bash
# R8b: R8's exact recipe and seed on the merged trainer (mask metrics + boundary-loss code, flags off). R11 and R12 — the first two runs after that merge — both lost tea, fruit_juice and soup almost entirely; if R8b loses them too, the merge changed the flag-off path and R11/R12 are not attributable; if R8b matches R8, the liquids are fragile and the levers stand.
source "$(dirname "$0")/lib.sh"
run_variant r8b_seed1_newtrainer -- --loss combined --class-weighting none --photometric-augment --seed 1
