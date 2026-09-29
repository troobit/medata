#!/usr/bin/env bash
# Build the MeData iOS app, and optionally install and launch it on a device.
# Normally invoked through the Makefile (`make app` / `make deploy`); the full
# surface is documented in docs/build-and-field-loop.md.
#
#   CONFIG=Debug|Release|ProductRelease   Xcode configuration      (default Release)
#   SEGMENTER=model|stub                  which segmenter binds    (default: stub for Debug, model otherwise)
#   INSTALL=0|1                           install and launch       (default 1)
#   DEVICE_UDID=<devicectl id>            required when INSTALL=1
#   BUNDLE_ID=<id>                        default rtob.MeData

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$REPO_ROOT/MeData/MeData.xcodeproj"
MANIFEST="$REPO_ROOT/Package.swift"
MODEL_PACKAGE="$REPO_ROOT/MedataCore/Sources/Pipeline/Resources/segmenter.mlpackage"

CONFIG="${CONFIG:-Release}"
INSTALL="${INSTALL:-1}"
BUNDLE_ID="${BUNDLE_ID:-rtob.MeData}"

case "$CONFIG" in
    Debug|Release|ProductRelease) ;;
    *) echo "error: CONFIG=$CONFIG — expected Debug, Release or ProductRelease" >&2; exit 1 ;;
esac

# Debug defines DEV_STUB_SEGMENTER unconditionally in Package.swift, so it can
# only ever be the stub.
if [ "$CONFIG" = Debug ]; then
    SEGMENTER="${SEGMENTER:-stub}"
    if [ "$SEGMENTER" != stub ]; then
        echo "error: CONFIG=Debug cannot bind a real model — Package.swift defines" >&2
        echo "DEV_STUB_SEGMENTER for the debug configuration. Use CONFIG=Release." >&2
        exit 1
    fi
else
    SEGMENTER="${SEGMENTER:-model}"
    [ "$SEGMENTER" = model ] || [ "$SEGMENTER" = stub ] || {
        echo "error: SEGMENTER=$SEGMENTER — expected model or stub" >&2; exit 1; }
fi

# The one definition of the build stamp: <sha>[-dirty]-<timestamp>, injected into
# Info.plist via MEDATA_BUILD_STAMP and echoed by the app at launch. Dirtiness is
# over TRACKED files only (`git diff --quiet HEAD`, not `git status --porcelain`)
# — the routine mid-session divergence is untracked-but-unignored files, which
# say nothing about whether the built sources differ from the commit. Every git
# call carries -C so a deploy invoked from elsewhere measures this tree.
BUILD_STAMP="${BUILD_STAMP:-$(git -C "$REPO_ROOT" rev-parse --short HEAD)$(git -C "$REPO_ROOT" diff --quiet HEAD || echo '-dirty')-$(date +%Y%m%d-%H%M%S)}"

# Per-checkout, not a fixed /tmp path. Xcode's SourcePackages/checkouts records
# absolute paths, so two checkouts sharing one derived-data directory corrupt
# each other's package resolution — the same class of bug as the shared test log
# fixed on 2026-08-13, and orbit runs several worktrees at once by design.
DERIVED="${DERIVED:-$REPO_ROOT/.build/xcode/$CONFIG}"
APP="$DERIVED/Build/Products/$CONFIG-iphoneos/MeData.app"

# --- segmenter ---------------------------------------------------------------

bundled_model_version() {
    # export.py writes the 12-hex checkpoint prefix into the Core ML metadata as
    # medata.modelVersion; the app reports the same id as segmenterSource on
    # every capture. Print it because swapping the bundled model is a directory
    # copy that leaves no other trace — the build stamp names the BUILD, not the
    # model inside it. `|| true`: an unstamped model exits 1 through the pipe.
    strings -a "$MODEL_PACKAGE/Data/com.apple.CoreML/model.mlmodel" 2>/dev/null \
        | grep -A1 -x 'medata\.modelVersion' | tail -1 || true
}

MODEL_VERSION=stub
if [ "$SEGMENTER" = model ]; then
    if [ ! -d "$MODEL_PACKAGE" ]; then
        echo "error: no segmenter bundled at $MODEL_PACKAGE" >&2
        echo "  export one:  make model CHECKPOINT=tools/segmenter/build/checkpoint.pt" >&2
        echo "  or build against the stub:  make dev-stub" >&2
        exit 1
    fi
    MODEL_VERSION="$(bundled_model_version)"
    [ -n "$MODEL_VERSION" ] || MODEL_VERSION="unstamped (exported without --checkpoint)"
    echo "SEGMENTER: $MODEL_VERSION"
fi

# Forcing the stub into a non-Debug build means making the Package.swift define
# unconditional. It has to be a tracked-file edit rather than an environment
# variable: Xcode caches the evaluated manifest and does not re-evaluate it when
# only the environment changes, so an env-driven flag can silently build the
# WRONG configuration — the exact stale-binary failure this tooling exists to
# prevent. The trap guarantees the revert even when the build fails.
DEBUG_ONLY_DEFINE='.define("DEV_STUB_SEGMENTER", .when(configuration: .debug))'
UNCONDITIONAL_DEFINE='.define("DEV_STUB_SEGMENTER")'

if [ "$SEGMENTER" = stub ] && [ "$CONFIG" != Debug ]; then
    # The revert is a `git checkout`, so refuse a manifest that already differs.
    git -C "$REPO_ROOT" diff --quiet -- Package.swift || {
        echo "error: Package.swift has uncommitted changes; commit or stash them first." >&2
        exit 1; }
    grep -qF "$DEBUG_ONLY_DEFINE" "$MANIFEST" || {
        echo "error: expected '$DEBUG_ONLY_DEFINE' in Package.swift — the stub" >&2
        echo "mechanism has changed; update tools/deploy.sh to match." >&2
        exit 1; }
    trap 'git -C "$REPO_ROOT" checkout -- Package.swift; echo "Package.swift reverted."' EXIT
    perl -pi -e "s/\Q$DEBUG_ONLY_DEFINE\E/$UNCONDITIONAL_DEFINE/" "$MANIFEST"
    echo "SEGMENTER: stub forced into $CONFIG for this build"
fi

# --- build -------------------------------------------------------------------

# INSTALL=0 targets the generic device so a build is runnable with no phone
# attached; the install path needs the real destination to sign for it.
if [ "$INSTALL" = 1 ]; then
    DESTINATION="id=${DEVICE_UDID:?set DEVICE_UDID (xcrun devicectl list devices)}"
    SIGNING=""
else
    DESTINATION="generic/platform=iOS"
    SIGNING=CODE_SIGNING_ALLOWED=NO
fi

xcodebuild build -project "$PROJECT" -scheme MeData \
    -configuration "$CONFIG" -destination "$DESTINATION" \
    -derivedDataPath "$DERIVED" -allowProvisioningUpdates \
    MEDATA_BUILD_STAMP="$BUILD_STAMP" $SIGNING

# --- product gate ------------------------------------------------------------

# ProductRelease is Release minus FIELD_LOOP (ml-feedback-loop Req 9), so every
# App/Field*.swift file and every #if FIELD_LOOP block must have compiled out.
#
# `profile=field` is part of the os_log FORMAT string in the launch line and is
# emitted only inside #if FIELD_LOOP; if it survives, the condition leaked. It
# has to be a format literal rather than an interpolated value — Swift keeps a
# 13-byte String in registers, so an interpolated "profile=field" never reaches
# the binary and this grep would pass on both profiles. `strings` rather than
# `nm`: a stripped Swift Release binary keeps its literals and loses its symbol
# names, so nm reads clean on a binary that is not.
#
# Three assertions, because an absence proves nothing alone: that
# `profile=product` IS present (so the launch line compiled at all), and that no
# `fieldnote.` literal survives (the note layer's own strings — independent
# evidence that App/Field*.swift compiled out, not just that one token did).
if [ "$CONFIG" = ProductRelease ]; then
    BINARY="$APP/MeData"
    [ -f "$BINARY" ] || { echo "error: built binary missing at $BINARY" >&2; exit 1; }
    gate_fail() { echo "PRODUCT GATE FAILED: $1" >&2; exit 1; }
    LITERALS="$(strings -a "$BINARY")"
    if grep -q 'profile=field' <<<"$LITERALS"; then
        gate_fail "'profile=field' present — FIELD_LOOP leaked into ProductRelease"
    fi
    if ! grep -q 'profile=product' <<<"$LITERALS"; then
        gate_fail "'profile=product' absent — the launch line did not compile in, so the check above proved nothing"
    fi
    if grep -q 'event=fieldnote\.' <<<"$LITERALS"; then
        gate_fail "field-note log literals present"
    fi
    echo "PRODUCT GATE: profile=field absent, profile=product present, no fieldnote literals"
fi

if [ "$INSTALL" != 1 ]; then
    echo "BUILD STAMP: $BUILD_STAMP  ($CONFIG, segmenter=$MODEL_VERSION, not installed)"
    exit 0
fi

# --- install and launch ------------------------------------------------------

# The first install attempt can fail with a transient CoreDeviceError 4000
# device-disconnect; one retry clears it.
xcrun devicectl device install app --device "$DEVICE_UDID" "$APP" || {
    echo "install failed (transient CoreDeviceError 4000 is common) — retrying once"
    xcrun devicectl device install app --device "$DEVICE_UDID" "$APP"; }

xcrun devicectl device process launch --device "$DEVICE_UDID" \
    --terminate-existing "$BUNDLE_ID"

echo ""
echo "DEPLOYED BUILD STAMP: $BUILD_STAMP  ($CONFIG, segmenter=$MODEL_VERSION)"
echo "Match it against the app's own launch line before trusting any capture:"
echo "  event=launch buildStamp=$BUILD_STAMP ...   (make logs, or Console.app)"
