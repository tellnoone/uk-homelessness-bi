"""Integrity of the star schema and correctness of the analysis SQL."""

from decimal import ROUND_HALF_UP, Decimal

import pandas as pd
import pytest


def scalar(con, sql):
    return con.execute(sql).fetchone()[0]


def round1(x: float) -> float:
    """Round to one decimal, halves away from zero, after snapping float noise
    (published values have one decimal, so medians are exact to two)."""
    return float(Decimal(f"{x:.4f}").quantize(Decimal("0.1"), rounding=ROUND_HALF_UP))


# --------------------------------------------------------------- star schema
@pytest.mark.parametrize("dim, key", [
    ("dim_landlord", "landlord_key"), ("dim_measure", "measure_key"),
    ("dim_tenure", "tenure_key"), ("dim_date", "date_key"),
    ("dim_survey_method", "method_key"), ("dim_value_status", "status_key"),
])
def test_dimension_keys_are_unique_and_not_null(con, dim, key):
    assert scalar(con, f"SELECT count(*) - count(DISTINCT {key}) FROM mart.{dim}") == 0
    assert scalar(con, f"SELECT count(*) FROM mart.{dim} WHERE {key} IS NULL") == 0


@pytest.mark.parametrize("fact, key, dim, dim_key", [
    ("fact_tsm_result", "landlord_key", "dim_landlord", "landlord_key"),
    ("fact_tsm_result", "measure_key", "dim_measure", "measure_key"),
    ("fact_tsm_result", "tenure_key", "dim_tenure", "tenure_key"),
    ("fact_tsm_result", "date_key", "dim_date", "date_key"),
    ("fact_tsm_result", "status_key", "dim_value_status", "status_key"),
    ("fact_survey", "landlord_key", "dim_landlord", "landlord_key"),
    ("fact_survey_method", "method_key", "dim_survey_method", "method_key"),
    ("fact_repairs_target", "landlord_key", "dim_landlord", "landlord_key"),
])
def test_every_fact_key_resolves(con, fact, key, dim, dim_key):
    orphans = scalar(con, f"""
        SELECT count(*) FROM mart.{fact} f
        LEFT JOIN mart.{dim} d ON f.{key} = d.{dim_key}
        WHERE d.{dim_key} IS NULL""")
    assert orphans == 0


def test_date_dimension_covers_the_financial_year(con):
    first, last, days = con.execute(
        "SELECT min(date), max(date), count(*) FROM mart.dim_date").fetchone()
    assert (str(first), str(last), days) == ("2024-04-01", "2025-03-31", 365)
    assert scalar(con, "SELECT count(DISTINCT fiscal_year) FROM mart.dim_date") == 1


def test_every_measure_has_a_name_and_short_name(con):
    assert scalar(con, "SELECT count(*) FROM mart.dim_measure WHERE measure_name IS NULL OR short_name IS NULL") == 0
    assert scalar(con, "SELECT count(*) FROM mart.dim_measure") == 26


def test_usable_results_have_values_and_others_do_not(con):
    mismatched = scalar(con, """
        SELECT count(*) FROM mart.fact_tsm_result f JOIN mart.dim_value_status s USING (status_key)
        WHERE s.is_usable <> (f.value IS NOT NULL)""")
    assert mismatched == 0


def test_no_blocking_data_quality_failures(con):
    assert scalar(con, "SELECT count(*) FROM dq.check_result WHERE status = 'FAIL'") == 0


# ------------------------------------------------------------------ analysis
def test_sql_spearman_matches_pandas(con):
    wide = con.execute("SELECT * FROM analysis.lcra_perception_wide").df()
    sql = dict(con.execute(
        "SELECT lower(measure_code), spearman_rho FROM analysis.tp01_driver_correlation").fetchall())
    for measure, rho in sql.items():
        pair = wide[["tp01", measure]].dropna()
        assert rho == pytest.approx(pair.corr("spearman").iloc[0, 1], abs=5e-4), measure


def test_method_gap_matches_an_independent_calculation(con):
    raw = con.execute("SELECT * FROM raw.lcra_perception").df()
    tel = pd.to_numeric(raw["TP01_Satisfied_Telephone_LCRA"], errors="coerce")
    web = pd.to_numeric(raw["TP01_Satisfied_Internet_LCRA"], errors="coerce")
    gap = (tel - web).dropna()
    summary = con.execute("SELECT landlords, median_gap_pts FROM analysis.method_gap_summary").fetchone()
    assert summary[0] == len(gap)
    assert float(summary[1]) == pytest.approx(round1(gap.median()))


def test_median_tp01_matches_the_raw_file(con):
    raw = con.execute("SELECT TP01_Satisfied_Calc_LCRA AS v FROM raw.lcra_perception").df()
    expected = round1(pd.to_numeric(raw["v"], errors="coerce").median())
    assert float(scalar(con, "SELECT median_tp01 FROM analysis.tp01_summary")) == pytest.approx(expected)
