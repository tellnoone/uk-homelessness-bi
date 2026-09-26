# DAX measures

Create these in a dedicated `_Measures` table. They are written against the
model in [MODEL.md](MODEL.md).

> **Status: not yet run in Power BI.** These measures were written against the
> exported model but Power BI Desktop was not available where the model was
> built. The "Expected" column gives the value each should return, taken from
> the SQL analysis (`outputs/results.json`). Build a card for each with the
> stated filters and compare. If one disagrees, the SQL is the reference.

## Conventions

- Satisfaction and management results are **per-landlord values**. Across
  landlords the default summary is the **median**. A mean is pulled around by
  outliers (data quality check RG03), and a sum of percentages means nothing.
- Measures return BLANK when the filter context makes the answer ambiguous,
  e.g. two measures selected at once, instead of returning a wrong number.

## Core

```dax
Landlords =
DISTINCTCOUNT ( fact_tsm_result[landlord_key] )
```

```dax
Landlords with a result =
CALCULATE (
    DISTINCTCOUNT ( fact_tsm_result[landlord_key] ),
    NOT ISBLANK ( fact_tsm_result[value] )
)
```

```dax
-- The headline measure. For one landlord it is that landlord's value; for
-- many it is the median across them. Blank unless exactly one TSM is selected.
Median result =
IF (
    HASONEVALUE ( dim_measure[measure_code] ),
    MEDIAN ( fact_tsm_result[value] )
)
```

```dax
-- Sector-wide figure weighted by homes: all numerators over all denominators.
-- Only management information measures have a numerator and denominator.
Pooled result =
VAR _unit  = SELECTEDVALUE ( dim_measure[unit] )
VAR _ratio = DIVIDE ( SUM ( fact_tsm_result[numerator] ), SUM ( fact_tsm_result[denominator] ) )
RETURN
    SWITCH ( _unit, "%", _ratio * 100, "per 1,000 homes", _ratio * 1000 )
```

## Benchmarking one landlord

Put a single-select slicer on `dim_landlord[landlord_name]`.

```dax
-- Median of landlords of the same type (LA / PRP) in the same region.
Peer median (type and region) =
VAR _type   = SELECTEDVALUE ( dim_landlord[landlord_type] )
VAR _region = SELECTEDVALUE ( dim_landlord[predominant_region] )
RETURN
    IF (
        HASONEVALUE ( dim_landlord[landlord_key] )
            && HASONEVALUE ( dim_measure[measure_code] ),
        CALCULATE (
            MEDIAN ( fact_tsm_result[value] ),
            REMOVEFILTERS ( dim_landlord ),
            dim_landlord[landlord_type] = _type,
            dim_landlord[predominant_region] = _region
        )
    )
```

```dax
-- Median of landlords whose rented-tenant survey mainly used the same method
-- (telephone, internet, ...). The fair comparison for perception measures:
-- see the README's first finding.
Peer median (same survey method) =
VAR _method =
    CALCULATE (
        SELECTEDVALUE ( fact_survey[predominant_method] ),
        dim_tenure[tenure_code] = "LCRA"
    )
VAR _peers =
    CALCULATETABLE (
        VALUES ( fact_survey[landlord_key] ),
        REMOVEFILTERS ( dim_landlord ),
        fact_survey[predominant_method] = _method,
        dim_tenure[tenure_code] = "LCRA"
    )
RETURN
    IF (
        HASONEVALUE ( dim_landlord[landlord_key] )
            && HASONEVALUE ( dim_measure[measure_code] )
            && NOT ISBLANK ( _method ),
        CALCULATE (
            MEDIAN ( fact_tsm_result[value] ),
            REMOVEFILTERS ( dim_landlord ),
            TREATAS ( _peers, dim_landlord[landlord_key] )
        )
    )
```

```dax
Gap to peer median (same survey method) =
[Median result] - [Peer median (same survey method)]
```

```dax
-- 1 = best. Respects the measure's direction (RP01 is lower-is-better) and
-- skips landlords with no value, so they do not all tie for last or first.
Rank among landlords =
VAR _direction = SELECTEDVALUE ( dim_measure[direction] )
VAR _field =
    FILTER ( ALL ( dim_landlord ), NOT ISBLANK ( [Median result] ) )
RETURN
    IF (
        HASONEVALUE ( dim_landlord[landlord_key] )
            && HASONEVALUE ( dim_measure[measure_code] )
            && NOT ISBLANK ( [Median result] )
            && _direction <> "No direction",
        IF (
            _direction = "Lower is better",
            RANKX ( _field, [Median result], , ASC, SKIP ),
            RANKX ( _field, [Median result], , DESC, SKIP )
        )
    )
```

## Survey method

```dax
-- Overall satisfaction among one survey method's respondents.
TP01 by method =
AVERAGE ( fact_survey_method[tp01_pct_satisfied] )
```

```dax
-- For landlords that surveyed both ways: telephone TP01 minus internet TP01,
-- median across those landlords.
Telephone minus internet (median) =
VAR _pairs =
    ADDCOLUMNS (
        VALUES ( dim_landlord[landlord_key] ),
        "@tel", CALCULATE ( [TP01 by method], dim_survey_method[method_code] = "Telephone" ),
        "@web", CALCULATE ( [TP01 by method], dim_survey_method[method_code] = "Internet" )
    )
RETURN
    MEDIANX (
        FILTER ( _pairs, NOT ISBLANK ( [@tel] ) && NOT ISBLANK ( [@web] ) ),
        [@tel] - [@web]
    )
```

## Data quality

```dax
Results in model =
COUNTROWS ( fact_tsm_result )
```

```dax
Results with a usable value =
CALCULATE ( COUNTROWS ( fact_tsm_result ), dim_value_status[is_usable] = TRUE () )
```

```dax
Completeness % =
DIVIDE ( [Results with a usable value], [Results in model] )
```

```dax
DQ checks passed =
CALCULATE ( COUNTROWS ( data_quality_check_result ), data_quality_check_result[status] = "PASS" )
```

```dax
DQ checks =
COUNTROWS ( data_quality_check_result )
```

## Expected values

Filters: `dim_tenure[tenure_code] = "LCRA"` unless stated otherwise.

| Measure | Extra filters | Expected | Source in `outputs/results.json` |
|---|---|---:|---|
| `[Landlords with a result]` | `measure_code = "TP01"` | 353 | `tp01.landlords` |
| `[Median result]` | `measure_code = "TP01"` | 71.8 | `tp01.median_tp01` |
| `[Median result]` | `measure_code = "TP01"`, `landlord_type = "LA"` | 68.5 | `tp01_by_peer_attribute["Landlord type\|LA"]` |
| `[Median result]` | `measure_code = "TP01"`, `predominant_region = "London"` | 61.2 | `tp01_by_peer_attribute["Region\|London"]` |
| `[Telephone minus internet (median)]` | none beyond LCRA | 14.9 | `method_gap.median_gap_pts` |
| `[Results in model]` | **no tenure filter** | 10,016 | `model.fact_tsm_result` |
| `[Completeness %]` | **no tenure filter** | 99.89% (10,005 / 10,016) | `data_quality.by_check.CP02` |
| `[DQ checks passed]` / `[DQ checks]` | none | 14 / 19 | `data_quality.checks` |

Medians in Power BI and DuckDB both interpolate between the middle two values
when the count is even, so they should agree to the displayed decimal place.
