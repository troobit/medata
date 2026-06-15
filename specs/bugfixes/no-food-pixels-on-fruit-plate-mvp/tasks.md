---
references:
    - specs/bugfixes/no-food-pixels-on-fruit-plate-mvp/smolspec.md
    - specs/bugfixes/no-food-pixels-on-fruit-plate-mvp/agent_protocol.md
---
# No Food Pixels Refusal On Fruit Plate Double-Mode Capture — Tasks

## Fix bug 1 — lost-age across nadir → oblique stash

- [x] 1. Add failing regression tests at the CaptureFlowModel → CaptureResult boundary <!-- id:op0jbkv -->
  - Test A (single-view nadir): inject a PreShutterMaskSource spy with latest populated to a known fresh BinaryMask; drive model.shutter() for a single-view nadir tap; capture the CaptureResult handed to a spy PipelineEstimator.
  - Test A asserts: preShutterFoodMask non-nil AND preShutterMaskAgeMs >= 0.
  - Test B (double-mode oblique stash): nadir tap with mask published at a known timestamp; second shutter() on the oblique stage; assert the oblique-stage CaptureResult carries preShutterMaskAgeMs >= 0 reflecting the nadir-instant age (not nil).
  - Both tests MUST fail today. swift build MUST remain clean.

- [x] 2. Diagnose suspect mechanism(s); apply minimal App-layer fix; record Root cause + Fix in smolspec.md <!-- id:op0jbkw -->
  - Use the failing tests as harness to identify which suspect mechanism(s) fire: (a) state-transition race in PreShutterSegmenter.pause() / awaitPaused(), (b) lost age across the nadir→oblique stash in CaptureFlowModel.performFlow.
  - Apply the minimal fix in App/CaptureFlowModel.swift only — no CaptureResult / RawFrame / Pipeline edits.
  - Append one-paragraph ## Root cause (lost-age) and one-paragraph ## Fix (lost-age) sections to specs/bugfixes/no-food-pixels-on-fruit-plate-mvp/smolspec.md.
  - Both tests from task 1 MUST pass after the fix; no existing test may regress.
  - Blocked-by: op0jbkv (Add failing regression tests at the CaptureFlowModel → CaptureResult boundary)

- [x] 3. swift build clean and swift test green (baseline + new regression tests) <!-- id:op0jbkx -->
  - Run swift build (clean) and swift test on the MedataCore SwiftPM target.
  - Confirm swift test reports the existing baseline (312 + 16) plus the two new regression tests, all passing.
  - Blocked-by: op0jbkw (Diagnose suspect mechanism(s); apply minimal App-layer fix; record Root cause + Fix in smolspec.md), suspect, minimal

## Fix bug 2 — PreShutterSegmenter cadence stall

- [x] 4. Add cadence-diagnostic `.info` instrumentation on a throwaway branch <!-- id:qx7n2ta -->
  - In `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` `frames` getter: log `os_log .info` immediately after `frameContinuations[id] = cont` with the id and `count=frameContinuations.count` so we can see the registration ordering.
  - In `MedataCore/Sources/CaptureKit/ARKitCaptureEngine.swift` `session(_:didUpdate:)` `stateQueue.async` block: log `os_log .info` per yield with the continuation count (`yielded count=N`).
  - In `App/PreShutterSegmenter.swift` `resume(frames:)` for-await body: log `os_log .info` on each iteration entry (`event=preshutter.loop.iter`).
  - In `App/PreShutterSegmenter.swift`: log `os_log .info` on entry to `makeRawFrame` and on the post-convert guard branches (success vs nil).
  - In `App/PreShutterSegmenter.swift`: log `os_log .info` after `segment(_:)` returns (success / nil).
  - In `App/PreShutterSegmenter.swift`: log `os_log .info` after `publish()` returns (`event=preshutter.loop.published`).
  - All log lines MUST be on a clearly-marked throwaway branch (one-line `// CADENCE-DIAG:` comment per line) so task 6 can grep-and-remove them confidently.
  - Use `category: "Shutter"` to match the existing Console.app filter.
  - swift build MUST stay clean; xcodebuild iphoneos build MUST succeed.
  - Blocked-by: op0jbkx (swift build clean and swift test green (baseline + new regression tests))

- [ ] 5. STOP — human runs device capture; agent reads trail and diagnoses <!-- id:qx7n2tb -->
  - Agent: build for device (`xcodebuild -project MeData/MeData.xcodeproj -scheme MeData -destination 'id=76A45E6D-C57E-5BA6-ABAD-205C3C668572' -configuration Debug build`).
  - Agent: print the install/launch commands and Console.app filter for the user.
  - User: install, launch, set Console filter, capture 2 shutter taps in Double mode at a fruit plate, ~30 seconds total session.
  - User: paste the full filtered Console trail back into the conversation (event lines from `onAppear` through second `estimate.end`).
  - Agent: diagnose from the trail which of H1 / H2 / H3 fired.
  - H1 fires if `frames` registration count and `session(_:didUpdate:)` yield count diverge for the producer's subscription id.
  - H2 fires if the engine logs ≥ 2 Hz yields to the producer's id but the producer logs only one `preshutter.loop.iter`.
  - H3 fires if the producer logs ≥ 2 Hz iterations but only one `preshutter.loop.published` (nil from makeRawFrame).
  - Agent: report the diagnosis verbatim to the user before writing any fix code.
  - Blocked-by: qx7n2ta (Add cadence-diagnostic `.info` instrumentation on a throwaway branch)

- [ ] 6. Apply minimal cadence fix; remove instrumentation; append Root cause (cadence) + Fix (cadence) to smolspec.md <!-- id:qx7n2tc -->
  - Apply the minimal fix matching the diagnosed hypothesis from task 5.
  - H1 → register `frameContinuations[id] = cont` synchronously before returning the stream from `ARKitCaptureEngine.frames`.
  - H2 → replace `bufferingNewest(1)` with a hand-rolled latest-frame channel (Mutex<ARFrame?> + Continuation resume on every set), keeping the `frames` public type byte-identical (`AsyncStream<ARFrame>`).
  - H3 → log and short-circuit nil-conversion frames at INFO instead of silently `continue`, then fix the root cause (likely a stale CVPixelBuffer reference held past the next session callback).
  - Remove every `// CADENCE-DIAG:` line added in task 4. Grep MUST find zero matches.
  - swift build clean. xcodebuild iphoneos build succeeds.
  - Append one-paragraph `## Root cause (cadence)` and one-paragraph `## Fix (cadence)` sections to specs/bugfixes/no-food-pixels-on-fruit-plate-mvp/smolspec.md (after the existing ## Fix (lost-age) section, before ## Verification attempt 2026-06-15).
  - Blocked-by: qx7n2tb (STOP — human runs device capture; agent reads trail and diagnoses)

- [ ] 7. swift build clean and swift test green (no regressions) <!-- id:qx7n2td -->
  - Run swift build (clean) and swift test on MedataCore SwiftPM target.
  - Confirm 312 + 16 baseline + 2 lost-age regression tests still pass; no new failures introduced by the cadence fix.
  - If H2 was the diagnosed fix path, add one unit test exercising the hand-rolled latest-frame channel synchronously (multi-set overwrite, single resume on consume).
  - Blocked-by: qx7n2tc (Apply minimal cadence fix; remove instrumentation; append Root cause (cadence) + Fix (cadence) to smolspec.md)

## Verify

- [ ] 8. STOP — human verifies on device in Single AND Double modes; agent diagnoses success or new failure <!-- id:op0jbky -->
  - Agent: rebuild for device, print install/launch commands and Console filter.
  - User: install, launch, capture in **Single** mode first (one nadir tap at a fruit plate), then in **Double** mode (nadir + oblique at a fruit plate). Paste both trails back.
  - Success criteria (BOTH modes) — `event=estimate.start maskAgeMs=N` with `N >= 0` AND `N <= 750`.
  - Success criteria (BOTH modes) — `event=estimate.end success=true mealId=… capturePath=…`.
  - Success criteria (BOTH modes) — ResultView renders (carbs + confidence visible). User confirms.
  - Same-refusal (`maskAgeMs=-1`) or different-refusal aborts closeout — agent reports observed delta vs hypothesis and waits for direction (do not iterate blind).
  - Blocked-by: qx7n2td (swift build clean and swift test green (no regressions))

- [ ] 9. Append `## Verification` section to smolspec.md with build SHA and observed success trail (both modes) <!-- id:op0jbkz -->
  - Append a `## Verification` section to specs/bugfixes/no-food-pixels-on-fruit-plate-mvp/smolspec.md noting the build SHA used for the rerun and the verbatim observed success trail for both modes (event lines from `fired` through `estimate.end success=true`), confirming `maskAgeMs >= 0` in each.
  - Blocked-by: op0jbky (STOP — human verifies on device in Single AND Double modes; agent diagnoses success or new failure)

- [ ] 10. Append `### On-device observation (complete, rerun)` block to shutter-blocked-feedback/decision_log.md; tick task 5 (id:f4inr0r) in shutter-blocked-feedback/tasks.md <!-- id:op0jbl0 -->
  - Append a `### On-device observation (complete, rerun)` block to specs/shutter-blocked-feedback/decision_log.md immediately after the existing (complete) block, mirroring its template (Date, Device, Mode tested, Outcome=success, observed trail, UI outcome, Notes).
  - Tick task 5 in specs/shutter-blocked-feedback/tasks.md (the line marked id:f4inr0r) from [ ] to [x].
  - These two doc edits land alongside the smolspec `## Verification` section in the same closeout commit (per nextup.md step 8).
  - Blocked-by: op0jbkz (Append `## Verification` section to smolspec.md with build SHA and observed success trail (both modes)), section, success
