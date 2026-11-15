-- =====================================================================
-- 04_members_vs_casual.sql — Do members and casual riders use the system
-- for different things?
-- Grain: 1 row per rider type.
-- =====================================================================
SELECT member_type,
       COUNT(*)                                                                    AS trips,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1)                          AS pct_trips,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_min)::NUMERIC, 1) AS median_min,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY duration_min)::NUMERIC, 1) AS p90_min,
       ROUND(100.0 * AVG(is_weekend::INT), 1)                                      AS pct_weekend,
       -- commuting windows: weekday 7-9 and 16-18
       ROUND(100.0 * AVG((NOT is_weekend AND (start_hour BETWEEN 7 AND 9
                                              OR start_hour BETWEEN 16 AND 18))::INT), 1) AS pct_commute_hours,
       ROUND(100.0 * AVG((rideable_type = 'electric_bike')::INT), 1)               AS pct_electric,
       -- return to the dock they left from: sightseeing, not a one-way trip
       ROUND(100.0 * AVG(is_same_station::INT), 1)                                 AS pct_round_trip
FROM mart.fact_trip
WHERE is_valid
GROUP BY member_type
ORDER BY member_type;
