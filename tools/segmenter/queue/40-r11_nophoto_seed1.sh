#!/bin/bash
# R11: R8 without photometric augmentation — Decision 36's unseparated lever; attributes the augmentation's offline share of R3's gain.
source "$(dirname "$0")/lib.sh"
run_variant r11_nophoto_seed1 -- --loss combined --class-weighting none --seed 1
