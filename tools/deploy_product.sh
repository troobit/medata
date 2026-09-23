#!/usr/bin/env bash
# deploy_product.sh — ProductRelease build (ml-feedback-loop Req 9).
#
# ProductRelease duplicates Release with ONE difference: FIELD_LOOP is absent
# from SWIFT_ACTIVE_COMPILATION_CONDITIONS, so every `App/FieldNote*.swift`
# file and every `#if FIELD_LOOP` block compiles out. Everything else — the
# real segmenter, the capture-bundle recorder, the estimation path — is
# identical to Release (Req 9.3).
#
# Usage: DEVICE_UDID=<devicectl id> bash tools/deploy_product.sh
#        INSTALL=0 bash tools/deploy_product.sh   # build + gate only, no device
# (normally invoked as `make deploy-product` / `make build-product`)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE_ID="${BUNDLE_ID:-rtob.MeData}"
DERIVED_PRODUCT="${DERIVED_PRODUCT:-/tmp/medata-product}"
INSTALL="${INSTALL:-1}"
BUILD_STAMP="${BUILD_STAMP:-$(git -C "$REPO_ROOT" rev-parse --short HEAD)$(git -C "$REPO_ROOT" diff --quiet HEAD || echo '-dirty')-$(date +%Y%m%d-%H%M%S)}"

MODEL_PATH="$REPO_ROOT/MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage"
APP_PATH="$DERIVED_PRODUCT/Build/Products/ProductRelease-iphoneos/MeData.app"

if [ ! -d "$MODEL_PATH" ]; then
    echo "error: $MODEL_PATH missing — export it first:" >&2
    echo "  tools/segmenter/.venv/bin/python tools/segmenter/export.py \\" >&2
    echo "      --checkpoint tools/segmenter/build/checkpoint.pt --skip-tflite" >&2
    exit 1
fi

# INSTALL=0 builds for the generic iOS device so the gate is runnable with no
# phone attached; the install path needs the real destination.
if [ "$INSTALL" = "1" ]; then
    DESTINATION="id=${DEVICE_UDID:?set DEVICE_UDID (xcrun devicectl list devices)}"
else
    DESTINATION="generic/platform=iOS"
fi

xcodebuild build -project "$REPO_ROOT/MeData/MeData.xcodeproj" -scheme MeData \
    -configuration ProductRelease -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED_PRODUCT" -allowProvisioningUpdates \
    MEDATA_BUILD_STAMP="$BUILD_STAMP"

# Product gate (Req 9.1). `profile=field` is part of the os_log FORMAT string in
# App/App.swift's launch line, emitted only inside `#if FIELD_LOOP`; if it
# survives into this binary the condition leaked and the field machinery
# shipped. It has to be a format literal, not an interpolated value: Swift
# stores a 13-byte String as a small string in registers, so an interpolated
# "profile=field" never reaches the binary at all and this grep would pass on
# both profiles. `strings` rather than `nm`: a stripped Swift Release binary
# keeps its literals and loses its symbol names, so nm reads clean on a binary
# that is not.
#
# Two more assertions follow it, because an absence proves nothing on its own:
# that `profile=product` IS present (so the launch line compiled at all), and
# that no `fieldnote.` log literal survives (the note layer's own strings —
# independent evidence that App/Field*.swift compiled out, not just that one
# token did).
BINARY="$APP_PATH/MeData"
if [ ! -f "$BINARY" ]; then
    echo "error: built binary missing at $BINARY" >&2
    exit 1
fi
if strings -a "$BINARY" | grep -q 'profile=field'; then
    echo "PRODUCT GATE FAILED: 'profile=field' is present in $BINARY" >&2
    echo "  FIELD_LOOP leaked into the ProductRelease configuration." >&2
    exit 1
fi
if ! strings -a "$BINARY" | grep -q 'profile=product'; then
    echo "PRODUCT GATE FAILED: 'profile=product' absent from $BINARY" >&2
    echo "  The launch-identity line did not compile in — the gate above proved nothing." >&2
    exit 1
fi
if strings -a "$BINARY" | grep -q 'event=fieldnote\.'; then
    echo "PRODUCT GATE FAILED: field-note log literals are present in $BINARY" >&2
    exit 1
fi
echo "PRODUCT GATE: profile=field absent, profile=product present, no fieldnote literals"

if [ "$INSTALL" != "1" ]; then
    echo "BUILD STAMP: $BUILD_STAMP  (ProductRelease, not installed)"
    exit 0
fi

if ! xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"; then
    echo "install failed (transient CoreDeviceError 4000 is common) — retrying once"
    xcrun devicectl device install app --device "$DEVICE_UDID" "$APP_PATH"
fi

xcrun devicectl device process launch --device "$DEVICE_UDID" \
    --terminate-existing "$BUNDLE_ID"

echo ""
echo "DEPLOYED BUILD STAMP: $BUILD_STAMP  (ProductRelease)"
echo "Verify the app logged the SAME stamp with profile=product at launch:"
echo "  event=launch buildStamp=$BUILD_STAMP ... profile=product"
