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
WWW_DIR="$ROOT_DIR/www"
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
    rm -f ./downloaded/HA43*
    tar -xvf KNMIdownload.tar
    mv HA43* ./downloaded/
    mv KNMIdownload.tar ./downloaded/
    echo "[1/5] Download and extraction complete."
else
    echo "[1/5] Skipping download."
fi

# ── Step 2: Convert raw model output to per-parameter grib files ────────────
echo "[2/5] Converting raw model output to per-parameter grib files..."

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

echo "[2/5] Per-parameter conversion complete."

# ── Step 3: Combine into ModelArea master file ─────────────────────────────
echo "[3/5] Combining parameters into ModelArea master grib file..."

grib_copy ./extracted/KNMI43Wind.grib ./extracted/KNMI43Temperature.grib ./extracted/KNMI43DewPointTemp.grib \
    ./extracted/KNMI43Precipitation.grib ./extracted/KNMI43Pressure.grib ./extracted/KNMI43Humidity.grib \
    ./extracted/KNMI43Gusts.grib ./extracted/KNMI43CloudCover.grib \
    KNMI43-ModelArea-alltime-allparams.grib

echo "[3/5] Master file created."

# ── Step 4: Slice into area / time-window / parameter subsets ──────────────
echo "[4/5] Slicing into area, time-window, and parameter subsets..."

AREAS="ModelArea Zealand NorthSea Channel WaddenSea NorthSeaSouth LakeIJssel"
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

mv KNMI43-* ./sliced/
echo "[4/5] Slicing complete. 28 files written to ./sliced/"

# ── Step 5: Generate overview page and upload ───────────────────────────────
echo "[5/5] Generating download overview page..."
python3 generate_overview.py

if [ "$DO_UPLOAD" = true ]; then
    echo "[5/5] Uploading grib files, images, and overview page to Google Storage..."
    gsutil -m cp ./sliced/KNMI43-*.grib gs://weatherfiles.com/models/harm-nl-2km/downloads/
    gsutil -m cp "$WWW_DIR/models/harm-nl-2km/img/"* gs://weatherfiles.com/models/harm-nl-2km/img/
    gsutil -h "Content-Type:text/html" -h "Cache-Control:no-cache, no-store, must-revalidate" cp "$WWW_DIR/index.html" gs://weatherfiles.com
    gsutil -h "Content-Type:text/html" -h "Cache-Control:no-cache, no-store, must-revalidate" cp "$WWW_DIR/models/harm-nl-2km/index.html" gs://weatherfiles.com/models/harm-nl-2km/

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
rm -f ./downloaded/HA43*
echo "Cleaned up downloaded files."

echo "Done."
