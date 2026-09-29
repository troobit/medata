# Prerequisites for ML Feedback Loop

These tasks must be completed by the user before or during implementation. The task ledger's STOP tasks (29–31) are the device-verification gates themselves; the items here are the setup those gates and the live tooling depend on.

## Before Starting

- [ ] None — streams 1 and 3 (Swift core, Python tooling) run from a clean checkout with the standard toolchain.

## During Implementation

- [ ] **Provider credentials for every enabled adapter** — one adapter is active at a time, but the per-cycle health probe exercises every enabled one (Decision 16 amended), so live cycles need credentials (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY` or a local base URL, `GOOGLE_API_KEY`) for whichever adapters the `refmodel.json` enabled set contains. Adapter tests (tasks 21–22) use stub transports and need none of them; the first live cycle (task 31) needs the enabled set's credentials or the probe records failures.
- [ ] **LM Studio (or another OpenAI-compatible local server) running** — when the `openai` adapter is pointed at a local base URL; not needed for tasks 21–22 (stubbed).

## Before Testing (device STOPs)

- [ ] **Speech locale asset download** (blocks task 29): the on-device `SpeechTranscriber` locale model downloads over the network on first field-profile launch. Launch the field build once with network available and confirm voice entry works before running the offline parts of the checklist.
- [ ] **Device connected and trusted for `devicectl`** (blocks task 31): the first real cycle needs the iPhone 16 Pro (`6AD781BA-89FF-5A82-A2A1-B5EC9469F465`) docked for `make field-pull`; the corpus directory is created by the tooling at `<repo-parent>/medata-corpus/` — no manual setup, but note the recorded single-copy risk (Decision 14).
