# MVP gap analysis — working-model readiness

**Date:** 2026-09-10 (re-baselined; supersedes the 2026-06-28 edition in full)
**MVP, stated once:** photograph food, get a carbohydrate number you can dose against,
on the fly.

## Why this note was rewritten

The 2026-06-28 edition opened with *"The MVP is blocked on exactly one thing: there is
no trained CoreML segmenter."* That has been false since 2026-07-26. It also listed four
P1 cleanups, all four of which have since landed. A reader starting from it was being
sent at solved problems, which is the most expensive kind of stale document — it looks
authoritative and costs a session before it is caught.

Every claim below was re-verified against the tree at `research` on the date in the
header. Where the old note was right, it is restated; where it was overtaken, the
correction is explicit.

## Verdict

**The MVP is no longer blocked on a missing artefact. It is blocked on machine access
and human time.** The segmenter exists, ships, and has a measurably better successor
sitting unexported. Every remaining item on the capture-to-estimate path needs either
the M5 Pro Mac, the iPhone 16 Pro, a human holding it, or a kitchen scale — and in most
cases several of those at once.

That is a different kind of problem from June's. June needed something *built*. Today
needs someone in a room with a plate of food.

## What changed since 2026-06-28

**The segmenter shipped.** `ab812dc3aa9d` (`deeplab_mnv3`) is the bundled model.
Release builds load it via `PipelineFactory` and stamp
`segmenterSource = "coreml_<modelVersion>"` on every capture. The June note's
`StubInferenceEngine` verdict now applies only to Debug builds, which is by design
(MD-26).

**A better model is adopted but not shipped.** R3 (`0a019c00e943`) is the recipe of
record (segmenter-foundation Decision 36) and beats the incumbent by +0.0265 mean
food-class IoU on the 182-image leak-free anchor, with `bread_white` crossing its 0.45
floor for the first time. The bundle still carries the incumbent. Until 2026-09-10 this
step existed only as the word "unscheduled" inside another task's detail; it is now
`estimation-quality` task 11 and carries its own commands.

**All four P1 cleanups are done.** Verified individually:

| June P1 item | State today |
|---|---|
| Delete dead `RetentionScheduler` | Gone from `MedataCore/Sources/Persistence/` |
| Δθ readout inert (hardcoded `0`) | Live — `ResultView.maxDeltaThetaDeg` reads proto fields 5/6 |
| Video-range YCbCr colour gap | Fixed — `PixelBufferAdapter` selects the video-range matrix on `420v` |
| Shutter log subsystem split | Fixed — `App.swift:267` logs under `ie.medata.app` / `Shutter` |

**β_c is partly calibrated, not absent.** June called it "every class ships
`β = 1.0 / uncalibrated_unity`". Nutrition5k calibration is Done (45 tasks) with βs
baked into the food DB, and cross-dataset calibration is Done (23 tasks).
`uncalibratedUnity` survives as the *fallback status for classes with no fit*, which is
correct behaviour rather than an outstanding gap. What remains is the MetaFood3D corpus
run, still gated on a request-gated dataset snapshot.

## The two myths from June, both still true

Retained because both are still live traps:

- **The "~22 s freeze" is not a code defect.** A Debug `-Onone` artifact; Release runs a
  full estimate in ~827 ms with no AR-frame starvation (MD-28). Do not schedule a perf fix.
- **OVERVIEW "Done" ≠ shipped and trusted.** Several specs are code-complete while their
  *accuracy* stays unverifiable until a capture session happens.

## A new operational constraint (2026-09-10)

Work is split across two machines and this is now load-bearing:

- **The Intel Mac** (i7-9750H) can do specs, docs, and the Python tooling. It **cannot**
  `swift build` for the macOS host (`Float16` is unavailable on x86_64), **cannot**
  install Xcode (26.6 requires Apple M1 or later), and **cannot** run MPS training.
- **The M5 Pro Mac** (`/Users/r/repos/medata`) does every Swift build, every device
  deploy, and every training run.
- No checkpoints, datasets, or model artefacts exist on the Intel machine. `build/` and
  `*.mlpackage` are gitignored in full.

Consequence for anyone planning work here: a task is agent-executable from the Intel box
only if it touches no Swift, no model, and no device. Everything else is a handover, and
handovers must carry runnable commands including the `git checkout` / `git pull` that
precedes them.

## The critical path today

**1. Export R3 and swap the bundle** — `estimation-quality` task 11. M5 Pro Mac, then
the phone. This is the highest-value open action and everything below it is downstream:
the on-device passes are all more informative against the better model.

**2. Confirm the two-view path end to end** — `bugfixes/two-view-carve-no-volume` task 1.
The carve was exonerated; the root cause was a mis-aimed oblique, and the tilt aim guide
that fixes it has since been wired into `CaptureFlowView`. What is owed is one
well-aimed two-view trail reaching `estimate.end success=true` with non-zero volume.

**3. Close the measurement STOPs** — `support-plane-reference` tasks 26/27 need a capture
session against weighed food; `insulin-dosing` tasks 22/23 need a reference meal on a
kitchen scale. These cannot be reasoned into existence; the constants are measurements.

**4. ANE residency** — `myfoodrepo-bridge` task 8. Xcode → Core ML performance report,
manual, M5 Pro Mac. A model that converts cleanly can fall back to CPU silently and blow
the 250 ms/view budget.

## Open work, by what it actually needs

46 open tasks across 17 files at `research` (47 with task 11). The distribution is the
finding:

| Needs | Count (approx) | Examples |
|---|---|---|
| Phone + a human looking at it | ~25 | dose-schedule 21–24, insulin-dosing 18/19/37, activity-events 8, mass-readout 4, unified-dark-theme 5, snaqui 8, ml-feedback-loop 29–31, cgm-connect 14/16 |
| M5 Pro Mac (build / export / GPU) | ~5 | estimation-quality 11 and 12, myfoodrepo-bridge 7/8 |
| Physical measurement or hardware purchase | ~9 | support-plane-reference 26/27, insulin-dosing 22/23, cgm-direct 13/14 (needs a *separate* Libre 3+ test sensor and a ground-truth reader) |
| Blocked on one of the above | ~7 | insulin-dosing 24–26 (fat rules), cgm-direct 16 (Phase B design) |
| Agent-executable from the Intel box | ~0 on the MVP path | — |

That last row is the honest headline. There is no meaningful MVP coding work available
on this machine; the useful contribution from here is keeping the specs, the ledger, and
the handover commands accurate so the machine-and-human time is not wasted when it
happens.

## Accessibility is not on this path

Recorded here because it repeatedly competed for attention: **MD-32 makes accessibility
advisory and never blocking**, at any point in the lifecycle. An audit on 2026-09-10
found no open task in any of the 17 task files gated on an accessibility bar — the cost
was never a blocked ledger entry, it was where the effort went. Shipped conformance
stays; the rule governs scheduling and gating, not code.

## Bottom line

June's gap was a missing artefact. Today's gap is a room, a plate, a phone, and an
afternoon. The specs are current, the ledger now names the export step, and the model
that should be on the phone is one command away from being exported — on a machine that
is not this one.
