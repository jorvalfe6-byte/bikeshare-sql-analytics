-- =====================================================================
-- 05_powerbi_views.sql — Star schema for the Power BI report.
--
-- 6.1 million trips do not belong in a CSV inside a Git repo, so the facts
-- are pre-aggregated at the finest grain the report needs. Every measure in
-- the report is a sum of these columns, so totals stay exact at any level.
-- Only valid trips (mart.fact_trip.is_valid) are included.
-- scripts/export_powerbi.sh writes each view to powerbi/data/*.csv.
--
--   fact_trips_hourly   grain: date x start hour x rider type x bike type
--   fact_station_month  grain: month x station x rider type
--   fact_duration       grain: rider type x bike type x 1-minute bucket (0-60, 60 = 60+)
--   dim_date            continuous 2024 calendar
--   dim_station         one row per station, with coordinates
--   dim_rider, dim_bike labels for rider type and bike type
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP SCHEMA IF EXISTS powerbi CASCADE;
CREATE SCHEMA powerbi;

CREATE VIEW powerbi.fact_trips_hourly AS
SELECT trip_date,
       start_hour,
       member_type,
       rideable_type,
       COUNT(*)                                     AS trips,
       ROUND(SUM(duration_min), 2)                  AS duration_min_sum,
       COUNT(*) FILTER (WHERE duration_min > 30)    AS trips_over_30min,
       COUNT(*) FILTER (WHERE is_same_station)      AS round_trips,
       COUNT(*) FILTER (WHERE NOT is_docked)        AS trips_outside_dock,
       COUNT(distance_km)                           AS trips_with_distance,
       ROUND(SUM(distance_km), 3)                   AS distance_km_sum
FROM mart.fact_trip
WHERE is_valid
GROUP BY trip_date, start_hour, member_type, rideable_type;

-- Starts and arrivals per station. The weekday 7-9 h window feeds the
-- rebalancing page: docks where more bikes arrive than leave fill up.
CREATE VIEW powerbi.fact_station_month AS
WITH starts AS (
    SELECT trip_month, start_station_id AS station_id, member_type,
           COUNT(*) AS starts,
           COUNT(*) FILTER (WHERE NOT is_weekend AND start_hour BETWEEN 7 AND 9) AS am_starts
    FROM mart.fact_trip
    WHERE is_valid AND start_station_id IS NOT NULL
    GROUP BY 1, 2, 3
),
arrivals AS (
    SELECT trip_month, end_station_id AS station_id, member_type,
           COUNT(*) AS arrivals,
           COUNT(*) FILTER (WHERE NOT is_weekend AND start_hour BETWEEN 7 AND 9) AS am_arrivals
    FROM mart.fact_trip
    WHERE is_valid AND end_station_id IS NOT NULL
    GROUP BY 1, 2, 3
)
SELECT COALESCE(s.trip_month, a.trip_month)   AS month_date,
       COALESCE(s.station_id, a.station_id)   AS station_id,
       COALESCE(s.member_type, a.member_type) AS member_type,
       COALESCE(s.starts, 0)                  AS starts,
       COALESCE(a.arrivals, 0)                AS arrivals,
       COALESCE(s.am_starts, 0)               AS am_starts,
       COALESCE(a.am_arrivals, 0)             AS am_arrivals
FROM starts AS s
FULL JOIN arrivals AS a
       ON a.trip_month = s.trip_month AND a.station_id = s.station_id AND a.member_type = s.member_type;

CREATE VIEW powerbi.fact_duration AS
SELECT member_type,
       rideable_type,
       LEAST(FLOOR(duration_min), 60)::INT AS minute_bucket,
       COUNT(*)                            AS trips
FROM mart.fact_trip
WHERE is_valid
GROUP BY 1, 2, 3;

CREATE VIEW powerbi.dim_date AS
SELECT d::DATE                                  AS date,
       EXTRACT(MONTH FROM d)::INT               AS month_num,
       TO_CHAR(d, 'Mon')                        AS month,
       EXTRACT(ISODOW FROM d)::INT              AS weekday_num,
       TO_CHAR(d, 'Dy')                         AS weekday,
       CASE WHEN EXTRACT(ISODOW FROM d) >= 6 THEN 'Weekend' ELSE 'Weekday' END AS day_type
FROM GENERATE_SERIES(DATE '2024-01-01', DATE '2024-12-31', INTERVAL '1 day') AS d;

CREATE VIEW powerbi.dim_station AS
SELECT station_id, name, lat, lng
FROM core.station;

CREATE VIEW powerbi.dim_rider AS
SELECT * FROM (VALUES ('member', 'Member'), ('casual', 'Casual')) AS r(member_type, rider);

CREATE VIEW powerbi.dim_bike AS
SELECT * FROM (VALUES ('classic_bike', 'Classic'), ('electric_bike', 'Electric'),
                      ('electric_scooter', 'Scooter')) AS b(rideable_type, bike);
