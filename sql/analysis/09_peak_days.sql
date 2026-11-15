-- =====================================================================
-- 09_peak_days.sql — Busiest and quietest days.
-- Grain: 1 row per day (top 5 and bottom 5).
--
-- vs_dow_avg compares each day with the average for its weekday, so a
-- quiet Sunday is not mistaken for a storm.
-- =====================================================================
WITH daily AS (
    SELECT trip_date, iso_dow, COUNT(*) AS trips
    FROM mart.fact_trip
    WHERE is_valid
    GROUP BY trip_date, iso_dow
),
scored AS (
    SELECT *,
           ROUND(100.0 * (trips / AVG(trips) OVER (PARTITION BY iso_dow) - 1), 0) AS vs_dow_avg_pct,
           RANK() OVER (ORDER BY trips DESC) AS busiest_rank,
           RANK() OVER (ORDER BY trips ASC)  AS quietest_rank
    FROM daily
)
SELECT trip_date,
       TO_CHAR(trip_date, 'Dy') AS weekday,
       trips,
       vs_dow_avg_pct,
       CASE WHEN busiest_rank <= 5 THEN 'busiest' ELSE 'quietest' END AS kind
FROM scored
WHERE busiest_rank <= 5 OR quietest_rank <= 5
ORDER BY trips DESC;
