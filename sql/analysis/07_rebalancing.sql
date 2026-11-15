-- =====================================================================
-- 07_rebalancing.sql — Which stations drain or flood during the commute?
-- Grain: 1 row per station and period (only the 10 most extreme each).
--
-- net_flow = arrivals - departures in the window. Negative: the station
-- loses bikes and the operator must bring more. Positive: it fills up and
-- docks run out. Only docked weekday trips with both stations are used,
-- so each trip counts as one departure and one arrival.
-- Windows: morning 7-9 h, evening 16-18 h (hour the trip starts).
-- =====================================================================
WITH windows AS (
    SELECT CASE WHEN start_hour BETWEEN 7  AND 9  THEN 'morning'
                WHEN start_hour BETWEEN 16 AND 18 THEN 'evening' END AS period,
           start_station_id, end_station_id
    FROM mart.fact_trip
    WHERE is_valid AND is_docked AND NOT is_weekend
      AND (start_hour BETWEEN 7 AND 9 OR start_hour BETWEEN 16 AND 18)
),
flows AS (
    SELECT period, start_station_id AS station_id, COUNT(*) AS departures, 0 AS arrivals
    FROM windows GROUP BY period, start_station_id
    UNION ALL
    SELECT period, end_station_id, 0, COUNT(*)
    FROM windows GROUP BY period, end_station_id
),
net AS (
    SELECT period, station_id,
           SUM(departures) AS departures,
           SUM(arrivals)   AS arrivals,
           SUM(arrivals) - SUM(departures) AS net_flow
    FROM flows GROUP BY period, station_id
),
ranked AS (
    SELECT *,
           ROW_NUMBER() OVER (PARTITION BY period ORDER BY net_flow ASC,  station_id) AS drain_rank,
           ROW_NUMBER() OVER (PARTITION BY period ORDER BY net_flow DESC, station_id) AS fill_rank
    FROM net
)
SELECT r.period,
       CASE WHEN r.drain_rank <= 10 THEN 'drains' ELSE 'fills' END AS behavior,
       s.name AS station,
       r.departures, r.arrivals, r.net_flow
FROM ranked AS r
JOIN core.station AS s USING (station_id)
WHERE r.drain_rank <= 10 OR r.fill_rank <= 10
ORDER BY r.period DESC, behavior DESC, r.net_flow * CASE WHEN r.drain_rank <= 10 THEN 1 ELSE -1 END;
