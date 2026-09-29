#!/bin/bash
# R12: R8 with the dice share raised from 0.5 to 0.75 — research note 4.2's region-term hypothesis (coherent regions, fewer speckles) taken one step further.
source "$(dirname "$0")/lib.sh"
run_variant r12_dice075_seed1 -- --loss combined --class-weighting none --photometric-augment --dice-weight 0.75 --seed 1
