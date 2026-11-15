-- =====================================================================
-- 02_transform.sql — staging → core, in a single transaction.
-- Idempotent: empties core and reloads it. Every table leaves a row in
-- audit.load_log (rows read vs. rows loaded).
--
-- Cleaning decisions (all counted, none silent):
--   * 141 ride_ids appear twice: a trip that crosses midnight at the end
--     of a month is published in both monthly files, once with
--     millisecond timestamps. One copy is kept (the more precise one).
--   * Timestamps are truncated to the second so both copies agree.
--   * Station names have stray spaces and some ids were renamed over the
--     year: each id keeps its most frequent name.
--   * Empty strings become NULL. Electric bikes can be left outside a
--     dock, so ~1.2 M trips have no start/end station: that is real, not
--     missing data, and it is kept.
-- =====================================================================
\set ON_ERROR_STOP on

BEGIN;

TRUNCATE core.trip, core.station;
SET LOCAL work_mem = '256MB';   -- sorts over 6 M rows stay in memory

-- ---------------------------------------------------------------------
-- station: one row per station_id, built from every start and end point.
-- ---------------------------------------------------------------------
CREATE TEMP TABLE points ON COMMIT DROP AS
SELECT start_station_id AS station_id, TRIM(start_station_name) AS name,
       start_lat::DOUBLE PRECISION AS lat, start_lng::DOUBLE PRECISION AS lng
FROM staging.trips
WHERE NULLIF(start_station_id, '') IS NOT NULL AND NULLIF(start_lat, '') IS NOT NULL
UNION ALL
SELECT end_station_id, TRIM(end_station_name),
       end_lat::DOUBLE PRECISION, end_lng::DOUBLE PRECISION
FROM staging.trips
WHERE NULLIF(end_station_id, '') IS NOT NULL AND NULLIF(end_lat, '') IS NOT NULL;

INSERT INTO core.station (station_id, name, lat, lng)
WITH nombre AS (
    SELECT station_id, MODE() WITHIN GROUP (ORDER BY name COLLATE "C") AS name   -- fixed collation: ties must not depend on the server locale
    FROM points
    WHERE NULLIF(name, '') IS NOT NULL
    GROUP BY station_id
),
coords AS (
    -- the most repeated coordinate pair is the dock itself: docked bikes
    -- report it exactly, while e-bike GPS points scatter around it
    SELECT DISTINCT ON (station_id) station_id, lat, lng
    FROM (SELECT station_id, ROUND(lat::NUMERIC, 5) AS lat, ROUND(lng::NUMERIC, 5) AS lng, COUNT(*) AS n
          FROM points GROUP BY 1, 2, 3) AS t
    ORDER BY station_id, n DESC, lat, lng
)
SELECT n.station_id, n.name, c.lat::DOUBLE PRECISION, c.lng::DOUBLE PRECISION
FROM nombre AS n JOIN coords AS c USING (station_id);

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded)
SELECT 'core.station',
       (SELECT COUNT(DISTINCT station_id) FROM points),
       (SELECT COUNT(*) FROM core.station);

-- ---------------------------------------------------------------------
-- trip
-- ---------------------------------------------------------------------
INSERT INTO core.trip (ride_id, rideable_type, member_type, started_at, ended_at,
                       start_station_id, end_station_id,
                       start_lat, start_lng, end_lat, end_lng)
SELECT DISTINCT ON (ride_id)
       ride_id,
       rideable_type,
       member_casual,
       DATE_TRUNC('second', started_at::TIMESTAMP),
       DATE_TRUNC('second', ended_at::TIMESTAMP),
       NULLIF(start_station_id, ''),
       NULLIF(end_station_id, ''),
       NULLIF(start_lat, '')::DOUBLE PRECISION,
       NULLIF(start_lng, '')::DOUBLE PRECISION,
       NULLIF(end_lat,   '')::DOUBLE PRECISION,
       NULLIF(end_lng,   '')::DOUBLE PRECISION
FROM staging.trips
ORDER BY ride_id, LENGTH(started_at) DESC, started_at;   -- keep the more precise copy

INSERT INTO audit.load_log (table_name, rows_staged, rows_loaded)
SELECT 'core.trip', (SELECT COUNT(*) FROM staging.trips), (SELECT COUNT(*) FROM core.trip);

COMMIT;

CREATE INDEX IF NOT EXISTS ix_trip_started_at ON core.trip (started_at);
CREATE INDEX IF NOT EXISTS ix_trip_start_stn  ON core.trip (start_station_id);
CREATE INDEX IF NOT EXISTS ix_trip_end_stn    ON core.trip (end_station_id);

ANALYZE;
