#!/bin/bash
# R10: the R3 recipe under a second seed — with R3, R7 and R8 that is four samples of the per-class spread; sets the per-staple tolerance.
source "$(dirname "$0")/lib.sh"
run_variant r10_seed2 -- --loss combined --class-weighting none --photometric-augment --seed 2
