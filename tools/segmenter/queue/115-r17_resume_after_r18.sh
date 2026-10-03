#!/bin/bash
# R17's first attempt stalled after epoch 7. Resume it after R18, before R19.
# A failed prerequisite or resume holds the runner so R19 cannot start.
source "$(dirname "$0")/lib.sh"
state="$B/queue"
read -r r18_status _ < "$state/done/110-r18_size769_seed1" || r18_status=missing
if [ "$r18_status" != 0 ]; then
    echo "[queue] R18 did not finish successfully (exit=$r18_status); holding R19"
    touch "$state/PAUSE"
    exit 1
fi

sidecar="$B/checkpoint_r17_size641_seed2.pt.resume.pt"
if [ ! -f "$sidecar" ]; then
    echo "[queue] R17 resume sidecar missing; holding R19"
    touch "$state/PAUSE"
    exit 1
fi

# The earlier 90-minute watchdog stopped R17; allow three hours for an epoch.
MEDATA_STALL_SECS=10800
run_variant r17_size641_seed2 -- \
    --loss combined --class-weighting none --photometric-augment \
    --target-size 641 --seed 2 --resume "$sidecar"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "[queue] R17 resume or validation failed (exit=$rc); holding R19"
    touch "$state/PAUSE"
    exit "$rc"
fi

# The original marker says 124. Replace it only after training and v3 validation.
printf '0 %s (resumed by 115-r17_resume_after_r18)\n' "$(date '+%Y-%m-%d %H:%M:%S')" \
    > "$state/done/100-r17_size641_seed2"
echo "[queue] R17 recovered and validated; R19 may proceed"
