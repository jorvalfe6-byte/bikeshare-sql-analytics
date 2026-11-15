-- =====================================================================
-- 05_electric_adoption.sql — Electric vs classic bikes over the year.
-- Grain: 1 row per (month, bike type).
-- =====================================================================
SELECT trip_month,
       rideable_type,
       COUNT(*)                                                                    AS trips,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY trip_month), 1)   AS pct_of_month,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_min)::NUMERIC, 1) AS median_min,
       ROUND(100.0 * AVG((NOT is_docked)::INT), 1)                                 AS pct_outside_dock
FROM mart.fact_trip
WHERE is_valid
GROUP BY trip_month, rideable_type
ORDER BY trip_month, rideable_type;
