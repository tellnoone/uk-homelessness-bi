"""The data quality checks catch the problems they claim to catch.

Each test corrupts a throwaway warehouse in one specific way, re-runs the data
quality SQL, and asserts the matching check fails. A check that passes on
clean data proves nothing unless it also fails on bad data.
"""

from pathlib import Path

DQ_SQL = (Path(__file__).resolve().parent.parent / "sql" / "40_data_quality.sql").read_text(encoding="utf-8")


def rerun_checks(con) -> dict[str, int]:
    con.execute(DQ_SQL)
    return dict(con.execute("SELECT check_id, rows_failed FROM dq.check_result").fetchall())


def test_clean_data_has_no_duplicates_or_reconciliation_failures(scratch_con):
    failed = rerun_checks(scratch_con)
    for check in ("DU01", "DU02", "RC01", "RC02", "RC03", "RI01", "RI02", "RI04", "RG01", "RG02"):
        assert failed[check] == 0, check


def test_du01_catches_a_duplicated_landlord(scratch_con):
    scratch_con.execute("INSERT INTO raw.lcra_perception SELECT * FROM raw.lcra_perception LIMIT 1")
    assert rerun_checks(scratch_con)["DU01"] == 1


def test_rc01_catches_a_percentage_that_does_not_match_its_counts(scratch_con):
    scratch_con.execute("""
        UPDATE stg.perception_result SET value = value + 1
        WHERE landlord_code = 'L4240' AND measure_code = 'TP01' AND tenure_code = 'LCRA'""")
    assert rerun_checks(scratch_con)["RC01"] == 1


def test_rg01_and_rc02_catch_an_impossible_percentage(scratch_con):
    scratch_con.execute("""
        UPDATE mart.fact_tsm_result SET value = 120
        WHERE landlord_key = 1 AND measure_key = (SELECT measure_key FROM mart.dim_measure WHERE measure_code = 'BS01')""")
    failed = rerun_checks(scratch_con)
    assert failed["RG01"] == 1
    assert failed["RC02"] == 1


def test_ri01_catches_a_landlord_missing_from_the_coverage_file(scratch_con):
    scratch_con.execute("DELETE FROM stg.landlord WHERE landlord_code = 'L4240'")
    assert rerun_checks(scratch_con)["RI01"] >= 1


def test_cp03_catches_u_on_a_measure_that_applies(scratch_con):
    scratch_con.execute("""
        UPDATE stg.management_result SET status_code = '[U]'
        WHERE landlord_code = 'L4240' AND measure_code = 'BS01'""")
    assert rerun_checks(scratch_con)["CP03"] == 1
