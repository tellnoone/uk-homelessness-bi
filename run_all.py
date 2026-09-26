"""One command from the raw CSVs to every output:

    python run_all.py

1. Builds the DuckDB warehouse (raw -> staging -> star schema -> analysis -> data quality).
2. Stops if any blocking data quality check fails.
3. Writes the star schema for Power BI (outputs/powerbi/), the data quality
   results (outputs/data_quality/), the README figures (outputs/figures/) and
   every quoted number (outputs/results.json).

Then `python verify_report.py` checks the README against outputs/results.json.
"""

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
os.chdir(ROOT)
sys.path.insert(0, str(ROOT))

from src import export, report, warehouse  # noqa: E402


def main() -> None:
    print("Building warehouse from data/raw/ ...")
    con = warehouse.build()

    failures = export.blocking_failures(con)
    export.export_data_quality(con)
    if failures:
        print("\nBlocking data quality checks failed; outputs/data_quality/ has the detail:")
        for check_id, name, n in failures:
            print(f"  {check_id} {name}: {n} rows")
        sys.exit(1)

    print("Exporting star schema for Power BI ...")
    export.export_star_schema(con)
    print("Writing results and figures ...")
    report.write_results(report.collect_results(con))
    report.build_figures(con)

    summary = con.execute(
        "SELECT count(*) FILTER (WHERE status = 'PASS'), count(*) FILTER (WHERE status = 'WARN'), count(*) "
        "FROM dq.check_result").fetchone()
    print(f"\nDone. Data quality: {summary[0]} of {summary[2]} checks passed, {summary[1]} warnings, 0 blocking failures.")
    con.close()


if __name__ == "__main__":
    main()
