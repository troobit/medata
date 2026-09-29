# MeData developer loop. `make help` lists every target; the prose that used to
# live in this file — what each configuration is for, how the model is paired to
# a build, and the field loop's phase contract — is in
# docs/build-and-field-loop.md.

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -ec

# DEVICE_UDID is the devicectl (CoreDevice) identifier from
# `xcrun devicectl list devices`, NOT the hardware UDID that Finder and
# `log collect --device-udid` want; `make logs` therefore matches on DEVICE_NAME.
DEVICE_UDID ?= 6AD781BA-89FF-5A82-A2A1-B5EC9469F465
DEVICE_NAME ?= you
BUNDLE_ID   ?= rtob.MeData

# The two axes of every app build: CONFIG is the literal Xcode configuration
# name, SEGMENTER which segmenter the binary binds. Left empty, SEGMENTER takes
# tools/deploy.sh's default — stub for Debug, which cannot bind a model, and the
# bundled model otherwise.
CONFIG    ?= Release
SEGMENTER ?=

LOG_FILE    ?= /tmp/medata-device.log
LOG_ARCHIVE ?= /tmp/medata-device.logarchive
LOG_LAST    ?= 10m

# tools/deploy.sh owns the build stamp, the segmenter check, the product gate and
# the install retry for every configuration.
DEPLOY = CONFIG=$(CONFIG) SEGMENTER=$(SEGMENTER) DEVICE_UDID=$(DEVICE_UDID) \
         BUNDLE_ID=$(BUNDLE_ID) bash tools/deploy.sh

# `python3` for the Mac-side tooling; the segmenter venv for anything importing
# torch or coremltools.
PYTHON ?= python3
SEGMENTER_PYTHON ?= tools/segmenter/.venv/bin/python

.PHONY: help build test test-corpus test-python spell food-db model app deploy \
        debug dev dev-stub product logs harness-accuracy spec-portfolio worktree \
        field-pull field-notes field-discard field-triage field-diagnose \
        field-report field-close field-derive

help:  ## list every target
	@awk 'BEGIN {FS = ":.*##"} \
	     /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } \
	     /^[a-z][a-z0-9-]*:.*##/ { printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2 }' \
	     $(MAKEFILE_LIST)
	@echo ""
	@echo "  Parameters, and the field loop's phase contract: docs/build-and-field-loop.md"
	@echo "  CONFIG=$(CONFIG)  DEVICE_NAME=$(DEVICE_NAME)  PYTHON=$(PYTHON)"

##@ Core (SwiftPM — no device needed)

build:  ## swift build: MedataCore and the harnesses
	swift build

# Print BOTH totals. `swift test` runs each bundle separately, so each framework
# prints one summary line per bundle and these sum them; an agent once read only
# the swift-testing line and reported 16 tests for a suite of 313 + 16. The log
# lives under this checkout's .build/ because parallel worktree runs would grep
# each other's totals from a shared /tmp path. pipefail: without it the exit
# status is tee's, so a failing suite passed by exit code.
TEST_LOG := $(CURDIR)/.build/medata-swift-test.log

test:  ## swift test, reporting both framework totals
	@mkdir -p $(dir $(TEST_LOG))
	set -o pipefail; swift test 2>&1 | tee $(TEST_LOG)
	@echo ""
	@echo "---- Test totals (two frameworks — report BOTH) ----"
	@echo "XCTest:        $$(grep -a -A1 -E "Test Suite 'All tests' (passed|failed)" $(TEST_LOG) | grep -a -oE 'Executed [0-9]+ tests?, with ([0-9]+ tests? skipped and )?[0-9]+ failures?' | awk '{t+=$$2; f+=$$(NF-1)} END{printf "Executed %d tests, %d failures (summed over bundles)\n", t, f}')"
	@echo "swift-testing: $$(grep -a -oE 'Test run with [0-9]+ tests? in [0-9]+ suites? (passed|failed)' $(TEST_LOG) | awk '{t+=$$4; s+=$$7; if ($$9=="failed") f++} END{printf "%d tests in %d suites, %d bundles failed (summed over bundles)\n", t, s, f}')"

test-corpus:  ## the ~20 min support-plane corpus beam search, which test skips
	MEDATA_CORPUS=1 swift test --filter SupportPlaneCorpusMeasurementTests

# Two invocations, not one: both directories carry a conftest.py and the
# field-loop modules import theirs by name, so pytest cannot collect them
# together.
test-python:  ## pytest for tools/food_db and tools/field_loop
	@$(PYTHON) -c 'import pytest' 2>/dev/null || { \
	  echo "$(PYTHON) has no pytest — rerun as: make test-python PYTHON=<interpreter>"; \
	  exit 1; }
	$(PYTHON) -m pytest tools/food_db/tests/ -q
	$(PYTHON) -m pytest tools/field_loop/tests/ -q

spell:  ## spelling lint
	bash tools/check_spelling.sh

# generate.py aborts before writing on a palette drift, a serving-coverage gap, a
# bad calibration artifact or a bad loop overlay, and the pytest suite is what
# proves those gates still fire — so pytest's presence is checked BEFORE the
# bake, or a missing one would leave fresh databases behind a gate that never
# ran. The loop overlay at
# tools/food_db/loop_overlay.json is read by default, so a plain run regenerates
# with every landed loop fix. CALIBRATION is the HarnessCLI calibrate artifact:
# the committed databases carry calibration lineage and that artifact is not in
# this repo, so a bare run aborts rather than baking the lineage away.
food-db:  ## regenerate the bundled food databases  [CALIBRATION=<artifact>]
	@$(PYTHON) -c 'import pytest' 2>/dev/null || { \
	  echo "$(PYTHON) has no pytest — rerun as: make food-db PYTHON=<interpreter>"; \
	  exit 1; }
	$(PYTHON) tools/food_db/generate.py \
	  $(if $(CALIBRATION),--calibration-json "$(CALIBRATION)",)
	$(PYTHON) -m pytest tools/food_db/tests/ -q

##@ App (CONFIG=Debug|Release|ProductRelease, SEGMENTER=model|stub)

app:  ## build the app without a device
	INSTALL=0 $(DEPLOY)

deploy:  ## build, install and launch, honouring CONFIG and SEGMENTER
	INSTALL=1 $(DEPLOY)

debug:  ## Debug + stub: UI and non-capture work
	$(MAKE) deploy CONFIG=Debug SEGMENTER=stub

dev:  ## Release + the bundled model: the everyday capture build
	$(MAKE) deploy CONFIG=Release SEGMENTER=model

# The Debug stub runs at ~20 s/mask under -Onone, so the shutter never arms, and
# plain Release crashes at launch until a model is exported.
dev-stub:  ## Release + forced stub: capture testing with no model exported
	$(MAKE) deploy CONFIG=Release SEGMENTER=stub

product:  ## ProductRelease + the shipping gate: Release minus FIELD_LOOP
	$(MAKE) deploy CONFIG=ProductRelease SEGMENTER=model

# Which model a build binds is otherwise the residue of an earlier `cp -R`, whose
# only trace is the 12-hex id a deploy prints. Needs the segmenter venv, and
# contends with a live training run for the MPS device — check
# tools/segmenter/build/queue/runner.log first.
model:  ## export a checkpoint into the app bundle  CHECKPOINT=<path>
	@test -n "$(CHECKPOINT)" || { \
	  echo "usage: make model CHECKPOINT=tools/segmenter/build/checkpoint_<run>.pt"; \
	  exit 1; }
	$(SEGMENTER_PYTHON) tools/segmenter/export.py \
	  --checkpoint "$(CHECKPOINT)" --skip-tflite

# Post-hoc only: `log stream` is host-only and devicectl has no log subcommand,
# so macOS offers no scriptable live stream for an iOS device — live viewing is
# Console.app. `log collect --device-name` because --device-udid wants the
# hardware udid, which devicectl does not print. Retry under sudo on a
# permissions error. Anything a pull must show has to be logged at .notice: iOS
# persists notice and above, and `log collect` reads only the persisted store.
logs:  ## collect and filter the last LOG_LAST of device logs
	rm -rf $(LOG_ARCHIVE)
	log collect --device-name '$(DEVICE_NAME)' --last $(LOG_LAST) --output $(LOG_ARCHIVE)
	log show $(LOG_ARCHIVE) --predicate 'subsystem == "ie.medata.app"' \
	    --info --debug --style compact | tee $(LOG_FILE)
	@echo ""
	@echo "Filtered log written to $(LOG_FILE) (full archive: $(LOG_ARCHIVE))"

##@ Field loop (phase order and file contracts: docs/build-and-field-loop.md)

field-pull:  ## full session off the device into the corpus  [PULL_DIR=<path>]
	$(PYTHON) tools/field_loop/field_pull.py \
	  --device $(DEVICE_UDID) --bundle-id $(BUNDLE_ID) \
	  $(if $(PULL_DIR),--pull-dir "$(PULL_DIR)",--prune)

field-notes:  ## notes and the events DB only — seconds, not hours
	$(PYTHON) tools/field_loop/field_pull.py --notes-only \
	  --device $(DEVICE_UDID) --bundle-id $(BUNDLE_ID)

# FieldMaintenance deletes a bundle only against its SHA-256, so clearing the
# phone without copying it first means removing the app rather than pruning it.
# The reinstall is BUILT before the uninstall, so a missing model or a broken
# compile cannot leave the phone with no app on it.
field-discard:  ## drop the Mac's captures and wipe the phone  CONFIRM=yes
	@test "$(CONFIRM)" = yes || { \
	  echo "usage: make field-discard CONFIRM=yes"; \
	  echo "  Deletes the corpus captures and the phone's app container. Cannot be undone."; \
	  exit 1; }
	$(MAKE) field-notes
	$(MAKE) app
	$(PYTHON) tools/field_loop/field_discard.py --confirm "$(CONFIRM)"
	xcrun devicectl device uninstall app --device $(DEVICE_UDID) $(BUNDLE_ID)
	$(MAKE) deploy

field-triage:  ## regenerate the triage ledger from the corpus
	$(PYTHON) tools/field_loop/field_triage.py

field-diagnose:  ## replay annotated captures into a cycle task file  [CYCLE=<n>]
	$(PYTHON) tools/field_loop/field_diagnose.py \
	  $(if $(CYCLE),--cycle $(CYCLE),) \
	  $(if $(REPLAY_SHA),--replay-checkpoint $(REPLAY_SHA),)

field-report:  ## alignment metrics across the corpus  [CYCLE=<n> OUT=<file>]
	$(PYTHON) tools/field_loop/field_report.py \
	  $(if $(CYCLE),--cycle $(CYCLE),) $(if $(OUT),--out "$(OUT)",)

# The loop's sole committer; run it in a dedicated worktree — it refuses a dirty
# tree, and research and main.
field-close:  ## judge a cycle's drafts and commit survivors  CYCLE=<n>
	@test -n "$(CYCLE)" || { \
	  echo "usage: make field-close CYCLE=<n> [APPLIED_AT=<YYYY-MM-DD> REPO=<worktree> PROBE_IMAGE=<path>]"; \
	  exit 1; }
	$(PYTHON) tools/field_loop/field_close.py \
	  --cycle $(CYCLE) \
	  --applied-at "$(or $(APPLIED_AT),$(shell date -u +%Y-%m-%d))" \
	  $(if $(REPO),--repo "$(REPO)",) \
	  $(if $(PROBE_IMAGE),--probe-image "$(PROBE_IMAGE)",)

# Prepares inputs and records the commands; launching a run stays a human step.
field-derive:  ## training and calibration inputs  OUT=<corpus> | CALIBRATION_OUT=<dir>
	@test -n "$(OUT)$(CALIBRATION_OUT)" || { \
	  echo "usage: make field-derive [OUT=<merged corpus root>] [CALIBRATION_OUT=<dir>] [IDENT=<model ident>] [CYCLE_DIR=<dir>]"; \
	  exit 1; }
	$(PYTHON) tools/field_loop/derive_dataset.py \
	  $(if $(OUT),--out "$(OUT)",) \
	  $(if $(CALIBRATION_OUT),--calibration-out "$(CALIBRATION_OUT)",) \
	  $(if $(CYCLE_DIR),--cycle-dir "$(CYCLE_DIR)",) \
	  $(if $(IDENT),--ident "$(IDENT)",)

##@ Offline harnesses and repo tooling

# SHA is the bundle's bare segmenter stamp (ab812dc3aa9d), NOT the app-facing
# lineage form coreml_ab812dc3aa9d, which fails the load. A field replay reports
# every meal UNSCORED and exits non-zero, because device bundles record ground
# truth as zero — that is the harness working.
harness-accuracy:  ## replay capture bundles offline  FIXTURES=<dir> SHA=<sha256>
	@test -n "$(FIXTURES)" -a -n "$(SHA)" || { \
	  echo "usage: make harness-accuracy FIXTURES=<dir> SHA=<checkpoint-sha256> [OUT=<file>]"; \
	  exit 1; }
	swift run HarnessCLI accuracy \
	  --fixtures-dir "$(FIXTURES)" \
	  --checkpoint-sha256 "$(SHA)" \
	  $(if $(OUT),--output "$(OUT)",)

PORTFOLIO_DIR ?= /private/tmp/medata-portfolio
spec-portfolio:  ## every spec's remaining work as one explorable page
	@mkdir -p $(PORTFOLIO_DIR)
	$(PYTHON) tools/spec_portfolio/collect.py $(PORTFOLIO_DIR)/data.json
	$(PYTHON) tools/spec_portfolio/render.py --data $(PORTFOLIO_DIR)/data.json --out $(PORTFOLIO_DIR)/portfolio.html
	@echo "portfolio: $(PORTFOLIO_DIR)/portfolio.html"

worktree:  ## create .worktrees/<name>  name=<dir> [branch=<branch>]
	@tools/new_worktree.sh $(name) $(branch)
