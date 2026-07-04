# Ground-Truth Fixtures

Manual readings of every test image in `data/img/`, one CSV per image. These
fixtures are the accuracy gate for trace extraction (requirements
[1.7](../../specs/mvp/requirements.md#1.7) /
[1.8](../../specs/mvp/requirements.md#1.8), Decision 9) and were committed
before any extraction code existed. They are frozen: the pipeline is tuned to
match the fixtures, never the other way around.

## File format

`IMG_XXXX.csv` — header `local_time,value`, one row per 5-minute wall-clock
mark (:00, :05, :10, …) **where a value was read**:

```
local_time,value
2026-07-01T16:20,14.3
```

- `local_time` is naive local wall-clock time (the timezone the screenshots
  were taken in), minute precision.
- `value` is the plotted glucose in mmol/L to one decimal place.
- A mark inside the graph's window that has **no row** asserts the trace is
  absent (or occluded) there. This drives both the false-positive gate (no
  extracted reading at a fixture-absent mark) and the ≥98% recall bound.

## Reading procedure

Each value was read by locating the mark's horizontal position from the
printed hour labels (linear fit over the labels' gridlines, extrapolated
beyond the last label where the trace continues) and the glucose scale from
the labelled y-axis gridlines (linear fit over all label rows). The rules
below restate ACs 1.4, 1.5, and 1.6 so fixtures and extractor share one
definition:

1. **Stroke centre** — the value at a mark is the vertical centre of the
   trace stroke at that mark's horizontal position (nearest trace column
   within half a mark pitch).
2. **Turning-point extremum** — where that position holds multiple disjoint
   strokes (a steep flank or spike apex), the value is the local extremum:
   the topmost stroke if the neighbouring columns' centres lie below it, the
   bottommost if above.
3. **≤10-minute bridge** — where the trace is absent at a mark but the
   surrounding absence spans 10 minutes or less, the value is interpolated
   linearly between the adjacent trace ends. (No absence in this corpus is
   that short — every break exceeds 10 minutes, so no fixture value is
   interpolated.)
4. **Gaps are omitted** — where the absence spans more than 10 minutes, every
   mark inside it is omitted; gaps are never interpolated across.
5. **Isolated points are trace** — a plotted point detached from the main
   trace (see IMG_0584) is trace: its centre value is recorded at every mark
   whose column the point covers; the surrounding gap marks stay omitted.
6. **Dot-occluded marks are omitted** — marks whose columns are covered by
   the current-reading marker (the orange dot, including its dark ring) are
   omitted because the trace beneath cannot be read (IMG_0570, 00:10–00:30).
7. **All trace colours count** — red below-threshold segments are trace.
   Threshold lines, the target band, gridlines, and surrounding UI are not.
8. **No clamping** — values are read where they are plotted, including beyond
   the labelled gridline range (IMG_0582 dips below the 3 line).

### Now-line / dot coincidence (IMG_0570)

The 8-hour home view draws a dark dashed vertical "now" line at
(85, 85, 85) — close to, but not inside, the extractor's trace-black colour
class (channel sum < 240), which therefore excludes it. Independently, its
~4 px width lies entirely inside the ~50 px of columns occluded by the
current-reading dot, so every mark it touches is omitted as occluded even if
the colour class were ever loosened. The extractor's tests assert the
occlusion coincidence as a backstop for the colour exclusion; it is stated
here so nobody treats those columns as readable trace.

### Date attribution

- 24-hour daily reports: the printed report date; marks run 00:00–23:55
  (half-open window, at most 288 marks).
- 8-hour home view (IMG_0570): the date is the calendar date at the window's
  right edge — Thursday 2026-07-02 (status-bar clock 00:16, weekday label
  "Wed | T", one hour-label wrap 21:00 → 00:00). Rows before midnight belong
  to 2026-07-01, rows at and after midnight to 2026-07-02.

## Per-image notes

| Image | View | Date | Axis | Readings | Notes |
|---|---|---|---|---|---|
| IMG_0570 | home 8h | 2026-07-02 (right edge) | 3–21 | 94 | trace 16:20–00:05; 00:10–00:30 dot-occluded; window ≈ 16:16–00:16 |
| IMG_0578 | daily 24h | 2026-07-04 | 3–21 | 163 | partial day, trace ends 13:50; sensor breaks ~04:55 and ~06:25 |
| IMG_0579 | daily 24h | 2026-07-03 | 3–21 | 279 | fragmented 17:10–19:45 (three gaps) |
| IMG_0580 | daily 24h | 2026-07-02 | 3–27 | 288 | tall axis; red lows ~02:00 and 19:30–21:30; peak 20.5 |
| IMG_0581 | daily 24h | 2026-07-01 | 3–21 | 286 | gap 11:10–11:15; red dip ~03:00 |
| IMG_0582 | daily 24h | 2026-06-30 | 3–21 | 257 | trace starts 02:35; dips below the 3 gridline (2.7, not clamped) |
| IMG_0583 | daily 24h | 2026-06-29 | 3–21 | 216 | trace ends 18:05; gap 12:40–12:45; several red segments |
| IMG_0584 | daily 24h | 2026-06-28 | 3–21 | 191 | two isolated points (05:20–05:35 at 13.4, 14:50–15:05 at 6.1); large gaps |
| IMG_0585 | daily 24h | 2026-06-27 | 3–21 | 288 | continuous full day; red dips ~02:15 and ~22:00 |
