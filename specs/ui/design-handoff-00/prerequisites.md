# Prerequisites for UI Design Handoff 00

These tasks must be completed by the user; they cannot be performed by the agent.

## Before Testing (after the Integration gate, task 27)

On-device verification on the iPhone 13 Pro Max (match the `buildStamp` in device logs before trusting any run — see `docs/agent-notes/device-build-and-test.md`):

- [ ] `make deploy-device` (Debug): capture chrome per `capture.md` (mode capsule states, bubble level, telemetry capsule, Trends/Data/Settings buttons); Data / Trends / Settings sheets open and dismiss with the AR session releasing and re-arming; Settings + About content; Reduce Motion shows the static loading mark.
- [ ] In Settings (DEBUG build): tap `Seed demo glucose`, then verify Trends — dual-series day chart with target band, week/month aggregates, options sheet, time-in-range card. Before seeding, confirm the `no glucose data` empty state.
- [ ] `make deploy-release-stub`: full capture flow — shutter → draw-on loader → segmentation review (mask overlay visible on the fresh meal) → result (`Adjust` / `Done`, ⋯ menu) → correction (`corrected` marker appears in Data/overview). Error overlay: force a gate failure and check chip / hint / Retry / `2-view` / Cancel. Fork sheet via long-press on the mode control.
- [ ] Fallback checks: a pre-redesign meal in the store shows photo-only (no mask artefact); deny Photos access and confirm thumbnail placeholders; fresh install shows the `No meals yet` empty state and 1-view default (LiDAR device).

## Notes

- Debug builds cannot arm the shutter (17–21 s stub mask cycle) — capture-flow checks need the Release-stub build.
- The Trends glucose series stays empty in Release builds by design: seeding is DEBUG-only and no ingestion path ships in this spec (Decision 6).
