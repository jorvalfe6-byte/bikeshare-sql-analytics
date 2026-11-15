-- =====================================================================
-- 01_kpis.sql — Executive summary for the whole period.
-- Grain: 1 row.
-- =====================================================================
SELECT COUNT(*)                                                       AS valid_trips,
       COUNT(DISTINCT trip_date)                                      AS days_covered,
       ROUND(COUNT(*)::NUMERIC / COUNT(DISTINCT trip_date))           AS trips_per_day,
       ROUND(100.0 * AVG((member_type = 'member')::INT), 1)           AS pct_members,
       ROUND(100.0 * AVG((rideable_type = 'electric_bike')::INT), 1)  AS pct_electric,
       ROUND(100.0 * AVG((NOT is_docked)::INT), 1)                    AS pct_outside_dock,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_min)::NUMERIC, 1) AS median_min,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY duration_min)::NUMERIC, 1) AS p90_min,
       COUNT(DISTINCT start_station_id)                               AS stations_used
FROM mart.fact_trip
WHERE is_valid;
