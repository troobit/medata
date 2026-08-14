# Requirements: Glucose Lock Screen Widget

## Introduction

A WidgetKit accessory widget that surfaces the current (or most-recent) blood-glucose reading and a trend arrow on the Lock Screen with no interaction beyond a glance. The reading, its timestamp, a derived trend, and a target-band status are written by the app to a shared App Group snapshot whenever glucose events change; the widget renders solely from that snapshot. Data comes from the existing `bsl` event stream (CGM Connect and Libre screenshot import) — this feature adds a display surface, not a new data source.

## Non-Goals

- No ActivityKit Live Activity — the always-present accessory widget is the sole surface (a time-boxed Live Activity is a possible future).
- No Home Screen-only glucose widget for its own sake. `systemSmall` is offered solely because StandBy's widget panel is fed from the Home Screen pool and accessory families never reach it; the Home Screen listing is a side effect of StandBy support, not a targeted placement (Decision 3, amended 2026-08-03).
- No editing, logging, or dose entry from the widget — read-only glance surface (the existing launcher widgets own actions).
- No new glucose ingestion and no estimation-path code. *(Amended by Decision 16: "no network calls" no longer holds — the widget refetches from the existing LibreLinkUp source when the app is suspended. It is still not a new data source and it still writes nothing to the database: the fetch updates the display snapshot only, and the app ingests the same readings on its own poll.)*
- No mg/dL display — mmol/L only, matching CGM Connect.
- No historical chart, sparkline, or multi-reading history in the widget itself.
- No plumbing of a source-specific trend value (e.g. LibreLinkUp's `TrendArrow`) — the trend is derived uniformly from recent readings.

## Requirements

### 1. Shared latest-reading snapshot

**User Story:** As a user, I want the app to publish my most recent glucose reading to a place the widget can read, so that the Lock Screen shows current data without the widget touching the database.

**Acceptance Criteria:**

1. <a name="1.1"></a>The system SHALL maintain a shared snapshot readable by the widget extension with a fixed schema: a schema version, the most-recent `bsl` reading value in mmol/L, the reading's timestamp, the derived trend (Req 3), and the target-band status (Req 4). No other fields are required.  
2. <a name="1.2"></a>WHEN the set of `bsl` events changes, the system SHALL recompute the snapshot from the latest `bsl` events and write it.  
3. <a name="1.3"></a>WHEN the written snapshot differs from the stored snapshot in value, trend, status, or timestamp, the system SHALL request a widget timeline reload. A candidate dropped by Req 1.8 is not a written snapshot and SHALL NOT request one.  
4. <a name="1.4"></a>WHEN no `bsl` events exist, the system SHALL write a snapshot representing the never-recorded state (Req 8.1).  
5. <a name="1.5"></a>The snapshot SHALL be written atomically, so a concurrent widget read never observes a partially written snapshot.  
6. <a name="1.6"></a>IF the shared container is unavailable or not writable, the app SHALL fail without crashing and SHALL leave any previously written snapshot untouched.  
7. <a name="1.7"></a>WHEN the snapshot is missing, undecodable, or carries an unrecognised schema version, the widget SHALL render the never-recorded state (Req 8.1).  
8. <a name="1.8"></a>The stored snapshot SHALL be monotonic in the reading's timestamp: WHEN a writer offers a snapshot whose reading is not newer than the stored reading, the system SHALL drop that write and leave the stored snapshot in place. The rule SHALL hold for every writer — the app's publish (Req 1.2) and the widget's own fetch (Req 6.2) — because the snapshot may legitimately carry a reading the database has not ingested yet (Req 6.4), so an app catch-up must not move the display backwards. A snapshot carrying no reading is the never-recorded state of Req 1.4, not an older reading, and SHALL still be written. The guard is advisory in the same sense as Req 6.3's gate: two processes read-then-write with no cross-process atomicity, so a simultaneous pair may still interleave. *(Added by Decision 19 after the field pass caught a prime publish replacing a 10:55 reading with an 09:55 one.)*  

### 2. Widget rendering and placements

**User Story:** As a user, I want a glucose tile on my Lock Screen and StandBy, so that I can read my level at a glance.

**Acceptance Criteria:**

1. <a name="2.1"></a>The widget SHALL be offered as a distinct kind in the widget gallery, separate from the existing launcher widgets, with a functional display name and description (no reassurance/disclaimer copy).  
2. <a name="2.2"></a>The widget SHALL support the `accessoryCircular`, `accessoryRectangular`, and `accessoryInline` families, and SHALL additionally support `systemSmall` — the family StandBy's widget panel draws from, without which the widget cannot render in StandBy at all (Decision 3, amended 2026-08-03).  
3. <a name="2.3"></a>In `accessoryCircular`, the widget SHALL show the reading value, the status indicator (Req 4.2), and the trend arrow (Req 3) when a trend is available.  
4. <a name="2.4"></a>In `accessoryRectangular`, the widget SHALL show the reading value, the status indicator, the trend arrow when available, and the reading's relative age (Req 5.5).  
5. <a name="2.5"></a>In `accessoryInline`, the widget SHALL show the reading value and the trend arrow when available on a single line, within the family's single-line width.  
6. <a name="2.6"></a>The widget SHALL render from the shared snapshot and SHALL NOT query the event log or the persistence store. Its only permitted network activity is the vendor fetch of Req 6.2, which rewrites that same snapshot before rendering; every render still reads a snapshot and nothing else. *(Redefined in place by Decision 16 — the clause previously forbade "any network", which was the right rule while the app was the only publisher and the wrong one once a suspended app meant nobody published at all.)*  
7. <a name="2.7"></a>The value SHALL be shown in mmol/L to one decimal place. No ingestion source encodes an out-of-measurable-range sentinel (HI/LO) — `bsl` carries a plain mmol/L `Double` — so WHEN a reading is non-finite or outside the plausible measurable range, the system SHALL treat it as never-recorded (Req 8.1) rather than render a fabricated decimal.  
8. <a name="2.8"></a>Rendering glucose on a locked device is intended; the widget carries no privacy or consent copy (developer-phase copy rule).  

### 3. Trend arrow derivation

**User Story:** As a user, I want a trend arrow, so that I can tell at a glance whether my glucose is rising or falling.

**Acceptance Criteria:**

1. <a name="3.1"></a>The system SHALL derive the trend from `bsl` readings whose timestamps fall within the 30 minutes preceding the current time — the closed window `[now − 30m, now]`, both bounds inclusive — as a single rate of change in mmol/L per minute over those readings. *(Widened from 15 minutes by Decision 15 after the live LibreLinkUp cadence was measured at a modal 15-minute gap.)*  
2. <a name="3.2"></a>The system SHALL classify the rate into one of seven states — steady, rising-slow, rising, rising-fast, falling-slow, falling, falling-fast — by fixed, non-overlapping thresholds (recorded in the decision log), each rendered as a corresponding arrow glyph.  
3. <a name="3.3"></a>IF fewer than two readings fall within the window, OR the earliest and latest in-window readings span less than 10 minutes, THEN the system SHALL report no trend and the widget SHALL show the value without an arrow.  
4. <a name="3.4"></a>WHEN the most-recent reading is itself older than the window, the system SHALL report no trend (no two readings can fall within it). Note that the staleness ladder (Req 5.2) withholds the arrow from 15 minutes regardless, so the window being wider than `staleAge` never surfaces an arrow beside a stale value.  
5. <a name="3.5"></a>The trend derivation SHALL be a pure function in one shared maths module, covered by unit tests including each threshold boundary, so the same computation is reusable by the in-app Graph screen **and by the widget extension**, which derives the trend itself when it fetches (Req 6.2) and reads the already-derived one otherwise. *(Redefined in place by Decision 16. Superseded wording: the function was pinned to `TrendsMath` in `Persistence`, "not importable by the widget extension" — true while the widget only ever read a snapshot the app had derived, and no longer true once it can fetch. The implementation lives in `GlucoseTrendMath` in the Foundation-only `GlucoseWidgetShared`; `TrendsMath` forwards to it, so the app-side callers this clause was protecting are unchanged.)*  

### 4. Target-band status

**User Story:** As a user, I want the tile to signal low / in-range / high at a glance, so that I notice an out-of-range level without reading the number — even though the Lock Screen renders widgets in monochrome.

**Acceptance Criteria:**

1. <a name="4.1"></a>The system SHALL classify the reading against the existing `TrendsMath` target band: low below 3.9 mmol/L, in-range from 3.9 to 10.0 mmol/L inclusive, high above 10.0 mmol/L.  
2. <a name="4.2"></a>The widget SHALL distinguish low / in-range / high with a channel that survives the Lock Screen's monochrome vibrant rendering — a functional glyph or short status token, not colour alone.  
3. <a name="4.3"></a>The widget MAY additionally apply per-status colour where the system renders it in full colour (StandBy day mode); this colour SHALL be an enhancement layered on the Req 4.2 channel, never the sole status signal.  
4. <a name="4.4"></a>WHEN the reading is stale (Req 5.2) or absent (Req 8), the status indicator SHALL be suppressed.  

### 5. Staleness

**User Story:** As a user, I want an old reading to look old, so that I don't act on a value that no longer reflects my glucose.

**Acceptance Criteria:**

1. <a name="5.1"></a>WHEN the most-recent reading is 15 minutes old or less, the widget SHALL render it at full prominence with its status indicator and trend arrow (if any).  
2. <a name="5.2"></a>WHEN the most-recent reading is older than 15 minutes and 30 minutes old or less, the widget SHALL render the value de-emphasised (reduced opacity, which survives monochrome rendering) with its relative age, with no status indicator and no trend arrow. This state is reached routinely rather than exceptionally, because the reload cadence is longer than the 15-minute threshold — see Req 6.5 for the accepted window.  
3. <a name="5.3"></a>WHEN the most-recent reading is older than 30 minutes, the widget SHALL hide the numeric value and show the reading's relative age as a "last reading" label, distinguishing this from the never-recorded state (Req 8.1).  
4. <a name="5.4"></a>The widget's timeline content SHALL be generated by a pure function of the snapshot and a reference time that emits a render state at the 15-minute and 30-minute age boundaries, so the full → de-emphasised → last-reading transitions are pre-baked and appear without new data arriving; this function SHALL be unit-tested, and SHALL therefore be free of any WidgetKit type.  
5. <a name="5.5"></a>Relative age SHALL be shown to the minute (e.g. "12m") for the first hour and to the hour beyond it; a reading timestamped in the future (clock skew) SHALL be treated as zero age.  

### 6. Refresh

**User Story:** As a user, I want the tile to update when new glucose arrives, so that it reflects my latest reading.

**Acceptance Criteria:**

1. <a name="6.1"></a>WHEN the app or its background glucose refresh writes a newer reading (Req 1.2, 1.3), the widget SHALL reflect it at its next system-permitted reload. What "system-permitted" amounts to in practice is bounded by Req 6.5.  
2. <a name="6.2"></a>WHEN the widget's timeline reloads AND the stored snapshot's reading is at least one vendor poll interval old AND a LibreLinkUp connection is configured, the widget SHALL fetch the latest readings itself and re-derive the snapshot, so freshness does not depend on the app process being alive.  
3. <a name="6.3"></a>The app and the widget SHALL share one vendor request budget with a 5-minute poll interval: each request sent on either side SHALL be recorded in the shared container before it goes out, and neither side SHALL fetch while the recorded last request is younger than the interval. *(Redefined in place by Decision 17 — the clause previously recorded each "successful fetch", which left a failing request unrecorded and so unthrottled.)* The gate is advisory (no cross-process atomicity) — the combined steady-state rate SHALL target one fetch per interval, with rare overlapping fetches accepted. The gate governs *scheduled* traffic: the app's connect step MAY spend one request through a closed gate to validate stored credentials, since a user-initiated connect that reports nothing for up to an interval is indistinguishable from a broken one. The widget has no such exemption — every widget fetch is gated.  
4. <a name="6.4"></a>The app's database remains the source of record: a widget-side fetch updates the shared display snapshot only, and the app SHALL ingest the same readings through its own poll/catch-up. A failed or rate-gated widget fetch SHALL fall back to the stored snapshot with the staleness treatment (Req 5).  
5. <a name="6.5"></a>The reload cadence is a platform property this system requests but does not set. WidgetKit reloads the widget on its own visibility-gated staleness evaluation, keyed on the Req 5.1 threshold, and does not honour the booked timeline date: measured at gaps of about 20 minutes against a booked 5 minutes, with none of the 18 observed reloads attributable to the booked date (task 16.7, one device, one 3-hour window). The accepted operating window that follows SHALL be: a reading rendered 2–3 minutes old after each refresh, ageing until the next one, so the widget renders the Req 5.2 stale treatment for part of most cycles and the worst-case displayed age is about 22 minutes — with every fetch succeeding and nothing in Req 6.2–6.4 failing. This window is the platform's floor on this display, not a defect, and SHALL NOT be closed by raising the Req 5.1 threshold: that threshold is also what the staleness timer keys on, so raising it postpones the reload by the same interval it buys while relabelling stale data as fresh (Decision 18). *(Added by Decision 18. It bounds Req 6.1 and 6.2 in place: "reflect it at its next system-permitted reload" and "freshness does not depend on the app process being alive" both hold, at this cadence and no faster.)*  

### 7. Tap target

**User Story:** As a user, I want tapping the tile to open the glucose graph, so that the full trend is one tap away.

**Acceptance Criteria:**

1. <a name="7.1"></a>WHEN the widget is tapped, the system SHALL open the app to the Graph view via a `medata://` deep link, reusing the existing deep-link handling.  
2. <a name="7.2"></a>WHEN the tap occurs on a locked device, the Graph destination SHALL still be reached after the user authenticates and the app opens.  

### 8. No-data and empty states

**User Story:** As a user with no glucose data yet, I want the tile to say so plainly, so that it isn't showing a stale or fabricated number.

**Acceptance Criteria:**

1. <a name="8.1"></a>WHEN no `bsl` reading has ever been recorded (or the snapshot is unreadable per Req 1.7), the widget SHALL show a never-recorded placeholder with no numeric value, no status indicator, and no trend arrow — visually distinct from the >30-minute last-reading state (Req 5.3).  
2. <a name="8.2"></a>All placeholder, gallery-preview, and label copy SHALL be functional only, with no disclaimer, reassurance, or consent text (developer-phase copy rule).  
