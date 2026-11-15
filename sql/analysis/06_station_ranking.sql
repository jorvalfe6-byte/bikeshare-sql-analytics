-- =====================================================================
-- 06_station_ranking.sql — Busiest stations and how concentrated demand is.
-- =====================================================================

-- (a) Top 15 stations by departures. Grain: 1 row per station.
WITH departures AS (
    SELECT start_station_id AS station_id,
           COUNT(*)         AS trips,
           ROUND(100.0 * AVG((member_type = 'member')::INT), 1) AS pct_members
    FROM mart.fact_trip
    WHERE is_valid AND start_station_id IS NOT NULL
    GROUP BY start_station_id
)
SELECT RANK() OVER (ORDER BY d.trips DESC)                       AS rank,
       s.name                                                    AS station,
       d.trips,
       ROUND(100.0 * d.trips / SUM(d.trips) OVER (), 2)          AS pct_of_departures,
       d.pct_members
FROM departures AS d
JOIN core.station AS s USING (station_id)
ORDER BY d.trips DESC, s.name
LIMIT 15;

-- (b) Concentration: share of departures made by the top 1 %, 10 % and
--     20 % of stations. Grain: 1 row.
WITH per_station AS (
    SELECT start_station_id, COUNT(*) AS trips
    FROM mart.fact_trip
    WHERE is_valid AND start_station_id IS NOT NULL
    GROUP BY start_station_id
),
ranked AS (
    SELECT trips, PERCENT_RANK() OVER (ORDER BY trips DESC) AS pr FROM per_station
)
SELECT COUNT(*)                                                       AS stations,
       ROUND(100.0 * SUM(trips) FILTER (WHERE pr < 0.01) / SUM(trips), 1) AS pct_top1,
       ROUND(100.0 * SUM(trips) FILTER (WHERE pr < 0.10) / SUM(trips), 1) AS pct_top10,
       ROUND(100.0 * SUM(trips) FILTER (WHERE pr < 0.20) / SUM(trips), 1) AS pct_top20
FROM ranked;
