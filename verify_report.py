"""Check every number quoted in the README (and the expected values in the DAX
guide) against outputs/results.json, the file run_all.py writes.

For each claim below it checks two things:
  1. the documented value equals what the pipeline produced (after rounding
     to the precision the document shows), and
  2. the documented value appears in the document as written.
It also checks that the README's data quality table is exactly the one the
pipeline generated.

    python run_all.py && python verify_report.py
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
RESULTS = json.loads((ROOT / "outputs" / "results.json").read_text(encoding="utf-8"))
DOCS = {
    "README": (ROOT / "README.md").read_text(encoding="utf-8"),
    "DAX": (ROOT / "powerbi" / "DAX_MEASURES.md").read_text(encoding="utf-8"),
}


def get(path: str):
    node = RESULTS
    for part in path.split("/"):
        node = node[part]
    return node


R = get  # short alias for derived claims below

# (document, label, documented value as it appears, actual value, decimals)
CLAIMS = [
    # ------------------------------------------------------------ headline
    ("README", "landlords in release", "363", get("landlords/in_coverage_file"), 0),
    ("README", "landlords with LCRA survey", "353", get("tp01/landlords"), 0),
    ("README", "median TP01", "71.8%", get("tp01/median_tp01"), 1),
    ("README", "TP01 p25", "64.7", get("tp01/p25_tp01"), 1),
    ("README", "TP01 p75", "78.9%", get("tp01/p75_tp01"), 1),
    ("README", "PRP median TP01", "75.4%", get("tp01_by_peer_attribute/Landlord type|PRP/median_tp01"), 1),
    ("README", "LA median TP01", "68.5%", get("tp01_by_peer_attribute/Landlord type|LA/median_tp01"), 1),
    ("README", "North median TP01", "76.6%", get("tp01_by_peer_attribute/Region|North/median_tp01"), 1),
    ("README", "London median TP01", "61.2%", get("tp01_by_peer_attribute/Region|London/median_tp01"), 1),
    ("README", "North minus London", "15.4 points",
     get("tp01_by_peer_attribute/Region|North/median_tp01") - get("tp01_by_peer_attribute/Region|London/median_tp01"), 1),
    # ------------------------------------------------------ survey method
    ("README", "method gap landlords", "132 landlords", get("method_gap/landlords"), 0),
    ("README", "median phone-online gap", "14.9 points", get("method_gap/median_gap_pts"), 1),
    ("README", "gap p25", "10.0-19.7", get("method_gap/p25_gap_pts"), 1),
    ("README", "gap p75", "10.0-19.7", get("method_gap/p75_gap_pts"), 1),
    ("README", "phone higher count", "125 of 132", get("method_gap/telephone_higher"), 0),
    ("README", "phone higher pct", "94.7%", get("method_gap/telephone_higher_pct"), 1),
    ("README", "landlords with 100+ each way", "107", get("method_gap/landlords_100_plus_each"), 0),
    ("README", "gap with 100+ each way", "14.7 points", get("method_gap/median_gap_pts_100_plus_each"), 1),
    ("README", "phone+online landlords ranked", "286 landlords",
     get("peer_rank/Internet/landlords") + get("peer_rank/Telephone/landlords"), 0),
    ("README", "online median TP01", "67.9%", get("peer_rank/Internet/median_tp01"), 1),
    ("README", "phone median TP01", "71.7%", get("peer_rank/Telephone/median_tp01"), 1),
    ("README", "online landlords", "44 online-surveyed", get("peer_rank/Internet/landlords"), 0),
    ("README", "online in bottom quartile", "18 of the 44", get("peer_rank/Internet/bottom_quartile_national"), 0),
    ("README", "phone in bottom quartile", "55 of 242", get("peer_rank/Telephone/bottom_quartile_national"), 0),
    ("README", "online leaving bottom quartile", "7 of those 18", get("peer_rank/Internet/leave_bottom_quartile"), 0),
    # ------------------------------------------------------- correlations
    ("README", "TP04 rho", "(TP04, **0.95**)", get("tp01_correlation/TP04/spearman_rho"), 2),
    ("README", "TP06 rho", "(TP06, 0.92)", get("tp01_correlation/TP06/spearman_rho"), 2),
    ("README", "TP02 rho", "(TP02, 0.90)", get("tp01_correlation/TP02/spearman_rho"), 2),
    ("README", "TP12 rho", "(TP12, 0.67)", get("tp01_correlation/TP12/spearman_rho"), 2),
    ("README", "RP01 vs TP04 rho", "**-0.52**", get("management_vs_perception/RP01|TP04/spearman_rho"), 2),
    ("README", "CH02 vs TP09 rho", "**0.41**", get("management_vs_perception/CH02_1|TP09/spearman_rho"), 2),
    ("README", "RP02 vs TP02 rho", "**0.25**", get("management_vs_perception/RP02_1|TP02/spearman_rho"), 2),
    # ------------------------------------------------------ repair targets
    ("README", "min repair target", "from 5 to 260", get("repairs_target/min_target"), 0),
    ("README", "max repair target", "from 5 to 260", get("repairs_target/max_target"), 0),
    ("README", "median repair target", "(median 28, middle half", get("repairs_target/median_target"), 0),
    ("README", "repair target p25", "20-60", get("repairs_target/p25_target"), 0),
    ("README", "repair target p75", "20-60", get("repairs_target/p75_target"), 0),
    ("README", "landlords with targets", "282 of 356", get("repairs_target/landlords"), 0),
    ("README", "multiple targets", "282 of 356", get("repairs_target/multiple_targets"), 0),
    ("README", "multiple targets pct", "(79.2%)", get("repairs_target/multiple_targets_pct"), 1),
    ("README", "target vs RP02 landlords", "across 354\nlandlords", get("repairs_target_vs_rp02/landlords"), 0),
    ("README", "target vs RP02 rho", "**-0.10**", get("repairs_target_vs_rp02/spearman_rho"), 2),
    # ------------------------------------------------------- data quality
    ("README", "DQ checks", "19 run over", get("data_quality/checks/total"), 0),
    ("README", "DQ rows tested", "62,083 rows", get("data_quality/checks/rows_tested"), 0),
    ("README", "DQ passed", "14 passed", get("data_quality/checks/passed"), 0),
    ("README", "DQ warnings", "5 warnings", get("data_quality/checks/warned"), 0),
    ("README", "DQ blocking", "0 blocking", get("data_quality/checks/failed"), 0),
    ("README", "reconciled values", "All 10,005 published", get("data_quality/reconciled_values"), 0),
    ("README", "unexplained exclusions", "Three landlords are excluded", get("data_quality/unexplained_exclusion_landlords"), 0),
    ("README", "short surveys", "Eleven surveys fell short", get("data_quality/sample_shortfall/surveys"), 0),
    ("README", "min shortfall", "between 0.6 and", get("data_quality/sample_shortfall/min_responses_short"), 1),
    ("README", "max shortfall", "124.4 responses", get("data_quality/sample_shortfall/max_responses_short"), 1),
    ("README", "CP03 cells failed on first attempt", "CP03 failed on 25 cells",
     get("data_quality/u_cells_measure_not_applicable"), 0),
    # ------------------------------------------------------------- model
    ("README", "fact_tsm_result rows", "| 10,016 |", get("model/fact_tsm_result"), 0),
    ("README", "fact_survey rows", "| 414 |", get("model/fact_survey"), 0),
    ("README", "fact_survey_method rows", "| 2,484 |", get("model/fact_survey_method"), 0),
    ("README", "fact_repairs_target rows", "| 359 |", get("model/fact_repairs_target"), 0),
    ("README", "dim_landlord rows", "| 363 |", get("model/dim_landlord"), 0),
    ("README", "dim_measure rows", "| 26 |", get("model/dim_measure"), 0),
    ("README", "dim_date rows", "| 365 |", get("model/dim_date"), 0),
    # ------------------------------------------------------------ CV bullets
    ("README", "CV: result rows", "10,016\n  result rows", get("model/fact_tsm_result"), 0),
    ("README", "CV: landlords", "Measures for 363 landlords", get("landlords/in_coverage_file"), 0),
    ("README", "CV: checks", "Wrote 19 data quality checks", get("data_quality/checks/total"), 0),
    ("README", "CV: rows", "over 62,083 rows", get("data_quality/checks/rows_tested"), 0),
    ("README", "CV: reconciled", "reconciled all 10,005", get("data_quality/reconciled_values"), 0),
    ("README", "CV: unexplained", "found 3\n  landlords excluded", get("data_quality/unexplained_exclusion_landlords"), 0),
    ("README", "CV: gap", "a median 14.9 points higher", get("method_gap/median_gap_pts"), 1),
    ("README", "CV: gap landlords", "across 132 landlords", get("method_gap/landlords"), 0),
    ("README", "CV: leave bottom", "that 7 of 18", get("peer_rank/Internet/leave_bottom_quartile"), 0),
    ("README", "CV: bottom", "7 of 18", get("peer_rank/Internet/bottom_quartile_national"), 0),
    # ------------------------------------------------ DAX expected values
    ("DAX", "expected landlords", "| 353 |", get("tp01/landlords"), 0),
    ("DAX", "expected median TP01", "| 71.8 |", get("tp01/median_tp01"), 1),
    ("DAX", "expected LA median", "| 68.5 |", get("tp01_by_peer_attribute/Landlord type|LA/median_tp01"), 1),
    ("DAX", "expected London median", "| 61.2 |", get("tp01_by_peer_attribute/Region|London/median_tp01"), 1),
    ("DAX", "expected method gap", "| 14.9 |", get("method_gap/median_gap_pts"), 1),
    ("DAX", "expected fact rows", "| 10,016 |", get("model/fact_tsm_result"), 0),
    ("DAX", "expected completeness", "99.89% (10,005 / 10,016)",
     100 * (get("data_quality/by_check/CP02/rows_tested") - get("data_quality/by_check/CP02/rows_failed"))
     / get("data_quality/by_check/CP02/rows_tested"), 2),
    ("DAX", "expected checks passed", "| 14 / 19 |", get("data_quality/checks/passed"), 0),
]


WORDS = {"three": 3, "eleven": 11}


def documented_numbers(text: str) -> list[float]:
    """Numbers in a snippet. A hyphen is a minus sign only when it does not
    follow a digit, so the range "10.0-19.7" reads as 10.0 and 19.7."""
    import re
    numbers = [float(n.replace(",", ""))
               for n in re.findall(r"(?:(?<![\w.])-)?\d+(?:,\d{3})*(?:\.\d+)?", text)]
    numbers += [v for w, v in WORDS.items() if re.search(rf"\b{w}\b", text, re.IGNORECASE)]
    return numbers


def main() -> None:
    failures = []
    for doc, label, documented, actual, decimals in CLAIMS:
        if documented not in DOCS[doc]:
            failures.append(f"[{doc}] {label}: text {documented!r} not found")
            continue
        expected = round(float(actual), decimals)
        if not any(abs(n - expected) < 10 ** -(decimals + 3) for n in documented_numbers(documented)):
            failures.append(f"[{doc}] {label}: documented {documented!r}, pipeline gives {expected}")

    table = (ROOT / "outputs" / "data_quality" / "check_result.md").read_text(encoding="utf-8")
    if table.strip() not in DOCS["README"]:
        failures.append("[README] data quality table differs from outputs/data_quality/check_result.md")

    if failures:
        print("MISMATCHES:\n  " + "\n  ".join(failures))
        sys.exit(1)
    print(f"{len(CLAIMS)}/{len(CLAIMS)} documented figures verified; data quality table matches.")


if __name__ == "__main__":
    main()
