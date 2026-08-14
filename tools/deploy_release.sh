#!/usr/bin/env bash
# deploy_release.sh — plain Release build (real MLM).
# Requires the exported model at
# MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage — without it the
# app throws segmenterModelMissing at pipeline construction.
#
# Usage: DEVICE_UDID=<devicectl id> bash tools/deploy_release.sh
# (normally invoked as `make deploy-release`)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_UDID="${DEVICE_UDID:?set DEVICE_UDID (xcrun devicectl list devices)}"
BUNDLE_ID="${BUNDLE_ID:-rtob.MeData}"
DERIVED_RELEASE="${DERIVED_RELEASE:-/tmp/medata-release}"
# Same expression as Makefile's BUILD_STAMP: <sha>[-dirty]-<timestamp>, with
# dirtiness over TRACKED files only. Both git calls carry -C "$REPO_ROOT" — a
# deploy invoked from another directory would otherwise measure that tree.
BUILD_STAMP="${BUILD_STAMP:-$(git -C "$REPO_ROOT" rev-parse --short HEAD)$(git -C "$REPO_ROOT" diff --quiet HEAD || echo '-dirty')-$(date +%Y%m%d-%H%M%S)}"

MODEL_PATH="$REPO_ROOT/MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage"
APP_PATH="$DERIVED_RELEASE/Build/Products/Release-iphoneos/MeData.app"

if [ ! -d "$MODEL_PATH" ]; then
    echo "error: $MODEL_PATH missing — export it first:" >&2
    echo "  tools/segmenter/.venv/bin/python tools/segmenter/export.py \\" >&2
    echo "      --checkpoint tools/segmenter/build/checkpoint.pt --skip-tflite" >&2
    exit 1
fi

# Which model is about to go on the phone. The 12-hex id is stamped into the
# Core ML metadata by export.py as `medata.modelVersion`, and it is the SAME id
# the app reports as `segmenterSource = coreml_<id>` on every capture. Printed
# here because swapping the bundled model is a plain `cp -R` that leaves no
# other trace — the build stamp identifies the BUILD, not the model in it.
MODEL_VERSION="$(strings -a "$MODEL_PATH/Data/com.apple.CoreML/model.mlmodel" 2>/dev/null \
    | grep -A1 -x 'medata\.modelVersion' | tail -1)"
[ -n "$MODEL_VERSION" ] || MODEL_VERSION="unstamped (exported without --checkpoint)"
echo "BUNDLED SEGMENTER: $MODEL_VERSION"

xcodebuild build -project "$REPO_ROOT/MeData/MeData.xcodeproj" -scheme MeData \
    -configuration Release -destination "id=$DEVICE_UDID" \
    -derivedDataPath "$DERIVED_RELEASE" -allowProvisioningUpdates \
    MEDATA_BUILD_STAMP="$BUILD_STAMP"

# First install attempt can fail with a transient CoreDeviceError 4000
# device-disconnect — retry once.
if ! xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"; then
    echo "install failed (transient CoreDeviceError 4000 is common) — retrying once"
    xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"
fi

xcrun devicectl device process launch --device "$DEVICE_UDID" \
    --terminate-existing "$BUNDLE_ID"

echo ""
echo "DEPLOYED BUILD STAMP: $BUILD_STAMP  (Release + segmenter)"
echo "DEPLOYED SEGMENTER:   $MODEL_VERSION"
echo "Every capture from this install stamps segmenterSource=coreml_$MODEL_VERSION"
