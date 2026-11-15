-- =====================================================================
-- 04_dashboard_views.sql — Compact views that feed the dashboard.
-- Each one is the short version of a query in sql/analysis/.
-- scripts/export_dashboard.sh dumps them to docs/data/dashboard.json.
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP VIEW IF EXISTS mart.dash_kpis, mart.dash_monthly, mart.dash_hourly, mart.dash_riders,
                    mart.dash_stations, mart.dash_concentration, mart.dash_rebalance,
                    mart.dash_leisure, mart.dash_routes CASCADE;

-- KPIs (see analysis/01)
CREATE VIEW mart.dash_kpis AS
SELECT COUNT(*)                                                      AS trips,
       ROUND(COUNT(*)::NUMERIC / COUNT(DISTINCT trip_date))          AS trips_per_day,
       ROUND(100.0 * AVG((member_type = 'member')::INT), 1)          AS pct_members,
       ROUND(100.0 * AVG((rideable_type = 'electric_bike')::INT), 1) AS pct_electric,
       ROUND(100.0 * AVG((NOT is_docked)::INT), 1)                   AS pct_outside_dock,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_min)::NUMERIC, 1) AS median_min,
       COUNT(DISTINCT start_station_id)                              AS stations,
       MIN(trip_date)                                                AS first_day,
       MAX(trip_date)                                                AS last_day,
       (SELECT COUNT(*) FROM mart.fact_trip WHERE NOT is_valid)      AS excluded_trips
FROM mart.fact_trip
WHERE is_valid;

-- Monthly series (see analysis/02 and 05)
CREATE VIEW mart.dash_monthly AS
WITH m AS (
    SELECT trip_month AS month,
           COUNT(*) AS trips,
           ROUND(100.0 * AVG((member_type = 'casual')::INT), 1)          AS pct_casual,
           ROUND(100.0 * AVG((rideable_type = 'electric_bike')::INT), 1) AS pct_electric
    FROM mart.fact_trip WHERE is_valid GROUP BY trip_month
)
SELECT month, trips,
       ROUND(AVG(trips) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)) AS trips_ma3,
       pct_casual, pct_electric
FROM m;

-- Hourly profile (see analysis/03)
CREATE VIEW mart.dash_hourly AS
WITH days AS (
    SELECT is_weekend, COUNT(DISTINCT trip_date) AS n_days FROM mart.fact_trip WHERE is_valid GROUP BY is_weekend
)
SELECT f.member_type,
       CASE WHEN f.is_weekend THEN 'weekend' ELSE 'weekday' END AS day_type,
       f.start_hour AS hour,
       ROUND(COUNT(*)::NUMERIC / d.n_days) AS trips_per_day
FROM mart.fact_trip AS f JOIN days AS d USING (is_weekend)
WHERE f.is_valid
GROUP BY f.member_type, f.is_weekend, f.start_hour, d.n_days;

-- Members vs casual (see analysis/04)
CREATE VIEW mart.dash_riders AS
SELECT member_type,
       COUNT(*) AS trips,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS pct_trips,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY duration_min)::NUMERIC, 1) AS median_min,
       ROUND(100.0 * AVG(is_weekend::INT), 1) AS pct_weekend,
       ROUND(100.0 * AVG((NOT is_weekend AND (start_hour BETWEEN 7 AND 9 OR start_hour BETWEEN 16 AND 18))::INT), 1) AS pct_commute_hours,
       ROUND(100.0 * AVG((rideable_type = 'electric_bike')::INT), 1) AS pct_electric,
       ROUND(100.0 * AVG(is_same_station::INT), 1) AS pct_round_trip
FROM mart.fact_trip WHERE is_valid GROUP BY member_type;

-- Busiest stations (see analysis/06a)
CREATE VIEW mart.dash_stations AS
WITH d AS (
    SELECT start_station_id AS station_id, COUNT(*) AS trips,
           ROUND(100.0 * AVG((member_type = 'member')::INT), 1) AS pct_members
    FROM mart.fact_trip WHERE is_valid AND start_station_id IS NOT NULL GROUP BY 1
)
SELECT RANK() OVER (ORDER BY d.trips DESC) AS rank, s.name AS station, d.trips,
       ROUND(100.0 * d.trips / SUM(d.trips) OVER (), 2) AS pct_of_departures, d.pct_members
FROM d JOIN core.station AS s USING (station_id)
ORDER BY d.trips DESC, s.name
LIMIT 15;

-- Concentration (see analysis/06b)
CREATE VIEW mart.dash_concentration AS
WITH p AS (
    SELECT trips, PERCENT_RANK() OVER (ORDER BY trips DESC) AS pr
    FROM (SELECT COUNT(*) AS trips FROM mart.fact_trip
          WHERE is_valid AND start_station_id IS NOT NULL GROUP BY start_station_id) AS t
)
SELECT COUNT(*) AS stations,
       ROUND(100.0 * SUM(trips) FILTER (WHERE pr < 0.01) / SUM(trips), 1) AS pct_top1,
       ROUND(100.0 * SUM(trips) FILTER (WHERE pr < 0.10) / SUM(trips), 1) AS pct_top10,
       ROUND(100.0 * SUM(trips) FILTER (WHERE pr < 0.20) / SUM(trips), 1) AS pct_top20
FROM p;

-- Rebalancing (see analysis/07)
CREATE VIEW mart.dash_rebalance AS
WITH windows AS (
    SELECT CASE WHEN start_hour BETWEEN 7 AND 9 THEN 'morning'
                WHEN start_hour BETWEEN 16 AND 18 THEN 'evening' END AS period,
           start_station_id, end_station_id
    FROM mart.fact_trip
    WHERE is_valid AND is_docked AND NOT is_weekend
      AND (start_hour BETWEEN 7 AND 9 OR start_hour BETWEEN 16 AND 18)
),
flows AS (
    SELECT period, start_station_id AS station_id, COUNT(*) AS departures, 0 AS arrivals FROM windows GROUP BY 1, 2
    UNION ALL
    SELECT period, end_station_id, 0, COUNT(*) FROM windows GROUP BY 1, 2
),
net AS (
    SELECT period, station_id, SUM(departures) AS departures, SUM(arrivals) AS arrivals,
           SUM(arrivals) - SUM(departures) AS net_flow
    FROM flows GROUP BY 1, 2
),
ranked AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY period ORDER BY net_flow ASC,  station_id) AS drain_rank,
              ROW_NUMBER() OVER (PARTITION BY period ORDER BY net_flow DESC, station_id) AS fill_rank
    FROM net
)
SELECT r.period,
       CASE WHEN r.drain_rank <= 10 THEN 'drains' ELSE 'fills' END AS behavior,
       s.name AS station, r.departures, r.arrivals, r.net_flow
FROM ranked AS r JOIN core.station AS s USING (station_id)
WHERE r.drain_rank <= 10 OR r.fill_rank <= 10;

-- Round-trip (leisure) hotspots (see analysis/08b)
CREATE VIEW mart.dash_leisure AS
SELECT RANK() OVER (ORDER BY COUNT(*) DESC) AS rank, s.name AS station, COUNT(*) AS round_trips,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.duration_min)::NUMERIC, 1) AS median_min,
       ROUND(100.0 * AVG((f.member_type = 'casual')::INT), 1) AS pct_casual
FROM mart.fact_trip AS f JOIN core.station AS s ON s.station_id = f.start_station_id
WHERE f.is_valid AND f.is_same_station
GROUP BY s.name
ORDER BY round_trips DESC, station
LIMIT 10;

-- Top one-way routes (see analysis/08a)
CREATE VIEW mart.dash_routes AS
SELECT RANK() OVER (ORDER BY COUNT(*) DESC) AS rank, so.name AS origin, sd.name AS destination,
       COUNT(*) AS trips,
       ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY f.duration_min)::NUMERIC, 1) AS median_min,
       ROUND(100.0 * AVG((f.member_type = 'member')::INT), 1) AS pct_members
FROM mart.fact_trip AS f
JOIN core.station AS so ON so.station_id = f.start_station_id
JOIN core.station AS sd ON sd.station_id = f.end_station_id
WHERE f.is_valid AND f.is_docked AND NOT f.is_same_station
GROUP BY so.name, sd.name
ORDER BY trips DESC, origin, destination
LIMIT 10;
