#!/usr/bin/env python3
"""The D0 measurement behind `specs/data/insulin-dosing/` Req 11.2: is outcome
scoring viable on this developer's real recorded history at all?

Req 11.2 names six figures. This reads an exported medata event log — the
`meals.sqlite` inside an `exportArchive()` ZIP, or that file on its own — and
reports every one of them:

  * the `sigma_meal` distribution over stored meals;
  * the fat-protein-unit distribution over those same meals;
  * meal-or-intake to bolus pairing yield inside 45 minutes;
  * glucose coverage across the 6 hours after each such dose;
  * the rate at which a further bolus lands inside that window;
  * the combined surviving fraction under all the confounding filters.

The last one is the headline. Req 11.3 makes a low number a legitimate answer,
so it is printed with the denominator it came from and with each filter's own
attrition, not as a bare percentage. Every rate here carries its n for the same
reason: on a corpus this size a fraction over four windows is not a result.

Req 11.4 forbids loosening the filters to raise that fraction, so the filter
constants below are module constants with no command-line override. The
coverage ladder is the one place several thresholds appear, and all of its rungs
print on every run — it exists so the sensitivity is visible to the human making
the Req 11.3 call, not so a rung can be selected after seeing the answer.

Three readings of the source data are load-bearing and easy to get wrong:

  * A meal's `events.value` is the UNCORRECTED carbohydrate total. Corrections
    live in the `corrections` side table and are never written back into the row
    or into the inner protobuf record. Anything reading `value` alone silently
    ignores every correction the developer ever made.
  * The inner meal record is protobuf-JSON with SwiftProtobuf's defaults: keys
    are lowerCamelCase and any field equal to its proto3 default is ABSENT.
    `totalCarbsG` missing means 0 g; `confidence` missing means the sub-message
    was never populated. Those two are not the same fact, and the second is
    reported as absent rather than folded into the distribution as a zero.
  * Fat and protein grams reach the record through `macros.clinicalTotals`.
    A meal contributes an FPU only where that message holds at least one of the
    two keys; where it is missing or empty the meal is counted and excluded, and
    where no meal has it the distribution is UNAVAILABLE with its reason.
    Substituting zeros for an empty message would manufacture a "fat never
    matters" answer out of an empty field, one meal at a time.

Read-only throughout: the database is opened `mode=ro` and a ZIP is expanded
into a temporary directory that is removed on exit.

Usage:
    tools/dosing/retrospective.py <export.zip | meals.sqlite>
"""

import argparse
import bisect
import json
import math
import shutil
import sqlite3
import sys
import tempfile
import zipfile
from collections import Counter
from pathlib import Path

# ---------------------------------------------------------------- the filters
#
# No command-line override exists for any of these (Req 11.4). Each cites the
# spec text that fixes it.

# `specs/data/insulin-dosing/decision_log.md` Decision 12: "Recording a meal or
# an intake arms a seed ... with a 45-minute lifetime. ... The same 45 minutes
# is the pairing window the retrospective measurement uses." One constant, so
# the live association and this measurement cannot disagree about the same
# history.
PAIR_WINDOW_MIN = 45.0

# Decision 8: "Scoring needs a roughly 6-hour post-dose glucose window".
OUTCOME_WINDOW_MIN = 360.0

# Coverage is measured as the fraction of 30-minute buckets in the outcome
# window holding at least one glucose reading. Bucket occupancy rather than
# sample count is deliberate: the polling cadence changed from 15 minutes to 5
# minutes part-way through this history (cgm-connect Decision 13), so a
# density-based measure would report the cadence change rather than the gaps
# that actually break a post-dose trajectory.
COVERAGE_BUCKET_MIN = 30.0
COVERAGE_BUCKETS = int(OUTCOME_WINDOW_MIN / COVERAGE_BUCKET_MIN)

# Every rung prints on every run. `COVERAGE_PRIMARY` is the rung the headline
# `surviving` line uses.
COVERAGE_LADDER = (0.50, 0.70, 0.90, 1.00)
COVERAGE_PRIMARY = 0.70

MS_PER_MIN = 60_000.0

# `MedataCore/Sources/Persistence/PersistenceStore.swift` — the four event types.
MEAL, BSL, INSULIN, INTAKE = "meal", "bsl", "insulin", "intake"
CARB_TYPES = (MEAL, INTAKE)

# `specs/data/insulin-dosing/design.md`: fpu = (fat_g x 9 + protein_g x 4) / 100.
KCAL_PER_G_FAT, KCAL_PER_G_PROTEIN, KCAL_PER_FPU = 9.0, 4.0, 100.0

# medreg refuses a plate below 0.5 (`suggest/dose.py:46`); medata's UI calls
# below 0.2 "Very Low" (`specs/estimation/pipeline/design.md`). Both are
# reported so the disagreement is sized rather than assumed.
SIGMA_MEDREG_FLOOR = 0.50
SIGMA_VERY_LOW = 0.20


# ------------------------------------------------------------------- plumbing

def open_database(path, workdir):
    """Return a read-only connection to the event log at `path`.

    A ZIP is scanned for the first member with a database suffix that actually
    holds an `events` table, matching how medreg's loader reads the same
    archive (`~/repos/medreg/src/medreg/ingest/loader.py`).
    """
    if zipfile.is_zipfile(path):
        with zipfile.ZipFile(path) as archive:
            members = [m for m in archive.namelist()
                       if m.lower().endswith((".sqlite", ".sqlite3", ".db"))]
            for member in members:
                extracted = Path(archive.extract(member, path=workdir))
                if has_events_table(extracted):
                    return connect(extracted), extracted
        raise SystemExit(f"no member with an events table in {path}")
    if not has_events_table(path):
        raise SystemExit(f"no events table in {path}")
    return connect(path), Path(path)


def connect(path):
    return sqlite3.connect(f"file:{path}?mode=ro", uri=True)


def has_events_table(path):
    try:
        db = connect(path)
    except sqlite3.Error:
        return False
    try:
        row = db.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='events'"
        ).fetchone()
        return row is not None
    except sqlite3.Error:
        return False
    finally:
        db.close()


def table_exists(db, name):
    return db.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name=?", (name,)
    ).fetchone() is not None


# --------------------------------------------------------------- field access

def field(obj, *names):
    """First present key among `names`, or None.

    SwiftProtobuf emits lowerCamelCase and no encoder options are set anywhere
    in the repository, so camelCase is what lands on device. snake_case is
    accepted too, because a record written by a differently configured encoder
    should not read as an empty meal.
    """
    if not isinstance(obj, dict):
        return None
    for name in names:
        if name in obj:
            return obj[name]
    return None


def number(value):
    """A finite float, or None.

    proto3 JSON encodes non-finite floats as the strings "NaN"/"Infinity". No
    pipeline path is known to produce one, which is exactly why an unchecked
    float() here would fail loudly on the day one appears.
    """
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        result = float(value)
    elif isinstance(value, str):
        try:
            result = float(value)
        except ValueError:
            return None
    else:
        return None
    return result if math.isfinite(result) else None


def submessage(obj, *names):
    value = field(obj, *names)
    return value if isinstance(value, dict) else None


# ------------------------------------------------------------------ meal rows

class Meal:
    """One decoded meal row: the SQL row plus the parts of the inner record read here."""

    __slots__ = ("event_id", "timestamp_ms", "stored_carbs_g", "decoded",
                 "sigma_meal", "sigma_present", "fat_g", "protein_g",
                 "clinical_present", "clinical_has_any_key", "corrected_carbs_g",
                 "correction_ms")

    def __init__(self, event_id, timestamp_ms, stored_carbs_g):
        self.event_id = event_id
        self.timestamp_ms = timestamp_ms
        self.stored_carbs_g = stored_carbs_g
        self.decoded = False
        self.sigma_meal = None
        self.sigma_present = False
        self.fat_g = None
        self.protein_g = None
        self.clinical_present = False
        self.clinical_has_any_key = False
        self.corrected_carbs_g = None
        self.correction_ms = None

    @property
    def corrected(self):
        return self.corrected_carbs_g is not None

    @property
    def effective_carbs_g(self):
        return self.corrected_carbs_g if self.corrected else self.stored_carbs_g

    @property
    def fpu(self):
        """The meal's fat-protein units, or None where the field says nothing.

        An empty `clinicalTotals` message carries no more information than a
        missing one — proto3 omits a field equal to its default, so neither key
        being present is indistinguishable from both being genuinely zero. Only
        a message with at least one key contributes; there the OTHER key's
        absence is a real zero, because something populated the message.
        """
        if not self.clinical_has_any_key:
            return None
        fat = self.fat_g if self.fat_g is not None else 0.0
        protein = self.protein_g if self.protein_g is not None else 0.0
        return (fat * KCAL_PER_G_FAT + protein * KCAL_PER_G_PROTEIN) / KCAL_PER_FPU


def decode_meal_metadata(meal, metadata):
    """Fill `meal` from the two-key metadata envelope.

    `metadata.record` is a JSON STRING, not a nested object — it is decoded a
    second time (`MedataCore/Sources/Persistence/MealRecord.swift`).
    """
    try:
        outer = json.loads(metadata)
    except (TypeError, ValueError):
        return
    inner_raw = field(outer, "record")
    if not isinstance(inner_raw, str):
        return
    try:
        record = json.loads(inner_raw)
    except ValueError:
        return
    if not isinstance(record, dict):
        return
    meal.decoded = True

    confidence = submessage(record, "confidence")
    if confidence is not None:
        sigma = number(field(confidence, "sigmaMeal", "sigma_meal"))
        # `sigma_meal` is floored at 0.01 in `Confidence.swift`, so it is never
        # legitimately absent-as-zero: an absent key inside a present
        # `confidence` message means the value was not written.
        if sigma is not None:
            meal.sigma_meal = sigma
            meal.sigma_present = True

    macros = submessage(record, "macros")
    clinical = submessage(macros, "clinicalTotals", "clinical_totals") if macros else None
    if clinical is not None:
        meal.clinical_present = True
        meal.clinical_has_any_key = len(clinical) > 0
        meal.fat_g = number(field(clinical, "fatG", "fat_g"))
        meal.protein_g = number(field(clinical, "proteinG", "protein_g"))

    # A record written by an older build could in principle carry the inner
    # correction that today's pipeline never populates. It is read here so the
    # side table and the record can be compared by age rather than assumed.
    inner_correction = submessage(record, "userCorrection", "user_correction")
    if inner_correction is not None:
        value = number(field(inner_correction, "correctedTotalCarbsG",
                             "corrected_total_carbs_g"))
        created = number(field(inner_correction, "createdAtMs", "created_at_ms"))
        if value is not None:
            meal.corrected_carbs_g = value
            meal.correction_ms = created if created is not None else -1.0


def apply_corrections(db, meals_by_id):
    """Overlay the `corrections` side table, newest correction winning.

    A meal can hold several correction rows, and only the ones with the
    carbohydrate oneof actually set count — the same reading every app surface
    composes on read.
    """
    if not table_exists(db, "corrections"):
        return 0
    applied = 0
    for meal_id, created_at, blob in db.execute(
        "SELECT meal_id, created_at, correction_json FROM corrections"
    ):
        meal = meals_by_id.get(meal_id)
        if meal is None:
            continue
        if isinstance(blob, bytes):
            blob = blob.decode("utf-8", "replace")
        try:
            payload = json.loads(blob)
        except (TypeError, ValueError):
            continue
        value = number(field(payload, "correctedTotalCarbsG", "corrected_total_carbs_g"))
        if value is None:
            continue
        stamp = number(created_at)
        if stamp is None:
            stamp = number(field(payload, "createdAtMs", "created_at_ms")) or 0.0
        if meal.correction_ms is None or stamp >= meal.correction_ms:
            meal.corrected_carbs_g = value
            meal.correction_ms = stamp
        applied += 1
    return applied


# ----------------------------------------------------------------- other rows

def bolus_kind(metadata):
    """"bolus" / "basal" / None, from the hand-built snake_case insulin envelope."""
    try:
        payload = json.loads(metadata)
    except (TypeError, ValueError):
        return None
    kind = field(payload, "kind")
    return kind if isinstance(kind, str) else None


def bsl_source(metadata):
    """Which ingestion path wrote a glucose row.

    There is no source column. Live rows carry `source_id`, screenshot imports
    carry `source_hash`, and the DEBUG seeder writes a literal empty object —
    the key shape is the only discriminator.
    """
    try:
        payload = json.loads(metadata)
    except (TypeError, ValueError):
        return "unparsed"
    if not isinstance(payload, dict):
        return "unparsed"
    if not payload:
        return "empty"
    source_id = field(payload, "source_id")
    if isinstance(source_id, str) and source_id:
        return source_id
    if field(payload, "source_hash") is not None:
        return "screenshot"
    return "other"


def intake_subtype(metadata):
    try:
        payload = json.loads(metadata)
    except (TypeError, ValueError):
        return "unparsed"
    subtype = field(payload, "subtype")
    return subtype if isinstance(subtype, str) else "other"


# ------------------------------------------------------------------ load pass

class Corpus:
    def __init__(self):
        self.meals = []
        self.intakes = []          # (event_id, timestamp_ms, carbs_g, subtype)
        self.boluses = []          # (event_id, timestamp_ms, units)
        self.basals = []
        self.insulin_unparsed = 0
        self.bsl_ms = []
        self.bsl_sources = Counter()
        self.type_counts = Counter()
        self.undecodable_meals = 0
        self.schema_version = None
        self.corrections_applied = 0
        self.corrections_table = False


def load(db):
    corpus = Corpus()
    meals_by_id = {}

    for event_id, timestamp, event_type, value, metadata in db.execute(
        "SELECT id, timestamp, event_type, value, metadata FROM events"
    ):
        corpus.type_counts[event_type] += 1
        stamp = number(timestamp)
        if stamp is None:
            continue
        if event_type == MEAL:
            meal = Meal(event_id, stamp, number(value))
            decode_meal_metadata(meal, metadata)
            if not meal.decoded:
                corpus.undecodable_meals += 1
            corpus.meals.append(meal)
            meals_by_id[event_id] = meal
        elif event_type == INTAKE:
            corpus.intakes.append(
                (event_id, stamp, number(value), intake_subtype(metadata)))
        elif event_type == INSULIN:
            kind = bolus_kind(metadata)
            if kind == "bolus":
                corpus.boluses.append((event_id, stamp, number(value)))
            elif kind == "basal":
                corpus.basals.append((event_id, stamp, number(value)))
            else:
                corpus.insulin_unparsed += 1
        elif event_type == BSL:
            corpus.bsl_ms.append(stamp)
            corpus.bsl_sources[bsl_source(metadata)] += 1

    corpus.meals.sort(key=lambda m: (m.timestamp_ms, m.event_id))
    corpus.intakes.sort(key=lambda row: (row[1], row[0]))
    corpus.boluses.sort(key=lambda row: (row[1], row[0]))
    corpus.bsl_ms.sort()

    corpus.corrections_table = table_exists(db, "corrections")
    corpus.corrections_applied = apply_corrections(db, meals_by_id)

    if table_exists(db, "meta"):
        # The column names are `k` / `v`, not `key` / `value`
        # (`GRDBPersistenceStore.createSchema`).
        row = db.execute("SELECT v FROM meta WHERE k='schema_version'").fetchone()
        if row is not None:
            corpus.schema_version = row[0]

    return corpus


# --------------------------------------------------------------- the windows

class Window:
    __slots__ = ("carb_event_id", "carb_kind", "carb_ms", "bolus_id", "bolus_ms",
                 "gap_min", "complete", "second_bolus", "intervening_carb",
                 "shared_bolus", "coverage", "samples", "max_gap_min")

    def __init__(self, carb_event_id, carb_kind, carb_ms):
        self.carb_event_id = carb_event_id
        self.carb_kind = carb_kind
        self.carb_ms = carb_ms
        self.bolus_id = None
        self.bolus_ms = None
        self.gap_min = None
        self.complete = False
        self.second_bolus = False
        self.intervening_carb = False
        self.shared_bolus = False
        self.coverage = None
        self.samples = 0
        self.max_gap_min = None

    @property
    def paired(self):
        return self.bolus_id is not None


def slice_between(sorted_values, low, high):
    """Indices of the closed range [low, high] in a sorted list of instants."""
    return bisect.bisect_left(sorted_values, low), bisect.bisect_right(sorted_values, high)


def nearest_bolus(boluses, bolus_ms_sorted, carb_ms):
    """The bolus closest in time to `carb_ms` within the pairing window.

    Req 11.2 says "pairable with a bolus inside 45 minutes" without a direction,
    and pre-bolusing puts the dose before the meal, so the window is symmetric.
    The directional split is reported separately rather than folded away.
    """
    span = PAIR_WINDOW_MIN * MS_PER_MIN
    low, high = slice_between(bolus_ms_sorted, carb_ms - span, carb_ms + span)
    best = None
    best_gap = PAIR_WINDOW_MIN
    for bolus_id, bolus_ms, _units in boluses[low:high]:
        gap = abs(bolus_ms - carb_ms) / MS_PER_MIN
        if gap <= best_gap:
            best_gap, best = gap, (bolus_id, bolus_ms, (bolus_ms - carb_ms) / MS_PER_MIN)
    return best


def build_windows(corpus):
    carb_events = [(m.event_id, MEAL, m.timestamp_ms) for m in corpus.meals]
    carb_events += [(row[0], INTAKE, row[1]) for row in corpus.intakes]
    carb_events.sort(key=lambda row: (row[2], row[0]))
    carb_ms_sorted = [row[2] for row in carb_events]
    carb_id_by_index = [row[0] for row in carb_events]

    bolus_ms_sorted = [row[1] for row in corpus.boluses]
    last_bsl_ms = corpus.bsl_ms[-1] if corpus.bsl_ms else None
    span_ms = OUTCOME_WINDOW_MIN * MS_PER_MIN

    windows = []
    for event_id, kind, carb_ms in carb_events:
        window = Window(event_id, kind, carb_ms)
        match = nearest_bolus(corpus.boluses, bolus_ms_sorted, carb_ms)
        if match is None:
            windows.append(window)
            continue
        window.bolus_id, window.bolus_ms, window.gap_min = match

        start, end = window.bolus_ms, window.bolus_ms + span_ms
        window.complete = last_bsl_ms is not None and last_bsl_ms >= end

        # Both confound tests span a CLOSED interval and exclude the window's
        # own event by identity rather than by instant. Excluding by instant
        # would let a second dose recorded at the paired dose's exact timestamp
        # pass as the paired dose itself.
        low, high = slice_between(bolus_ms_sorted, start, end)
        window.second_bolus = any(bolus_id != window.bolus_id
                                  for bolus_id, _ms, _units in corpus.boluses[low:high])

        # The span opens at the EARLIER of the meal and the dose it was paired
        # to, not at the dose. Where the dose came first, a carbohydrate event
        # between the two lands in the same trajectory, and a span opening at
        # the dose would miss it.
        low, high = slice_between(carb_ms_sorted, min(carb_ms, start), end)
        window.intervening_carb = any(carb_id_by_index[i] != event_id
                                      for i in range(low, high))

        low, high = slice_between(corpus.bsl_ms, start, end)
        inside = corpus.bsl_ms[low:high]
        window.samples = len(inside)
        buckets = {int((ms - start) // (COVERAGE_BUCKET_MIN * MS_PER_MIN))
                   for ms in inside if ms < end}
        window.coverage = len(buckets) / COVERAGE_BUCKETS
        window.max_gap_min = largest_gap_min(inside, start, end)
        windows.append(window)

    mark_shared_boluses(windows)
    return windows


def mark_shared_boluses(windows):
    """Flag every window whose dose was also paired to another carbohydrate event.

    This is the second half of attribution, and it is a pairing fact rather than
    a span fact: a meal and a manual intake either side of one dose feed that
    dose whatever their spacing, and no interval anchored on one of them is
    guaranteed to contain the other. A dose covering two plates cannot be
    scored against either, so both windows are confounded.
    """
    per_bolus = Counter(w.bolus_id for w in windows if w.paired)
    for window in windows:
        window.shared_bolus = window.paired and per_bolus[window.bolus_id] > 1


def largest_gap_min(sorted_ms, start, end):
    """Longest stretch of the window with no reading, including both edges."""
    marks = [start] + list(sorted_ms) + [end]
    return max((marks[i + 1] - marks[i]) / MS_PER_MIN for i in range(len(marks) - 1))


# ------------------------------------------------------------------ reporting

def percentile(values, q):
    """Nearest-rank percentile over an already-sorted list."""
    if not values:
        return None
    rank = max(1, min(len(values), int(math.ceil(q * len(values)))))
    return values[rank - 1]


def num(value, places=4):
    return "na" if value is None else f"{value:.{places}f}"


def frac(numerator, denominator):
    return "na" if not denominator else f"{numerator / denominator:.4f}"


def emit_distribution(tag, values, places=4):
    ordered = sorted(values)
    n = len(ordered)
    if n == 0:
        print(f"{tag} n=0")
        return
    mean = sum(ordered) / n
    print(f"{tag} n={n} min={num(ordered[0], places)} "
          f"p10={num(percentile(ordered, 0.10), places)} "
          f"p25={num(percentile(ordered, 0.25), places)} "
          f"p50={num(percentile(ordered, 0.50), places)} "
          f"p75={num(percentile(ordered, 0.75), places)} "
          f"p90={num(percentile(ordered, 0.90), places)} "
          f"max={num(ordered[-1], places)} mean={num(mean, places)}")


def report(corpus, windows, db_path):
    counts = corpus.type_counts
    print(f"db file={db_path.name} schema_version={corpus.schema_version} "
          f"corrections_table={int(corpus.corrections_table)}")
    print(f"events total={sum(counts.values())} meal={counts[MEAL]} bsl={counts[BSL]} "
          f"insulin={counts[INSULIN]} intake={counts[INTAKE]} "
          f"other={sum(counts.values()) - sum(counts[t] for t in (MEAL, BSL, INSULIN, INTAKE))}")

    stamps = [m.timestamp_ms for m in corpus.meals] + corpus.bsl_ms \
        + [row[1] for row in corpus.boluses] + [row[1] for row in corpus.intakes]
    if stamps:
        first, last = min(stamps), max(stamps)
        print(f"span first_ms={int(first)} last_ms={int(last)} "
              f"days={num((last - first) / 86_400_000.0, 2)}")
    else:
        print("span n=0")

    print(f"insulin bolus={len(corpus.boluses)} basal={len(corpus.basals)} "
          f"unparsed={corpus.insulin_unparsed}")

    sources = " ".join(f"{k}={v}" for k, v in sorted(corpus.bsl_sources.items()))
    print(f"bsl n={len(corpus.bsl_ms)} {sources}".rstrip())

    report_meals(corpus)
    report_sigma(corpus)
    report_fpu(corpus)
    report_pairing(corpus, windows)
    report_coverage(windows)
    report_survival(windows)


def report_meals(corpus):
    decoded = [m for m in corpus.meals if m.decoded]
    corrected = [m for m in decoded if m.corrected]
    print(f"meal n={len(corpus.meals)} decoded={len(decoded)} "
          f"undecodable={corpus.undecodable_meals} corrected={len(corrected)} "
          f"corrected_frac={frac(len(corrected), len(corpus.meals))} "
          f"correction_rows={corpus.corrections_applied}")
    emit_distribution("meal_carbs_uncorrected_g",
                      [m.stored_carbs_g for m in corpus.meals
                       if m.stored_carbs_g is not None], places=2)
    emit_distribution("meal_carbs_effective_g",
                      [m.effective_carbs_g for m in corpus.meals
                       if m.effective_carbs_g is not None], places=2)


def report_sigma(corpus):
    decoded = [m for m in corpus.meals if m.decoded]
    present = [m.sigma_meal for m in decoded if m.sigma_present]
    absent = len(decoded) - len(present)
    print(f"sigma n={len(present)} absent={absent} denominator={len(corpus.meals)}")
    emit_distribution("sigma_dist", present)
    if present:
        very_low = sum(1 for s in present if s < SIGMA_VERY_LOW)
        below = sum(1 for s in present if s < SIGMA_MEDREG_FLOOR)
        print(f"sigma_thresholds n={len(present)} "
              f"lt_{SIGMA_VERY_LOW:.2f}={very_low} "
              f"lt_{SIGMA_VERY_LOW:.2f}_frac={frac(very_low, len(present))} "
              f"lt_{SIGMA_MEDREG_FLOOR:.2f}={below} "
              f"lt_{SIGMA_MEDREG_FLOOR:.2f}_frac={frac(below, len(present))}")
    else:
        print(f"sigma_thresholds n=0 lt_{SIGMA_VERY_LOW:.2f}=na "
              f"lt_{SIGMA_MEDREG_FLOOR:.2f}=na")


def report_fpu(corpus):
    decoded = [m for m in corpus.meals if m.decoded]
    with_clinical = [m for m in decoded if m.clinical_present]
    populated = [m for m in with_clinical if m.clinical_has_any_key]
    values = [m.fpu for m in with_clinical if m.fpu is not None]

    if not decoded:
        print("fpu status=unavailable reason=no_decodable_meal_record n=0 "
              f"denominator={len(corpus.meals)}")
        return
    if not with_clinical:
        print("fpu status=unavailable reason=clinical_totals_absent_in_all_meals "
              f"n=0 denominator={len(decoded)}")
        return
    if not populated:
        print("fpu status=unavailable reason=clinical_totals_empty_in_all_meals "
              f"n=0 denominator={len(decoded)}")
        return

    # Every count on this line shares the set that produced the distribution,
    # so the ratios below are numerator and denominator over the same meals.
    stale = sum(1 for m in populated if m.corrected)
    fat_absent = sum(1 for m in populated if m.fat_g is None)
    protein_absent = sum(1 for m in populated if m.protein_g is None)
    print(f"fpu status=available n={len(values)} denominator={len(decoded)} "
          f"clinical_populated={len(populated)} "
          f"clinical_empty={len(with_clinical) - len(populated)} stale={stale} "
          f"stale_frac={frac(stale, len(values))} "
          f"fat_key_absent={fat_absent} protein_key_absent={protein_absent}")
    emit_distribution("fpu_dist", values, places=3)
    emit_distribution("fpu_fat_g", [m.fat_g for m in populated
                                    if m.fat_g is not None], places=2)
    emit_distribution("fpu_protein_g", [m.protein_g for m in populated
                                        if m.protein_g is not None], places=2)
    for band in (1.0, 2.0, 3.0):
        hits = sum(1 for v in values if v >= band)
        print(f"fpu_band ge={band:.1f} n={hits} denominator={len(values)} "
              f"frac={frac(hits, len(values))}")


def report_pairing(corpus, windows):
    paired = [w for w in windows if w.paired]
    by_kind = Counter(w.carb_kind for w in windows)
    paired_by_kind = Counter(w.carb_kind for w in paired)
    print(f"carb_events n={len(windows)} meal={by_kind[MEAL]} intake={by_kind[INTAKE]}")
    print(f"pair window_min={PAIR_WINDOW_MIN:.0f} n={len(paired)} "
          f"denominator={len(windows)} frac={frac(len(paired), len(windows))}")
    for kind in CARB_TYPES:
        print(f"pair_by_kind kind={kind} n={paired_by_kind[kind]} "
              f"denominator={by_kind[kind]} "
              f"frac={frac(paired_by_kind[kind], by_kind[kind])}")
    after = sum(1 for w in paired if w.gap_min > 0)
    before = sum(1 for w in paired if w.gap_min < 0)
    same = sum(1 for w in paired if w.gap_min == 0)
    print(f"pair_direction n={len(paired)} bolus_after={after} bolus_before={before} "
          f"simultaneous={same} after_frac={frac(after, len(paired))}")
    distinct = len({w.bolus_id for w in paired})
    print(f"pair_bolus distinct={distinct} bolus_total={len(corpus.boluses)} "
          f"shared={len(paired) - distinct}")
    emit_distribution("pair_gap_min", [abs(w.gap_min) for w in paired], places=2)


def report_coverage(windows):
    paired = [w for w in windows if w.paired]
    complete = [w for w in paired if w.complete]
    print(f"window span_min={OUTCOME_WINDOW_MIN:.0f} buckets={COVERAGE_BUCKETS} "
          f"bucket_min={COVERAGE_BUCKET_MIN:.0f} n={len(paired)} "
          f"complete={len(complete)} truncated={len(paired) - len(complete)}")
    emit_distribution("coverage_dist", [w.coverage for w in complete])
    emit_distribution("coverage_samples", [float(w.samples) for w in complete], places=1)
    emit_distribution("coverage_max_gap_min",
                      [w.max_gap_min for w in complete if w.max_gap_min is not None],
                      places=1)
    for rung in COVERAGE_LADDER:
        hits = sum(1 for w in complete if w.coverage >= rung)
        print(f"coverage_ladder min={rung:.2f} n={hits} denominator={len(complete)} "
              f"frac={frac(hits, len(complete))}")

    stacked = sum(1 for w in paired if w.second_bolus)
    print(f"stack n={stacked} denominator={len(paired)} "
          f"frac={frac(stacked, len(paired))}")
    intervening = sum(1 for w in paired if w.intervening_carb)
    print(f"intervening_carb n={intervening} denominator={len(paired)} "
          f"frac={frac(intervening, len(paired))}")
    shared = sum(1 for w in paired if w.shared_bolus)
    print(f"shared_bolus n={shared} denominator={len(paired)} "
          f"frac={frac(shared, len(paired))}")


def report_survival(windows):
    """The headline, as a waterfall: every filter's own attrition, then the product.

    Filters are applied in a fixed order and each step prints what entered it,
    what left it, and what fraction of the ORIGINAL candidate set remains — so a
    reader can see which filter consumed the windows rather than only that they
    are gone. The coverage threshold is the last rung of that same waterfall
    rather than a step applied after it, so the final `filter` line and the
    `surviving` headline are the same number reached two ways.
    """
    candidates = len(windows)
    steps = [
        ("candidates", list(windows)),
    ]
    stage = [w for w in windows if w.paired]
    steps.append((f"paired_{PAIR_WINDOW_MIN:.0f}min", stage))
    stage = [w for w in stage if w.complete]
    steps.append(("window_complete", stage))
    stage = [w for w in stage if not w.second_bolus]
    steps.append(("no_second_bolus", stage))
    stage = [w for w in stage if not w.shared_bolus]
    steps.append(("no_shared_bolus", stage))
    stage = [w for w in stage if not w.intervening_carb]
    steps.append(("no_intervening_carb", stage))
    unconfounded = stage
    stage = [w for w in stage if w.coverage >= COVERAGE_PRIMARY]
    steps.append((f"coverage_ge_{COVERAGE_PRIMARY:.2f}", stage))

    previous = candidates
    for name, kept in steps:
        print(f"filter step={name} n={len(kept)} entered={previous} "
              f"kept_frac={frac(len(kept), previous)} "
              f"of_candidates={frac(len(kept), candidates)}")
        previous = len(kept)

    for rung in COVERAGE_LADDER:
        survivors = [w for w in unconfounded if w.coverage >= rung]
        print(f"surviving_ladder coverage_min={rung:.2f} n={len(survivors)} "
              f"denominator={candidates} frac={frac(len(survivors), candidates)}")

    survivors = stage
    print(f"surviving n={len(survivors)} denominator={candidates} "
          f"frac={frac(len(survivors), candidates)} "
          f"coverage_min={COVERAGE_PRIMARY:.2f} "
          f"pair_window_min={PAIR_WINDOW_MIN:.0f} "
          f"outcome_window_min={OUTCOME_WINDOW_MIN:.0f}")
    by_kind = Counter(w.carb_kind for w in survivors)
    for kind in CARB_TYPES:
        print(f"surviving_by_kind kind={kind} n={by_kind[kind]} "
              f"denominator={candidates}")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("export", type=Path,
                        help="exportArchive() ZIP, or the meals.sqlite inside it")
    args = parser.parse_args(argv)

    if not args.export.exists():
        raise SystemExit(f"no such file: {args.export}")

    workdir = tempfile.mkdtemp(prefix="medata-retrospective-")
    try:
        db, db_path = open_database(args.export, workdir)
        try:
            corpus = load(db)
        finally:
            db.close()
        report(corpus, build_windows(corpus), db_path)
    finally:
        shutil.rmtree(workdir, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
