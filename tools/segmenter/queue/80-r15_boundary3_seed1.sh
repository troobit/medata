#!/bin/bash
# R15: R8 recipe plus a boundary-weighted CE term (weight 3 within 2 px of a label change) — boundary F sat at 0.45–0.46 for every recipe from R3 to R9, so the loss is made to care about edges; read against R8 on food IoU, region IoU, boundary F and the truth-bearing class mean.
source "$(dirname "$0")/lib.sh"
run_variant r15_boundary3_seed1 -- --loss combined --class-weighting none --photometric-augment --boundary-weight 3 --boundary-band-px 2 --seed 1
