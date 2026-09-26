-- Layer 2: the star schema Power BI reads. Surrogate integer keys on every
-- dimension; facts hold only keys, measures and degenerate status columns.
-- Modelling decisions are written up in docs/modelling_decisions.md.

CREATE SCHEMA IF NOT EXISTS mart;

-- ---------------------------------------------------------------- dim_date
-- Day grain across the 2024/25 reporting year (1 April 2024 - 31 March 2025).
-- Facts join on the last day of the reporting period, so adding the 2025/26
-- release later means new fact rows keyed to 2026-03-31, with no schema change.
CREATE OR REPLACE TABLE mart.dim_date AS
SELECT
    CAST(strftime(d, '%Y%m%d') AS INTEGER)                      AS date_key,
    CAST(d AS DATE)                                             AS date,
    year(d)                                                     AS calendar_year,
    month(d)                                                    AS calendar_month,
    strftime(d, '%B')                                           AS month_name,
    -- UK social housing reports on the April-March financial year.
    CASE WHEN month(d) >= 4 THEN year(d) ELSE year(d) - 1 END   AS fiscal_year_start,
    CASE WHEN month(d) >= 4
         THEN year(d)::VARCHAR || '/' || right((year(d) + 1)::VARCHAR, 2)
         ELSE (year(d) - 1)::VARCHAR || '/' || right(year(d)::VARCHAR, 2)
    END                                                         AS fiscal_year,
    ((month(d) + 8) % 12) // 3 + 1                              AS fiscal_quarter,
    d = last_day(d) AND month(d) = 3                            AS is_fiscal_year_end
FROM range(DATE '2024-04-01', DATE '2025-04-01', INTERVAL 1 DAY) AS t(d);

-- ------------------------------------------------------------ dim_landlord
CREATE OR REPLACE TABLE mart.dim_landlord AS
WITH exclusion_note AS (
    SELECT landlord_code, string_agg(scope || ': ' || rsh_note, ' | ' ORDER BY scope) AS rsh_exclusion_note
    FROM stg.exclusion
    GROUP BY landlord_code
)
SELECT
    ROW_NUMBER() OVER (ORDER BY l.landlord_code)                AS landlord_key,
    l.landlord_code,
    l.landlord_name,
    l.landlord_type,
    CASE l.landlord_type WHEN 'LA'  THEN 'Local authority'
                         WHEN 'PRP' THEN 'Housing association (PRP)' END AS landlord_type_name,
    coalesce(l.group_size_band, 'Unknown')                      AS group_size_band,
    CASE l.group_size_band WHEN '<5,000' THEN 1 WHEN '5,000-40,000' THEN 2
                           WHEN '>40,000' THEN 3 ELSE 9 END     AS group_size_sort,
    coalesce(l.predominant_region, 'Unknown')                   AS predominant_region,
    l.above_30pct_supported_housing,
    l.publication_url,
    l.in_lcra_perception,
    l.in_lcho_perception,
    l.in_combined_perception,
    l.in_management_info,
    -- A landlord is excluded if RSH's coverage file says so, whether or not
    -- it appears on the published exclusion lists (see data quality check RI03).
    l.flagged_perception_excluded,
    l.flagged_management_excluded,
    e.rsh_exclusion_note
FROM stg.landlord AS l
LEFT JOIN exclusion_note AS e USING (landlord_code);

-- ------------------------------------------------------------- dim_measure
-- One row per TSM. Names come from RSH's data dictionary; category, unit and
-- direction ("is a higher value better?") are added here because the report
-- needs them and the dictionary does not carry them.
CREATE OR REPLACE TABLE mart.dim_measure AS
WITH codes AS (
    SELECT DISTINCT measure_code, 'Tenant perception survey' AS source FROM stg.perception_result
    UNION ALL
    SELECT DISTINCT measure_code, 'Landlord management information' FROM stg.management_result
),
names AS (
    -- The dictionary has one row per published column; take the LCRA or
    -- whole-landlord version of each measure's headline column.
    SELECT
        -- regexp_extract returns '' (not NULL) on no match, hence the NULLIFs.
        coalesce(NULLIF(regexp_extract(Data_Field_Name, '^(TP\d{2})_Satisfied_Calc_LCRA$', 1), ''),
                 NULLIF(regexp_extract(Data_Field_Name, '^(BS0\d|NM01_\d|RP01|RP02_\d)_Calculated_Value$', 1), ''),
                 NULLIF(regexp_extract(Data_Field_Name, '^(CH0\d_\d)_Calculated_Value_LCRA$', 1), '')) AS measure_code,
        regexp_replace(Column_Heading, '^LCRA - ', '')                                      AS measure_name
    FROM raw.data_dictionary
    WHERE regexp_matches(Data_Field_Name,
          '^(TP\d{2}_Satisfied_Calc_LCRA|(BS0\d|NM01_\d|RP01|RP02_\d)_Calculated_Value|CH0\d_\d_Calculated_Value_LCRA)$')
),
short_names AS (
    SELECT * FROM (VALUES
        ('TP01', 'Overall satisfaction'),          ('TP02', 'Repairs service'),
        ('TP03', 'Time taken for repair'),         ('TP04', 'Home well maintained'),
        ('TP05', 'Home is safe'),                  ('TP06', 'Listens and acts'),
        ('TP07', 'Keeps tenants informed'),        ('TP08', 'Fair and respectful'),
        ('TP09', 'Complaints handling'),           ('TP10', 'Communal areas'),
        ('TP11', 'Neighbourhood contribution'),    ('TP12', 'Anti-social behaviour handling'),
        ('BS01', 'Gas safety checks'),             ('BS02', 'Fire risk assessments'),
        ('BS03', 'Asbestos surveys'),              ('BS04', 'Legionella assessments'),
        ('BS05', 'Lift safety checks'),            ('RP01', 'Homes not decent'),
        ('RP02_1', 'Non-emergency repairs on time'), ('RP02_2', 'Emergency repairs on time'),
        ('CH01_1', 'Stage 1 complaints'),          ('CH01_2', 'Stage 2 complaints'),
        ('CH02_1', 'Stage 1 answered on time'),    ('CH02_2', 'Stage 2 answered on time'),
        ('NM01_1', 'ASB cases'),                   ('NM01_2', 'ASB cases involving hate incidents')
    ) AS t(measure_code, short_name)
)
SELECT
    ROW_NUMBER() OVER (ORDER BY c.measure_code)                 AS measure_key,
    c.measure_code,
    s.short_name,
    regexp_replace(n.measure_name, '\s*\([A-Z]{2}\d{2}( \d)?\)$', '') AS measure_name,
    c.source,
    CASE
        WHEN c.measure_code IN ('TP01')                          THEN 'Overall satisfaction'
        WHEN c.measure_code IN ('TP02', 'TP03', 'TP04', 'TP05')  THEN 'Keeping properties in good repair'
        WHEN c.measure_code IN ('TP06', 'TP07', 'TP08')          THEN 'Respectful and helpful engagement'
        WHEN c.measure_code IN ('TP09')                          THEN 'Effective handling of complaints'
        WHEN c.measure_code IN ('TP10', 'TP11', 'TP12')          THEN 'Responsible neighbourhood management'
        WHEN c.measure_code LIKE 'BS%'                           THEN 'Maintaining building safety'
        WHEN c.measure_code LIKE 'RP%'                           THEN 'Keeping properties in good repair'
        WHEN c.measure_code LIKE 'CH%'                           THEN 'Effective handling of complaints'
        WHEN c.measure_code LIKE 'NM%'                           THEN 'Responsible neighbourhood management'
    END                                                          AS theme,
    CASE WHEN c.measure_code LIKE 'CH01%' OR c.measure_code LIKE 'NM01%'
         THEN 'per 1,000 homes' ELSE '%' END                     AS unit,
    -- Complaints and ASB volumes are ambiguous (more can mean better recording),
    -- non-decent homes (RP01) is lower-is-better, the rest higher-is-better.
    CASE WHEN c.measure_code = 'RP01' THEN 'Lower is better'
         WHEN c.measure_code LIKE 'CH01%' OR c.measure_code LIKE 'NM01%' THEN 'No direction'
         ELSE 'Higher is better' END                             AS direction
FROM codes AS c
LEFT JOIN names AS n USING (measure_code)
LEFT JOIN short_names AS s USING (measure_code);

-- -------------------------------------------------------------- dim_tenure
CREATE OR REPLACE TABLE mart.dim_tenure AS
SELECT * FROM (VALUES
    (1, 'LCRA', 'Low cost rental (tenants)'),
    (2, 'LCHO', 'Low cost home ownership (shared owners)'),
    (3, 'COMB', 'Combined rental and ownership'),
    (4, 'ALL',  'All homes (not split by tenure)')
) AS t(tenure_key, tenure_code, tenure_name);

-- ------------------------------------------------------- dim_survey_method
CREATE OR REPLACE TABLE mart.dim_survey_method AS
SELECT * FROM (VALUES
    (1, 'Telephone',  'Telephone',    'Interviewer-led'),
    (2, 'FacetoFace', 'Face to face', 'Interviewer-led'),
    (3, 'Internet',   'Internet',     'Self-completion'),
    (4, 'Postal',     'Postal',       'Self-completion'),
    (5, 'SMS',        'SMS',          'Self-completion'),
    (6, 'Other',      'Other',        'Other')
) AS t(method_key, method_code, method_name, method_mode);

-- ------------------------------------------------------- dim_value_status
-- Every fact row carries the status of the published cell. RSH does not
-- define the markers in these files; meanings below are inferred from where
-- each one appears and are documented as such (docs/modelling_decisions.md).
CREATE OR REPLACE TABLE mart.dim_value_status AS
SELECT * FROM (VALUES
    (1, 'REPORTED', 'Value published',                                         true),
    (2, '[E]',      'Excluded by RSH after review (see RSH comments)',         false),
    (3, '[S]',      'Suppressed (small number of responses)',                  false),
    (4, '[X]',      'Not available for this breakdown',                        false),
    (5, '[Z]',      'Not applicable',                                          false),
    (6, '[U]',      'Measure does not apply to this landlord',                 false),
    (7, 'BLANK',    'Cell left empty in the published file',                   false),
    (8, 'UNPARSEABLE', 'Text that is neither a number nor a known marker',     false)
) AS t(status_key, status_code, status_description, is_usable);

-- --------------------------------------------------------- fact_tsm_result
-- Grain: landlord x measure x tenure x reporting period. One row per
-- published headline cell, including cells that carry a marker instead of a
-- number, so completeness can be reported from the model itself.
-- [U] cells are not loaded: they only say the measure does not apply to the
-- landlord (no homes of that tenure, or none the measure covers, e.g. no lifts
-- for BS05). Data quality check CP03 proves that is all they mean.
CREATE OR REPLACE TABLE mart.fact_tsm_result AS
WITH results AS (
    SELECT landlord_code, measure_code, tenure_code, status_code, value, numerator, denominator
    FROM stg.perception_result
    UNION ALL
    SELECT landlord_code, measure_code, tenure_code, status_code, value, numerator, denominator
    FROM stg.management_result
)
SELECT
    l.landlord_key,
    m.measure_key,
    t.tenure_key,
    20250331                                                    AS date_key,
    s.status_key,
    r.value,
    r.numerator,
    r.denominator
FROM results AS r
JOIN mart.dim_landlord     AS l USING (landlord_code)
JOIN mart.dim_measure      AS m USING (measure_code)
JOIN mart.dim_tenure       AS t USING (tenure_code)
JOIN mart.dim_value_status AS s USING (status_code)
WHERE r.status_code <> '[U]';

-- ------------------------------------------------------- fact_survey_method
-- Grain: landlord x tenure x survey method x period. How many responses each
-- method collected, and overall satisfaction (TP01) among them.
CREATE OR REPLACE TABLE mart.fact_survey_method AS
SELECT
    l.landlord_key,
    t.tenure_key,
    sm.method_key,
    20250331                                                    AS date_key,
    s.status_key                                                AS tp01_status_key,
    x.responses,
    x.tp01_pct_satisfied
FROM stg.survey_method AS x
JOIN mart.dim_landlord      AS l  USING (landlord_code)
JOIN mart.dim_tenure        AS t  USING (tenure_code)
JOIN mart.dim_survey_method AS sm USING (method_code)
JOIN mart.dim_value_status  AS s  ON s.status_code = x.tp01_status_code;

-- -------------------------------------------------------------- fact_survey
-- Grain: landlord x tenure x period. How each perception survey was run.
CREATE OR REPLACE TABLE mart.fact_survey AS
SELECT
    l.landlord_key,
    t.tenure_key,
    20250331                                                    AS date_key,
    sm.method_key                                               AS predominant_method_key,
    s.predominant_method,
    s.census_or_sample,
    s.external_contractor,
    s.weighted,
    s.tenant_population,
    s.minimum_sample,
    s.responses,
    s.margin_of_error_pts,
    s.tenants_excluded,
    s.responses / s.tenant_population                           AS response_rate
FROM stg.survey AS s
JOIN mart.dim_landlord AS l USING (landlord_code)
JOIN mart.dim_tenure   AS t USING (tenure_code)
LEFT JOIN mart.dim_survey_method AS sm
       ON sm.method_name = s.predominant_method
       OR (sm.method_code = 'FacetoFace' AND s.predominant_method = 'Face to Face');

-- ------------------------------------------------------ fact_repairs_target
-- Grain: landlord x period. How each landlord defines "on time" for RP02.
CREATE OR REPLACE TABLE mart.fact_repairs_target AS
SELECT
    l.landlord_key,
    20250331 AS date_key,
    r.max_target_non_emergency,
    r.multiple_targets_non_emergency,
    r.max_target_emergency,
    r.multiple_targets_emergency,
    r.repairs_completed
FROM stg.repairs_target AS r
JOIN mart.dim_landlord AS l USING (landlord_code);
