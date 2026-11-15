-- =====================================================================
-- 10_weekday_hour_heatmap.sql — Demand by day of week and hour.
-- Grain: 1 row per (weekday, hour): 7 x 24 = 168 rows.
--
-- trips_per_day divides by how many Mondays, Tuesdays... the year has, so
-- the cells are comparable. intensity indexes each cell against the
-- busiest one (100 = the busiest hour of the week).
-- =====================================================================
WITH days AS (
    SELECT iso_dow, COUNT(DISTINCT trip_date) AS n_days
    FROM mart.fact_trip WHERE is_valid
    GROUP BY iso_dow
),
cells AS (
    SELECT f.iso_dow, f.start_hour, COUNT(*)::NUMERIC / d.n_days AS trips_per_day
    FROM mart.fact_trip AS f JOIN days AS d USING (iso_dow)
    WHERE f.is_valid
    GROUP BY f.iso_dow, f.start_hour, d.n_days
)
SELECT TO_CHAR(DATE '2024-01-01' + (iso_dow - 1), 'Dy')               AS weekday,   -- 2024-01-01 is a Monday
       start_hour                                                     AS hour,
       ROUND(trips_per_day)                                           AS trips_per_day,
       ROUND(100 * trips_per_day / MAX(trips_per_day) OVER ())        AS intensity
FROM cells
ORDER BY iso_dow, start_hour;
