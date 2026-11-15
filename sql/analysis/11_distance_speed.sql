-- =====================================================================
-- 11_distance_speed.sql — How far and how fast, by bike and rider type.
-- Grain: 1 row per (bike type, rider type).
--
-- Only one-way trips of at least 100 m and 2 minutes, so a loop around the
-- park (distance ~0) or a failed undock does not drag the medians down.
-- Distance is straight-line, so net speed is a lower bound of real speed.
-- Trips with GPS points outside the D.C. metro box have no distance.
-- =====================================================================
SELECT rideable_type,
       member_type,
       COUNT(*)                                                                      AS trips,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY distance_km)::NUMERIC, 2)   AS median_km,
       ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY distance_km)::NUMERIC, 2)   AS p90_km,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY distance_km / (duration_min / 60.0))::NUMERIC, 1)
                                                                                     AS median_kmh
FROM mart.fact_trip
WHERE is_valid
  AND distance_km >= 0.1
  AND duration_min >= 2
GROUP BY rideable_type, member_type
ORDER BY rideable_type, member_type;
