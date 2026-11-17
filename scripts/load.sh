#!/usr/bin/env bash
# Full load: schema → staging → core → marts → dashboard views → checks.
# Usage:
#   export PGHOST=localhost PGUSER=postgres PGDATABASE=bikeshare
#   ./scripts/load.sh            # reads ./data by default
#   ./scripts/load.sh /path/to/csv
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DATA_DIR="${1:-$ROOT/data}"
PSQL=(psql -X -q -v ON_ERROR_STOP=1)

shopt -s nullglob
files=("$DATA_DIR"/*-capitalbikeshare-tripdata.csv)
if (( ${#files[@]} == 0 )); then
    echo "No *-capitalbikeshare-tripdata.csv files in $DATA_DIR" >&2
    echo "Run ./scripts/download_data.sh first." >&2
    exit 1
fi

echo "→ schema";  "${PSQL[@]}" -f "$ROOT/sql/01_schema.sql"
echo "→ staging (${#files[@]} files)"
for f in "${files[@]}"; do
    echo "   $(basename "$f")"
    "${PSQL[@]}" -c "\\copy staging.trips FROM '$f' WITH (FORMAT csv, HEADER true)"
done
echo "→ core";      "${PSQL[@]}" -f "$ROOT/sql/02_transform.sql"
echo "→ marts";     "${PSQL[@]}" -f "$ROOT/sql/03_marts.sql"
echo "→ dashboard"; "${PSQL[@]}" -f "$ROOT/sql/04_dashboard_views.sql"
echo "→ power bi";  "${PSQL[@]}" -f "$ROOT/sql/05_powerbi_views.sql"
echo "→ checks"
checks="$("${PSQL[@]}" -f "$ROOT/sql/analysis/00_data_quality.sql")"
echo "$checks"
if grep -q 'REVIEW' <<<"$checks"; then
    echo "Some data-quality checks say REVIEW: the load does not match the expected dataset." >&2
    exit 1
fi
echo "Done."
