#!/bin/bash
# R8: the R3 recipe of record, seeded — the reference every seeded variant is read against.
source "$(dirname "$0")/lib.sh"
run_variant r8_seed1 -- --loss combined --class-weighting none --photometric-augment --seed 1
