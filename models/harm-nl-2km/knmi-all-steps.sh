#!/bin/bash
set -e

# ── Run modes ──────────────────────────────────────────────────────────────
# Usage: ./knmi-all-steps.sh [--no-download] [--no-upload]
#   (default: full run — download, process, upload)

DO_DOWNLOAD=true
DO_UPLOAD=true

for arg in "$@"; do
    case $arg in
        --no-download) DO_DOWNLOAD=false ;;
        --no-upload)   DO_UPLOAD=false ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

# ── Paths ───────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$SCRIPT_DIR"

# ── Raspberry Pi environment setup ─────────────────────────────────────────
RUNNING_ON_PI=false

if [ "$RUNNING_ON_PI" = true ]; then
    export LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:$LD_LIBRARY_PATH
    if [ -f '/home/pi/google-cloud-sdk/path.bash.inc' ]; then . '/home/pi/google-cloud-sdk/path.bash.inc'; fi
    if [ -f '/home/pi/google-cloud-sdk/completion.bash.inc' ]; then . '/home/pi/google-cloud-sdk/completion.bash.inc'; fi
fi

# ── Step 1: Download ────────────────────────────────────────────────────────
if [ "$DO_DOWNLOAD" = true ]; then
    echo "[1/5] Downloading latest KNMI model file..."
    python3 KNMI.py
    rm -f ./extracted/HA43*
    tar -xvf KNMIdownload.tar
    mv HA43* ./extracted/
    echo "[1/5] Download and extraction complete."
else
    echo "[1/5] Skipping download."
fi

# ── Step 2: Convert raw model output to per-parameter grib files ────────────
echo "[2/5] Converting raw model output to per-parameter grib files..."

grib_copy  -w indicatorOfParameter=33/34,level=10 ./extracted/HA43* KNMI43Wind.grib
grib_copy  -w indicatorOfParameter=11,level=2     ./extracted/HA43* KNMI43Temperature.grib
grib_copy  -w indicatorOfParameter=17             ./extracted/HA43* KNMI43DewPointTemp.grib
grib_copy  -w indicatorOfParameter=61             ./extracted/HA43* KNMI43Precipitation.grib

# Pressure: reassign level type to mean sea level
grib_filter -o KNMI43Pressure.grib fix_pressure_filter.txt ./extracted/HA43*

# Humidity: extract fraction, then scale to percentage
grib_copy  -w indicatorOfParameter=52 ./extracted/HA43* KNMI43HumidityFraction.grib
python3 ScaleFraction.py KNMI43HumidityFraction.grib KNMI43Humidity.grib

# Gusts: extract U+V components, combine into magnitude
grib_copy  -w indicatorOfParameter=162 ./extracted/HA43* KNMI43GustU.grib
grib_copy  -w indicatorOfParameter=163 ./extracted/HA43* KNMI43GustV.grib
python3 CombineGusts.py KNMI43GustU.grib KNMI43GustV.grib KNMI43Gusts.grib

# Cloud cover: extract, fix level metadata, scale to percentage
grib_copy  -w indicatorOfParameter=71 ./extracted/HA43* KNMI43CloudCoverRaw.grib
grib_filter -o KNMI43CloudCoverFraction.grib fix_tcdc_filter.txt KNMI43CloudCoverRaw.grib
python3 ScaleFraction.py KNMI43CloudCoverFraction.grib KNMI43CloudCover.grib

echo "[2/5] Per-parameter conversion complete."

# ── Step 3: Combine into ModelArea master file ─────────────────────────────
echo "[3/5] Combining parameters into ModelArea master grib file..."

grib_copy KNMI43Wind.grib KNMI43Temperature.grib KNMI43DewPointTemp.grib \
    KNMI43Precipitation.grib KNMI43Pressure.grib KNMI43Humidity.grib \
    KNMI43Gusts.grib KNMI43CloudCover.grib \
    KNMI43-ModelArea-alltime-allparams.grib

echo "[3/5] Master file created."

# ── Step 4: Slice into area / time-window / parameter subsets ──────────────
echo "[4/5] Slicing into area, time-window, and parameter subsets..."

AREAS="ModelArea Zealand NorthSea Channel WaddenSea NorthSeaSouth LakeIJssel"
NEXTDAY="P1=0/1/2/3/4/5/6/7/8/9/10/11/12/13/14/15/16/17/18/19/20/21/22/23/24/25/26/27/28/29/30"
PARAMS="KNMI43Wind.grib KNMI43Temperature.grib KNMI43DewPointTemp.grib KNMI43Precipitation.grib KNMI43Pressure.grib KNMI43Humidity.grib KNMI43Gusts.grib KNMI43CloudCover.grib"

# Slice each parameter individually by area then combine — avoids CDO dropping
# parameters when processing a multi-parameter GRIB1 file over small areas.
slice_area() {
    local AREA=$1
    local BBOX=$2
    local TMPDIR=$(mktemp -d)
    local SLICED=()
    for PARAM in $PARAMS; do
        local OUT="$TMPDIR/${PARAM}"
        cdo sellonlatbox,$BBOX "$PARAM" "$OUT" 2>/dev/null
        SLICED+=("$OUT")
    done
    grib_copy "${SLICED[@]}" "KNMI43-${AREA}-alltime-allparams.grib"
    rm -rf "$TMPDIR"
}

slice_area Zealand        3,4.5,51.2,52
slice_area NorthSea       0,9,51,56
slice_area Channel        0,2,49.3,51
slice_area WaddenSea      4.5,7.5,52.9,53.8
slice_area NorthSeaSouth  0,5,51,54
slice_area LakeIJssel     5,5.9,52.2,53.1

# Slice by time window (next day = P1 0–30h)
for AREA in $AREAS; do
    grib_copy -w "$NEXTDAY" KNMI43-${AREA}-alltime-allparams.grib KNMI43-${AREA}-nextday-allparams.grib
done

# Slice by parameter subset (wind only)
for AREA in $AREAS; do
    grib_copy -w indicatorOfParameter=33/34,level=10 KNMI43-${AREA}-alltime-allparams.grib KNMI43-${AREA}-alltime-windonly.grib
    grib_copy -w "$NEXTDAY" KNMI43-${AREA}-alltime-windonly.grib KNMI43-${AREA}-nextday-windonly.grib
done

mv KNMI43-* ./downloads/
echo "[4/5] Slicing complete. 28 files written to ./downloads/"

# ── Step 5: Generate overview page and upload ───────────────────────────────
echo "[5/5] Generating download overview page..."
python3 generate_overview.py

if [ "$DO_UPLOAD" = true ]; then
    echo "[5/5] Uploading grib files, images, and overview page to Google Storage..."
    gsutil -m cp ./downloads/KNMI43-*.grib gs://weatherfiles.com
    gsutil -m cp ./img/* gs://weatherfiles.com/img/
    gsutil -h "Content-Type:text/html" -h "Cache-Control:no-cache, no-store, must-revalidate" cp "$ROOT_DIR/index.html" gs://weatherfiles.com
    gsutil -h "Content-Type:text/html" -h "Cache-Control:no-cache, no-store, must-revalidate" cp downloadoverview.html gs://weatherfiles.com

    echo "[5/5] Purging Cloudflare cache..."
    source "$ROOT_DIR/.env"
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/purge_cache" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"purge_everything":true}' | python3 -c "import sys,json; r=json.load(sys.stdin); print('Cache purged OK' if r['success'] else f'Cache purge failed: {r[\"errors\"]}')"

    echo "[5/5] Upload complete."
else
    echo "[5/5] Skipping upload."
fi

# ── Cleanup ─────────────────────────────────────────────────────────────────
rm -f ./extracted/HA43*
echo "Cleaned up extracted files."

echo "Done."
