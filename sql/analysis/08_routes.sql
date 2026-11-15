-- =====================================================================
-- 08_routes.sql — Most common routes and round-trip hotspots.
-- =====================================================================

-- (a) Top 15 one-way routes (origin ≠ destination). Grain: 1 row per route.
SELECT RANK() OVER (ORDER BY COUNT(*) DESC)               AS rank,
       so.name                                            AS origin,
       sd.name                                            AS destination,
       COUNT(*)                                           AS trips,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.duration_min)::NUMERIC, 1) AS median_min,
       ROUND(100.0 * AVG((f.member_type = 'member')::INT), 1) AS pct_members
FROM mart.fact_trip AS f
JOIN core.station   AS so ON so.station_id = f.start_station_id
JOIN core.station   AS sd ON sd.station_id = f.end_station_id
WHERE f.is_valid AND f.is_docked AND NOT f.is_same_station
GROUP BY so.name, sd.name
ORDER BY trips DESC, so.name COLLATE "C", sd.name COLLATE "C"
LIMIT 15;

-- (b) Top 10 stations where people return to where they started: tourist
--     and leisure spots. Grain: 1 row per station.
SELECT RANK() OVER (ORDER BY COUNT(*) DESC)                AS rank,
       s.name                                              AS station,
       COUNT(*)                                            AS round_trips,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.duration_min)::NUMERIC, 1) AS median_min,
       ROUND(100.0 * AVG((f.member_type = 'casual')::INT), 1) AS pct_casual
FROM mart.fact_trip AS f
JOIN core.station   AS s ON s.station_id = f.start_station_id
WHERE f.is_valid AND f.is_same_station
GROUP BY s.name
ORDER BY round_trips DESC, s.name COLLATE "C"
LIMIT 10;
