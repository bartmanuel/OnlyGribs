#!/bin/bash
set -e

# ── Run modes ──────────────────────────────────────────────────────────────
# Usage: ./pipeline.sh [--no-download]
# Called by scripts/run.sh — upload and overview generation are handled there.

DO_DOWNLOAD=true

for arg in "$@"; do
    case $arg in
        --no-download) DO_DOWNLOAD=false ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

# ── Paths ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
WWW_DIR="$ROOT_DIR/www"
cd "$SCRIPT_DIR"

# ── Step 1: Download ────────────────────────────────────────────────────────
if [ "$DO_DOWNLOAD" = true ]; then
    echo "[1/4] Downloading latest AROME HD model files..."
    rm -f ./downloaded/arome__001__*.grib2
    python3 AROME_MF.py
    echo "[1/4] Download complete."
else
    echo "[1/4] Skipping download."
fi

# ── Step 2: Convert to per-parameter grib files ─────────────────────────────
if [ "$DO_DOWNLOAD" = true ]; then
    echo "[2/4] Converting to per-parameter grib files..."

    # Combine all hourly SP1 files (wind, temp, humidity, gusts) into one
    cat ./downloaded/arome__001__SP1__*H__*.grib2 > ./extracted/AROME_SP1_alltime.grib2

    # Combine all hourly SP2 files (precip, cloud, pressure) into one
    cat ./downloaded/arome__001__SP2__*H__*.grib2 > ./extracted/AROME_SP2_alltime.grib2

    # Extract per-parameter files from SP1
    grib_copy -w shortName=10u/10v              ./extracted/AROME_SP1_alltime.grib2 ./extracted/AROME_Wind.grib2
    grib_copy -w shortName=2t                   ./extracted/AROME_SP1_alltime.grib2 ./extracted/AROME_Temperature.grib2
    grib_copy -w shortName=2r                   ./extracted/AROME_SP1_alltime.grib2 ./extracted/AROME_Humidity.grib2
    grib_copy -w shortName=max_10efg/max_10nfg  ./extracted/AROME_SP1_alltime.grib2 ./extracted/AROME_GustComponents.grib2
    python3 CombineGusts_GRIB2.py ./extracted/AROME_GustComponents.grib2 ./extracted/AROME_Gusts.grib2

    # Extract per-parameter files from SP2
    grib_copy -w shortName=tirf ./extracted/AROME_SP2_alltime.grib2 ./extracted/AROME_Precipitation.grib2
    grib_copy -w shortName=sp   ./extracted/AROME_SP2_alltime.grib2 ./extracted/AROME_Pressure.grib2
    grib_copy -w shortName=lcc  ./extracted/AROME_SP2_alltime.grib2 ./extracted/AROME_CloudCover.grib2

    echo "[2/4] Per-parameter conversion complete."
else
    echo "[2/4] Skipping conversion (using existing files in extracted/)."
fi

# ── Step 3: Combine into ModelArea master file ─────────────────────────────
echo "[3/4] Combining parameters into ModelArea master grib file..."

cat ./extracted/AROME_Wind.grib2 ./extracted/AROME_Temperature.grib2 ./extracted/AROME_Humidity.grib2 \
    ./extracted/AROME_Gusts.grib2 ./extracted/AROME_Precipitation.grib2 \
    ./extracted/AROME_Pressure.grib2 ./extracted/AROME_CloudCover.grib2 \
    > AROME-ModelArea-alltime-allparams.grib2

echo "[3/4] Master file created."

# ── Step 4: Slice into area / time-window / parameter subsets ──────────────
echo "[4/4] Slicing into area, time-window, and parameter subsets..."

NEXTDAY="step=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30"
PARAMS="./extracted/AROME_Wind.grib2 ./extracted/AROME_Temperature.grib2 ./extracted/AROME_Humidity.grib2 ./extracted/AROME_Gusts.grib2 ./extracted/AROME_Precipitation.grib2 ./extracted/AROME_Pressure.grib2 ./extracted/AROME_CloudCover.grib2"

# Slice each parameter individually by area then combine — avoids CDO dropping
# parameters when processing a multi-parameter GRIB file over small areas.
slice_area() {
    local AREA=$1
    local BBOX=$2
    local TMPDIR=$(mktemp -d)
    local SLICED=()
    for PARAM in $PARAMS; do
        local OUT="$TMPDIR/$(basename $PARAM)"
        cdo sellonlatbox,$BBOX "$PARAM" "$OUT" 2>/dev/null
        SLICED+=("$OUT")
    done
    cat "${SLICED[@]}" > "AROME-${AREA}-alltime-allparams.grib2"
    rm -rf "$TMPDIR"
}

# Load areas from model_meta.json; slice each bounded area
AREAS=""
while IFS=$'\t' read -r AREA_ID AREA_BBOX; do
    AREAS="$AREAS $AREA_ID"
    [ "$AREA_BBOX" != "null" ] && slice_area "$AREA_ID" "$AREA_BBOX"
done < <(python3 -c "
import json
with open('model_meta.json') as f:
    areas = json.load(f)['areas']
for a in areas:
    print(a['key'] + '\t' + (a['bbox'] if a.get('bbox') else 'null'))
")
AREAS="${AREAS# }"

# Slice by time window (next day = step 0–30h)
for AREA in $AREAS; do
    grib_copy -w "$NEXTDAY" "AROME-${AREA}-alltime-allparams.grib2" "AROME-${AREA}-nextday-allparams.grib2"
done

# Slice by parameter subset (wind only)
for AREA in $AREAS; do
    grib_copy -w shortName=10u/10v "AROME-${AREA}-alltime-allparams.grib2" "AROME-${AREA}-alltime-windonly.grib2"
    grib_copy -w "$NEXTDAY" "AROME-${AREA}-alltime-windonly.grib2" "AROME-${AREA}-nextday-windonly.grib2"
done

mv AROME-* "$WWW_DIR/models/arome-hd-1.3km/downloads/"
echo "[4/4] Slicing complete."

# ── Cleanup ─────────────────────────────────────────────────────────────────
rm -f ./downloaded/arome__001__*.grib2
echo "Cleaned up downloaded files."
