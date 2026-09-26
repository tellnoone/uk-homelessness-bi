-- Layer 1: staging. One model per business concept, with clean names and
-- types, reshaped from the published wide layout (one column per measure) to
-- long (one row per landlord x measure). Status markers are kept alongside
-- the parsed value rather than thrown away, so the data quality layer and the
-- report can both see exactly what was published.

CREATE SCHEMA IF NOT EXISTS stg;

-- Landlord attributes appear on every published table. Take them from the
-- first table each landlord appears in, in a fixed order, so a landlord that
-- is only in the LCHO or combined table still gets its attributes. (The data
-- quality layer checks that the tables agree wherever a landlord is in more
-- than one.)
CREATE OR REPLACE TABLE stg.landlord AS
WITH attributes AS (
    SELECT ProviderNumber, ProviderName, ProviderType, "Group size", "Predominant region",
           Above_30_SH, Publication_URL, 1 AS source_order
    FROM raw.management_info
    UNION ALL
    SELECT ProviderNumber, ProviderName, ProviderType, "Group size", "Predominant region",
           Above_30_SH, Publication_URL, 2
    FROM raw.lcra_perception
    UNION ALL
    SELECT ProviderNumber, ProviderName, ProviderType, "Group size", "Predominant region",
           Above_30_SH, Publication_URL, 3
    FROM raw.comb_perception
    UNION ALL
    SELECT ProviderNumber, ProviderName, ProviderType, "Group size", "Predominant region",
           NULL, Publication_URL, 4
    FROM raw.lcho_perception
),
first_seen AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY ProviderNumber ORDER BY source_order) AS rn
    FROM attributes
)
SELECT
    trim(c.Landlord_code)                         AS landlord_code,
    trim(c.Landlord_name)                         AS landlord_name,
    trim(c.Landlord_type)                         AS landlord_type,
    a."Group size"                                AS group_size_band,
    a."Predominant region"                        AS predominant_region,
    a.Above_30_SH = 'Yes'                         AS above_30pct_supported_housing,
    NULLIF(trim(a.Publication_URL), '[X]')        AS publication_url,
    c.TSM25_LCRA_Perception = 'Yes'               AS in_lcra_perception,
    c.TSM25_LCHO_Perception = 'Yes'               AS in_lcho_perception,
    c.TSM25_Combined_Perception = 'Yes'           AS in_combined_perception,
    c."TSM25_Management _Info" = 'Yes'            AS in_management_info,
    c.TSM25_Perception_Not_Inc = 'Yes'            AS flagged_perception_excluded,
    c.TSM25_Man_Info_Not_Inc = 'Yes'              AS flagged_management_excluded
FROM raw.table_coverage AS c
LEFT JOIN first_seen AS a
       ON a.ProviderNumber = trim(c.Landlord_code) AND a.rn = 1;

-- RSH's published exclusion lists (files 05 and 06).
CREATE OR REPLACE TABLE stg.exclusion AS
SELECT trim("Landlord code") AS landlord_code, trim("Landlord name") AS landlord_name,
       'Perception' AS scope, "Notes from RSH following TSM review" AS rsh_note
FROM raw.perception_not_included
UNION ALL
SELECT trim("Landlord code"), trim("Landlord name"),
       'Management information', "Notes from RSH following TSM review"
FROM raw.management_not_included;

-- Perception measures (TP01-TP12): the headline "% satisfied" per landlord and
-- tenure. INCLUDE NULLS keeps blank cells so completeness can be measured.
CREATE OR REPLACE TABLE stg.perception_result AS
WITH lcra AS (
    SELECT * FROM (SELECT ProviderNumber, COLUMNS('^TP\d{2}_Satisfied_Calc_LCRA$') FROM raw.lcra_perception)
    UNPIVOT INCLUDE NULLS (raw_value FOR source_column IN (COLUMNS(* EXCLUDE (ProviderNumber))))
),
lcho AS (
    SELECT * FROM (SELECT ProviderNumber, COLUMNS('^TP\d{2}_Satisfied_Calc_LCHO$') FROM raw.lcho_perception)
    UNPIVOT INCLUDE NULLS (raw_value FOR source_column IN (COLUMNS(* EXCLUDE (ProviderNumber))))
),
comb AS (
    SELECT * FROM (SELECT ProviderNumber, COLUMNS('^TP\d{2}_Satisfied_Calc_COMB$') FROM raw.comb_perception)
    UNPIVOT INCLUDE NULLS (raw_value FOR source_column IN (COLUMNS(* EXCLUDE (ProviderNumber))))
),
unioned AS (
    SELECT * FROM lcra UNION ALL SELECT * FROM lcho UNION ALL SELECT * FROM comb
)
SELECT
    trim(ProviderNumber)                                    AS landlord_code,
    regexp_extract(source_column, '^(TP\d{2})', 1)          AS measure_code,
    regexp_extract(source_column, '_(LCRA|LCHO|COMB)$', 1)  AS tenure_code,
    source_column,
    raw_value,
    value_status(raw_value)                                 AS status_code,
    parse_num(raw_value)                                    AS value,
    CAST(NULL AS DOUBLE)                                    AS numerator,
    CAST(NULL AS DOUBLE)                                    AS denominator
FROM unioned;

-- Response counts behind each perception measure: very satisfied (VS), fairly
-- satisfied (FS), neither (NSD), fairly/very dissatisfied (FD/VD), not
-- applicable / don't know (NADK). Used to reconcile the published percentages.
CREATE OR REPLACE TABLE stg.perception_response_count AS
WITH lcra AS (
    SELECT * FROM (SELECT ProviderNumber, COLUMNS('^TP\d{2}_(VS|FS|NSD|FD|VD|NADK)_LCRA$') FROM raw.lcra_perception)
    UNPIVOT INCLUDE NULLS (raw_value FOR source_column IN (COLUMNS(* EXCLUDE (ProviderNumber))))
),
lcho AS (
    SELECT * FROM (SELECT ProviderNumber, COLUMNS('^TP\d{2}_(VS|FS|NSD|FD|VD|NADK)_LCHO$') FROM raw.lcho_perception)
    UNPIVOT INCLUDE NULLS (raw_value FOR source_column IN (COLUMNS(* EXCLUDE (ProviderNumber))))
),
comb AS (
    SELECT * FROM (SELECT ProviderNumber, COLUMNS('^TP\d{2}_(VS|FS|NSD|FD|VD|NADK)_COMB$') FROM raw.comb_perception)
    UNPIVOT INCLUDE NULLS (raw_value FOR source_column IN (COLUMNS(* EXCLUDE (ProviderNumber))))
),
long AS (
    SELECT
        trim(ProviderNumber)                                             AS landlord_code,
        regexp_extract(source_column, '^(TP\d{2})', 1)                   AS measure_code,
        regexp_extract(source_column, '_(VS|FS|NSD|FD|VD|NADK)_', 1)     AS answer,
        regexp_extract(source_column, '_(LCRA|LCHO|COMB)$', 1)           AS tenure_code,
        parse_num(raw_value)                                             AS responses
    FROM (SELECT * FROM lcra UNION ALL SELECT * FROM lcho UNION ALL SELECT * FROM comb)
)
PIVOT long ON answer IN ('VS', 'FS', 'NSD', 'FD', 'VD', 'NADK') USING first(responses)
GROUP BY landlord_code, measure_code, tenure_code;

-- Management information measures. Each one is published as a calculated
-- value plus the numerator and denominator it was calculated from; complaints
-- measures are split by tenure, everything else covers all homes.
CREATE OR REPLACE TABLE stg.management_result AS
WITH long AS (
    SELECT * FROM (
        SELECT ProviderNumber,
               COLUMNS('^(BS0\d|NM01_\d|RP01|RP02_\d|CH0\d_\d)_(Calculated_Value|Numerator|Denominator)(_(LCRA|LCHO|COMB))?$')
        FROM raw.management_info
    )
    UNPIVOT INCLUDE NULLS (raw_value FOR source_column IN (COLUMNS(* EXCLUDE (ProviderNumber))))
),
parsed AS (
    SELECT
        trim(ProviderNumber)                                                         AS landlord_code,
        regexp_extract(source_column, '^(BS0\d|NM01_\d|RP01|RP02_\d|CH0\d_\d)', 1)   AS measure_code,
        regexp_extract(source_column, '_(Calculated_Value|Numerator|Denominator)', 1) AS part,
        coalesce(NULLIF(regexp_extract(source_column, '_(LCRA|LCHO|COMB)$', 1), ''), 'ALL') AS tenure_code,
        source_column,
        raw_value
    FROM long
)
SELECT
    landlord_code,
    measure_code,
    tenure_code,
    max(source_column) FILTER (WHERE part = 'Calculated_Value')                AS source_column,
    max(raw_value)     FILTER (WHERE part = 'Calculated_Value')                AS raw_value,
    value_status(max(raw_value) FILTER (WHERE part = 'Calculated_Value'))      AS status_code,
    parse_num(max(raw_value) FILTER (WHERE part = 'Calculated_Value'))         AS value,
    parse_num(max(raw_value) FILTER (WHERE part = 'Numerator'))                AS numerator,
    parse_num(max(raw_value) FILTER (WHERE part = 'Denominator'))              AS denominator
FROM parsed
GROUP BY landlord_code, measure_code, tenure_code;

-- Survey design, one row per landlord and tenure survey.
CREATE OR REPLACE TABLE stg.survey AS
SELECT trim(ProviderNumber) AS landlord_code, 'LCRA' AS tenure_code,
       parse_num(Relevant_ten_pop_size_LCRA)  AS tenant_population,
       parse_num(MinimumSample_LCRA)          AS minimum_sample,
       parse_num(Total_sample_size_LCRA)      AS responses,
       parse_num(Estimated_margin_LCRA)       AS margin_of_error_pts,
       parse_num(Excluded_tens_LCRA)          AS tenants_excluded,
       Census_or_Sample_LCRA                  AS census_or_sample,
       Predominant_method__LCRA               AS predominant_method,
       External_contractor_LCRA = 'Yes'       AS external_contractor,
       Weighting_used_LCRA = 'Yes'            AS weighted
FROM raw.lcra_perception
UNION ALL
SELECT trim(ProviderNumber), 'LCHO',
       parse_num(Relevant_ten_pop_size_LCHO), parse_num(MinimumSample_LCHO),
       parse_num(Total_sample_size_LCHO), parse_num(Estimated_margin_LCHO),
       parse_num(Excluded_tens_LCHO), Census_or_Sample_LCHO, Predominant_method_LCHO,
       External_contractor_LCHO = 'Yes', Weighting_used_LCHO = 'Yes'
FROM raw.lcho_perception
UNION ALL
SELECT trim(ProviderNumber), 'COMB',
       parse_num(Relevant_ten_pop_size_COMB), parse_num(MinimumSample_COMB),
       parse_num(Total_sample_size_COMB), parse_num(Estimated_margin_COMB),
       parse_num(Excluded_tens_COMB), Census_or_Sample_COMB, Predominant_method_COMB,
       External_contractor_COMB = 'Yes', Weighting_used_COMB = 'Yes'
FROM raw.comb_perception;

-- Responses and TP01 (overall satisfaction) by survey method.
CREATE OR REPLACE TABLE stg.survey_method AS
WITH long AS (
    SELECT * FROM (
        SELECT ProviderNumber,
               COLUMNS('^(Responses|TP01_Satisfied)_(Telephone|Internet|FacetoFace|Postal|SMS|Other)_(LCRA|LCHO|COMB)$')
        FROM (SELECT * FROM raw.lcra_perception
              UNION ALL BY NAME SELECT * FROM raw.lcho_perception
              UNION ALL BY NAME SELECT * FROM raw.comb_perception)
    )
    UNPIVOT INCLUDE NULLS (raw_value FOR source_column IN (COLUMNS(* EXCLUDE (ProviderNumber))))
),
parsed AS (
    SELECT
        trim(ProviderNumber)                                                             AS landlord_code,
        regexp_extract(source_column, '^(Responses|TP01_Satisfied)', 1)                  AS part,
        regexp_extract(source_column, '_(Telephone|Internet|FacetoFace|Postal|SMS|Other)_', 1) AS method_code,
        regexp_extract(source_column, '_(LCRA|LCHO|COMB)$', 1)                           AS tenure_code,
        raw_value
    FROM long
)
SELECT
    landlord_code, tenure_code, method_code,
    parse_num(max(raw_value) FILTER (WHERE part = 'Responses'))                 AS responses,
    value_status(max(raw_value) FILTER (WHERE part = 'TP01_Satisfied'))        AS tp01_status_code,
    parse_num(max(raw_value) FILTER (WHERE part = 'TP01_Satisfied'))           AS tp01_pct_satisfied
FROM parsed
GROUP BY landlord_code, tenure_code, method_code
-- UNION ALL BY NAME pads each file with the other files' columns, so a
-- landlord gets rows for tenures it has no survey for. Keep only real surveys.
HAVING max(raw_value) FILTER (WHERE part = 'Responses') IS NOT NULL;

-- How each landlord defines "on time" for repairs (context for RP02).
CREATE OR REPLACE TABLE stg.repairs_target AS
SELECT
    trim(ProviderNumber)                       AS landlord_code,
    parse_num(RP02_Max_Timescale_Non_Emer)     AS max_target_non_emergency,
    More_than_one_target_NE = 'Yes'            AS multiple_targets_non_emergency,
    parse_num(RP02_Max_Timescale_Emer)         AS max_target_emergency,
    More_than_one_target_E = 'Yes'             AS multiple_targets_emergency,
    parse_num("Repairs Calculated Value")      AS repairs_completed
FROM raw.management_info;
