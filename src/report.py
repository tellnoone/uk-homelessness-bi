"""Collect every figure the README quotes into outputs/results.json, and draw
the README charts. Numbers come from the SQL analysis views; nothing is
recalculated here."""

import json
from pathlib import Path

import duckdb
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
RESULTS_PATH = ROOT / "outputs" / "results.json"
FIG_DIR = ROOT / "outputs" / "figures"

# Reference palette (light mode), validated as a pair: slot 1 blue, slot 2
# orange. Text and axes use neutral ink, never a series colour.
SURFACE = "#fcfcfb"
INK = "#0b0b0b"
INK_2 = "#52514e"
GRID = "#e4e3df"
BLUE = "#2a78d6"
ORANGE = "#eb6834"


def _rows(con: duckdb.DuckDBPyConnection, query: str) -> list[dict]:
    cur = con.execute(query)
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def _one(con: duckdb.DuckDBPyConnection, query: str) -> dict:
    rows = _rows(con, query)
    assert len(rows) == 1, query
    return rows[0]


def collect_results(con: duckdb.DuckDBPyConnection) -> dict:
    results = {
        "landlords": _one(con, """
            SELECT count(*) AS in_coverage_file,
                   count(*) FILTER (WHERE in_lcra_perception) AS with_lcra_survey,
                   count(*) FILTER (WHERE in_management_info) AS with_management_info
            FROM mart.dim_landlord"""),
        "tp01": _one(con, "SELECT * FROM analysis.tp01_summary"),
        "tp01_by_peer_attribute": {
            f"{r['attribute']}|{r['peer_group']}": {"landlords": r["landlords"], "median_tp01": r["median_tp01"]}
            for r in _rows(con, "SELECT * FROM analysis.tp01_by_peer_attribute")
        },
        "method_gap": _one(con, "SELECT * FROM analysis.method_gap_summary"),
        "peer_rank": {
            r["predominant_method"]: r
            for r in _rows(con, "SELECT * FROM analysis.peer_rank_summary")
        },
        "tp01_correlation": {
            r["measure_code"]: {"landlords": r["landlords"], "spearman_rho": r["spearman_rho"]}
            for r in _rows(con, "SELECT * FROM analysis.tp01_driver_correlation")
        },
        "management_vs_perception": {
            f"{r['mi_code']}|{r['perception_code']}": {"landlords": r["landlords"], "spearman_rho": r["spearman_rho"]}
            for r in _rows(con, "SELECT * FROM analysis.management_vs_perception")
        },
        "repairs_target": _one(con, "SELECT * FROM analysis.repairs_target_summary"),
        "repairs_target_vs_rp02": _one(con, "SELECT * FROM analysis.repairs_target_vs_rp02"),
        "model": {
            t: con.execute(f"SELECT count(*) FROM mart.{t}").fetchone()[0]
            for t in ("dim_landlord", "dim_measure", "dim_date", "fact_tsm_result",
                      "fact_survey", "fact_survey_method", "fact_repairs_target")
        },
        "data_quality": {
            "checks": _one(con, """
                SELECT count(*) AS total,
                       count(*) FILTER (WHERE status = 'PASS') AS passed,
                       count(*) FILTER (WHERE status = 'WARN') AS warned,
                       count(*) FILTER (WHERE status = 'FAIL') AS failed,
                       sum(rows_tested) AS rows_tested
                FROM dq.check_result"""),
            "by_check": {
                r["check_id"]: {"rows_tested": r["rows_tested"], "rows_failed": r["rows_failed"], "status": r["status"]}
                for r in _rows(con, "SELECT * FROM dq.check_result")
            },
            "sample_shortfall": _one(con, """
                SELECT count(*) AS surveys,
                       round(min(minimum_sample - responses), 1) AS min_responses_short,
                       round(max(minimum_sample - responses), 1) AS max_responses_short
                FROM stg.survey WHERE responses < minimum_sample"""),
            # [U] cells on whole-landlord measures: the cells that failed CP03
            # under the first (wrong) reading of [U] as "no homes of this tenure".
            "u_cells_measure_not_applicable": con.execute(
                "SELECT count(*) FROM stg.management_result WHERE status_code = '[U]' AND tenure_code = 'ALL'"
            ).fetchone()[0],
            "reconciled_values": con.execute(
                "SELECT sum(rows_tested) FROM dq.check_result WHERE check_id IN ('RC01', 'RC02')"
            ).fetchone()[0],
            "unexplained_exclusion_landlords": con.execute(
                "SELECT count(DISTINCT landlord_code) FROM dq.check_failure WHERE check_id = 'RI03'"
            ).fetchone()[0],
        },
    }
    return results


def write_results(results: dict) -> None:
    RESULTS_PATH.parent.mkdir(parents=True, exist_ok=True)
    RESULTS_PATH.write_text(json.dumps(results, indent=2, sort_keys=True, default=float) + "\n",
                            encoding="utf-8")


def _style(ax) -> None:
    ax.set_facecolor(SURFACE)
    for side in ("top", "right", "left"):
        ax.spines[side].set_visible(False)
    ax.spines["bottom"].set_color(INK_2)
    ax.tick_params(colors=INK_2, labelsize=9, length=0)
    ax.grid(axis="x", color=GRID, linewidth=0.8)
    ax.set_axisbelow(True)


def _figure(width: float, height: float):
    fig, ax = plt.subplots(figsize=(width, height), dpi=150)
    fig.patch.set_facecolor(SURFACE)
    _style(ax)
    return fig, ax


def plot_method_gap(con: duckdb.DuckDBPyConnection) -> None:
    rows = _rows(con, """
        SELECT tp01_telephone, tp01_internet FROM analysis.method_gap_by_landlord
        ORDER BY telephone_minus_internet, tp01_telephone""")
    summary = _one(con, "SELECT * FROM analysis.method_gap_summary")
    fig, ax = _figure(8, 6.2)
    for i, r in enumerate(rows):
        ax.plot([r["tp01_internet"], r["tp01_telephone"]], [i, i], color=GRID, linewidth=1.2, zorder=1)
    ax.scatter([r["tp01_internet"] for r in rows], range(len(rows)), s=14, color=ORANGE,
               edgecolor=SURFACE, linewidth=0.6, zorder=2, label="Surveyed online")
    ax.scatter([r["tp01_telephone"] for r in rows], range(len(rows)), s=14, color=BLUE,
               edgecolor=SURFACE, linewidth=0.6, zorder=3, label="Surveyed by telephone")
    ax.set_yticks([])
    ax.set_ylim(-2, len(rows) + 1)
    ax.set_xlim(20, 100)
    ax.set_xlabel("Tenants satisfied with the landlord's service overall (TP01, %)", color=INK_2, fontsize=9)
    fig.suptitle(
        f"The same landlord scores {summary['median_gap_pts']:.1f} points higher by phone than online",
        x=0.02, y=0.985, ha="left", color=INK, fontsize=12)
    fig.text(0.02, 0.935,
             f"Median gap. Phone was higher at {summary['telephone_higher']} of the {summary['landlords']} landlords "
             "that surveyed tenants both ways (one row each), 2024/25.",
             ha="left", color=INK_2, fontsize=8.5)
    legend = ax.legend(loc="lower left", bbox_to_anchor=(0, 1.0), ncol=2, frameon=False, fontsize=9,
                       borderaxespad=0.2)
    for text in legend.get_texts():
        text.set_color(INK)
    fig.tight_layout(rect=(0, 0, 1, 0.925))
    fig.savefig(FIG_DIR / "01_method_gap.png", facecolor=SURFACE)
    plt.close(fig)


def plot_drivers(con: duckdb.DuckDBPyConnection) -> None:
    rows = _rows(con, """
        SELECT c.measure_code, m.short_name, c.spearman_rho
        FROM analysis.tp01_driver_correlation c
        JOIN mart.dim_measure m USING (measure_code)
        ORDER BY c.spearman_rho""")
    mi = _rows(con, """
        SELECT v.pair_label, v.spearman_rho FROM analysis.management_vs_perception v
        WHERE (mi_code, perception_code) IN (('RP02_1', 'TP02'), ('RP01', 'TP04'), ('CH02_1', 'TP09'))
        ORDER BY v.spearman_rho""")
    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(11.5, 4.6), dpi=150,
                                   gridspec_kw={"width_ratios": [1.15, 1]})
    fig.patch.set_facecolor(SURFACE)
    for ax in (ax1, ax2):
        _style(ax)
        ax.set_xlim(-1, 1)
        ax.set_xticks([-1, -0.5, 0, 0.5, 1])
        ax.axvline(0, color=INK_2, linewidth=0.8)
    labels = [f"{r['short_name']} ({r['measure_code']})" for r in rows]
    ax1.barh(labels, [r["spearman_rho"] for r in rows], color=BLUE, height=0.6)
    for i, r in enumerate(rows):
        ax1.text(r["spearman_rho"] + 0.02, i, f"{r['spearman_rho']:.2f}", va="center", fontsize=8, color=INK)
    ax1.set_title("Tenant survey measures vs overall satisfaction", loc="left", fontsize=10, color=INK)
    ax1.set_xlabel("Spearman rank correlation with TP01, across landlords", fontsize=8.5, color=INK_2)
    short = {"Non-emergency repairs on time vs repairs satisfaction": "Repairs on time (RP02)\nvs repairs satisfaction",
             "Homes not decent vs home well maintained": "Homes not decent (RP01)\nvs home well maintained",
             "Stage 1 complaints answered on time vs complaints satisfaction":
                 "Complaints answered on time (CH02)\nvs complaints satisfaction"}
    ax2.barh([short[r["pair_label"]] for r in mi], [r["spearman_rho"] for r in mi], color=BLUE, height=0.5)
    for i, r in enumerate(mi):
        x = r["spearman_rho"]
        ax2.text(x + (0.02 if x >= 0 else -0.02), i, f"{x:.2f}", va="center",
                 ha="left" if x >= 0 else "right", fontsize=8, color=INK)
    ax2.set_title("Landlord-reported KPIs vs tenant view", loc="right", fontsize=10, color=INK)
    ax2.set_xlabel("Spearman rank correlation, across landlords", fontsize=8.5, color=INK_2)
    fig.tight_layout()
    fig.savefig(FIG_DIR / "02_what_moves_with_satisfaction.png", facecolor=SURFACE)
    plt.close(fig)


def plot_repairs_targets(con: duckdb.DuckDBPyConnection) -> None:
    targets = [r[0] for r in con.execute(
        "SELECT max_target_non_emergency FROM mart.fact_repairs_target "
        "WHERE max_target_non_emergency IS NOT NULL ORDER BY 1").fetchall()]
    summary = _one(con, "SELECT * FROM analysis.repairs_target_summary")
    fig, ax = _figure(8, 3.4)
    ax.grid(axis="x", visible=False)
    ax.grid(axis="y", color=GRID, linewidth=0.8)
    bins = list(range(0, 275, 10))
    ax.hist(targets, bins=bins, color=BLUE, edgecolor=SURFACE, linewidth=2)
    ax.set_xlabel("Maximum target for a non-emergency repair, as each landlord reported it (RSH does not state the unit)",
                  fontsize=8.5, color=INK_2)
    ax.set_ylabel("Landlords", fontsize=8.5, color=INK_2)
    ax.set_title(
        f"Each landlord sets its own \"on time\": targets run from {summary['min_target']:.0f} to "
        f"{summary['max_target']:.0f} (median {summary['median_target']:.0f})",
        loc="left", fontsize=10.5, color=INK)
    fig.tight_layout()
    fig.savefig(FIG_DIR / "03_repairs_targets.png", facecolor=SURFACE)
    plt.close(fig)


def build_figures(con: duckdb.DuckDBPyConnection) -> None:
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    plt.rcParams.update({"font.family": "DejaVu Sans", "svg.hashsalt": "tsm", "path.simplify": True})
    plot_method_gap(con)
    plot_drivers(con)
    plot_repairs_targets(con)
