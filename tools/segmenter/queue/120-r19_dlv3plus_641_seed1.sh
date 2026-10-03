#!/bin/bash
# R19: R16's exact recipe (R8 at target size 641, seed 1) on --arch deeplabv3plus_mnv3 — the shipping backbone and ASPP plus a DeepLabV3+ decoder (48-channel skip from the stride-4 stage, two 3x3 convs at 256, research note 4.6). The decoder is the only change from R16. Read against R16 (seed 1) and R17 (seed 2) at 641 on the mask block, boundary F first: R15 showed boundary quality is not loss-limited, so this asks whether stride-4 features let the model draw the edge. Region IoU and the readable-13 mean second. Weights 23,577,303 B FP16 (gate 25,165,824). Each step costs more than R16's (conv multiply-adds 3x, CPU inference ~1.8x), so an epoch may pass the default 90-minute stall window — hence 3 h here.
source "$(dirname "$0")/lib.sh"
MEDATA_STALL_SECS=10800
run_variant r19_dlv3plus_641_seed1 -- --loss combined --class-weighting none --photometric-augment --target-size 641 --seed 1 --arch deeplabv3plus_mnv3
