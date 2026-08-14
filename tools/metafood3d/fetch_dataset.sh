#!/usr/bin/env bash
# fetch_dataset.sh — resumable, detachable download of MetaFood3D components.
#
# The distribution is plain static files; the "password" on the project page is a
# client-side JS string comparison that only unhides the download div, so no auth,
# cookie or token is involved here. Access is still request-gated in the terms
# sense (form + approval, obtained 2026-08-10) — see docs/references.md.
#
# Naming matches what the browser produced for the components already on disk:
# the page's `download` attribute turns ./MetaFood3D_new/X.tar.gz into
# _MetaFood3D_new_X.tar.gz, so re-fetching is idempotent against those files.
#
# Usage (detached, survives a closed shell and a sleeping Mac):
#   nohup caffeinate -is bash tools/metafood3d/fetch_dataset.sh \
#       RGBD_videos.tar.gz RGBD_videos_flipped_food.tar.gz \
#       >> data/metafood3d_fetch.log 2>&1 &
#
# Re-running resumes each partial file (curl -C -) and skips any already at full
# length, so it is safe to re-launch after an interruption.

set -uo pipefail

BASE="https://lorenz.ecn.purdue.edu/~food3d/MetaFood3D_new"
DEST="${DEST:-/Users/r/repos/medata/data}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-100}"

[ "$#" -gt 0 ] || { echo "usage: $0 <component.tar.gz> [...]" >&2; exit 2; }

for component in "$@"; do
    out="$DEST/_MetaFood3D_new_${component}"
    want=$(curl -sS -I --max-time 60 "$BASE/$component" \
           | awk '/^[Cc]ontent-[Ll]ength/{print $2}' | tr -d '\r')
    if [ -z "$want" ]; then
        echo "component=$component status=no_content_length — skipped"
        continue
    fi
    echo "component=$component want_bytes=$want dest=$out"

    attempt=0
    while :; do
        have=$( [ -f "$out" ] && stat -f%z "$out" || echo 0 )
        [ "$have" = "$want" ] && break
        attempt=$((attempt + 1))
        if [ "$attempt" -gt "$MAX_ATTEMPTS" ]; then
            echo "component=$component status=gave_up attempts=$attempt have=$have want=$want"
            break
        fi
        echo "component=$component attempt=$attempt have=$have"
        # --speed-time/--speed-limit kills a stalled socket so the retry loop can
        # resume it, rather than hanging forever on a half-open connection.
        curl -fsS -C - --retry 5 --retry-delay 10 --retry-all-errors \
             --speed-limit 1024 --speed-time 120 \
             -o "$out" "$BASE/$component"
        sleep 5
    done

    have=$( [ -f "$out" ] && stat -f%z "$out" || echo 0 )
    if [ "$have" = "$want" ]; then
        echo "component=$component status=complete bytes=$have"
        echo "component=$component sha256=$(shasum -a 256 "$out" | cut -d' ' -f1)"
    fi
done
echo "fetch done"
