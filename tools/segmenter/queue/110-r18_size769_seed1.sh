#!/bin/bash
# R18: R8 recipe at target size 769 (1 + 24·32, the next DeepLab-aligned step above 641) — is the resolution gain monotone? Costs 2.25× the 513 pixels per image; the export weight budget is unchanged (resolution adds no parameters) but the on-device cost is, so this is a measurement, not a candidate, unless region IoU moves by more than the 641 band. Read against R16/R17 on the mask block.
source "$(dirname "$0")/lib.sh"
run_variant r18_size769_seed1 -- --loss combined --class-weighting none --photometric-augment --target-size 769 --seed 1
