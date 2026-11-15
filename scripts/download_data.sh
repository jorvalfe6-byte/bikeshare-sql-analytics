#!/usr/bin/env bash
# Downloads the 12 monthly Capital Bikeshare files for a year (default 2024)
# from the operator's public bucket. No account needed. Needs Python 3
# (standard library only).
# Usage: ./scripts/download_data.sh [year] [destination_dir]   (default ./data)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
YEAR="${1:-2024}"
DEST="${2:-$ROOT/data}"
BASE="https://s3.amazonaws.com/capitalbikeshare-data"
mkdir -p "$DEST"

for m in 01 02 03 04 05 06 07 08 09 10 11 12; do
    echo "→ ${YEAR}${m}"
    # The zip is read in memory (no temp files). The CSV inside is not always
    # named like the zip (April 2024 says "202004"), and macOS zips carry a
    # __MACOSX folder: take the one real CSV and name it after the zip's month.
    python3 -I - "$BASE/${YEAR}${m}-capitalbikeshare-tripdata.zip" \
                 "$DEST/${YEAR}${m}-capitalbikeshare-tripdata.csv" <<'PY'
import io, shutil, sys, time, urllib.request, zipfile

url, out = sys.argv[1], sys.argv[2]
for attempt in range(1, 4):
    try:
        with urllib.request.urlopen(url, timeout=120) as r:
            data = r.read()
        break
    except OSError as e:
        if attempt == 3:
            sys.exit(f"Download failed: {url}: {e}")
        time.sleep(2 * attempt)

z = zipfile.ZipFile(io.BytesIO(data))
names = [n for n in z.namelist() if n.endswith(".csv") and not n.startswith("__MACOSX")]
if len(names) != 1:
    sys.exit(f"Expected exactly one CSV in {url}, found {names}")
with z.open(names[0]) as src, open(out, "wb") as dst:
    shutil.copyfileobj(src, dst)
PY
done
echo "Done: 12 CSV files in $DEST"
