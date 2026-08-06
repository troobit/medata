# Prerequisites: Meal Review

These checks must be performed by the user on device; they cannot be performed by the agent. Each corresponds to a requirement whose acceptance is visual, tactile, or timing-dependent.

Device: iPhone 16 Pro (`6AD781BA-89FF-5A82-A2A1-B5EC9469F465`, name `you`). Match the `event=launch buildStamp=…` line before trusting any observation (`docs/agent-notes/device-build-and-test.md`).

## Layout and interaction cost

- [ ] **Req 6.6** — The scale control is visible without scrolling when the review surface first appears, on a meal carrying *all three* accessory signals (calibration banner, liquid over-estimate, unknown region) and four or more detected foods. This is the worst case the requirements permit and the one the layout is most likely to fail.
- [ ] **Req 7.5** — Recording an unmodified estimate takes exactly one tap.
- [ ] **Req 7.6** — Scaling the whole meal and recording takes no more than two taps.
- [ ] **Req 7.7** — On a three-food meal, adjusting one food by one serving step and recording takes no more than six interactions.
- [ ] **Req 7.8** — On a three-food meal, relabelling one food from the offered alternatives and recording takes no more than six interactions.

## Overlay legibility and performance

- [ ] **Req 2.1, 2.2** — Detected foods are distinguishable from one another and from the plate, with the food's own pixels unobscured, on a busy multi-food plate.
- [ ] **Req 2.3** — Two foods remain distinguishable with Differentiate Without Colour enabled.
- [ ] **Req 2.5** — Selecting a food leaves its areas the highest-contrast content in the image.
- [ ] **Req 10.3** — Text over the photo meets 4.5:1 against the composited result, measured on a bright white plate under kitchen lighting, not against an assumed dark background.
- [ ] Push transition into the review surface shows no dropped frames with the contour decode active. If it does, the design's `Canvas` fallback applies (design.md, Overlay section).
- [ ] **Req 3.4** — The full eligible list is reachable in one interaction from the shortlist and is usable at AX5.

## Accessibility

- [ ] **Req 2.6** — VoiceOver reaches each detected food, names it, and activation selects it. Focus ring follows the food's outline rather than a bounding box.
- [ ] **Req 10.4** — Every control offers a 44 × 44 pt hit region, including outlines for small foods (which fall back to their row).
- [ ] **Req 10.5** — Reduce Transparency renders review chrome opaquely.
- [ ] **Req 10.6** — The carb total remains legible at AX5.

## Correction durability

- [ ] **Req 9.4** — Relabel a food, then force-quit before tapping the primary action. Reopen: the correction is present in the corpus, and Records shows the corrected total and the corrected food name.
- [ ] **Req 9.10** — Relabel a food, record, then delete the meal from Records. The correction records survive; the meal and its artefacts are gone.
- [ ] **Req 9.9** — After many captures over time, no correction record has been discarded: the count only ever grows.
- [ ] **Req 8.7** — A relabelled meal names the corrected food in Records, Graph and the meal overview, not the predicted one.

## Corpus

- [ ] **Req 9.13** — Correction records are browsable in-app and export without network access.
- [ ] **Req 9.11** — An exported record can be read as a training example outside the app, using only the export's own contents — no food database, no mask.
- [ ] **Req 9.8** — Corrections made under a Debug build are distinguishable from Release ones by `segmenter_source`, so stub-derived corrections can be excluded from a training export.
