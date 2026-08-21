# Decision Log: Fingerstick Glucose

## Decision 1: Apple Health is the first meter transport; direct Bluetooth is a later phase

**Date**: 2026-08-20
**Status**: accepted

### Context

A Contour Next meter can reach the app by two routes. Ascensia's Contour Diabetes app already syncs the meter over Bluetooth and writes blood glucose into Apple Health, and MeData already runs `HealthKitGlucoseSource` against `HKQuantityType(.bloodGlucose)`. Alternatively MeData could be its own Bluetooth central, bond with the meter and read the Bluetooth glucose service directly — the route xDrip+ takes on Android, and the route `docs/drivers.md` argues for on principle: "They lock your data (data about **you**), behind their _safety features_."

The two routes differ by roughly an order of magnitude in build cost, and only one of them can be specified today.

### Decision

Blood readings arrive through Apple Health. The direct-Bluetooth route is recorded as a non-goal of this spec and left for a later phase.

### Rationale

The Health route needs no new driver, no bonding flow and no background-wake strategy: `HealthKitGlucoseSource` already backfills, observes, and holds a durable anchor, so the work reduces to classifying which writer a sample came from. A blood-glucose meter is also the case where vendor-app dependency costs least — a fingerstick is a discrete act the user initiates, so there is no real-time delivery requirement of the kind that makes CGM vendor lock-in intolerable.

The direct route cannot be honestly specified yet. `specs/data/cgm-direct` established what a direct BLE phase costs on iOS, and its own [prerequisites](../cgm-direct/prerequisites.md) gate Phase B on a living feasibility note for exactly this reason; xDrip's issue tracker records the Contour connection dropping after a Bluetooth restart and importing only at pairing time. Specifying it before someone has read the meter's profile on real hardware would be invention.

### Alternatives Considered

- **Direct Bluetooth only**: MeData bonds with the meter and reads the glucose service itself, cutting Ascensia out entirely - rejected because the profile is unverified on this hardware, iOS background constraints already cost `specs/data/cgm-direct` a full phase of design, and the feature would deliver nothing until all of it worked.
- **Both routes in one spec**: two sources behind the existing `GlucoseSource` abstraction, whichever connects first winning - rejected because the direct half is unspecifiable today, so the spec would ship half-imaginary and the ledger would stall on it.
- **Hand entry only, no meter integration**: rejected because it makes every blood reading cost an interaction, which is the cost this feature exists to remove.

### Consequences

**Positive:**
- Reuses a source that already handles backfill, observation, durable acknowledgement, and background delivery.
- The classification seam it introduces is the same seam a direct-BLE source would deliver through later, so the later phase adds a source and changes nothing downstream.

**Negative:**
- Blood readings reach MeData only while Ascensia's app is installed, running, and syncing — a dependency this project's stated principles dislike.
- Delivery latency is the vendor app's, not ours, and is neither measured nor controllable here.

---

## Decision 2: Blood readings supersede by display precedence, never by deletion

**Date**: 2026-08-20
**Status**: accepted

### Context

A blood reading and a sensor reading disagreeing at the same moment is the normal case, not an error: capillary blood and interstitial fluid differ by a lag and a bias. "Override the CGM reading" admits three readings — destroy the sensor value, hide it, or leave it in place and outrank it only where a single current value must be named.

Existing glucose rows are merged keep-first on a shared 5-minute grid (`specs/data/cgm-connect` [Req 5.1](../cgm-connect/requirements.md#5.1): "SHALL treat a reading as already present WHEN a stored `bsl` event exists at that grid instant, regardless of source"), so under today's rule a later blood reading at an occupied mark is silently discarded.

### Decision

A blood reading never modifies, hides, or deletes a sensor reading. Both persist, both render, and precedence applies only where one current value must be reported.

### Rationale

A blood reading beside a sensor reading at the same instant is a paired measurement — the only data from which this sensor's own error can ever be estimated. Destroying the sensor half destroys the pair, and the pair is not reconstructible afterwards.

The project already settled the identical question one domain over. `specs/ui/meal-review` [Req 8.1](../../ui/meal-review/requirements.md#8.1) requires that the system "SHALL retain each detected food's original predicted class, volume, mass and carbohydrate contribution unchanged after any correction, and SHALL NOT overwrite a stored prediction with a corrected value" — a correction is recorded beside what it corrects, never over it, because the pair is the deliverable. A blood reading correcting a sensor reading is the same relationship.

Hiding rather than deleting was rejected for a weaker but sufficient reason: a hidden row is one the Graph must special-case while the trace still has to be drawn through it, which is more mechanism than showing it costs.

### Alternatives Considered

- **Overwrite the sensor value at the grid mark**: one reading per instant, closest to the literal reading of "replace" - rejected because it destroys the paired measurement irreversibly and leaves the event log asserting the sensor reported a value it never reported.
- **Flag the sensor reading superseded and hide it from Graph and Records**: no data lost, one value visible per moment - rejected because it buys tidiness at the cost of a hidden-state concept every read path must honour, and the sensor trace must be drawn continuously through the instant anyway.

### Consequences

**Positive:**
- Sensor-versus-blood pairs accumulate as a by-product, making sensor error measurable later without any collection effort.
- No read path needs a hidden-row concept; the Graph's sensor trace stays continuous by construction.
- Nothing this feature does is destructive, so a misclassified writer cannot cost historical data.

**Negative:**
- Records shows two rows close together where a user might expect one, and the Graph carries a marker series the sensor trace does not explain.
- The event log holds contradictory values at nearly the same instant, so any future consumer reading it must understand provenance rather than trusting the newest row.

---

## Decision 3: A tunable hold window, defaulting to 15 minutes

**Date**: 2026-08-20
**Status**: accepted

### Context

With sensor rows preserved (Decision 2), precedence needs a duration. Sensor readings arrive on a 5-minute grid, so a rule of "newest reading wins, provenance breaking ties only at equal instants" gives a blood reading the headline for at most one CGM cycle. A rule of "the latest blood reading holds indefinitely" leaves an hour-old blood value on the Lock Screen above a live trace.

The physiology sets no single correct duration. Rebrin, Sheppard and Steil (2010) review the interstitial-to-blood delay across research groups and find it inseparable from a per-sensor offset; Abbott states a 5–10 minute interstitial delay for FreeStyle Libre, and the lag widens further when glucose is moving quickly — precisely when a fingerstick gets taken. Worse for any constant, McClatchey and others (2019) attribute more than 80% of the delay to fibrotic encapsulation of the implanted sensor, so the lag grows over a sensor's wear period rather than holding still.

### Decision

A blood reading is the reported current value while its instant is within the hold window of now. The window is 15 minutes unless changed, and is adjustable in Settings. Sensor readings arriving inside the window still ingest, still draw, and still feed the trend; they do not take the reported value back until the window expires.

### Rationale

A fingerstick is taken precisely when the sensor is not trusted right now — a compression low, hypoglycaemia symptoms contradicting the trace, the first hours of a new sensor. A precedence that expires at the next sensor tick returns the display to the value that was distrusted, minutes after the finger was pricked, which forfeits the reason for taking the reading.

The window is tunable rather than fixed because the encapsulation finding rules out any constant staying right: the correct value differs between people, between sensors, and across a single sensor's life. Making it a setting also closes a loop this spec already opens — Decision 2 preserves every blood-and-sensor pair specifically so sensor error becomes measurable later, and this is the parameter those pairs would inform. A constant would leave that measurement with nothing to act on.

15 minutes is the default because it is the boundary at which `specs/ui/glucose-lock-widget` [Req 5.1](../../ui/glucose-lock-widget/requirements.md#5.1) stops rendering a reading "at full prominence with its status indicator and trend arrow". At that value one threshold governs both precedence and staleness, so a held blood reading relinquishes the display at the same moment the staleness ladder would have begun de-emphasising it, and no state exists in which a dimmed blood value outranks a fresh sensor one. Raising the window past 15 minutes reintroduces that state deliberately, which is a reasonable trade to make knowingly and a poor one to ship by default.

### Alternatives Considered

- **Newest reading wins, provenance breaks ties only**: no window to tune, and the display never shows a number older than the freshest data - rejected because the override then survives under five minutes, too short to be worth the interaction it costs.
- **The latest blood reading holds until the next one**: unambiguous and the strongest reading of "override" - rejected because the reported value goes stale silently while a live sensor trace sits beneath it on the Graph.
- **A fixed constant with no setting**: one less value to plumb into the widget extension - rejected because the lag it approximates varies by person, by sensor, and across a sensor's life, so a constant is knowingly wrong and cannot be corrected without a rebuild.
- **Release the hold once a sensor reading converges to within a margin of the blood value, capped by a maximum**: encodes "hold until the sensor catches up" directly and self-adjusts to both rapid change and an ageing sensor - rejected for now because it replaces one tuned number with two and is harder to explain on a device screen; the tunable window can be superseded by it if the preserved pairs show a fixed duration behaving badly.
- **Fit an offset from the pairs and correct the sensor trace**: rejected as a different feature, and one requiring several pairs and a validated model rather than a rule.

### Consequences

**Positive:**
- At the default, one threshold governs both precedence and staleness, so the two cannot contradict each other.
- The blood reading survives long enough to be the number acted on, which is the point of taking it.
- The window can be corrected from measured data later without a code change.

**Negative:**
- For the duration of the window the reported value is knowingly not the most recent measurement available, and a user watching a fast fall sees the trend arrow move while the number does not.
- A hold's expiry must reach the widget extension, which cannot read app settings; the design meets this by publishing an absolute expiry date rather than sharing the window value (design.md, "The snapshot contract").
- Raising it above 15 minutes produces held readings rendered as stale, a combination the widget's staleness ladder was not designed around.

---

## Decision 4: Meter and hand-entered readings are one behavioural class

**Date**: 2026-08-20
**Status**: accepted

### Context

Blood readings arrive by two routes — synced from the meter through Apple Health, or typed in. Provenance could distinguish three classes (sensor, meter, hand-entered) or two (sensor, blood), with the route recorded but not acted upon.

### Decision

Provenance has two classes: sensor and blood. Meter-synced and hand-entered readings are identical on every surface and in every precedence decision. Which route recorded a reading is retained on the reading and acts on nothing.

### Rationale

Both routes describe the same physical measurement — a drop of capillary blood on a strip — and the number typed in is usually read off the very meter the other route would have synced. A behavioural distinction between them would encode how the number travelled rather than what it measures, and would put a second marker style on the Graph and a second label in Records for a difference the reader cannot act on.

Retaining the route costs one field and keeps the record honest: a later question about how much of the corpus arrived by hand stays answerable without the answer leaking into behaviour.

### Alternatives Considered

- **Three provenance classes, distinguished on display**: rejected because it multiplies markers, labels, and precedence cases to express a difference in transport rather than measurement.
- **Two classes, route discarded entirely**: simplest - rejected because it makes an irreversible loss of provenance to save one field, and this project's stated preference is to keep the record.

### Consequences

**Positive:**
- One marker style, one label, one precedence rule regardless of how a blood reading arrived.
- Hand entry is a complete substitute for the meter route, so a flat battery or an uninstalled vendor app degrades interaction cost and nothing else.

**Negative:**
- A reading's route is invisible without inspecting the stored event, so a silently broken Health sync looks like diligent hand entry on every surface.

---

## Decision 5: The home page row with Dose is added to with 'BSL', and echoes the row above, inverting the capture/intake button styling

**Date**: 2026-08-20
**Status**: accepted (narrows `specs/ui/home-router` Decision 15)

### Context

Graph location is where you end up if you click the blood glucose reading on top of screen.

Recording a reading has to cost almost nothing or it will not happen, and the record is the product. Home already carries the latest reading as, in the words of `specs/ui/home-router` [Decision 15](../../ui/home-router/decision_log.md), "Home shows the latest glucose reading, narrowing the pure-router rule" — a display element, not a route, sitting above six route rows.

### Decision

Tapping a page's button presents the glucose-entry surface. A `medata://glucose/add` deep link and a launcher widget in the existing `MeDataWidgets` family present the same surface without the app being open.

### Rationale

The number the user disagrees with is the control that corrects it — the shortest path from noticing a wrong value to recording the right one, and no new chrome on a page already carrying six route rows plus two primary actions.

The widget matters more than the in-app entry. `InsulinDoseWidget` and `CaptureWidget` already establish a launcher family of roughly ten lines each, deep-linking into the app without a persistence import. A glucose launcher means a reading is recorded from the Lock Screen without the app being opened at all, which is the lowest interaction cost this feature can reach.

### Alternatives Considered

- **A seventh route row on home**: consistent with how every other entry sheet is reached, and leaves the home-router decision untouched - rejected because it lengthens the page and puts the target further from the value it corrects.
- **Both, built for a side-by-side device comparison**: rejected because the two are not exclusive — the header tap subsumes the row's function — and the extra ledger cost would land on the least uncertain part of the feature.

### Consequences

**Positive:**
- A blood reading reaches the record from the Lock Screen without opening the app.
- The correction affordance sits on the value being corrected, needing no label to explain it.

**Negative:**
- A display element becomes interactive, so the home page no longer separates cleanly into routes and one read-only reading, and the tap target must be discoverable without a label.
- A fourth widget joins the bundle, adding to what the user must arrange on a Lock Screen already holding dose and capture launchers.

---

## Decision 6: Blood readings are recorded off the 5-minute grid

**Date**: 2026-08-20
**Status**: accepted

### Context

Every glucose row today is snapped to a 5-minute grid mark before storage, which is what lets keep-first dedup work across LibreLinkUp, HealthKit, and screenshot import (`specs/data/cgm-connect` [Req 5.1](../cgm-connect/requirements.md#5.1)). A blood reading passing through that path would be moved by up to 150 seconds and would then collide with whatever sensor reading already occupied the mark.

### Decision


Reconsider: 2 write paths - can we jsut assert that this is actually the TRUE value, and record the delta between the CGM data as a measure to improve on?

A blood reading is stored at the instant it was measured. Sensor readings continue to snap and merge keep-first exactly as they do now.

### Rationale

The grid is a dedup device for samples of one continuous trace, where two sources reporting the same 5-minute mark are reporting the same underlying measurement. A fingerstick is not a sample of that trace; it is a discrete event with no counterpart to deduplicate against, and snapping it would falsify its instant for no benefit while manufacturing exactly the collision Decision 2 rejects.

Keeping the instant true also protects the pairing: the interval between a blood reading and the sensor readings around it is the quantity any later error analysis depends on, and rounding it away destroys resolution that cannot be recovered.

### Alternatives Considered

- **Snap blood readings to the grid like everything else**: one storage rule, no special case - rejected because it moves the reading's instant by up to 150 seconds and forces a collision with the sensor row at that mark.
- **Snap to a finer grid, such as one minute**: rejected because it retains a rounding rule that buys nothing when there is nothing to deduplicate against.

### Consequences

**Positive:**
- A blood reading's instant is exactly as measured, preserving the interval to its neighbouring sensor readings.
- Sensor ingestion is untouched, so existing dedup, backfill, and import behaviour carry no risk from this feature.

**Negative:**
- Glucose events are no longer uniformly grid-aligned, so any consumer that assumed alignment must be checked.
- Two write paths for one event type now exist, and the choice between them depends on provenance.

---

## Decision 7: The trend arrow is derived from sensor readings alone

**Date**: 2026-08-20
**Status**: accepted

### Context

The trend arrow is a least-squares rate over readings in a window, defined by `specs/ui/glucose-lock-widget` [Req 3.1](../../ui/glucose-lock-widget/requirements.md#3.1) as "a single rate of change in mmol/L per minute over those readings" across the preceding 30 minutes. It is a pure function shared by the home page, the widget publisher, and the widget extension's own fetch. Blood readings entering that series would sit in it at a systematic offset from the interstitial values around them.

### Decision

Can this be reconsidered? The blood readings are TRUE, cgm are not correct at the time. A blood reading could alter the trend. It is also possible that these readings ARE the only data - as CGM data can't be gathered at all times: so - the system must be able to take readings and infer direction with these data in the same way.

Blood readings are excluded from the trend derivation. The reported current value may be a blood reading while the arrow beside it describes the sensor trace.

### Rationale

A single blood point dropped into a regression over interstitial values does not measure a change in glucose; it measures the difference between two measurement modalities, and the arrow would report that difference as a rate. On a steady trace a blood reading a millimole above the sensor would swing the arrow to rising, at the moment the user is looking hardest at it.

The arrow and the number answering to different sources is not a contradiction: the number answers "what is my glucose", where blood is the better measurement, and the arrow answers "which way is it going", which only a series can answer and only the sensor provides.

### Alternatives Considered

- **Include blood readings in the derivation**: one series, no exclusion rule - rejected because it converts a modality offset into a reported rate of change, precisely when the arrow is being relied on.
- **Suppress the arrow entirely while a blood reading holds the value**: honest about the mismatch - rejected because it withholds correct sensor information for up to 15 minutes, and direction is what a user checks after an unexpected blood result.

### Consequences

**Positive:**
- The arrow keeps one meaning and one input, and cannot be moved by an act of measurement.
- Trend behaviour is unchanged for anyone with no blood readings, so existing verification stands.

**Negative:**
- The displayed value and the arrow can derive from different readings, which is defensible but needs explaining to anyone reading the code.
- A user with no sensor connected and only blood readings gets no arrow at all.

---

## Decision 8: Precedence is a shared pure derivation, not a per-surface rule

**Date**: 2026-08-20
**Status**: accepted

### Context

Three surfaces report a current glucose value: the home header, the lock-screen widget, and the widget extension's own render while the app is suspended. Req 3.7 requires them to agree. The app derives from database rows and can see every reading; the extension fetches the vendor feed directly and, since `specs/ui/glucose-lock-widget` Decision 16, holds no database access at all.

### Decision

Precedence lives in one pure function in `GlucoseDerivation` — the latest blood reading inside the hold window, else the latest reading of any provenance — which every app-side caller invokes. The resolved reading and an absolute `holdsUntil` are published in the snapshot, so the extension consumes the outcome rather than re-deriving it.

### Rationale

The project has already twice extracted "the latest reading and its trend" into shared code for this exact reason, most recently when the widget began deriving its own snapshot. Two surfaces computing precedence independently is how they drift, and drift here is not cosmetic: the Lock Screen and the home page would report different blood-sugar values.

Publishing an absolute expiry rather than the window duration is what keeps the extension out of the app's settings. The extension compares a date it already holds, so the hold window stays an ordinary app-private setting and no new App Group state is introduced.

### Alternatives Considered

- **Each surface applies its own precedence rule**: no shared type change - rejected because the extension cannot see blood readings at all, so its rule could not be the same rule however carefully written.
- **Give the extension database access so it can derive precedence itself**: rejected because it puts GRDB inside a 30 MB extension, the constraint `specs/ui/glucose-lock-widget` Decision 16 was explicitly built to respect.
- **Publish the hold window to the App Group and let the extension compute the expiry**: rejected as strictly more shared state for the same outcome, and it would leave the extension recomputing a value the app already knows.

### Consequences

**Positive:**
- One definition of the rule, so the surfaces cannot disagree by construction.
- No new App Group state, and the hold window stays a plain app setting.

**Negative:**
- The snapshot schema version increments, so a build whose app and extension disagree reads never-recorded until the next publish.
- A hold's expiry is fixed when published, so changing the window mid-hold affects only the following publish.

---

## Decision 9: The hold rule extends the snapshot store's ordering guard

**Date**: 2026-08-20
**Status**: accepted (extends `specs/ui/glucose-lock-widget` Decision 19)

### Context

`GlucoseSnapshotStore.write` is monotonic in `readingDate`: a write carrying an older reading than the stored one is dropped. That guard exists because two processes write the snapshot, and it fixed an observed regression in which the app republished an hour-old database reading over the newer one the widget had fetched.

A held blood reading inverts the situation the guard was built for. A blood reading at 13:02 holding until 13:17 is *older* than the sensor reading the extension fetches at 13:05, so the guard as written admits the clobber rather than preventing it — and the extension has no way to know a hold exists.

### Decision

`supersedesStored` is replaced by a pure `merged(candidate:into:now:)` policy with three cases: a sensor candidate arriving during an active hold contributes only its trend; a candidate carrying the same displayed reading as stored is admitted only when its trend differs; otherwise the existing strictly-newer rule applies unchanged.

### Rationale

The first case is required for correctness. Without it the third case accepts the sensor reading and the Lock Screen loses the held value, violating Req 3.8.

The second case exists because the arrow would otherwise freeze for the whole hold. During a hold the app republishes the same displayed reading with a freshly derived trend; under a strictly-newer test that write is refused, and the freeze occurs with the app in the foreground as readily as in the background. Since a candidate whose displayed reading is identical cannot roll anything back, admitting it for a trend refresh costs the guard nothing.

The invariant is therefore preserved in substance rather than merely in form: the displayed reading's date never decreases, and neither new case moves it at all. Keeping the policy inside the store follows Decision 19's own reasoning that any future writer should inherit the rule by construction.

### Alternatives Considered

- **Reject sensor writes outright during a hold**: one clause instead of three - rejected because the trend arrow then freezes for the full window, including in the foreground, and the arrow is what a user checks after an unexpected blood reading.
- **Have the app clear the hold by writing a fresh snapshot on a timer**: rejected because the app is suspended for precisely the window this must cover, which was the premise of Decision 16.
- **Let the extension write freely and apply precedence at render instead**: rejected because the stored snapshot would then no longer be the displayed state, and every reader would need the overlay rather than one writer applying it.

### Consequences

**Positive:**
- The clobber is closed for every writer, including any added later.
- The arrow stays live and sensor-derived while a blood value is displayed.

**Negative:**
- A load-bearing shared function grows from one condition to three, in a file already carrying a subtle two-writer invariant.
- The policy is still advisory in the same sense Decision 19 noted: read-then-write across two processes has no compare-and-set.

---

## Decision 10: Blood readings deduplicate on native id; hand entries never deduplicate

**Date**: 2026-08-20
**Status**: accepted

### Context

Sensor readings are made idempotent by the keep-first merge on the shared grid, which is what makes `HealthKitGlucoseSource`'s 90-day backfill safe to re-run on every connect. Blood readings are stored off-grid (Decision 6) and so have no keep-first to absorb a repeat.

### Decision

A blood reading carrying a native id is deduplicated on `(source_id, native_id)`, using `HKObject.uuid`. A hand-entered reading carries no native id and is never deduplicated.

### Rationale

The backfill re-runs, so without a rule every reconnection would multiply every meter reading it has ever seen. The sample's own stable identifier is the natural key and needs no heuristic on value or instant.

Hand entries are excluded deliberately rather than by omission: two fingersticks a minute apart are two measurements, and a value-and-instant heuristic would silently discard the second. Recording both is correct even when they are identical.

### Alternatives Considered

- **Deduplicate blood readings on instant and value**: works without a native id - rejected because it discards genuine repeat measurements, and near-identical readings minutes apart are the expected case around a hypoglycaemia treatment.
- **Extend keep-first to blood readings on a fine grid**: rejected because it reintroduces the instant falsification Decision 6 removed, to solve a problem the native id already solves exactly.

### Consequences

**Positive:**
- Reconnecting, or a repeated backfill, cannot duplicate meter readings.
- Genuine repeat fingersticks are all retained.

**Negative:**
- Deduplication reads a JSON field rather than an indexed column, so it is a scan over the candidate range rather than a key lookup.
- A hand entry saved twice by a double tap produces two rows, correctable only by deletion.

---

## Decision 11: A deletion may roll the snapshot back, but only over the reading it removed

**Date**: 2026-08-20
**Status**: accepted (extends `specs/ui/glucose-lock-widget` Decision 19)

### Context

Req 6.2 requires that deleting a reading returns every current-value surface to what it would have reported had that reading never existed. The snapshot store's monotonic guard prevents exactly that: once the displayed reading is deleted, the recomputed snapshot carries an older `readingDate`, so the write is refused and the widget goes on rendering a reading that no longer exists in the event log.

Decision 19 anticipated the history emptying entirely — a candidate carrying no reading is the never-recorded state and always writes — but not a partial deletion falling back to an older reading. The hole predates this feature: deleting the newest sensor reading through `specs/ui/records-deletion` has the same effect today. Req 6.2 is what makes it this spec's to close.

### Decision

A snapshot write may be marked as following a deletion, carrying the instants just removed. Such a write is admitted regardless of date ordering, but only when the stored snapshot's `readingDate` is among those instants.

### Rationale

The app is authoritative about a row it has just destroyed, in a way it is not authoritative about dates generally — which is the distinction the narrowing captures. An unconditional force-write would reinstate the precise regression Decision 19 was written to fix, where a stale app-side recompute rolled the snapshot back over a newer reading the extension had fetched while the app was suspended.

Restricting the rollback to the removed instants means it can only ever discard a reading the app has just deleted. A newer extension fetch the app never saw does not match a removed instant and is left alone, so the guard's protection survives intact for every case it was built for.

### Alternatives Considered

- **Force-write unconditionally after any deletion**: one flag, no matching - rejected because it lets a stale recompute roll back a newer extension fetch, which is the Decision 19 regression returning by another route.
- **Have the publisher clear the snapshot and rewrite it in two steps**: sidesteps the ordering rule without changing it - rejected because the intermediate never-recorded state is observable, so the widget can render an empty tile between the two writes.
- **Leave the hole and let the next reading overwrite the deleted one**: rejected because it leaves a deleted value on the Lock Screen for an unbounded period, and with no sensor connected it never clears at all.

### Consequences

**Positive:**
- A deleted reading leaves every surface promptly, satisfying Req 6.2 without weakening the guard.
- Closes a pre-existing defect affecting sensor readings deleted through the Records surface.

**Negative:**
- The store's write signature grows a parameter that only the deletion paths supply, and every deletion path must remember to supply it.
- A rollback can still discard an extension fetch in the narrow case where the displayed reading was deleted while the extension held a newer one; that self-corrects on the next widget wake.
