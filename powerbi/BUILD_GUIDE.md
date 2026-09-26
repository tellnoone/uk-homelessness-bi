# Building the Power BI report

About an hour in Power BI Desktop (Windows). Everything it needs is already
in `outputs/`; you do not need Python unless you want to regenerate the data.

## 1. Load the data

1. **Get data → Text/CSV**, and load each file in `outputs/powerbi/` (ten
   files). Use **Transform data** to check the types listed under "Settings"
   in [MODEL.md](MODEL.md), then **Close & Apply**.
2. **Get data → Text/CSV** → `outputs/data_quality/check_result.csv`, and
   rename the query `data_quality_check_result`.

## 2. Model

1. In **Model view**, delete any relationships Power BI auto-detected, then
   create the ones in the table in [MODEL.md](MODEL.md). Note that
   `fact_survey[predominant_method_key]` is **inactive**.
2. Mark `dim_date` as a date table, set the sort-by columns, set `value` to
   "Don't summarize", and hide the key columns.
3. Create a `_Measures` table (**Enter data**, one dummy column, then delete
   the column once a measure exists) and add every measure from
   [DAX_MEASURES.md](DAX_MEASURES.md).
4. **Check the wiring:** build a card for each row of the "Expected values"
   table in DAX_MEASURES.md. All eight should match before you build pages.

## 3. Pages

Add a page-level filter `dim_tenure[tenure_code] = "LCRA"` on pages 1-4.

| Page | Question it answers | Visuals |
|---|---|---|
| **1. Sector overview** | Where does overall satisfaction sit, and how does it vary? | Card: `[Median result]` (TP01). Column chart: `[Median result]` by `predominant_region`. Column chart by `landlord_type_name`. Slicer: `dim_measure[short_name]` (single select, default "Overall satisfaction"). |
| **2. Landlord scorecard** | How does one landlord compare with fair peers? | Slicer: `landlord_name` (single select). Table: `dim_measure[short_name]`, `[Median result]`, `[Peer median (same survey method)]`, `[Gap to peer median (same survey method)]`, `[Rank among landlords]`. Conditional formatting on the gap column. Card: the landlord's `fact_survey[predominant_method]` and `margin_of_error_pts`. |
| **3. Survey method** | How much does the way a landlord surveys change its score? | Scatter: x = `TP01 by method` for Internet, y = for Telephone, one point per landlord (use two measures with `CALCULATE` filters), with a y = x reference line. Card: `[Telephone minus internet (median)]`. |
| **4. Repairs and complaints** | Do landlord-reported KPIs match what tenants say? | Scatter: RP02_1 `[Median result]` against TP02 per landlord. Histogram (binned column chart) of `fact_repairs_target[max_target_non_emergency]`. Table of landlords with their target beside their RP02 result. |
| **5. Data quality** | Can the numbers be trusted, and what was done about the gaps? | Table: `data_quality_check_result` (all columns). Cards: `[DQ checks passed]` / `[DQ checks]`, `[Completeness %]`. Table: `dim_landlord` filtered to `flagged_perception_excluded = True`, with `rsh_exclusion_note`. |

Keep to the charting rules the README figures use: one colour per series, no
dual axes, direct labels on bars, values in neutral ink.

## 4. Publish into the repository

1. Save as `powerbi/tsm_benchmark.pbix`.
2. For each page, **File → Export → Export to PDF**, or take a screenshot at
   1600 px wide. Save PNGs as `docs/powerbi/01_sector_overview.png` ...
   `05_data_quality.png`.
3. Add a "Power BI report" section to the README with the five screenshots.
4. Remove the "not yet run in Power BI" note from DAX_MEASURES.md once every
   expected value matches.
