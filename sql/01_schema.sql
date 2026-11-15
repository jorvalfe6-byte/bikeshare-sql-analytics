-- =====================================================================
-- 01_schema.sql — Modelo relacional Capital Bikeshare (PostgreSQL 14+)
--
-- Capas:
--   staging : copia 1:1 de los CSV, todo TEXT. Nunca falla por tipos.
--   core    : modelo tipado con PK, FK y CHECK. Conserva TODOS los viajes.
--   mart    : vistas analíticas; aquí se decide qué viaje cuenta como válido.
--   audit   : bitácora de cada carga.
--
-- Los timestamps del dataset no traen zona horaria (hora local de
-- Washington D. C.), por eso se usa TIMESTAMP y no TIMESTAMPTZ.
-- =====================================================================

SET client_min_messages = warning;  -- silencia los avisos de DROP ... CASCADE

DROP SCHEMA IF EXISTS mart    CASCADE;
DROP SCHEMA IF EXISTS core    CASCADE;
DROP SCHEMA IF EXISTS staging CASCADE;
DROP SCHEMA IF EXISTS audit   CASCADE;

CREATE SCHEMA staging;
CREATE SCHEMA core;
CREATE SCHEMA mart;
CREATE SCHEMA audit;

CREATE TABLE audit.load_log (
    load_id        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    table_name     TEXT        NOT NULL,
    rows_staged    BIGINT      NOT NULL,
    rows_loaded    BIGINT      NOT NULL,
    rows_rejected  BIGINT      GENERATED ALWAYS AS (rows_staged - rows_loaded) STORED,
    loaded_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- staging: mismas columnas que los CSV, todo texto
CREATE TABLE staging.trips (
    ride_id TEXT, rideable_type TEXT, started_at TEXT, ended_at TEXT,
    start_station_name TEXT, start_station_id TEXT,
    end_station_name TEXT,   end_station_id TEXT,
    start_lat TEXT, start_lng TEXT, end_lat TEXT, end_lng TEXT,
    member_casual TEXT
);

-- core -----------------------------------------------------------------
-- Una fila por estación física (id). Las bicis eléctricas pueden dejarse
-- fuera de una estación: esos viajes tienen la estación en NULL.
CREATE TABLE core.station (
    station_id  TEXT PRIMARY KEY,
    name        TEXT             NOT NULL,
    lat         DOUBLE PRECISION NOT NULL CHECK (lat  BETWEEN -90  AND 90),
    lng         DOUBLE PRECISION NOT NULL CHECK (lng  BETWEEN -180 AND 180)
);

CREATE TABLE core.trip (
    ride_id           TEXT      PRIMARY KEY,
    rideable_type     TEXT      NOT NULL CHECK (rideable_type IN ('classic_bike','electric_bike','electric_scooter')),
    member_type       TEXT      NOT NULL CHECK (member_type IN ('member','casual')),
    started_at        TIMESTAMP NOT NULL,
    ended_at          TIMESTAMP NOT NULL,
    start_station_id  TEXT REFERENCES core.station (station_id) ON DELETE RESTRICT,
    end_station_id    TEXT REFERENCES core.station (station_id) ON DELETE RESTRICT,
    start_lat         DOUBLE PRECISION,
    start_lng         DOUBLE PRECISION,
    end_lat           DOUBLE PRECISION,
    end_lng           DOUBLE PRECISION
);
