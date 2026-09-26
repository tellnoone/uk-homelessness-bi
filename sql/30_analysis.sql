-- Layer 3: analysis views over the star schema. These are the queries behind
-- every number quoted in the README; analysis.py only reads them, it does not
-- recompute anything. All results are for tenants in low cost rental housing
-- (LCRA), the tenure every landlord in scope reports on, using reported
-- values only.

CREATE SCHEMA IF NOT EXISTS analysis;

-- Every published value has one decimal place, so a median or quartile is
-- exact to at most two decimals, e.g. 14.85. In floating point that can be
-- stored as 14.8499999... or 14.8500001..., and rounding it to one decimal
-- would then depend on noise. Snapping to four decimals first makes the
-- result exact, and DECIMAL rounding then rounds halves away from zero.
CREATE OR REPLACE MACRO round1(x) AS round(CAST(x AS DECIMAL(18, 4)), 1);

-- One row per landlord with its LCRA perception results side by side.
CREATE OR REPLACE VIEW analysis.lcra_perception_wide AS
SELECT
    l.landlord_key, l.landlord_code, l.landlord_name, l.landlord_type,
    l.group_size_band, l.predominant_region,
    s.predominant_method,
    max(f.value) FILTER (WHERE m.measure_code = 'TP01') AS tp01,
    max(f.value) FILTER (WHERE m.measure_code = 'TP02') AS tp02,
    max(f.value) FILTER (WHERE m.measure_code = 'TP03') AS tp03,
    max(f.value) FILTER (WHERE m.measure_code = 'TP04') AS tp04,
    max(f.value) FILTER (WHERE m.measure_code = 'TP05') AS tp05,
    max(f.value) FILTER (WHERE m.measure_code = 'TP06') AS tp06,
    max(f.value) FILTER (WHERE m.measure_code = 'TP07') AS tp07,
    max(f.value) FILTER (WHERE m.measure_code = 'TP08') AS tp08,
    max(f.value) FILTER (WHERE m.measure_code = 'TP09') AS tp09,
    max(f.value) FILTER (WHERE m.measure_code = 'TP10') AS tp10,
    max(f.value) FILTER (WHERE m.measure_code = 'TP11') AS tp11,
    max(f.value) FILTER (WHERE m.measure_code = 'TP12') AS tp12
FROM mart.fact_tsm_result AS f
JOIN mart.dim_landlord     AS l USING (landlord_key)
JOIN mart.dim_measure      AS m USING (measure_key)
JOIN mart.dim_tenure       AS t USING (tenure_key)
JOIN mart.dim_value_status AS v USING (status_key)
LEFT JOIN mart.fact_survey AS s
       ON s.landlord_key = f.landlord_key AND s.tenure_key = f.tenure_key
WHERE t.tenure_code = 'LCRA' AND v.is_usable AND m.measure_code LIKE 'TP%'
GROUP BY ALL;

-- Headline distribution of overall satisfaction.
CREATE OR REPLACE VIEW analysis.tp01_summary AS
SELECT
    count(*)                                AS landlords,
    round1(median(tp01))                  AS median_tp01,
    round1(quantile_cont(tp01, 0.25))     AS p25_tp01,
    round1(quantile_cont(tp01, 0.75))     AS p75_tp01,
    min(tp01)                               AS min_tp01,
    max(tp01)                               AS max_tp01
FROM analysis.lcra_perception_wide;

-- Median overall satisfaction by the peer attributes a benchmarking club
-- would group on.
CREATE OR REPLACE VIEW analysis.tp01_by_peer_attribute AS
SELECT 'Landlord type' AS attribute, landlord_type AS peer_group, count(*) AS landlords,
       round1(median(tp01)) AS median_tp01
FROM analysis.lcra_perception_wide GROUP BY ALL
UNION ALL
SELECT 'Region', predominant_region, count(*), round1(median(tp01))
FROM analysis.lcra_perception_wide GROUP BY ALL
UNION ALL
SELECT 'Group size', group_size_band, count(*), round1(median(tp01))
FROM analysis.lcra_perception_wide GROUP BY ALL
UNION ALL
SELECT 'Predominant survey method', predominant_method, count(*), round1(median(tp01))
FROM analysis.lcra_perception_wide GROUP BY ALL;

-- Finding 1: survey method. Landlords that surveyed by both telephone and
-- internet publish TP01 for each, so the same landlord's tenants can be
-- compared across methods. This is a paired comparison: landlord, stock and
-- service are held constant; only the method differs.
CREATE OR REPLACE VIEW analysis.method_gap_by_landlord AS
WITH by_method AS (
    SELECT f.landlord_key, sm.method_code, f.responses, f.tp01_pct_satisfied
    FROM mart.fact_survey_method AS f
    JOIN mart.dim_survey_method AS sm USING (method_key)
    JOIN mart.dim_tenure        AS t  USING (tenure_key)
    JOIN mart.dim_value_status  AS v  ON v.status_key = f.tp01_status_key
    WHERE t.tenure_code = 'LCRA' AND v.is_usable
)
SELECT
    tel.landlord_key,
    tel.tp01_pct_satisfied                              AS tp01_telephone,
    web.tp01_pct_satisfied                              AS tp01_internet,
    tel.tp01_pct_satisfied - web.tp01_pct_satisfied     AS telephone_minus_internet,
    tel.responses                                       AS telephone_responses,
    web.responses                                       AS internet_responses
FROM by_method AS tel
JOIN by_method AS web
  ON web.landlord_key = tel.landlord_key AND web.method_code = 'Internet'
WHERE tel.method_code = 'Telephone';

CREATE OR REPLACE VIEW analysis.method_gap_summary AS
SELECT
    count(*)                                                     AS landlords,
    round1(median(telephone_minus_internet))                   AS median_gap_pts,
    round1(avg(telephone_minus_internet))                      AS mean_gap_pts,
    round1(quantile_cont(telephone_minus_internet, 0.25))      AS p25_gap_pts,
    round1(quantile_cont(telephone_minus_internet, 0.75))      AS p75_gap_pts,
    count(*) FILTER (WHERE telephone_minus_internet > 0)         AS telephone_higher,
    round(100.0 * count(*) FILTER (WHERE telephone_minus_internet > 0) / count(*), 1)
                                                                 AS telephone_higher_pct,
    -- Both groups must be big enough that the gap is not noise: at least
    -- 100 responses by each method.
    count(*) FILTER (WHERE telephone_responses >= 100 AND internet_responses >= 100)
                                                                 AS landlords_100_plus_each,
    round1(median(telephone_minus_internet)
          FILTER (WHERE telephone_responses >= 100 AND internet_responses >= 100))
                                                                 AS median_gap_pts_100_plus_each
FROM analysis.method_gap_by_landlord;

-- What the method effect does to a league table: rank every landlord on TP01
-- nationally, then again only against landlords whose survey was mainly the
-- same method, and see how many change quartile.
CREATE OR REPLACE VIEW analysis.peer_rank AS
WITH ranked AS (
    SELECT
        landlord_key, landlord_name, landlord_type, predominant_method, tp01,
        PERCENT_RANK() OVER (ORDER BY tp01)                                   AS pct_rank_national,
        PERCENT_RANK() OVER (PARTITION BY predominant_method ORDER BY tp01)   AS pct_rank_same_method,
        count(*) OVER (PARTITION BY predominant_method)                       AS method_peer_count
    FROM analysis.lcra_perception_wide
    WHERE predominant_method IN ('Telephone', 'Internet')
)
SELECT *,
       least(floor(pct_rank_national    * 4) + 1, 4) AS quartile_national,
       least(floor(pct_rank_same_method * 4) + 1, 4) AS quartile_same_method
FROM ranked;

CREATE OR REPLACE VIEW analysis.peer_rank_summary AS
SELECT
    predominant_method,
    count(*)                                                          AS landlords,
    round1(median(tp01))                                            AS median_tp01,
    count(*) FILTER (WHERE quartile_national <> quartile_same_method) AS change_quartile,
    count(*) FILTER (WHERE quartile_national = 1)                     AS bottom_quartile_national,
    count(*) FILTER (WHERE quartile_national = 1 AND quartile_same_method > 1)
                                                                      AS leave_bottom_quartile
FROM analysis.peer_rank
GROUP BY ALL;

-- Findings 2 and 3: what moves with overall satisfaction. Spearman rank
-- correlation computed in SQL: average ranks (ties share the mean of the
-- ranks they span), then Pearson correlation of the ranks.
CREATE OR REPLACE VIEW analysis.tp01_driver_correlation AS
WITH long AS (
    UNPIVOT (SELECT landlord_key, tp01, tp02, tp03, tp04, tp05, tp06, tp07, tp08, tp09, tp10, tp11, tp12
             FROM analysis.lcra_perception_wide)
    ON tp02, tp03, tp04, tp05, tp06, tp07, tp08, tp09, tp10, tp11, tp12
    INTO NAME measure VALUE other_value
),
ranked AS (
    SELECT measure,
           RANK() OVER (PARTITION BY measure ORDER BY tp01)
             + (count(*) OVER (PARTITION BY measure, tp01) - 1) / 2.0         AS r_tp01,
           RANK() OVER (PARTITION BY measure ORDER BY other_value)
             + (count(*) OVER (PARTITION BY measure, other_value) - 1) / 2.0  AS r_other
    FROM long
    WHERE tp01 IS NOT NULL AND other_value IS NOT NULL
)
SELECT upper(measure) AS measure_code, count(*) AS landlords,
       round(corr(r_tp01, r_other), 3) AS spearman_rho
FROM ranked
GROUP BY measure;

-- Management information against the perception measure it should move.
CREATE OR REPLACE VIEW analysis.management_vs_perception AS
WITH mi AS (
    SELECT f.landlord_key, m.measure_code, f.value
    FROM mart.fact_tsm_result AS f
    JOIN mart.dim_measure      AS m USING (measure_key)
    JOIN mart.dim_tenure       AS t USING (tenure_key)
    JOIN mart.dim_value_status AS v USING (status_key)
    WHERE v.is_usable AND t.tenure_code IN ('ALL', 'LCRA')
),
pairs AS (
    SELECT * FROM (VALUES
        ('RP02_1', 'tp02', 'Non-emergency repairs on time vs repairs satisfaction'),
        ('RP02_1', 'tp03', 'Non-emergency repairs on time vs satisfaction with repair time'),
        ('RP01',   'tp04', 'Homes not decent vs home well maintained'),
        ('CH02_1', 'tp09', 'Stage 1 complaints answered on time vs complaints satisfaction')
    ) AS t(mi_code, perception_column, pair_label)
),
joined AS (
    SELECT p.mi_code, p.perception_column, p.pair_label, mi.value AS mi_value,
           CASE p.perception_column WHEN 'tp02' THEN w.tp02 WHEN 'tp03' THEN w.tp03
                                    WHEN 'tp04' THEN w.tp04 WHEN 'tp09' THEN w.tp09 END AS perception_value
    FROM pairs AS p
    JOIN mi ON mi.measure_code = p.mi_code
    JOIN analysis.lcra_perception_wide AS w USING (landlord_key)
),
ranked AS (
    SELECT mi_code, perception_column, pair_label,
           RANK() OVER (PARTITION BY mi_code, perception_column ORDER BY mi_value)
             + (count(*) OVER (PARTITION BY mi_code, perception_column, mi_value) - 1) / 2.0 AS r_mi,
           RANK() OVER (PARTITION BY mi_code, perception_column ORDER BY perception_value)
             + (count(*) OVER (PARTITION BY mi_code, perception_column, perception_value) - 1) / 2.0 AS r_p
    FROM joined
    WHERE mi_value IS NOT NULL AND perception_value IS NOT NULL
)
SELECT mi_code, upper(perception_column) AS perception_code, pair_label,
       count(*) AS landlords, round(corr(r_mi, r_p), 3) AS spearman_rho
FROM ranked
GROUP BY ALL;

-- Do landlords with longer targets report more repairs "on time"? If they
-- did, target length would explain why RP02 tracks tenant views so weakly.
CREATE OR REPLACE VIEW analysis.repairs_target_vs_rp02 AS
WITH pairs AS (
    SELECT r.max_target_non_emergency AS target, f.value AS rp02
    FROM mart.fact_repairs_target AS r
    JOIN mart.fact_tsm_result     AS f USING (landlord_key)
    JOIN mart.dim_measure         AS m USING (measure_key)
    WHERE m.measure_code = 'RP02_1' AND f.value IS NOT NULL AND r.max_target_non_emergency IS NOT NULL
),
ranked AS (
    SELECT RANK() OVER (ORDER BY target) + (count(*) OVER (PARTITION BY target) - 1) / 2.0 AS r_target,
           RANK() OVER (ORDER BY rp02)   + (count(*) OVER (PARTITION BY rp02) - 1) / 2.0   AS r_rp02
    FROM pairs
)
SELECT count(*) AS landlords, round(corr(r_target, r_rp02), 3) AS spearman_rho
FROM ranked;

-- How landlords define "on time" for RP02, which is why RP02 is not
-- comparable between landlords.
CREATE OR REPLACE VIEW analysis.repairs_target_summary AS
SELECT
    count(max_target_non_emergency)                                  AS landlords,
    min(max_target_non_emergency)                                    AS min_target,
    quantile_cont(max_target_non_emergency, 0.25)                    AS p25_target,
    median(max_target_non_emergency)                                 AS median_target,
    quantile_cont(max_target_non_emergency, 0.75)                    AS p75_target,
    max(max_target_non_emergency)                                    AS max_target,
    count(*) FILTER (WHERE multiple_targets_non_emergency)           AS multiple_targets,
    round(100.0 * count(*) FILTER (WHERE multiple_targets_non_emergency)
          / count(max_target_non_emergency), 1)                      AS multiple_targets_pct
FROM mart.fact_repairs_target;
