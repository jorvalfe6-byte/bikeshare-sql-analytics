-- =====================================================================
-- 02_monthly_usage.sql — Monthly demand with MoM change, 3-month moving
-- average and the busiest month flagged.
-- Grain: 1 row per month.
--
-- A calendar built with generate_series keeps a month with no trips as 0
-- instead of letting LAG and the moving average skip it.
-- =====================================================================
WITH calendar AS (
    SELECT generate_series(DATE '2024-01-01', DATE '2024-12-01', INTERVAL '1 month')::DATE AS month
),
monthly AS (
    SELECT trip_month                                           AS month,
           COUNT(*)                                             AS trips,
           COUNT(*) FILTER (WHERE member_type = 'member')       AS member_trips,
           COUNT(*) FILTER (WHERE member_type = 'casual')       AS casual_trips
    FROM mart.fact_trip
    WHERE is_valid
    GROUP BY trip_month
)
SELECT c.month,
       COALESCE(m.trips, 0)                                                AS trips,
       ROUND(100.0 * (m.trips::NUMERIC / NULLIF(LAG(m.trips) OVER w, 0) - 1), 1) AS mom_pct,   -- ::NUMERIC avoids integer division
       ROUND(AVG(COALESCE(m.trips, 0)) OVER (ORDER BY c.month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)) AS trips_ma3,
       ROUND(100.0 * m.casual_trips / NULLIF(m.trips, 0), 1)               AS pct_casual,
       RANK() OVER (ORDER BY COALESCE(m.trips, 0) DESC)                    AS demand_rank
FROM calendar AS c
LEFT JOIN monthly AS m USING (month)
WINDOW w AS (ORDER BY c.month)
ORDER BY c.month;
