#!/usr/bin/env bash
# Dumps the mart.dash_* views to the single JSON the dashboard reads.
# Only aggregates leave the database: no individual trip is published.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/docs/data/dashboard.json"
mkdir -p "$(dirname "$OUT")"

psql -X -q -At -v ON_ERROR_STOP=1 > "$OUT" <<'SQL'
SELECT json_build_object(
    -- date of the load, not of the export: exporting twice gives the same file
    'generated',     (SELECT to_char(MAX(loaded_at), 'YYYY-MM-DD') FROM audit.load_log),
    'kpis',          (SELECT row_to_json(k) FROM mart.dash_kpis k),
    'monthly',       (SELECT json_agg(m ORDER BY month)                         FROM mart.dash_monthly m),
    'hourly',        (SELECT json_agg(h ORDER BY member_type, day_type, hour)   FROM mart.dash_hourly h),
    'riders',        (SELECT json_agg(r ORDER BY member_type)                   FROM mart.dash_riders r),
    'stations',      (SELECT json_agg(s ORDER BY rank)                          FROM mart.dash_stations s),
    'concentration', (SELECT row_to_json(c) FROM mart.dash_concentration c),
    'rebalance',     (SELECT json_agg(b ORDER BY period DESC, behavior, abs(net_flow) DESC) FROM mart.dash_rebalance b),
    'leisure',       (SELECT json_agg(l ORDER BY rank)                          FROM mart.dash_leisure l),
    'routes',        (SELECT json_agg(r ORDER BY rank)                          FROM mart.dash_routes r),
    'heat',          (SELECT json_agg(h ORDER BY dow, hour)                     FROM mart.dash_heat h),
    'map',           (SELECT json_agg(m ORDER BY departures DESC, station)      FROM mart.dash_map m),
    'speed',         (SELECT json_agg(s ORDER BY rideable_type)                 FROM mart.dash_speed s),
    'duration',      (SELECT json_agg(d ORDER BY bucket)                        FROM mart.dash_duration d)
);
SQL

echo "→ $OUT ($(wc -c < "$OUT") bytes)"
