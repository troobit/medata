#!/bin/bash
# R9: R8 again, same seed — is MPS training deterministic under --seed? If the anchor per-class IoU matches R8 exactly, seeded comparisons are exact; if not, |R9 - R8| is the residual noise floor.
source "$(dirname "$0")/lib.sh"
run_variant r9_seed1_repeat -- --loss combined --class-weighting none --photometric-augment --seed 1
