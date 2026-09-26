"""Write the star schema and the data quality results to outputs/."""

from pathlib import Path

import duckdb

ROOT = Path(__file__).resolve().parent.parent
POWERBI_DIR = ROOT / "outputs" / "powerbi"
DQ_DIR = ROOT / "outputs" / "data_quality"

STAR_SCHEMA = [
    "dim_date", "dim_landlord", "dim_measure", "dim_tenure",
    "dim_survey_method", "dim_value_status",
    "fact_tsm_result", "fact_survey", "fact_survey_method", "fact_repairs_target",
]


def _write_csv(con: duckdb.DuckDBPyConnection, query: str, path: Path) -> None:
    # A fixed ORDER BY in every query keeps the files byte-stable between runs,
    # so git only shows a diff when the data actually changed.
    con.execute(f"COPY ({query}) TO '{path.as_posix()}' (HEADER, DELIMITER ',')")


def export_star_schema(con: duckdb.DuckDBPyConnection) -> None:
    POWERBI_DIR.mkdir(parents=True, exist_ok=True)
    for table in STAR_SCHEMA:
        _write_csv(con, f"SELECT * FROM mart.{table} ORDER BY ALL", POWERBI_DIR / f"{table}.csv")


def export_data_quality(con: duckdb.DuckDBPyConnection) -> None:
    DQ_DIR.mkdir(parents=True, exist_ok=True)
    _write_csv(con, "SELECT * FROM dq.check_result ORDER BY check_id", DQ_DIR / "check_result.csv")
    _write_csv(
        con,
        """SELECT f.check_id, f.landlord_code, l.landlord_name, f.detail
           FROM dq.check_failure f LEFT JOIN stg.landlord l USING (landlord_code)
           ORDER BY ALL""",
        DQ_DIR / "check_failure.csv",
    )
    (DQ_DIR / "check_result.md").write_text(_markdown_table(con), encoding="utf-8")


def _markdown_table(con: duckdb.DuckDBPyConnection) -> str:
    rows = con.execute(
        """SELECT check_id, category, check_name, rows_tested, rows_failed, status, action_taken
           FROM dq.check_result ORDER BY check_id"""
    ).fetchall()
    lines = [
        "| Check | Category | What is tested | Rows tested | Failed | Status | Action taken |",
        "|---|---|---|---:|---:|---|---|",
    ]
    for check_id, category, name, tested, failed, status, action in rows:
        lines.append(f"| {check_id} | {category} | {name} | {tested:,} | {failed:,} | {status} | {action} |")
    return "\n".join(lines) + "\n"


def blocking_failures(con: duckdb.DuckDBPyConnection) -> list[tuple]:
    """Checks whose failure means the model cannot be trusted."""
    return con.execute(
        "SELECT check_id, check_name, rows_failed FROM dq.check_result WHERE status = 'FAIL'"
    ).fetchall()
