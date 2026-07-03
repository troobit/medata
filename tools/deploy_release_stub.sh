#!/usr/bin/env bash
# deploy_release_stub.sh — Release build with DEV_STUB_SEGMENTER forced on,
# installed and launched on a connected device. Automates "Path B" from
# docs/agent-notes/device-build-and-test.md.
#
# Why this exists: the Debug stub runs at ~20 s/mask (-Onone), so the shutter
# never arms; a plain Release build has no segmenter until the real model ships
# and crashes at launch. Capture testing therefore needs Release + stub, which
# requires making the DEV_STUB_SEGMENTER define unconditional in Package.swift.
#
# Why edit-and-revert rather than an env var read inside Package.swift:
# Xcode caches the evaluated manifest and does not re-evaluate it when only the
# environment changes, so an env-driven flag can silently build the WRONG
# configuration — the exact stale-binary failure mode this tooling exists to
# kill. A tracked-file edit always invalidates the manifest; the trap below
# guarantees the revert even when the build fails.
#
# Usage: DEVICE_UDID=<devicectl id> bash tools/deploy_release_stub.sh
# (normally invoked as `make deploy-release-stub`)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE_UDID="${DEVICE_UDID:?set DEVICE_UDID (xcrun devicectl list devices)}"
BUNDLE_ID="${BUNDLE_ID:-rtob.MeData}"
DERIVED_RELEASE="${DERIVED_RELEASE:-/tmp/medata-release}"
BUILD_STAMP="${BUILD_STAMP:-$(git -C "$REPO_ROOT" rev-parse --short HEAD)-$(date +%Y%m%d-%H%M%S)}"

MANIFEST="$REPO_ROOT/Package.swift"
DEBUG_ONLY_DEFINE='.define("DEV_STUB_SEGMENTER", .when(configuration: .debug))'
UNCONDITIONAL_DEFINE='.define("DEV_STUB_SEGMENTER")'
APP_PATH="$DERIVED_RELEASE/Build/Products/Release-iphoneos/MeData.app"

# Refuse to touch a manifest that already has local changes — the revert below
# is a `git checkout` and would destroy them.
if ! git -C "$REPO_ROOT" diff --quiet -- Package.swift; then
    echo "error: Package.swift has uncommitted changes; commit or stash them first." >&2
    exit 1
fi

if ! grep -qF "$DEBUG_ONLY_DEFINE" "$MANIFEST"; then
    echo "error: expected '$DEBUG_ONLY_DEFINE' in Package.swift — the stub" >&2
    echo "mechanism has changed; update tools/deploy_release_stub.sh to match." >&2
    exit 1
fi

restore_manifest() {
    git -C "$REPO_ROOT" checkout -- Package.swift
    echo "Package.swift reverted (stub define back to Debug-only)."
}
trap restore_manifest EXIT

# Force the stub into Release: make the define unconditional.
perl -pi -e "s/\Q$DEBUG_ONLY_DEFINE\E/$UNCONDITIONAL_DEFINE/" "$MANIFEST"
echo "Package.swift: DEV_STUB_SEGMENTER forced unconditional for this build."

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
echo "DEPLOYED BUILD STAMP: $BUILD_STAMP  (Release + forced stub)"
echo "Launch from the HOME SCREEN after this, never Xcode Run — an Xcode Run"
echo "reinstalls a Debug build over it. Confirm on-device before trusting a"
echo "capture: the launch log line must show buildStamp=$BUILD_STAMP and"
echo "segmenterSource=stub, and preshutter.mask.update latencyMs must be"
echo "sub-second (tens of thousands of ms => you are on a Debug build)."
