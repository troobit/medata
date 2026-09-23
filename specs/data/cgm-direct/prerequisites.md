# Prerequisites for CGM Direct

These tasks must be completed by the user before or during implementation. Surfaced by the design
review and the Abbott-custody discussion (2026-08-17).

## Before Starting

- [ ] Confirm an uploader is active for the worn Libre 3+ — a LibreLink app (region-matched to the
      sensor's country) or a Juggluco bridge — activating the sensor and uploading to LibreView
      (Req 10.1). Phase A observes that session; it does not create one. If none is available because
      of a regional App Store restriction, follow `docs/libre-app-region-setup.md` (Route A: switch
      the iPhone App Store region to install the matching LibreLink) — this is a documented,
      recoverable step, not a block.

## Before Testing

- [ ] Task 8 (on-device pairing/coexistence verification) requires the user physically wearing an
      active Libre 3+ with the Abbott app connected and alarming normally — the verification is
      explicitly that MeData's heartbeat does not disturb that session (Req 2.2, 2.6).
- [ ] Grant the Bluetooth permission prompt on first enable (triggered by the
      `NSBluetoothAlwaysUsageDescription` added in task 6). A denial is expected to surface as the
      distinct unavailable state (Req 5.6), which is itself part of the verification.
- [ ] Task 9 (24 h measured close-out) needs one baseline day with the heartbeat off and one with
      it on, app never foregrounded — plan the two days before starting, and note any Abbott-app
      or sensor events (swap, outage) that would contaminate the comparison.

## No portal or signing work

No Apple Developer portal change is required: Phase A uses only the self-service
`bluetooth-central` background mode (Decision 4); the existing signing profile continues to work.
