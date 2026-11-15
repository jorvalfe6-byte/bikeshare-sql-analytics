-- =====================================================================
-- 03_marts.sql — Semantic layer for analysis and dashboards.
--
-- Business definitions used across the project:
--   * Valid trip : a trip that is physically plausible. Excluded, with the
--                  reason kept in invalid_reason (never silently dropped):
--                    - ends_before_start     : ended_at <= started_at
--                                              (includes 60 trips on 2024-11-03,
--                                              the hour clocks go back, which
--                                              timestamps without time zone
--                                              cannot represent)
--                    - under_60s_same_dock   : < 60 s and returned to the same
--                                              station (a failed undock)
--                    - over_24h              : > 24 h (bike lost or not docked)
--   * Duration   : minutes between ended_at and started_at.
--   * Docked trip: it starts and ends at a station. Electric bikes may be
--                  parked anywhere, so those trips have a NULL station
--                  (so do 4,908 classic-bike trips that were not docked).
-- =====================================================================
\set ON_ERROR_STOP on
SET client_min_messages = warning;

DROP MATERIALIZED VIEW IF EXISTS mart.fact_trip CASCADE;

CREATE MATERIALIZED VIEW mart.fact_trip AS
WITH base AS (
    SELECT t.*,
           EXTRACT(EPOCH FROM t.ended_at - t.started_at) AS seconds,
           -- explicit NOT NULL tests: comparing against a NULL station would
           -- turn these flags (and everything derived from them) into NULL
           (t.start_station_id IS NOT NULL AND t.end_station_id IS NOT NULL) AS is_docked,
           (t.start_station_id IS NOT NULL AND t.end_station_id IS NOT NULL
            AND t.start_station_id = t.end_station_id)                       AS is_same_station
    FROM core.trip AS t
),
flagged AS (
    SELECT *,
           CASE WHEN seconds <= 0                       THEN 'ends_before_start'
                WHEN seconds <  60 AND is_same_station  THEN 'under_60s_same_dock'
                WHEN seconds > 86400                    THEN 'over_24h'
           END AS invalid_reason
    FROM base
)
SELECT ride_id,
       rideable_type,
       member_type,
       started_at,
       ended_at,
       DATE_TRUNC('month', started_at)::DATE          AS trip_month,
       started_at::DATE                               AS trip_date,
       EXTRACT(HOUR FROM started_at)::SMALLINT        AS start_hour,
       EXTRACT(ISODOW FROM started_at)::SMALLINT      AS iso_dow,        -- 1 = Monday
       EXTRACT(ISODOW FROM started_at) >= 6           AS is_weekend,
       ROUND((seconds / 60.0)::NUMERIC, 2)            AS duration_min,
       start_station_id,
       end_station_id,
       is_docked,
       is_same_station,
       invalid_reason,
       invalid_reason IS NULL                         AS is_valid
FROM flagged;

CREATE UNIQUE INDEX ux_fact_trip        ON mart.fact_trip (ride_id);
CREATE INDEX ix_fact_trip_month         ON mart.fact_trip (trip_month) WHERE is_valid;
CREATE INDEX ix_fact_trip_start_station ON mart.fact_trip (start_station_id) WHERE is_valid;

ANALYZE mart.fact_trip;
