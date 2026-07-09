# MeData developer loop.
#
# SwiftPM core:   make build / make test / make spell
# Device loop:    make deploy-device        (Debug — UI/non-capture work only)
#                 make deploy-release-stub  (Release + forced stub — capture testing)
#                 make logs-device          (pull filtered device logs)
#
# Device targets need a connected, paired iPhone. Override the default device:
#   make deploy-device DEVICE_UDID=<devicectl-identifier> DEVICE_NAME=<name>

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -ec

# Default device: `you` — iPhone 16 Pro, the current primary test device.
# DEVICE_UDID is the devicectl (CoreDevice) identifier from
# `xcrun devicectl list devices`, NOT the hardware UDID Finder/`log collect
# --device-udid` show. `logs-device` therefore matches on DEVICE_NAME instead.
# Override for another device:
#   make <target> DEVICE_UDID=<devicectl-id> DEVICE_NAME=<name>
DEVICE_UDID ?= 6AD781BA-89FF-5A82-A2A1-B5EC9469F465
DEVICE_NAME ?= you
BUNDLE_ID   ?= rtob.MeData

DERIVED_DEBUG   ?= /tmp/medata-debug
DERIVED_RELEASE ?= /tmp/medata-release
LOG_FILE    ?= /tmp/medata-device.log
LOG_ARCHIVE ?= /tmp/medata-device.logarchive
LOG_LAST    ?= 30m

# Build stamp: git short SHA + wall-clock time, injected into Info.plist and
# logged by the app at launch (event=launch in App/App.swift). Match the stamp
# printed here against the one in the device log before trusting any capture —
# stale binaries have silently invalidated whole test rounds before.
BUILD_STAMP := $(shell git rev-parse --short HEAD)-$(shell date +%Y%m%d-%H%M%S)

XCODEBUILD = xcodebuild -project MeData/MeData.xcodeproj -scheme MeData \
	-destination 'id=$(DEVICE_UDID)'

.PHONY: help build test build-app deploy-device logs-device deploy-release deploy-release-stub spell worktree

help:
	@echo "MeData targets:"
	@echo "  worktree             create .worktrees/<name> and share root's nextup.md into it"
	@echo "                       (name=<dir> [branch=<branch>]; branch defaults to name, off HEAD)"
	@echo "  build                swift build (SwiftPM core: MedataCore, Harness*)"
	@echo "  test                 swift test + print the two test totals (XCTest AND swift-testing)"
	@echo "  spell                Irish/British spelling lint (tools/check_spelling.sh)"
	@echo "  build-app            xcodebuild MeData for device, Debug  [DEVICE_UDID=$(DEVICE_UDID)]"
	@echo "  deploy-device        build-app + install + launch on the device, with build stamp"
	@echo "  deploy-release       Release build with the REAL bundled segmenter, install + launch"
	@echo "                       (requires an exported segmenter.mlpackage)"
	@echo "  deploy-release-stub  Release build with DEV_STUB_SEGMENTER forced on, install + launch"
	@echo "                       (capture testing — Debug stub is too slow to arm the shutter;"
	@echo "                        plain Release crashes until the real model ships)"
	@echo "  logs-device          collect + filter device logs (subsystem ie.medata.app) to"
	@echo "                       stdout and $(LOG_FILE)."
	@echo "                       LIMIT: post-hoc snapshot of the last LOG_LAST=$(LOG_LAST), not a"
	@echo "                       live stream — 'log stream' cannot attach to an iOS device and"
	@echo "                       devicectl has no log subcommand. For live viewing use Console.app"
	@echo "                       (recipe: docs/agent-notes/device-build-and-test.md)."

worktree:
	@tools/new_worktree.sh "$(name)" $(branch)

build:
	swift build

# Print BOTH totals: XCTest ("Executed N tests") and swift-testing
# ("Test run with N tests"). An agent once read only the swift-testing line and
# concluded the suite was 16 tests when it was 313 + 16.
test:
	swift test 2>&1 | tee /tmp/medata-swift-test.log
	@echo ""
	@echo "---- Test totals (two frameworks — report BOTH) ----"
	@echo "XCTest:        $$(grep -E 'Executed [0-9]+ tests' /tmp/medata-swift-test.log | tail -1 | sed 's/^[[:space:]]*//')"
	@echo "swift-testing: $$(grep -E 'Test run with [0-9]+ test' /tmp/medata-swift-test.log | tail -1 | sed 's/^[^A-Za-z]*//')"

spell:
	bash tools/check_spelling.sh

build-app:
	$(XCODEBUILD) -configuration Debug -derivedDataPath $(DERIVED_DEBUG) \
		MEDATA_BUILD_STAMP='$(BUILD_STAMP)' build
	@echo "BUILD STAMP: $(BUILD_STAMP)"

deploy-device: build-app
	xcrun devicectl device install app --device $(DEVICE_UDID) \
		$(DERIVED_DEBUG)/Build/Products/Debug-iphoneos/MeData.app \
		|| { echo "install failed (transient CoreDeviceError 4000 is common) — retrying once"; \
		     xcrun devicectl device install app --device $(DEVICE_UDID) \
		         $(DERIVED_DEBUG)/Build/Products/Debug-iphoneos/MeData.app; }
	xcrun devicectl device process launch --device $(DEVICE_UDID) --terminate-existing $(BUNDLE_ID)
	@echo ""
	@echo "DEPLOYED BUILD STAMP: $(BUILD_STAMP)"
	@echo "Verify the app logged the SAME stamp at launch:"
	@echo "  event=launch buildStamp=$(BUILD_STAMP) ...   (make logs-device, or Console.app)"

# Post-hoc log pull. `log collect --device-name` talks to a paired device;
# --device-udid would need the HARDWARE udid, which devicectl does not print,
# so we match by name. The device must be connected, unlocked and trusted.
# If collect fails with a permissions error, retry the make target with sudo.
logs-device:
	rm -rf $(LOG_ARCHIVE)
	log collect --device-name '$(DEVICE_NAME)' --last $(LOG_LAST) --output $(LOG_ARCHIVE)
	log show $(LOG_ARCHIVE) --predicate 'subsystem == "ie.medata.app"' \
		--info --debug --style compact | tee $(LOG_FILE)
	@echo ""
	@echo "Filtered log written to $(LOG_FILE) (full archive: $(LOG_ARCHIVE))"

# Plain Release with the real bundled segmenter (no manifest edit). Requires
# an exported segmenter.mlpackage; the script refuses to build without it.
deploy-release:
	DEVICE_UDID=$(DEVICE_UDID) BUNDLE_ID=$(BUNDLE_ID) BUILD_STAMP='$(BUILD_STAMP)' \
	DERIVED_RELEASE=$(DERIVED_RELEASE) bash tools/deploy_release.sh

# Release + stub for capture testing (docs/agent-notes/device-build-and-test.md
# Path B, automated). Edits Package.swift to force DEV_STUB_SEGMENTER on,
# builds/installs/launches, and ALWAYS reverts Package.swift (trap in script).
deploy-release-stub:
	DEVICE_UDID=$(DEVICE_UDID) BUNDLE_ID=$(BUNDLE_ID) BUILD_STAMP='$(BUILD_STAMP)' \
	DERIVED_RELEASE=$(DERIVED_RELEASE) bash tools/deploy_release_stub.sh
