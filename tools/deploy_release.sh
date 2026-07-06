#!/usr/bin/env bash
# deploy_release.sh — plain Release build (real Core ML segmenter), installed
# and launched on a connected device.
#
# This is deploy_release_stub.sh WITHOUT the Package.swift stub-forcing edit:
# Release builds use the real bundled segmenter.mlpackage (DEV_STUB_SEGMENTER
# is Debug-only). Requires the exported model at
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
BUILD_STAMP="${BUILD_STAMP:-$(git -C "$REPO_ROOT" rev-parse --short HEAD)-$(date +%Y%m%d-%H%M%S)}"

MODEL_PATH="$REPO_ROOT/MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage"
APP_PATH="$DERIVED_RELEASE/Build/Products/Release-iphoneos/MeData.app"

if [ ! -d "$MODEL_PATH" ]; then
    echo "error: $MODEL_PATH missing — export it first:" >&2
    echo "  tools/segmenter/.venv/bin/python tools/segmenter/export.py \\" >&2
    echo "      --checkpoint tools/segmenter/build/checkpoint.pt --skip-tflite" >&2
    exit 1
fi

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
echo "DEPLOYED BUILD STAMP: $BUILD_STAMP  (Release + real segmenter)"
