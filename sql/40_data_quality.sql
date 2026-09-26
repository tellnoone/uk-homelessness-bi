-- Layer 4: data quality. Every check records how many rows it tested
-- (dq.check_tested) and every row that failed (dq.check_failure), and
-- dq.check_result joins them to the check's definition and the action taken.
-- Checks run against the raw files where the question is "is the published
-- data sound?" and against the marts where it is "did the model load it all?".

CREATE SCHEMA IF NOT EXISTS dq;

CREATE OR REPLACE TABLE dq.check_tested  (check_id VARCHAR, rows_tested BIGINT);
CREATE OR REPLACE TABLE dq.check_failure (check_id VARCHAR, landlord_code VARCHAR, detail VARCHAR);

-- ============================================================ Duplication
-- DU01: a landlord appears at most once in each published table.
CREATE OR REPLACE TEMP VIEW published_rows AS
SELECT 'LCRA perception' AS source_table, trim(ProviderNumber) AS landlord_code FROM raw.lcra_perception
UNION ALL SELECT 'LCHO perception',     trim(ProviderNumber) FROM raw.lcho_perception
UNION ALL SELECT 'Combined perception', trim(ProviderNumber) FROM raw.comb_perception
UNION ALL SELECT 'Management info',     trim(ProviderNumber) FROM raw.management_info
UNION ALL SELECT 'Table coverage',      trim(Landlord_code)  FROM raw.table_coverage;

INSERT INTO dq.check_tested SELECT 'DU01', count(*) FROM published_rows;
INSERT INTO dq.check_failure
SELECT 'DU01', landlord_code, source_table || ': appears ' || count(*) || ' times'
FROM published_rows GROUP BY landlord_code, source_table HAVING count(*) > 1;

-- DU02: the fact table's grain (landlord x measure x tenure x period) is unique.
INSERT INTO dq.check_tested SELECT 'DU02', count(*) FROM mart.fact_tsm_result;
INSERT INTO dq.check_failure
SELECT 'DU02', l.landlord_code, m.measure_code || ' appears ' || count(*) || ' times'
FROM mart.fact_tsm_result f
JOIN mart.dim_landlord l USING (landlord_key) JOIN mart.dim_measure m USING (measure_key)
GROUP BY l.landlord_code, m.measure_code, f.tenure_key, f.date_key HAVING count(*) > 1;

-- ================================================== Referential integrity
-- RI01: every landlord in a measure table is in RSH's coverage file.
INSERT INTO dq.check_tested SELECT 'RI01', count(*) FROM published_rows WHERE source_table <> 'Table coverage';
INSERT INTO dq.check_failure
SELECT 'RI01', p.landlord_code, p.source_table || ': not in the coverage file'
FROM published_rows p
WHERE p.source_table <> 'Table coverage'
  AND p.landlord_code NOT IN (SELECT landlord_code FROM stg.landlord);

-- RI02: the coverage file's "is this landlord in table X?" flags match what
-- the tables actually contain.
CREATE OR REPLACE TEMP VIEW coverage_vs_actual AS
SELECT l.landlord_code, 'LCRA perception' AS source_table, l.in_lcra_perception AS flagged,
       l.landlord_code IN (SELECT landlord_code FROM published_rows WHERE source_table = 'LCRA perception') AS present
FROM stg.landlord l
UNION ALL
SELECT l.landlord_code, 'LCHO perception', l.in_lcho_perception,
       l.landlord_code IN (SELECT landlord_code FROM published_rows WHERE source_table = 'LCHO perception')
FROM stg.landlord l
UNION ALL
SELECT l.landlord_code, 'Combined perception', l.in_combined_perception,
       l.landlord_code IN (SELECT landlord_code FROM published_rows WHERE source_table = 'Combined perception')
FROM stg.landlord l
UNION ALL
SELECT l.landlord_code, 'Management info', l.in_management_info,
       l.landlord_code IN (SELECT landlord_code FROM published_rows WHERE source_table = 'Management info')
FROM stg.landlord l;

INSERT INTO dq.check_tested SELECT 'RI02', count(*) FROM coverage_vs_actual;
INSERT INTO dq.check_failure
SELECT 'RI02', landlord_code,
       source_table || ': coverage says ' || CASE WHEN flagged THEN 'present' ELSE 'absent' END
       || ', table says ' || CASE WHEN present THEN 'present' ELSE 'absent' END
FROM coverage_vs_actual WHERE flagged <> present;

-- RI03: every landlord the coverage file marks as excluded is on RSH's
-- published exclusion list for that scope, so the exclusion has a reason.
CREATE OR REPLACE TEMP VIEW exclusion_flags AS
SELECT landlord_code, 'Perception' AS scope FROM stg.landlord WHERE flagged_perception_excluded
UNION ALL
SELECT landlord_code, 'Management information' FROM stg.landlord WHERE flagged_management_excluded;

INSERT INTO dq.check_tested SELECT 'RI03', count(*) FROM exclusion_flags;
INSERT INTO dq.check_failure
SELECT 'RI03', f.landlord_code, f.scope || ': flagged as excluded, but not on RSH''s exclusion list (no reason published)'
FROM exclusion_flags f
LEFT JOIN stg.exclusion e USING (landlord_code, scope)
WHERE e.landlord_code IS NULL;

-- RI04: every staged result reached the fact table (no row dropped by a
-- failed dimension join). [U] rows are excluded by design; see CP03.
INSERT INTO dq.check_tested
SELECT 'RI04', (SELECT count(*) FROM stg.perception_result)
             + (SELECT count(*) FROM stg.management_result WHERE status_code <> '[U]');
INSERT INTO dq.check_failure
SELECT 'RI04', NULL,
       'staged ' || staged || ' results, fact table holds ' || loaded
FROM (SELECT (SELECT count(*) FROM stg.perception_result)
           + (SELECT count(*) FROM stg.management_result WHERE status_code <> '[U]') AS staged,
             (SELECT count(*) FROM mart.fact_tsm_result) AS loaded)
WHERE staged <> loaded;

-- ============================================================ Consistency
-- CS01: a landlord's type, size band, region and name are the same in every
-- table it appears in.
CREATE OR REPLACE TEMP VIEW landlord_attributes AS
SELECT trim(ProviderNumber) AS landlord_code, ProviderName AS name, ProviderType AS type,
       "Group size" AS size_band, "Predominant region" AS region FROM raw.lcra_perception
UNION ALL SELECT trim(ProviderNumber), ProviderName, ProviderType, "Group size", "Predominant region" FROM raw.lcho_perception
UNION ALL SELECT trim(ProviderNumber), ProviderName, ProviderType, "Group size", "Predominant region" FROM raw.comb_perception
UNION ALL SELECT trim(ProviderNumber), ProviderName, ProviderType, "Group size", "Predominant region" FROM raw.management_info
UNION ALL SELECT trim(Landlord_code), Landlord_name, Landlord_type, NULL, NULL FROM raw.table_coverage;

INSERT INTO dq.check_tested SELECT 'CS01', count(DISTINCT landlord_code) FROM landlord_attributes;
INSERT INTO dq.check_failure
SELECT 'CS01', landlord_code, 'attributes differ between tables'
FROM landlord_attributes
GROUP BY landlord_code
HAVING count(DISTINCT name) > 1 OR count(DISTINCT type) > 1
    OR count(DISTINCT size_band) > 1 OR count(DISTINCT region) > 1;

-- ========================================================== Completeness
-- CP01: every landlord with an LCRA survey has a headline TP01 result.
INSERT INTO dq.check_tested SELECT 'CP01', count(*) FROM stg.perception_result
WHERE measure_code = 'TP01' AND tenure_code = 'LCRA';
INSERT INTO dq.check_failure
SELECT 'CP01', landlord_code, 'TP01 status ' || status_code
FROM stg.perception_result
WHERE measure_code = 'TP01' AND tenure_code = 'LCRA' AND status_code <> 'REPORTED';

-- CP02: every result that applies to the landlord carries a usable value.
INSERT INTO dq.check_tested SELECT 'CP02', count(*) FROM mart.fact_tsm_result;
INSERT INTO dq.check_failure
SELECT 'CP02', l.landlord_code, m.measure_code || ' (' || t.tenure_code || '): ' || v.status_description
FROM mart.fact_tsm_result f
JOIN mart.dim_landlord l USING (landlord_key) JOIN mart.dim_measure m USING (measure_key)
JOIN mart.dim_tenure t USING (tenure_key) JOIN mart.dim_value_status v USING (status_key)
WHERE NOT v.is_usable;

-- CP03: [U] only appears where the measure does not apply to the landlord:
-- either the landlord answered "No" to "do you own homes this measure applies
-- to?" (e.g. no lifts for BS05), or it is a complaints measure for a tenure
-- the landlord has no survey for. That is what justifies leaving [U] cells
-- out of the fact table.
CREATE OR REPLACE TEMP VIEW measure_applies AS
SELECT trim(ProviderNumber) AS landlord_code,
       regexp_replace(trim(source_column), '\s*Applies$', '') AS measure_code,
       applies
FROM (SELECT ProviderNumber, COLUMNS('Applies$') FROM raw.management_info)
UNPIVOT (applies FOR source_column IN (COLUMNS(* EXCLUDE (ProviderNumber))));

INSERT INTO dq.check_tested SELECT 'CP03', count(*) FROM stg.management_result WHERE status_code = '[U]';
INSERT INTO dq.check_failure
SELECT 'CP03', r.landlord_code, r.measure_code || ' (' || r.tenure_code || ') is [U] but the measure applies to the landlord'
FROM stg.management_result r
JOIN stg.landlord l USING (landlord_code)
LEFT JOIN measure_applies a USING (landlord_code, measure_code)
WHERE r.status_code = '[U]'
  AND NOT (   (r.tenure_code = 'ALL'  AND a.applies = 'No')
           OR (r.tenure_code = 'LCRA' AND NOT l.in_lcra_perception)
           OR (r.tenure_code = 'LCHO' AND NOT l.in_lcho_perception)
           OR (r.tenure_code = 'COMB' AND NOT l.in_combined_perception));

-- ======================================================= Range / validity
-- RG01: percentages lie between 0 and 100.
INSERT INTO dq.check_tested
SELECT 'RG01', count(*) FROM mart.fact_tsm_result f JOIN mart.dim_measure m USING (measure_key)
WHERE m.unit = '%' AND f.value IS NOT NULL;
INSERT INTO dq.check_failure
SELECT 'RG01', l.landlord_code, m.measure_code || ' = ' || f.value
FROM mart.fact_tsm_result f JOIN mart.dim_measure m USING (measure_key) JOIN mart.dim_landlord l USING (landlord_key)
WHERE m.unit = '%' AND (f.value < 0 OR f.value > 100);

-- RG02: for proportion measures the numerator never exceeds a positive denominator.
INSERT INTO dq.check_tested
SELECT 'RG02', count(*) FROM mart.fact_tsm_result f JOIN mart.dim_measure m USING (measure_key)
WHERE m.unit = '%' AND f.denominator IS NOT NULL;
INSERT INTO dq.check_failure
SELECT 'RG02', l.landlord_code, m.measure_code || ': ' || f.numerator || ' / ' || f.denominator
FROM mart.fact_tsm_result f JOIN mart.dim_measure m USING (measure_key) JOIN mart.dim_landlord l USING (landlord_key)
WHERE m.unit = '%' AND f.denominator IS NOT NULL AND (f.denominator <= 0 OR f.numerator > f.denominator);

-- RG03: per-1,000-homes rates are extreme outliers (more than 3 inter-quartile
-- ranges above the upper quartile for that measure and tenure).
CREATE OR REPLACE TEMP VIEW rate_fences AS
SELECT f.measure_key, f.tenure_key,
       quantile_cont(f.value, 0.75) + 3 * (quantile_cont(f.value, 0.75) - quantile_cont(f.value, 0.25)) AS upper_fence
FROM mart.fact_tsm_result f JOIN mart.dim_measure m USING (measure_key)
WHERE m.unit = 'per 1,000 homes' AND f.value IS NOT NULL
GROUP BY f.measure_key, f.tenure_key;

INSERT INTO dq.check_tested
SELECT 'RG03', count(*) FROM mart.fact_tsm_result f JOIN mart.dim_measure m USING (measure_key)
WHERE m.unit = 'per 1,000 homes' AND f.value IS NOT NULL;
INSERT INTO dq.check_failure
SELECT 'RG03', l.landlord_code,
       m.measure_code || ' (' || t.tenure_code || ') = ' || f.value || ' per 1,000; fence ' || round(r.upper_fence, 1)
FROM mart.fact_tsm_result f
JOIN rate_fences r USING (measure_key, tenure_key)
JOIN mart.dim_measure m USING (measure_key) JOIN mart.dim_landlord l USING (landlord_key)
JOIN mart.dim_tenure t USING (tenure_key)
WHERE f.value > r.upper_fence;

-- RG04: each survey met the minimum sample size RSH set for it.
INSERT INTO dq.check_tested SELECT 'RG04', count(*) FROM stg.survey WHERE minimum_sample IS NOT NULL;
INSERT INTO dq.check_failure
SELECT 'RG04', landlord_code,
       tenure_code || ': ' || responses::INTEGER || ' responses against a minimum of ' || minimum_sample
FROM stg.survey
WHERE responses < minimum_sample;

-- RG05: no survey has more responses than the tenants it sampled from.
INSERT INTO dq.check_tested SELECT 'RG05', count(*) FROM stg.survey WHERE tenant_population IS NOT NULL;
INSERT INTO dq.check_failure
SELECT 'RG05', landlord_code, tenure_code || ': ' || responses || ' responses from ' || tenant_population || ' tenants'
FROM stg.survey WHERE responses > tenant_population;

-- ======================================================== Reconciliation
-- RC01: each published "% satisfied" equals (very + fairly satisfied) divided
-- by everyone who gave a rating, to the published one decimal place.
CREATE OR REPLACE TEMP VIEW perception_recalc AS
SELECT r.landlord_code, r.measure_code, r.tenure_code, r.value,
       100 * (c.VS + c.FS) / (c.VS + c.FS + c.NSD + c.FD + c.VD) AS recalculated
FROM stg.perception_result r
JOIN stg.perception_response_count c USING (landlord_code, measure_code, tenure_code)
WHERE r.value IS NOT NULL AND (c.VS + c.FS + c.NSD + c.FD + c.VD) > 0;

INSERT INTO dq.check_tested SELECT 'RC01', count(*) FROM perception_recalc;
INSERT INTO dq.check_failure
SELECT 'RC01', landlord_code,
       measure_code || ' (' || tenure_code || '): published ' || value || ', recalculated ' || round(recalculated, 2)
FROM perception_recalc WHERE abs(value - recalculated) > 0.051;

-- RC02: each management measure equals numerator / denominator (x100 for
-- percentages, x1,000 for rates), to the published one decimal place.
CREATE OR REPLACE TEMP VIEW management_recalc AS
SELECT l.landlord_code, m.measure_code, t.tenure_code, f.value,
       f.numerator / f.denominator * CASE m.unit WHEN '%' THEN 100 ELSE 1000 END AS recalculated
FROM mart.fact_tsm_result f
JOIN mart.dim_measure m USING (measure_key) JOIN mart.dim_landlord l USING (landlord_key)
JOIN mart.dim_tenure t USING (tenure_key)
WHERE f.value IS NOT NULL AND f.denominator > 0;

INSERT INTO dq.check_tested SELECT 'RC02', count(*) FROM management_recalc;
INSERT INTO dq.check_failure
SELECT 'RC02', landlord_code,
       measure_code || ' (' || tenure_code || '): published ' || value || ', recalculated ' || round(recalculated, 2)
FROM management_recalc WHERE abs(value - recalculated) > 0.051;

-- RC03: the responses recorded by each survey method add up to the total.
CREATE OR REPLACE TEMP VIEW response_totals AS
SELECT s.landlord_code, s.tenure_code, s.responses AS total, sum(m.responses) AS by_method
FROM stg.survey s JOIN stg.survey_method m USING (landlord_code, tenure_code)
GROUP BY s.landlord_code, s.tenure_code, s.responses;

INSERT INTO dq.check_tested SELECT 'RC03', count(*) FROM response_totals;
INSERT INTO dq.check_failure
SELECT 'RC03', landlord_code, tenure_code || ': total ' || total || ', sum by method ' || by_method
FROM response_totals WHERE total <> by_method;

-- ========================================================= Comparability
-- CM01: RP02 ("repairs completed within target") is measured against each
-- landlord's own target; flag landlords using more than one.
INSERT INTO dq.check_tested SELECT 'CM01', count(*) FROM stg.repairs_target WHERE max_target_non_emergency IS NOT NULL;
INSERT INTO dq.check_failure
SELECT 'CM01', landlord_code, 'more than one non-emergency target; maximum ' || max_target_non_emergency
FROM stg.repairs_target WHERE multiple_targets_non_emergency;

-- ================================================================ Results
CREATE OR REPLACE TABLE dq.check_definition AS
SELECT * FROM (VALUES
    ('DU01', 'Duplication',           'Raw files',        'Each landlord appears once per published table',
     'FAIL', 'None needed if passing; a duplicate would be resolved before loading dim_landlord.'),
    ('DU02', 'Duplication',           'fact_tsm_result',  'Fact grain (landlord x measure x tenure x period) is unique',
     'FAIL', 'None needed if passing.'),
    ('RI01', 'Referential integrity', 'Raw files',        'Every landlord in a measure table is in the coverage file',
     'FAIL', 'None needed if passing; dim_landlord is built from the coverage file.'),
    ('RI02', 'Referential integrity', 'Raw files',        'Coverage flags match the landlords actually in each table',
     'FAIL', 'None needed if passing.'),
    ('RI03', 'Referential integrity', 'Raw files',        'Every excluded landlord is on RSH''s exclusion list with a reason',
     'WARN', 'Kept in dim_landlord with both exclusion flags set and no note; they hold no results, so no measure is affected. Reported here because a reader of the exclusion lists alone would miss them.'),
    ('RI04', 'Referential integrity', 'fact_tsm_result',  'Every staged result is loaded into the fact table',
     'FAIL', 'None needed if passing.'),
    ('CS01', 'Consistency',           'Raw files',        'Landlord name, type, size and region agree across tables',
     'FAIL', 'None needed if passing.'),
    ('CP01', 'Completeness',          'Raw files',        'Every LCRA survey has a headline TP01 result',
     'FAIL', 'None needed if passing.'),
    ('CP02', 'Completeness',          'fact_tsm_result',  'Every applicable result has a usable value',
     'WARN', 'Kept in the fact table with their status; the value is left empty, so averages and counts skip them. Most are RSH exclusions ([E]) explained in RSH''s comments.'),
    ('CP03', 'Completeness',          'Raw files',        '[U] appears only where the measure does not apply to the landlord',
     'FAIL', 'Justifies leaving [U] cells out of the fact table.'),
    ('RG01', 'Range',                 'fact_tsm_result',  'Percentages are between 0 and 100',
     'FAIL', 'None needed if passing.'),
    ('RG02', 'Range',                 'fact_tsm_result',  'Numerator never exceeds a positive denominator',
     'FAIL', 'None needed if passing.'),
    ('RG03', 'Range',                 'fact_tsm_result',  'Per-1,000 rates are not extreme outliers (over upper quartile + 3 IQR)',
     'WARN', 'Kept: they reconcile to their own numerator and denominator (RC02), so they are what the landlord reported. Medians, not means, are used in the report so they cannot dominate. Flagged for review, since they may reflect different recording practice.'),
    ('RG04', 'Range',                 'Raw files',        'Each survey met its required minimum sample',
     'WARN', 'Kept: RSH published them. Their results carry a wider margin of error than required; margin_of_error_pts is in fact_survey for the report to show.'),
    ('RG05', 'Range',                 'Raw files',        'No survey has more responses than tenants sampled',
     'FAIL', 'None needed if passing.'),
    ('RC01', 'Reconciliation',        'Raw files',        'Published % satisfied = (very + fairly satisfied) / all ratings',
     'FAIL', 'None needed if passing; confirms the headline figures can be trusted as published.'),
    ('RC02', 'Reconciliation',        'fact_tsm_result',  'Published management measure = numerator / denominator',
     'FAIL', 'None needed if passing.'),
    ('RC03', 'Reconciliation',        'Raw files',        'Responses by survey method add up to the survey total',
     'FAIL', 'None needed if passing.'),
    ('CM01', 'Comparability',         'Raw files',        'Landlord uses a single non-emergency repair target (RP02 comparable)',
     'WARN', 'RP02 is not ranked across landlords in the report; targets are shown next to it.')
) AS t(check_id, category, checked_in, check_name, severity_if_failed, action_taken);

CREATE OR REPLACE TABLE dq.check_result AS
SELECT
    d.check_id, d.category, d.checked_in, d.check_name,
    t.rows_tested,
    count(f.check_id)                                              AS rows_failed,
    CASE WHEN count(f.check_id) = 0 THEN 'PASS' ELSE d.severity_if_failed END AS status,
    CASE WHEN count(f.check_id) = 0 THEN '-' ELSE d.action_taken END          AS action_taken
FROM dq.check_definition d
JOIN dq.check_tested t USING (check_id)
LEFT JOIN dq.check_failure f USING (check_id)
GROUP BY d.check_id, d.category, d.checked_in, d.check_name, t.rows_tested,
         d.severity_if_failed, d.action_taken
ORDER BY d.check_id;
