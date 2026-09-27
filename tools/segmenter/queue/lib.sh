#!/bin/bash
# Shared body for serial training-queue entries (docs/agent-notes/segmenter-run-queue.md).
# Sourced by each tools/segmenter/queue/NN-<name>.sh; run from the repo root.
#
#   run_variant <name> [--epochs N] -- <train.py recipe flags...>
#
# Trains into build/checkpoint_<name>.pt with the train log at
# build/train_<name>_<YYYYMMDD>.log, keeps the lineage as build/lineage-<name>.json,
# then validates on the leak-free anchor into build/validate_<name>_leakfree_v2anchor.log.
# Exit code is the validation's (1 = below the 0.48 gate, expected today) or the
# trainer's when training fails. Never edit this file while the queue is live.
set -uo pipefail

MEDATA_ROOT="${MEDATA_ROOT:-/Users/r/repos/medata}"
PY="$MEDATA_ROOT/tools/segmenter/.venv/bin/python"
B="$MEDATA_ROOT/tools/segmenter/build"
DATA_TRAIN="$MEDATA_ROOT/data/merged_foodseg_foodrec2022"
DATA_ANCHOR="$MEDATA_ROOT/data/foodseg103_remapped_v2"

run_variant() {
    local name="$1"; shift
    local epochs=12
    while [ "$1" != "--" ]; do
        case "$1" in
            --epochs) epochs="$2"; shift 2 ;;
            *) echo "[queue] run_variant: unknown option $1" >&2; return 2 ;;
        esac
    done
    shift  # the --
    local stamp; stamp="$(date '+%Y%m%d')"
    local ckpt="$B/checkpoint_${name}.pt"
    local tlog="$B/train_${name}_${stamp}.log"
    local vlog="$B/validate_${name}_leakfree_v2anchor.log"
    cd "$MEDATA_ROOT" || return 2
    echo "[queue] $name: train start $(date '+%Y-%m-%d %H:%M:%S') epochs=$epochs flags: $*"
    "$PY" tools/segmenter/train.py \
        --data "$DATA_TRAIN" \
        --num-classes 36 --target-size 513 \
        --epochs "$epochs" --batch-size 16 --lr 1e-3 \
        --out "$ckpt" "$@" >> "$tlog" 2>&1
    local rc=$?
    if [ $rc -ne 0 ]; then
        echo "[queue] $name: TRAIN FAILED exit=$rc $(date '+%Y-%m-%d %H:%M:%S') — see $tlog"
        return $rc
    fi
    echo "[queue] $name: train done $(date '+%Y-%m-%d %H:%M:%S')"
    cp "$B/lineage.json" "$B/lineage-${name}.json"
    "$PY" tools/segmenter/run_validation.py \
        --checkpoint "$ckpt" \
        --data "$DATA_ANCHOR" \
        --split heldout_leakfree \
        --lineage "$B/lineage-${name}.json" > "$vlog" 2>&1
    rc=$?
    echo "[queue] $name: validation exit=$rc (1 = below the 0.48 gate, expected) $(date '+%Y-%m-%d %H:%M:%S')"
    grep -E "mean food-class IoU|staple |mask " "$vlog"
    return $rc
}
