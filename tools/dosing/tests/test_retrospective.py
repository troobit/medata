"""Tests for `tools/dosing/retrospective.py`.

Every number asserted here comes from a SYNTHETIC fixture built by
`fixture.py` and hand-counted in the test that uses it. None of it is, or may
be reported as, a measurement of the developer's recorded history — the
`specs/data/insulin-dosing` task these support is blocked on a real export for
exactly that reason.

Written as `unittest.TestCase` so the suite runs on a bare interpreter
(`python3 -m unittest discover tools/dosing/tests`) as well as under pytest
alongside the repository's other tool tests.
"""

import contextlib
import io
import json
import re
import sqlite3
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

import retrospective as rt  # noqa: E402
from fixture import HOUR, MINUTE, FixtureBuilder, meal_metadata  # noqa: E402

T0 = 1_700_000_000_000


def load_fixture(builder):
    """Run the tool's load + window construction over a built fixture."""
    db = rt.connect(builder.write())
    try:
        corpus = rt.load(db)
    finally:
        db.close()
    return corpus, rt.build_windows(corpus)


def capture(path):
    buffer = io.StringIO()
    with contextlib.redirect_stdout(buffer):
        rt.main([str(path)])
    return buffer.getvalue()


def parse(output):
    """Output lines as {tag: [{key: value}, ...]}."""
    parsed = {}
    for line in output.splitlines():
        tokens = line.split()
        pairs = dict(token.split("=", 1) for token in tokens[1:])
        parsed.setdefault(tokens[0], []).append(pairs)
    return parsed


class TempCase(unittest.TestCase):
    def setUp(self):
        self._dir = tempfile.TemporaryDirectory()
        self.dir = Path(self._dir.name)
        self.addCleanup(self._dir.cleanup)

    def builder(self, name="meals.sqlite"):
        return FixtureBuilder(self.dir / name)


# ------------------------------------------------------------ record decoding

class RecordDecodingTests(TempCase):
    def test_record_is_a_json_string_inside_the_envelope(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7, fat_g=20.0, protein_g=15.0)
        corpus, _ = load_fixture(builder)
        meal = corpus.meals[0]
        self.assertTrue(meal.decoded)
        self.assertEqual(meal.sigma_meal, 0.7)
        self.assertAlmostEqual(meal.fpu, 2.4)

    def test_snake_case_keys_are_accepted(self):
        builder = self.builder()
        record = json.dumps({"confidence": {"sigma_meal": 0.42},
                             "macros": {"clinical_totals": {"fat_g": 10.0,
                                                            "protein_g": 5.0}}})
        builder.event("meal", T0, 60.0,
                      json.dumps({"record": record, "palette_version": "v0"}))
        corpus, _ = load_fixture(builder)
        meal = corpus.meals[0]
        self.assertEqual(meal.sigma_meal, 0.42)
        self.assertAlmostEqual(meal.fpu, 1.1)

    def test_absent_confidence_is_absent_not_zero(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=None, fat_g=1.0)
        corpus, _ = load_fixture(builder)
        meal = corpus.meals[0]
        self.assertTrue(meal.decoded)
        self.assertFalse(meal.sigma_present)
        self.assertIsNone(meal.sigma_meal)

    def test_undecodable_metadata_is_counted_not_crashed(self):
        builder = self.builder()
        builder.event("meal", T0, 60.0, "not json at all")
        builder.event("meal", T0 + MINUTE, 60.0, json.dumps({"palette_version": "v0"}))
        corpus, _ = load_fixture(builder)
        self.assertEqual(corpus.undecodable_meals, 2)
        self.assertEqual(len(corpus.meals), 2)

    def test_non_finite_floats_do_not_enter_the_distribution(self):
        builder = self.builder()
        record = json.dumps({"confidence": {"sigmaMeal": "NaN"},
                             "macros": {"clinicalTotals": {"fatG": "Infinity"}}})
        builder.event("meal", T0, 60.0,
                      json.dumps({"record": record, "palette_version": "v0"}))
        corpus, _ = load_fixture(builder)
        meal = corpus.meals[0]
        self.assertFalse(meal.sigma_present)
        self.assertIsNone(meal.fat_g)


# ----------------------------------------------------------------- correction

class CorrectionTests(TempCase):
    def test_events_value_alone_is_the_uncorrected_total(self):
        builder = self.builder()
        meal_id = builder.meal(T0, 60.0, sigma=0.7)
        builder.correction(meal_id, T0 + HOUR, 45.0)
        corpus, _ = load_fixture(builder)
        meal = corpus.meals[0]
        self.assertEqual(meal.stored_carbs_g, 60.0)
        self.assertEqual(meal.effective_carbs_g, 45.0)
        self.assertTrue(meal.corrected)

    def test_latest_correction_wins(self):
        builder = self.builder()
        meal_id = builder.meal(T0, 60.0, sigma=0.7)
        builder.correction(meal_id, T0 + 2 * HOUR, 50.0)
        builder.correction(meal_id, T0 + HOUR, 45.0)
        corpus, _ = load_fixture(builder)
        self.assertEqual(corpus.meals[0].effective_carbs_g, 50.0)
        self.assertEqual(corpus.corrections_applied, 2)

    def test_correction_without_the_carbohydrate_oneof_is_ignored(self):
        builder = self.builder()
        meal_id = builder.meal(T0, 60.0, sigma=0.7)
        builder.corrections.append(
            (meal_id, T0 + HOUR, json.dumps({"createdAtMs": "1", "note": "looks fine"})))
        corpus, _ = load_fixture(builder)
        self.assertFalse(corpus.meals[0].corrected)
        self.assertEqual(corpus.meals[0].effective_carbs_g, 60.0)


# ------------------------------------------------------------------------ fpu

class FpuTests(TempCase):
    def test_unavailable_when_clinical_totals_are_absent(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7, clinical=False)
        builder.meal(T0 + HOUR, 40.0, sigma=0.6, clinical=False)
        output = parse(capture(builder.write()))
        row = output["fpu"][0]
        self.assertEqual(row["status"], "unavailable")
        self.assertEqual(row["reason"], "clinical_totals_absent_in_all_meals")
        self.assertEqual(row["denominator"], "2")
        self.assertNotIn("fpu_dist", output)

    def test_unavailable_when_clinical_totals_are_present_but_empty(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7)
        output = parse(capture(builder.write()))
        row = output["fpu"][0]
        self.assertEqual(row["status"], "unavailable")
        self.assertEqual(row["reason"], "clinical_totals_empty_in_all_meals")

    def test_an_empty_clinical_totals_row_is_excluded_not_read_as_zero(self):
        # Per row, for the reason the whole-corpus case is unavailable: proto3
        # omits a default, so an empty message cannot be told from two real
        # zeros, and folding it in would drag the distribution towards "fat
        # never matters".
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7, fat_g=20.0, protein_g=15.0)
        builder.meal(T0 + HOUR, 40.0, sigma=0.6)
        path = builder.write()
        db = rt.connect(path)
        try:
            corpus = rt.load(db)
        finally:
            db.close()
        empty = corpus.meals[1]
        self.assertTrue(empty.clinical_present)
        self.assertFalse(empty.clinical_has_any_key)
        self.assertIsNone(empty.fpu)

        row = parse(capture(path))["fpu"][0]
        self.assertEqual(row["status"], "available")
        self.assertEqual(row["n"], "1")
        self.assertEqual(row["clinical_empty"], "1")
        self.assertEqual(row["denominator"], "2")

    def test_one_populated_key_makes_the_other_a_real_zero(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7, fat_g=20.0)
        corpus, _ = load_fixture(builder)
        meal = corpus.meals[0]
        self.assertIsNone(meal.protein_g)
        self.assertAlmostEqual(meal.fpu, 1.8)

    def test_available_reports_stale_rows_separately(self):
        builder = self.builder()
        first = builder.meal(T0, 60.0, sigma=0.7, fat_g=20.0, protein_g=15.0)
        builder.meal(T0 + HOUR, 40.0, sigma=0.6, fat_g=10.0, protein_g=10.0)
        builder.correction(first, T0 + 2 * HOUR, 55.0)
        output = parse(capture(builder.write()))
        row = output["fpu"][0]
        self.assertEqual(row["status"], "available")
        self.assertEqual(row["n"], "2")
        self.assertEqual(row["stale"], "1")
        self.assertEqual(row["stale_frac"], "0.5000")
        # (20 x 9 + 15 x 4) / 100 = 2.4 and (10 x 9 + 10 x 4) / 100 = 1.3.
        self.assertEqual(output["fpu_dist"][0]["max"], "2.400")
        self.assertEqual(output["fpu_dist"][0]["min"], "1.300")


# -------------------------------------------------------------------- pairing

class PairingTests(TempCase):
    def test_symmetric_window_and_direction_split(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7)
        builder.bolus(T0 + 10 * MINUTE, 6.0)
        builder.meal(T0 + 10 * HOUR, 40.0, sigma=0.7)
        builder.bolus(T0 + 10 * HOUR - 20 * MINUTE, 4.0)
        _, windows = load_fixture(builder)
        paired = [w for w in windows if w.paired]
        self.assertEqual(len(paired), 2)
        self.assertEqual(sorted(round(w.gap_min) for w in paired), [-20, 10])

    def test_forty_six_minutes_does_not_pair(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7)
        builder.bolus(T0 + 46 * MINUTE, 6.0)
        _, windows = load_fixture(builder)
        self.assertFalse(windows[0].paired)

    def test_exactly_forty_five_minutes_pairs(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7)
        builder.bolus(T0 + 45 * MINUTE, 6.0)
        _, windows = load_fixture(builder)
        self.assertTrue(windows[0].paired)

    def test_basal_never_pairs(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7)
        builder.basal(T0 + 5 * MINUTE, 15.0)
        corpus, windows = load_fixture(builder)
        self.assertEqual(len(corpus.basals), 1)
        self.assertEqual(len(corpus.boluses), 0)
        self.assertFalse(windows[0].paired)

    def test_intakes_are_candidates_too(self):
        builder = self.builder()
        builder.intake(T0, 20.0)
        builder.bolus(T0 + 5 * MINUTE, 2.0)
        _, windows = load_fixture(builder)
        self.assertEqual(len(windows), 1)
        self.assertEqual(windows[0].carb_kind, "intake")
        self.assertTrue(windows[0].paired)


# ------------------------------------------------------------------- confounds

class ConfoundTests(TempCase):
    def base(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7)
        builder.bolus(T0 + 10 * MINUTE, 6.0)
        builder.bsl_series(T0 - HOUR, T0 + 12 * HOUR, 5)
        return builder

    def test_clean_window_survives_every_filter(self):
        _, windows = load_fixture(self.base())
        window = windows[0]
        self.assertTrue(window.complete)
        self.assertFalse(window.second_bolus)
        self.assertFalse(window.intervening_carb)
        self.assertEqual(window.coverage, 1.0)

    def test_second_bolus_inside_the_window_is_stacking(self):
        builder = self.base()
        builder.bolus(T0 + 3 * HOUR, 2.0)
        _, windows = load_fixture(builder)
        self.assertTrue(windows[0].second_bolus)

    def test_a_bolus_exactly_at_the_window_edge_counts(self):
        builder = self.base()
        builder.bolus(T0 + 10 * MINUTE + 6 * HOUR, 2.0)
        _, windows = load_fixture(builder)
        self.assertTrue(windows[0].second_bolus)

    def test_a_second_bolus_at_the_paired_dose_instant_is_stacking(self):
        # Exclusion is by bolus identity, not by instant: two doses recorded at
        # one timestamp are two doses, and only one of them was paired.
        builder = self.base()
        builder.bolus(T0 + 10 * MINUTE, 2.0)
        corpus, windows = load_fixture(builder)
        self.assertEqual(len(corpus.boluses), 2)
        self.assertTrue(windows[0].second_bolus)

    def test_the_paired_meal_itself_is_not_an_intervening_carbohydrate(self):
        _, windows = load_fixture(self.base())
        self.assertFalse(windows[0].intervening_carb)

    def test_a_later_intake_is_an_intervening_carbohydrate(self):
        builder = self.base()
        builder.intake(T0 + 2 * HOUR, 15.0)
        _, windows = load_fixture(builder)
        self.assertTrue(windows[0].intervening_carb)

    def test_two_carbohydrate_events_at_one_instant_each_see_the_other(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7)
        builder.intake(T0, 15.0)
        builder.bolus(T0 + 10 * MINUTE, 6.0)
        builder.bsl_series(T0 - HOUR, T0 + 12 * HOUR, 5)
        _, windows = load_fixture(builder)
        self.assertEqual(len(windows), 2)
        # One dose covers both plates, so neither window can attribute its own
        # outcome — confounded twice over, by the span and by the shared dose.
        self.assertEqual(len({w.bolus_id for w in windows}), 1)
        self.assertTrue(all(w.intervening_carb for w in windows))
        self.assertTrue(all(w.shared_bolus for w in windows))

    def test_one_dose_covering_an_intake_and_a_later_meal_confounds_both(self):
        # The pattern the span-only test missed: the intake sits before the
        # dose, so it is outside the meal window's span however that span opens,
        # yet the same dose covers both plates.
        builder = self.builder()
        builder.intake(T0, 15.0)
        builder.bolus(T0 + 5 * MINUTE, 6.0)
        builder.meal(T0 + 20 * MINUTE, 60.0, sigma=0.7)
        builder.bsl_series(T0 - HOUR, T0 + 12 * HOUR, 5)
        _, windows = load_fixture(builder)
        self.assertEqual(len(windows), 2)
        self.assertEqual(len({w.bolus_id for w in windows}), 1)
        self.assertTrue(all(w.shared_bolus for w in windows))

    def test_a_window_with_its_own_dose_does_not_share_it(self):
        builder = self.base()
        builder.intake(T0 + 20 * HOUR, 15.0)
        builder.bolus(T0 + 20 * HOUR + 5 * MINUTE, 2.0)
        _, windows = load_fixture(builder)
        self.assertEqual(len(windows), 2)
        self.assertFalse(any(w.shared_bolus for w in windows))

    def test_an_unpaired_window_shares_nothing(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7)
        builder.intake(T0 + 5 * MINUTE, 15.0)
        _, windows = load_fixture(builder)
        self.assertFalse(any(w.paired for w in windows))
        self.assertFalse(any(w.shared_bolus for w in windows))

    def test_the_windows_own_event_at_the_dose_instant_is_not_intervening(self):
        # Exclusion is by event identity, so a meal recorded at its dose's exact
        # instant is still not its own confound.
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7)
        builder.bolus(T0, 6.0)
        builder.bsl_series(T0 - HOUR, T0 + 12 * HOUR, 5)
        _, windows = load_fixture(builder)
        self.assertEqual(len(windows), 1)
        self.assertFalse(windows[0].intervening_carb)

    def test_a_carbohydrate_event_before_the_span_is_not_intervening(self):
        # The span opens at the meal, not arbitrarily earlier: a plate two hours
        # before an unrelated one does not confound it.
        builder = self.base()
        builder.intake(T0 - 2 * HOUR, 15.0)
        _, windows = load_fixture(builder)
        meal_window = next(w for w in windows if w.carb_kind == "meal")
        self.assertFalse(meal_window.intervening_carb)

    def test_window_running_past_the_last_reading_is_truncated(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7)
        builder.bolus(T0 + 10 * MINUTE, 6.0)
        builder.bsl_series(T0, T0 + 3 * HOUR, 5)
        _, windows = load_fixture(builder)
        self.assertFalse(windows[0].complete)


# ------------------------------------------------------------------- coverage

class CoverageTests(TempCase):
    def window_for(self, step_min=5, extent_hours=12):
        builder = self.builder(f"cadence-{step_min}-{extent_hours}.sqlite")
        builder.meal(T0, 60.0, sigma=0.7)
        builder.bolus(T0 + 10 * MINUTE, 6.0)
        builder.bsl_series(T0, T0 + extent_hours * HOUR, step_min)
        _, windows = load_fixture(builder)
        return windows[0]

    def test_fifteen_minute_cadence_still_covers_every_bucket(self):
        # Bucket occupancy, not sample density: the poll interval changed from
        # 15 minutes to 5 part-way through this history, and coverage must not
        # report that change as a coverage collapse.
        self.assertEqual(self.window_for(step_min=15).coverage, 1.0)
        self.assertEqual(self.window_for(step_min=5).coverage, 1.0)

    def test_sample_counts_do_track_cadence(self):
        self.assertGreater(self.window_for(step_min=5).samples,
                           self.window_for(step_min=15).samples)

    def test_a_hole_costs_whole_buckets(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7)
        start = T0 + 10 * MINUTE
        builder.bolus(start, 6.0)
        builder.bsl_series(T0, start + 2 * HOUR, 5)
        builder.bsl_series(start + 4 * HOUR, T0 + 12 * HOUR, 5)
        _, windows = load_fixture(builder)
        window = windows[0]
        # Readings run to +120 min (bucket 4) and resume at +240 min (bucket 8),
        # so buckets 5, 6 and 7 are empty and the largest hole is two hours.
        self.assertAlmostEqual(window.coverage, 9 / 12)
        self.assertAlmostEqual(window.max_gap_min, 120.0, places=3)

    def test_empty_window_reports_zero_coverage_and_a_full_span_gap(self):
        builder = self.builder()
        builder.meal(T0, 60.0, sigma=0.7)
        builder.bolus(T0 + 10 * MINUTE, 6.0)
        builder.bsl_series(T0 + 20 * HOUR, T0 + 30 * HOUR, 5)
        _, windows = load_fixture(builder)
        self.assertEqual(windows[0].coverage, 0.0)
        self.assertAlmostEqual(windows[0].max_gap_min, rt.OUTCOME_WINDOW_MIN)


# ------------------------------------------------------------- end-to-end run

def scenario(builder):
    """Five carbohydrate candidates with one hand-counted survivor.

    A  T0            paired +10 min, clean                     -> survives
    B  T0+24h        paired +5 min, second bolus at +3h        -> stacked out
    C  T0+48h        nearest bolus 50 min away                 -> unpaired
    D  T0+72h intake paired -10 min, meal E lands 2 h later    -> confounded
    E  T0+74h        no bolus at all                           -> unpaired
    """
    builder.meal(T0, 60.0, sigma=0.70, fat_g=20.0, protein_g=15.0)
    builder.bolus(T0 + 10 * MINUTE, 6.0)

    meal_b = builder.meal(T0 + 24 * HOUR, 40.0, sigma=0.30,
                          fat_g=10.0, protein_g=10.0)
    builder.bolus(T0 + 24 * HOUR + 5 * MINUTE, 4.0)
    builder.bolus(T0 + 27 * HOUR, 2.0)
    builder.correction(meal_b, T0 + 25 * HOUR, 45.0)
    builder.correction(meal_b, T0 + 26 * HOUR, 50.0)

    builder.meal(T0 + 48 * HOUR, 50.0, sigma=0.90, fat_g=5.0, protein_g=5.0)
    builder.bolus(T0 + 48 * HOUR + 50 * MINUTE, 5.0)

    builder.intake(T0 + 72 * HOUR, 20.0)
    builder.bolus(T0 + 72 * HOUR - 10 * MINUTE, 2.0)
    builder.meal(T0 + 74 * HOUR, 35.0, sigma=0.15, fat_g=30.0, protein_g=25.0)

    builder.basal(T0 + 7 * HOUR, 15.0)
    builder.bsl_series(T0 - HOUR, T0 + 96 * HOUR, 5)
    return builder


class EndToEndTests(TempCase):
    def setUp(self):
        super().setUp()
        self.output = parse(capture(scenario(self.builder()).write()))

    def test_candidate_and_pairing_counts(self):
        self.assertEqual(self.output["carb_events"][0],
                         {"n": "5", "meal": "4", "intake": "1"})
        pair = self.output["pair"][0]
        self.assertEqual((pair["n"], pair["denominator"], pair["frac"]),
                         ("3", "5", "0.6000"))
        direction = self.output["pair_direction"][0]
        self.assertEqual((direction["bolus_after"], direction["bolus_before"]),
                         ("2", "1"))

    def test_stacking_and_intervening_rates_carry_their_denominator(self):
        self.assertEqual(self.output["stack"][0],
                         {"n": "1", "denominator": "3", "frac": "0.3333"})
        self.assertEqual(self.output["intervening_carb"][0],
                         {"n": "1", "denominator": "3", "frac": "0.3333"})

    def test_attrition_waterfall_shows_where_the_windows_went(self):
        steps = {row["step"]: row for row in self.output["filter"]}
        self.assertEqual(steps["candidates"]["n"], "5")
        self.assertEqual(steps["paired_45min"]["n"], "3")
        self.assertEqual(steps["window_complete"]["n"], "3")
        self.assertEqual(steps["no_second_bolus"]["n"], "2")
        # No dose in this scenario is paired to two carbohydrate events, so the
        # shared-dose step passes all of them through.
        self.assertEqual(steps["no_shared_bolus"]["n"], "2")
        self.assertEqual(steps["no_intervening_carb"]["n"], "1")
        self.assertEqual(steps["no_second_bolus"]["entered"], "3")
        self.assertEqual(steps["no_intervening_carb"]["of_candidates"], "0.2000")

    def test_the_waterfall_order_is_fixed(self):
        self.assertEqual([row["step"] for row in self.output["filter"]],
                         ["candidates", "paired_45min", "window_complete",
                          "no_second_bolus", "no_shared_bolus",
                          "no_intervening_carb", "coverage_ge_0.70"])

    def test_the_last_waterfall_step_is_the_survivor_count(self):
        # Coverage is a rung of the waterfall, not a filter applied after it, so
        # a reader cannot mistake the last printed step for the headline.
        last = self.output["filter"][-1]
        self.assertEqual(last["step"], "coverage_ge_0.70")
        self.assertEqual(last["n"], self.output["surviving"][0]["n"])
        self.assertEqual(last["of_candidates"], self.output["surviving"][0]["frac"])

    def test_headline_surviving_fraction(self):
        surviving = self.output["surviving"][0]
        self.assertEqual(surviving["n"], "1")
        self.assertEqual(surviving["denominator"], "5")
        self.assertEqual(surviving["frac"], "0.2000")
        self.assertEqual(surviving["coverage_min"], "0.70")
        self.assertEqual(surviving["pair_window_min"], "45")
        self.assertEqual(surviving["outcome_window_min"], "360")

    def test_every_coverage_rung_is_reported(self):
        rungs = [row["coverage_min"] for row in self.output["surviving_ladder"]]
        self.assertEqual(rungs, ["0.50", "0.70", "0.90", "1.00"])
        for row in self.output["surviving_ladder"]:
            self.assertEqual(row["denominator"], "5")

    def test_sigma_distribution_and_both_thresholds(self):
        sigma = self.output["sigma"][0]
        self.assertEqual((sigma["n"], sigma["absent"], sigma["denominator"]),
                         ("4", "0", "4"))
        self.assertEqual(self.output["sigma_dist"][0]["min"], "0.1500")
        self.assertEqual(self.output["sigma_dist"][0]["max"], "0.9000")
        thresholds = self.output["sigma_thresholds"][0]
        self.assertEqual(thresholds["lt_0.20"], "1")
        self.assertEqual(thresholds["lt_0.50"], "2")

    def test_fpu_distribution_and_bands(self):
        self.assertEqual(self.output["fpu"][0]["status"], "available")
        self.assertEqual(self.output["fpu"][0]["n"], "4")
        self.assertEqual(self.output["fpu_dist"][0]["min"], "0.650")
        self.assertEqual(self.output["fpu_dist"][0]["max"], "3.700")
        bands = {row["ge"]: row["n"] for row in self.output["fpu_band"]}
        self.assertEqual(bands, {"1.0": "3", "2.0": "2", "3.0": "1"})

    def test_corrections_move_the_effective_carbohydrate_total(self):
        meal = self.output["meal"][0]
        self.assertEqual((meal["n"], meal["corrected"], meal["correction_rows"]),
                         ("4", "1", "2"))
        self.assertEqual(self.output["meal_carbs_uncorrected_g"][0]["max"], "60.00")
        self.assertEqual(self.output["meal_carbs_effective_g"][0]["p50"], "50.00")

    def test_basal_is_counted_but_excluded_from_pairing(self):
        self.assertEqual(self.output["insulin"][0],
                         {"bolus": "5", "basal": "1", "unparsed": "0"})


# ----------------------------------------------------------- output and input

class OutputShapeTests(TempCase):
    def test_every_line_is_a_tag_followed_by_key_equals_value(self):
        output = capture(scenario(self.builder()).write())
        line_pattern = re.compile(r"^[a-z_]+(?: [A-Za-z0-9_.]+=[^ ]+)*$")
        self.assertTrue(output.strip())
        for line in output.splitlines():
            self.assertRegex(line, line_pattern)

    def test_no_prose_sentences_appear(self):
        output = capture(scenario(self.builder()).write())
        self.assertNotIn(". ", output)
        self.assertEqual(output.count(":"), 0)


class InputTests(TempCase):
    def test_reads_a_zip_archive(self):
        db_path = scenario(self.builder()).write()
        archive = self.dir / "export.zip"
        with zipfile.ZipFile(archive, "w") as zf:
            zf.write(db_path, "meals.sqlite")
            zf.writestr("meals/abc/mask.png", b"\x89PNG")
        zipped = parse(capture(archive))
        direct = parse(capture(db_path))
        self.assertEqual(zipped["surviving"], direct["surviving"])

    def test_zip_member_without_an_events_table_is_skipped(self):
        db_path = scenario(self.builder()).write()
        decoy = self.dir / "other.sqlite"
        sqlite3.connect(str(decoy)).close()
        archive = self.dir / "export.zip"
        with zipfile.ZipFile(archive, "w") as zf:
            zf.write(decoy, "aaa.sqlite")
            zf.write(db_path, "meals.sqlite")
        self.assertEqual(parse(capture(archive))["surviving"][0]["n"], "1")

    def test_the_database_is_not_written_to(self):
        db_path = Path(scenario(self.builder()).write())
        before = db_path.read_bytes()
        capture(db_path)
        self.assertEqual(db_path.read_bytes(), before)
        self.assertFalse((self.dir / "meals.sqlite-wal").exists())
        self.assertFalse((self.dir / "meals.sqlite-journal").exists())

    def test_a_database_without_an_events_table_is_refused(self):
        path = self.dir / "empty.sqlite"
        sqlite3.connect(str(path)).close()
        with self.assertRaises(SystemExit):
            capture(path)

    def test_an_empty_event_log_reports_zeros_rather_than_failing(self):
        builder = self.builder()
        output = parse(capture(builder.write()))
        self.assertEqual(output["surviving"][0]["n"], "0")
        self.assertEqual(output["surviving"][0]["frac"], "na")
        self.assertEqual(output["fpu"][0]["status"], "unavailable")


class ConstantTests(unittest.TestCase):
    def test_the_filter_constants_are_the_spec_values(self):
        self.assertEqual(rt.PAIR_WINDOW_MIN, 45.0)
        self.assertEqual(rt.OUTCOME_WINDOW_MIN, 360.0)
        self.assertEqual(rt.COVERAGE_BUCKETS, 12)

    def test_no_command_line_flag_can_loosen_a_filter(self):
        # Req 11.4: the filters are not loosened to raise the surviving
        # fraction, so the only argument the tool accepts is the export path.
        buffer = io.StringIO()
        with contextlib.redirect_stderr(buffer):
            with self.assertRaises(SystemExit):
                rt.main(["a.sqlite", "--coverage-min", "0.1"])
        self.assertIn("unrecognized arguments", buffer.getvalue())


class MetadataShapeTests(TempCase):
    def test_glucose_sources_are_split_by_metadata_key_shape(self):
        from fixture import bsl_metadata, screenshot_metadata
        builder = self.builder()
        builder.bsl(T0, 6.0, bsl_metadata("librelinkup"))
        builder.bsl(T0 + 5 * MINUTE, 6.1, bsl_metadata("healthkit"))
        builder.bsl(T0 + 10 * MINUTE, 6.2, screenshot_metadata())
        builder.bsl(T0 + 15 * MINUTE, 6.3, "{}")
        output = parse(capture(builder.write()))
        row = output["bsl"][0]
        self.assertEqual(row["n"], "4")
        self.assertEqual(row["librelinkup"], "1")
        self.assertEqual(row["healthkit"], "1")
        self.assertEqual(row["screenshot"], "1")
        self.assertEqual(row["empty"], "1")

    def test_insulin_without_a_kind_is_counted_as_unparsed(self):
        builder = self.builder()
        builder.event("insulin", T0, 6.0, json.dumps({"insulin_type": "NovoRapid"}))
        corpus, _ = load_fixture(builder)
        self.assertEqual(corpus.insulin_unparsed, 1)
        self.assertEqual(len(corpus.boluses), 0)

    def test_meal_metadata_helper_omits_proto3_defaults(self):
        envelope = json.loads(meal_metadata(carbs_g=None, sigma=None, clinical=False))
        record = json.loads(envelope["record"])
        self.assertNotIn("macros", record)
        self.assertNotIn("confidence", record)


if __name__ == "__main__":
    unittest.main()
