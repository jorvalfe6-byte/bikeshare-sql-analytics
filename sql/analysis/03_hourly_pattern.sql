-- =====================================================================
-- 03_hourly_pattern.sql — When do people ride?
-- Grain: 1 row per (rider type, weekday/weekend, hour).
--
-- trips_per_day divides by the number of days of that kind in the year,
-- so a weekday hour and a weekend hour are comparable.
-- =====================================================================
WITH days AS (
    SELECT is_weekend, COUNT(DISTINCT trip_date) AS n_days
    FROM mart.fact_trip WHERE is_valid
    GROUP BY is_weekend
),
hourly AS (
    SELECT member_type, is_weekend, start_hour, COUNT(*) AS trips
    FROM mart.fact_trip WHERE is_valid
    GROUP BY member_type, is_weekend, start_hour
)
SELECT h.member_type,
       CASE WHEN h.is_weekend THEN 'weekend' ELSE 'weekday' END       AS day_type,
       h.start_hour,
       h.trips,
       ROUND(h.trips::NUMERIC / d.n_days)                              AS trips_per_day,
       -- share of that group's daily trips that start in this hour
       ROUND(100.0 * h.trips / SUM(h.trips) OVER (PARTITION BY h.member_type, h.is_weekend), 1) AS pct_of_day,
       RANK() OVER (PARTITION BY h.member_type, h.is_weekend ORDER BY h.trips DESC)            AS peak_rank
FROM hourly AS h
JOIN days   AS d USING (is_weekend)
ORDER BY h.member_type, h.is_weekend, h.start_hour;
