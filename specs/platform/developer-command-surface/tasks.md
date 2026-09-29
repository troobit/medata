---
references:
    - specs/platform/developer-command-surface/smolspec.md
    - specs/platform/developer-command-surface/decision_log.md
---
# Developer Command Surface Tasks

- [x] 1. `tools/deploy.sh` builds, gates and installs every configuration
  - **Outcome:** one script replaces `deploy_release.sh`, `deploy_release_stub.sh` and `deploy_product.sh`. `CONFIG=Debug|Release|ProductRelease`, `SEGMENTER=model|stub`, `INSTALL=0|1`. It owns the build stamp; nothing else computes one.
  - **Approach:** sequence the five steps from the smolspec. Reject `Debug`+`model` with the `Package.swift` reason. `SEGMENTER=model` requires the `.mlpackage` and prints its `medata.modelVersion`; `SEGMENTER=stub` on a non-Debug configuration rewrites the define under an `EXIT` trap. Destination is `id=$DEVICE_UDID` when installing, `generic/platform=iOS` with `CODE_SIGNING_ALLOWED=NO` when not. `ProductRelease` runs the three-assertion `strings` gate either way. Install retries once on `CoreDeviceError 4000`.
  - **Verification:** `CONFIG=Debug INSTALL=0 bash tools/deploy.sh` and `CONFIG=ProductRelease INSTALL=0 bash tools/deploy.sh` both succeed with no device attached; the second prints the gate line. `CONFIG=Debug SEGMENTER=model` exits non-zero with the reason.
  - **References:** decision_log.md (Decision 2), smolspec.md.

- [x] 2. `tools/field_loop/field_discard.py` clears captures on both sides
  - **Outcome:** `--corpus-side` deletes `corpus_root()/captures` and marks those `index.sqlite` rows content-absent; `--device-side` pushes a manifest authorising the device to delete its bundles uncopied. Notes, `db/` and `index.sqlite` survive. Refuses without `--confirm <count>` matching the capture count it just printed.
  - **Approach:** new module beside `field_pull.py`, reusing `corpus.py` for the root and `field_pull.push_manifest` for the handshake. Print the pre-flight (Mac capture count and bytes, device bundle count) before any deletion.
  - **Verification:** `make test-python` covers it against a scratch `MEDATA_CORPUS`; a run without `--confirm` exits non-zero having deleted nothing.
  - **References:** decision_log.md (Decision 3), smolspec.md.

- [x] 3. The Makefile is the two axes, four shortcuts and a generated help
  - **Outcome:** ~190 lines. `app`, `deploy`, `debug`, `dev`, `dev-stub`, `product`, `model`, `logs`, `field-discard`, `test-python` exist; `build-app`, `build-release-check`, `deploy-device`, `deploy-release`, `deploy-release-stub`, `build-product`, `deploy-product`, `logs-device`, `field-test` do not. `make help` is generated from `##` comments under `##@` sections.
  - **Approach:** delete the three `DERIVED_*` variables for one `/tmp/medata-<config>` expression and the `GIT_SHA`/`BUILD_STAMP` pair entirely (Decision 2 moves them into the script). Shortcuts recurse into `deploy` with `CONFIG`/`SEGMENTER` set. `test-python` runs both pytest directories as two invocations. Keep `LOG_LAST` at the trimmed 10m.
  - **Verification:** `make help` lists every target with no target missing a `##`; `make spell`.
  - **References:** decision_log.md (Decision 1, Q1-Q6).

- [x] 4. `docs/build-and-field-loop.md` documents both surfaces
  - **Outcome:** one page: the configuration/segmenter matrix, what each shortcut is, the model-pairing rule, and the field loop as an ordered sequence with its file contract between phases and every target's parameters. `make field-notes` versus `make field-pull` stated in one sentence each. `make help` points at it.
  - **Approach:** move the parameter prose out of the old help text and the sequence diagram out of `docs/agent-notes/ml-feedback-loop.md`, leaving that note its gotchas and a pointer.
  - **Verification:** `make spell`; every target in `make help` appears in the document.
  - **References:** smolspec.md, decision_log.md (Q5).

- [x] 5. Living documents name the new targets
  - **Outcome:** `README.md`, `CLAUDE.md`, `docs/agent-notes/device-build-and-test.md`, `docs/agent-notes/ml-feedback-loop.md`, `docs/agent-notes/model-production.md`, `docs/ml-training.md`, `docs/roadmap.md` and `App/Design/README.md` use the new names. `CHANGELOG.md`, completed `specs/**/tasks.md` and `specs/bugfixes/**/report.md` are untouched.
  - **Approach:** rename per the smolspec's mapping table. Where a document explains *why* a target exists, replace the explanation with a pointer to `docs/build-and-field-loop.md` rather than duplicating it.
  - **Verification:** `grep -rn 'deploy-device\|deploy-release\|deploy-product\|build-product\|build-app\|build-release-check\|logs-device\|field-test' README.md CLAUDE.md docs/ App/` returns nothing; `make spell`.
  - **References:** decision_log.md (Q4).

- [-] 6. Verified end to end
  - **Outcome:** everything off-device passes. `make help` lists all 24 targets and every one carries a `##` line; `make spell` clean; `make build` clean; `make app CONFIG=Debug`, `CONFIG=ProductRelease` (gate fired, model `ab812dc3aa9d` reported) and `CONFIG=Release SEGMENTER=stub` (manifest edited and reverted, including on a failed build) all exit 0; `make test-python` is 129 + 253 green; `CONFIG=Debug SEGMENTER=model` and a bare `make field-discard` both refuse with their reason and change nothing.
  - **Remaining:** the on-device half — `make dev-stub` on `you`, matching the launch line's stamp against the deploy output. Not run: another session has work in flight on that phone, and installing this worktree's build would replace theirs. One command once the phone is free.
  - **Verification:** the on-device stamp equals the deployed one.
  - **References:** smolspec.md.
