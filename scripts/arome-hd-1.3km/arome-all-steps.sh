#!/bin/bash
set -e

# ── Run modes ──────────────────────────────────────────────────────────────
# Usage: ./arome-all-steps.sh [--no-download] [--no-upload]
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
    echo "[1/5] Downloading latest AROME HD model files..."
    rm -f ./downloaded/arome__001__*.grib2
    python3 AROME_MF.py
    echo "[1/5] Download complete."
else
    echo "[1/5] Skipping download."
fi

# ── Step 2: Convert to per-parameter grib files ─────────────────────────────
echo "[2/5] Converting to per-parameter grib files..."

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

echo "[2/5] Per-parameter conversion complete."

# ── Step 3: Combine into ModelArea master file ─────────────────────────────
echo "[3/5] Combining parameters into ModelArea master grib file..."

cat ./extracted/AROME_Wind.grib2 ./extracted/AROME_Temperature.grib2 ./extracted/AROME_Humidity.grib2 \
    ./extracted/AROME_Gusts.grib2 ./extracted/AROME_Precipitation.grib2 \
    ./extracted/AROME_Pressure.grib2 ./extracted/AROME_CloudCover.grib2 \
    > AROME-ModelArea-alltime-allparams.grib2

echo "[3/5] Master file created."

# ── Step 4: Slice into area / time-window / parameter subsets ──────────────
echo "[4/5] Slicing into area, time-window, and parameter subsets..."

AREAS="ModelArea Zealand NorthSea Channel WaddenSea NorthSeaSouth LakeIJssel"
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

slice_area Zealand        3,4.5,51.2,52
slice_area NorthSea       0,9,51,56
slice_area Channel        0,2,49.3,51
slice_area WaddenSea      4.5,7.5,52.9,53.8
slice_area NorthSeaSouth  0,5,51,54
slice_area LakeIJssel     5,5.9,52.2,53.1

# Slice by time window (next day = step 0–30h)
for AREA in $AREAS; do
    grib_copy -w "$NEXTDAY" "AROME-${AREA}-alltime-allparams.grib2" "AROME-${AREA}-nextday-allparams.grib2"
done

# Slice by parameter subset (wind only)
for AREA in $AREAS; do
    grib_copy -w shortName=10u/10v "AROME-${AREA}-alltime-allparams.grib2" "AROME-${AREA}-alltime-windonly.grib2"
    grib_copy -w "$NEXTDAY" "AROME-${AREA}-alltime-windonly.grib2" "AROME-${AREA}-nextday-windonly.grib2"
done

mv AROME-* ./sliced/
echo "[4/5] Slicing complete. 28 files written to ./sliced/"

# ── Step 5: Generate overview page and upload ───────────────────────────────
echo "[5/5] Generating download overview page..."
python3 generate_overview.py

if [ "$DO_UPLOAD" = true ]; then
    echo "[5/5] Uploading grib files, images, and overview page to Google Storage..."
    gsutil -m cp ./sliced/AROME-*.grib2 gs://weatherfiles.com/models/arome-hd-1.3km/downloads/
    gsutil -m cp "$WWW_DIR/models/arome-hd-1.3km/img/"* gs://weatherfiles.com/models/arome-hd-1.3km/img/
    gsutil -h "Content-Type:text/html" -h "Cache-Control:no-cache, no-store, must-revalidate" cp "$WWW_DIR/models/arome-hd-1.3km/index.html" gs://weatherfiles.com/models/arome-hd-1.3km/

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
rm -f ./downloaded/arome__001__*.grib2
echo "Cleaned up downloaded files."

echo "Done."
