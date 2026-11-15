-- =====================================================================
-- 00_data_quality.sql — Checks after every load.
-- Each row is one check: 'OK' or 'REVIEW' with the value found.
-- Expected values correspond to the 12 monthly files of 2024 as published
-- by Capital Bikeshare (see scripts/download_data.sh). If the operator
-- republishes a file with corrections, a check turns REVIEW on purpose.
-- =====================================================================
WITH checks AS (
    SELECT 'rows staged (all 12 CSV files)'      AS check_name,
           (SELECT COUNT(*) FROM staging.trips)  AS value,
           6114323                               AS expected
    UNION ALL
    SELECT 'trips loaded',                     (SELECT COUNT(*) FROM core.trip), 6114182
    UNION ALL
    -- 141 trips that cross midnight at a month end appear in two files
    SELECT 'duplicate ride_ids removed',       (SELECT COUNT(*) - COUNT(DISTINCT ride_id) FROM staging.trips), 141
    UNION ALL
    SELECT 'rows rejected by the load (only duplicates)',
           -- the whole load runs in one transaction, so it shares now()
           (SELECT COALESCE(SUM(rows_rejected), 0) FROM audit.load_log
            WHERE loaded_at = (SELECT MAX(loaded_at) FROM audit.load_log)), 141
    UNION ALL
    SELECT 'stations',                         (SELECT COUNT(*) FROM core.station), 804
    UNION ALL
    SELECT 'months covered',                   (SELECT COUNT(DISTINCT DATE_TRUNC('month', started_at)) FROM core.trip), 12
    UNION ALL
    SELECT 'trips outside 2024',               (SELECT COUNT(*) FROM core.trip WHERE started_at < DATE '2024-01-01' OR started_at >= DATE '2025-01-01'), 0
    UNION ALL
    SELECT 'mart rows = core rows',            (SELECT COUNT(*) FROM mart.fact_trip), (SELECT COUNT(*) FROM core.trip)
    UNION ALL
    SELECT 'excluded: ends before start',      (SELECT COUNT(*) FROM mart.fact_trip WHERE invalid_reason = 'ends_before_start'), 1101
    UNION ALL
    SELECT 'excluded: under 60 s, same dock',  (SELECT COUNT(*) FROM mart.fact_trip WHERE invalid_reason = 'under_60s_same_dock'), 33517
    UNION ALL
    SELECT 'excluded: over 24 h',              (SELECT COUNT(*) FROM mart.fact_trip WHERE invalid_reason = 'over_24h'), 5011
    UNION ALL
    -- a classic bike can only be unlocked at a dock; if this is not 0, a column shifted
    SELECT 'classic bikes without a start station', (SELECT COUNT(*) FROM core.trip WHERE rideable_type = 'classic_bike' AND start_station_id IS NULL), 0
    UNION ALL
    SELECT 'classic bikes without an end station',  (SELECT COUNT(*) FROM core.trip WHERE rideable_type = 'classic_bike' AND end_station_id IS NULL), 4908
)
SELECT check_name,
       value,
       expected,
       CASE WHEN value = expected THEN 'OK' ELSE 'REVIEW' END AS status
FROM checks;

-- Known characteristics of the dataset (not load errors):
--   * ~1.2 M trips have no start or end station: electric bikes can be
--     locked outside a dock.
--   * 4,908 classic-bike trips (0.18 %) end with no station: the bike was
--     not returned to a dock. They are kept, and they count as undocked.
--   * 15 station ids were renamed during the year, and 2 names exist under
--     two ids. Each id keeps its most frequent name; both ids stay.
--   * A handful of end coordinates fall outside the metro area (GPS noise).
--   * The April 2024 archive contains a file named "202004-…" (typo by the
--     publisher); its trips are April 2024. The download script names the
--     file after the month in the zip's own name.
