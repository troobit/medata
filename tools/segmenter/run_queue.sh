#!/bin/bash
# Serial training-queue runner (docs/agent-notes/segmenter-run-queue.md).
#
# Runs every tools/segmenter/queue/NN-<name>.sh in name order, one at a time,
# skipping entries with a marker in build/queue/done/. State lives under
# build/queue/ (gitignored): runner.log, runner.pid, done/<entry> (holds the
# exit code), PAUSE (wait before starting the next entry — the window for
# landing train.py changes), STOP (exit after the current entry).
#
# Launch from the repo root, detached and sleep-proof:
#   nohup caffeinate -is tools/segmenter/run_queue.sh >/dev/null 2>&1 &
# The runner execs a copy of itself from build/queue/, so editing this file
# while it runs is safe; entries and lib.sh are read when their run starts.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
# Overridable for a dry run against a scratch queue (see the agent note).
Q="${MEDATA_QUEUE_DIR:-$ROOT/tools/segmenter/queue}"
STATE="${MEDATA_QUEUE_STATE:-$ROOT/tools/segmenter/build/queue}"
mkdir -p "$STATE/done"

if [ "${MEDATA_QUEUE_LIVE:-}" != "1" ]; then
    cp "$0" "$STATE/run_queue.live.sh"
    MEDATA_QUEUE_LIVE=1 MEDATA_QUEUE_DIR="$Q" MEDATA_QUEUE_STATE="$STATE" exec bash "$STATE/run_queue.live.sh"
fi

log() { echo "[runner] $(date '+%Y-%m-%d %H:%M:%S') $*" >> "$STATE/runner.log"; }
echo $$ > "$STATE/runner.pid"
log "start pid $$"

while true; do
    if [ -f "$STATE/STOP" ]; then log "STOP present — exiting"; break; fi
    while [ -f "$STATE/PAUSE" ]; do sleep 60; done
    next=""
    for entry in "$Q"/[0-9]*-*.sh; do
        [ -f "$entry" ] || continue
        name="$(basename "$entry" .sh)"
        [ -f "$STATE/done/$name" ] && continue
        next="$entry"; break
    done
    if [ -z "$next" ]; then log "queue empty — exiting"; break; fi
    name="$(basename "$next" .sh)"
    log "run $name"
    bash "$next" >> "$STATE/$name.log" 2>&1
    rc=$?
    echo "$rc $(date '+%Y-%m-%d %H:%M:%S')" > "$STATE/done/$name"
    log "done $name exit=$rc"
done
rm -f "$STATE/runner.pid"
log "end"
