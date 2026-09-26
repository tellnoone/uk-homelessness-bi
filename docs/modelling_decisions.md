# Modelling decisions

Why the warehouse is shaped the way it is. Each decision names the
alternative that was rejected and why.

## Layers

| Layer | Schema | What it holds |
|---|---|---|
| Raw | `raw` | The eight published CSVs, loaded as text. Nothing is parsed or dropped. |
| Staging | `stg` | One table per business concept, reshaped from wide to long, with a parsed value **and** a status for every published cell. |
| Marts | `mart` | The star schema Power BI reads. |
| Analysis | `analysis` | Views behind every number in the README. |
| Data quality | `dq` | Check definitions, rows tested, rows failed, and the action taken. |

The SQL files in `sql/` run in file-name order. Plain SQL files were chosen
over dbt: the model has five layers and one source, so dbt would add a
dependency and a project structure without removing any work. The layering,
one-model-per-concept staging and tested marts follow dbt conventions, so the
project would move to dbt without redesign.

## Grain

**`fact_tsm_result`: one row per landlord x measure x tenure x reporting period.**
This is the grain RSH publishes at, so no information is lost and nothing is
double counted. The alternative, one wide row per landlord (as published), would
need a separate Power BI measure for each of the 26 TSMs and could not be
filtered by theme or tenure.

Three smaller facts sit beside it because they describe different events at
different grains:

| Fact | Grain | Why separate |
|---|---|---|
| `fact_survey` | landlord x tenure x period | Survey design (population, sample, margin of error, method). Describes the survey, not a result. |
| `fact_survey_method` | landlord x tenure x survey method x period | TP01 and response counts **by method**. The finding on survey method depends on it. |
| `fact_repairs_target` | landlord x period | Each landlord's own definition of "on time" for RP02. Context for one measure, not a result. |

## Dimensions and keys

Every dimension has an integer surrogate key (`*_key`) and keeps the natural
key (`landlord_code`, `measure_code`, ...) as an attribute. Facts hold only
surrogate keys. The natural keys are strings with mixed formats (`L4240`,
`00GL`, `4743`), and integer keys make Power BI relationships smaller and
faster.

- **`dim_landlord`** (363 rows) is built from RSH's coverage file, not from the
  measure tables, so landlords that appear in no measure table (the excluded
  ones) still exist and can be reported on. It carries the peer attributes a
  benchmarking club groups on (type, size band, region) and every coverage and
  exclusion flag. It is a type 1 dimension: with one year of data there is no
  history to keep. When the 2025/26 release arrives, landlords that merge or
  change size band will need type 2 handling (valid-from/valid-to dates), and
  the surrogate key makes that possible without touching the facts.
- **`dim_measure`** (26 rows) takes each measure's full name from RSH's data
  dictionary and adds what the dictionary lacks: a short display name, the TSM
  theme, the unit (`%` or `per 1,000 homes`) and the direction (is higher
  better?). Direction matters because RP01 (homes not decent) is
  lower-is-better, and complaint and ASB volumes have no good direction (more
  complaints can mean better recording).
- **`dim_date`** is at day grain across the 2024/25 financial year, with
  fiscal year and quarter columns. The facts join on the period end date
  (2025-03-31). With one annual release a day-grain date table is more than the
  data needs today; it is there so the 2025/26 release loads as new fact rows
  keyed to 2026-03-31, and Power BI time intelligence works without redesign.
- **`dim_tenure`**: LCRA (rented), LCHO (shared ownership), combined, and "all
  homes" for measures RSH does not split by tenure.
- **`dim_survey_method`** groups methods into interviewer-led (telephone, face
  to face) and self-completion (internet, postal, SMS), which is the split the
  survey-method finding turns on.
- **`dim_value_status`** says what each published cell contained.

## Status markers are data, not nulls

RSH publishes markers in place of numbers. Parsing them to NULL would throw
away why a value is missing, so every fact row carries a `status_key`:

| Marker | Meaning used here | Evidence |
|---|---|---|
| `[E]` | Excluded by RSH after review | RSH's comments column explains each one |
| `[U]` | Measure does not apply to this landlord | Every one of the 2,673 `[U]` cells is either a measure the landlord answered "No" to "do you own homes this applies to?" or a complaints measure for a tenure the landlord has no survey for. Check CP03 proves this on every run. |
| `[S]` | Suppressed | Only on small breakdowns by survey method |
| `[X]` | Not available for this breakdown | e.g. TP01 for a survey method the landlord did not use |
| `[Z]` | Not applicable | e.g. weighting details when no weighting was used |

RSH does not define the markers in these files, so the meanings of `[S]`,
`[X]` and `[Z]` are inferred from where they appear. My first reading of `[U]`
was "landlord has no homes of this tenure"; check CP03 failed on 25 cells,
which is how the broader meaning was found.

`[U]` cells are not loaded into `fact_tsm_result`: a row saying "this does not
apply" adds nothing that `dim_landlord` and the "Applies" answers do not
already say, and loading them would make completeness look far worse than it
is. `[E]` cells are loaded with an empty value, because an excluded result is a
real gap a report reader should see.

## Values, numerators and denominators

Management information measures keep their numerator and denominator as well
as RSH's calculated value. That allows two things the value alone cannot:

1. Reconciliation (checks RC01 and RC02): every published value can be
   recalculated.
2. Pooled sector figures in Power BI: `SUM(numerator) / SUM(denominator)` gives
   the share of all homes with a gas safety check, weighted by landlord size,
   which the median of landlord percentages does not.

## Why the analysis uses medians and rank correlations

Per-1,000 rates have extreme outliers (check RG03), and percentages bunch near
100 for building safety. Medians and Spearman rank correlations are not moved
by a few extreme landlords, and rank correlation does not assume a straight-line
relationship. Spearman's rho is computed in SQL (average ranks for ties, then
Pearson correlation of the ranks), and a test checks it against pandas.

## Scope of the analysis

The findings use LCRA (rented) results only. Every landlord in scope reports
them, while only 59 report LCHO (shared ownership) results, which are also
collected differently. The model holds all tenures, so the Power BI report can
show LCHO too.
