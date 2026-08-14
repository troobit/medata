---
references:
    - smolspec.md
    - decision_log.md
---
# Build Provenance

- [x] 1. Make BUILD_STAMP dirty-aware in the Makefile <!-- id:bpv001a -->
  - Makefile:34 — split into GIT_SHA (short HEAD plus `-dirty` when `git diff --quiet HEAD` fails) and BUILD_STAMP (`$(GIT_SHA)-$(shell date +%Y%m%d-%H%M%S)`).
  - Tracked files only; untracked/gitignored artefacts (segmenter.mlpackage) must not trigger the marker.
  - A clean-tree stamp must be byte-identical to today's format.

- [x] 2. Mirror the dirty-aware default into both deploy scripts <!-- id:bpv002b -->
  - tools/deploy_release.sh:16 and tools/deploy_release_stub.sh:26 — same expression, preserving the `${BUILD_STAMP:-...}` override so a Make-supplied stamp still wins.
  - Blocked-by: bpv001a (Make BUILD_STAMP dirty-aware in the Makefile)

- [-] 3. Verify deploy-release-stub does not self-report dirty <!-- id:bpv003c -->
  - The stamp is computed before the script's Package.swift edit (Makefile `:=` at parse time; script default at line 26 ahead of the perl edit at line 54), and the script already refuses a pre-modified Package.swift.
  - Confirm by inspection plus one `make deploy-release-stub` from a clean tree: the printed stamp must have no `-dirty` marker.
  - Done by inspection and by an off-device run of the script with `xcodebuild`/`xcrun` shimmed out, from a foreign dirty repo, against a clean worktree: the `DEPLOYED BUILD STAMP` line — printed after the `perl -pi` edit — read `4864590-20260814-165324`, no marker, and the trap reverted Package.swift. Also confirmed `make deploy-release-stub` passes `BUILD_STAMP='$(BUILD_STAMP)'` (Makefile), expanded at parse time, so the script's own default is not reached on that path.
  - Remaining: one real `make deploy-release-stub` on the iPhone 16 Pro. Not run — no device available to this session.
  - Blocked-by: bpv002b (Mirror the dirty-aware default into both deploy scripts)

- [x] 4. Document the stamp format and the UI-attempt tag convention <!-- id:bpv004d -->
  - docs/agent-notes/device-build-and-test.md:66-79 — update the format line to `<sha>[-dirty]-<timestamp>` and state what `-dirty` means for trusting a capture round.
  - Same file: one short paragraph generalising the existing practice — tag a UI attempt's commit `<design>-attempt-N` when it is worth comparing against later (precedent: tilt-guide-attempt-1/2, docs/agent-notes/tilt-aim-guide.md:44). No numbering scheme, no version label, no tooling.
  - Blocked-by: bpv001a (Make BUILD_STAMP dirty-aware in the Makefile)

- [ ] 5. Gate: build, spell, and one on-device stamp check <!-- id:bpv005e -->
  - make build-app green; make spell clean.
  - One `make deploy-device` from a deliberately modified tree; the `event=launch buildStamp=...` line in `make logs-device` must show the `-dirty` marker and match the deploy output.
  - Blocked-by: bpv003c (Verify deploy-release-stub does not self-report dirty), bpv004d (Document the stamp format and the UI-attempt tag convention)
