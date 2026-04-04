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
    echo "[1/4] Downloading latest KNMI model file..."
    python3 KNMI.py
    rm -f ./downloaded/HA43*
    tar -xvf KNMIdownload.tar
    mv HA43* ./downloaded/
    mv KNMIdownload.tar ./downloaded/
    echo "[1/4] Download and extraction complete."
else
    echo "[1/4] Skipping download."
fi

# ── Step 2: Convert raw model output to per-parameter grib files ────────────
if [ "$DO_DOWNLOAD" = true ]; then
    echo "[2/4] Converting raw model output to per-parameter grib files..."

    grib_copy  -w indicatorOfParameter=33/34,level=10 ./downloaded/HA43* ./extracted/KNMI43Wind.grib
    grib_copy  -w indicatorOfParameter=11,level=2     ./downloaded/HA43* ./extracted/KNMI43Temperature.grib
    grib_copy  -w indicatorOfParameter=17             ./downloaded/HA43* ./extracted/KNMI43DewPointTemp.grib
    grib_copy  -w indicatorOfParameter=61             ./downloaded/HA43* ./extracted/KNMI43Precipitation.grib

    # Pressure: reassign level type to mean sea level
    grib_filter -o ./extracted/KNMI43Pressure.grib fix_pressure_filter.txt ./downloaded/HA43*

    # Humidity: extract fraction, then scale to percentage
    grib_copy  -w indicatorOfParameter=52 ./downloaded/HA43* ./extracted/KNMI43HumidityFraction.grib
    python3 ScaleFraction.py ./extracted/KNMI43HumidityFraction.grib ./extracted/KNMI43Humidity.grib

    # Gusts: extract U+V components, combine into magnitude
    grib_copy  -w indicatorOfParameter=162 ./downloaded/HA43* ./extracted/KNMI43GustU.grib
    grib_copy  -w indicatorOfParameter=163 ./downloaded/HA43* ./extracted/KNMI43GustV.grib
    python3 CombineGusts.py ./extracted/KNMI43GustU.grib ./extracted/KNMI43GustV.grib ./extracted/KNMI43Gusts.grib

    # Cloud cover: extract, fix level metadata, scale to percentage
    grib_copy  -w indicatorOfParameter=71 ./downloaded/HA43* ./extracted/KNMI43CloudCoverRaw.grib
    grib_filter -o ./extracted/KNMI43CloudCoverFraction.grib fix_tcdc_filter.txt ./extracted/KNMI43CloudCoverRaw.grib
    python3 ScaleFraction.py ./extracted/KNMI43CloudCoverFraction.grib ./extracted/KNMI43CloudCover.grib

    echo "[2/4] Per-parameter conversion complete."
else
    echo "[2/4] Skipping conversion (using existing files in extracted/)."
fi

# ── Step 3: Combine into ModelArea master file ─────────────────────────────
echo "[3/4] Combining parameters into ModelArea master grib file..."

grib_copy ./extracted/KNMI43Wind.grib ./extracted/KNMI43Temperature.grib ./extracted/KNMI43DewPointTemp.grib \
    ./extracted/KNMI43Precipitation.grib ./extracted/KNMI43Pressure.grib ./extracted/KNMI43Humidity.grib \
    ./extracted/KNMI43Gusts.grib ./extracted/KNMI43CloudCover.grib \
    KNMI43-ModelArea-alltime-allparams.grib

echo "[3/4] Master file created."

# ── Step 4: Slice into area / time-window / parameter subsets ──────────────
echo "[4/4] Slicing into area, time-window, and parameter subsets..."

NEXTDAY="P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30"
PARAMS="./extracted/KNMI43Wind.grib ./extracted/KNMI43Temperature.grib ./extracted/KNMI43DewPointTemp.grib ./extracted/KNMI43Precipitation.grib ./extracted/KNMI43Pressure.grib ./extracted/KNMI43Humidity.grib ./extracted/KNMI43Gusts.grib ./extracted/KNMI43CloudCover.grib"

# Slice each parameter individually by area then combine — avoids CDO dropping
# parameters when processing a multi-parameter GRIB1 file over small areas.
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
    grib_copy "${SLICED[@]}" "KNMI43-${AREA}-alltime-allparams.grib"
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

# Slice by time window (next day = P1 0–30h)
for AREA in $AREAS; do
    grib_copy -w "$NEXTDAY" KNMI43-${AREA}-alltime-allparams.grib KNMI43-${AREA}-nextday-allparams.grib
done

# Slice by parameter subset (wind only)
for AREA in $AREAS; do
    grib_copy -w indicatorOfParameter=33/34,level=10 KNMI43-${AREA}-alltime-allparams.grib KNMI43-${AREA}-alltime-windonly.grib
    grib_copy -w "$NEXTDAY" KNMI43-${AREA}-alltime-windonly.grib KNMI43-${AREA}-nextday-windonly.grib
done

mv KNMI43-* "$WWW_DIR/models/harm-nl-2km/downloads/"
echo "[4/4] Slicing complete."

# ── Cleanup ─────────────────────────────────────────────────────────────────
rm -f ./downloaded/HA43*
echo "Cleaned up downloaded files."
