# Prerequisites for fingerprick Glucose

These tasks must be completed by the user; none of them can be done from code.

## Before Starting

- [ ] Confirm the Contour Diabetes app is installed on the primary device, paired with the Contour Next meter, and permitted to write blood glucose to Apple Health. Without it there is no meter route to classify (Decision 1).
- [ ] Confirm MeData still holds Apple Health read authorisation for blood glucose on the device — `HealthKitGlucoseSource` was authorised under `specs/data/cgm-connect`, and a revoked permission presents as an empty backfill rather than an error.

## During Implementation

- [ ] Take a real fingerprick on the Contour Next meter and let it sync, so at least one genuine meter sample exists in Apple Health. Needed before task 11's classification can be exercised against anything real.

## Before Testing

- [ ] Read the meter writer's identity off the device — bundle identifier, display name, and device name/manufacturer if shown — from the Apple Health writers list added in task 23, and classify it as a blood meter. The literal identifiers are deliberately not in the spec or the code; they are set here (Req 1.5).
- [ ] Add the glucose launcher widget to the Lock Screen, alongside the existing dose and capture launchers, to verify `medata://glucose/add` opens the entry sheet with the app closed (Req 2.2).
- [ ] Keep a LibreLinkUp sensor connected and delivering while a blood reading is recorded, so the Lock Screen can be observed holding the blood value across at least one sensor tick and releasing it when the window expires (Reqs 3.1, 3.3, 3.8).
- [ ] Record a hand entry, confirm it displays, then delete it from Records and confirm the Lock Screen stops showing it without waiting for another reading (Req 6.2).
