-- Layer 0: raw. Each published CSV is loaded as-is, every column as text, so
-- nothing is lost or silently coerced before staging decides what it means.
-- Paths are relative to the repository root (run_all.py runs from there).

CREATE SCHEMA IF NOT EXISTS raw;

CREATE OR REPLACE TABLE raw.lcra_perception AS
SELECT * FROM read_csv('data/raw/tsm-2025/TSM_2025_Full_Data - File 01 - LCRA_perception.csv',
                       all_varchar = true, header = true);

CREATE OR REPLACE TABLE raw.lcho_perception AS
SELECT * FROM read_csv('data/raw/tsm-2025/TSM_2025_Full_Data - File 02 - LCHO_perception.csv',
                       all_varchar = true, header = true);

CREATE OR REPLACE TABLE raw.comb_perception AS
SELECT * FROM read_csv('data/raw/tsm-2025/TSM_2025_Full_Data - File 03 - COMB_perception.csv',
                       all_varchar = true, header = true);

CREATE OR REPLACE TABLE raw.management_info AS
SELECT * FROM read_csv('data/raw/tsm-2025/TSM_2025_Full_Data - File 04 - Management_info.csv',
                       all_varchar = true, header = true);

CREATE OR REPLACE TABLE raw.perception_not_included AS
SELECT * FROM read_csv('data/raw/tsm-2025/TSM_2025_Full_Data - File 05 - Perception_not_inc.csv',
                       all_varchar = true, header = true);

CREATE OR REPLACE TABLE raw.management_not_included AS
SELECT * FROM read_csv('data/raw/tsm-2025/TSM_2025_Full_Data - File 06 - Man_not_inc.csv',
                       all_varchar = true, header = true);

CREATE OR REPLACE TABLE raw.data_dictionary AS
SELECT * FROM read_csv('data/raw/tsm-2025/TSM_2025_Full_Data - File 0A - Data_dictionary.csv',
                       all_varchar = true, header = true);

CREATE OR REPLACE TABLE raw.table_coverage AS
SELECT * FROM read_csv('data/raw/tsm-2025/TSM_2025_Full_Data - File 0B - Table_coverage.csv',
                       all_varchar = true, header = true);

-- Parsing helpers used by every staging model.
-- A published cell is either a number (possibly with thousands separators),
-- a bracketed status marker such as [X] or [S], or blank.
CREATE OR REPLACE MACRO parse_num(x) AS
    TRY_CAST(replace(trim(x), ',', '') AS DOUBLE);

CREATE OR REPLACE MACRO value_status(x) AS
    CASE
        WHEN x IS NULL OR trim(x) = ''             THEN 'BLANK'
        WHEN regexp_full_match(trim(x), '\[[A-Z]\]') THEN trim(x)
        WHEN parse_num(x) IS NOT NULL             THEN 'REPORTED'
        ELSE 'UNPARSEABLE'
    END;
