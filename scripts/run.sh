#!/bin/bash
set -e

# ── Run modes ──────────────────────────────────────────────────────────────
# Usage: ./scripts/run.sh [--no-download] [--no-upload]
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
SCRIPTS_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"
WWW_DIR="$ROOT_DIR/www"

# ── Raspberry Pi environment setup ─────────────────────────────────────────
RUNNING_ON_PI=false

if [ "$RUNNING_ON_PI" = true ]; then
    export LD_LIBRARY_PATH=/usr/lib/aarch64-linux-gnu:$LD_LIBRARY_PATH
    if [ -f '/home/pi/google-cloud-sdk/path.bash.inc' ]; then . '/home/pi/google-cloud-sdk/path.bash.inc'; fi
    if [ -f '/home/pi/google-cloud-sdk/completion.bash.inc' ]; then . '/home/pi/google-cloud-sdk/completion.bash.inc'; fi
fi

# ── Read model list ─────────────────────────────────────────────────────────
MODEL_IDS=$(python3 -c "
import json
with open('$SCRIPTS_DIR/models_meta.json') as f:
    models = json.load(f)['models']
for m in models:
    print(m['id'])
")

# ── Run per-model pipeline scripts ──────────────────────────────────────────
PIPELINE_ARGS=""
[ "$DO_DOWNLOAD" = false ] && PIPELINE_ARGS="--no-download"

for MODEL_ID in $MODEL_IDS; do
    echo ""
    echo "══════════════════════════════════════════════════════════════════"
    echo "  Model: $MODEL_ID"
    echo "══════════════════════════════════════════════════════════════════"
    PIPELINE="$SCRIPTS_DIR/$MODEL_ID/pipeline.sh"
    if [ ! -f "$PIPELINE" ]; then
        echo "ERROR: No pipeline.sh found at $PIPELINE"
        exit 1
    fi
    bash "$PIPELINE" $PIPELINE_ARGS
done

# ── Generate overview pages ─────────────────────────────────────────────────
echo ""
echo "Generating download overview pages..."
python3 "$SCRIPTS_DIR/generate_overview.py"

# ── Upload ──────────────────────────────────────────────────────────────────
if [ "$DO_UPLOAD" = true ]; then
    echo ""
    echo "Uploading to Google Cloud Storage..."

    for MODEL_ID in $MODEL_IDS; do
        read -r PREFIX EXT < <(python3 -c "
import json
with open('$SCRIPTS_DIR/$MODEL_ID/model_meta.json') as f:
    m = json.load(f)
print(m['file_prefix'], m['file_extension'])
")
        echo "  [$MODEL_ID] grib files..."
        gsutil -m cp "$WWW_DIR/models/$MODEL_ID/downloads/${PREFIX}-*.${EXT}" \
            "gs://weatherfiles.com/models/$MODEL_ID/downloads/"
        echo "  [$MODEL_ID] images..."
        gsutil -m cp "$WWW_DIR/models/$MODEL_ID/img/"* \
            "gs://weatherfiles.com/models/$MODEL_ID/img/"
        echo "  [$MODEL_ID] index.html..."
        gsutil -h "Content-Type:text/html" \
               -h "Cache-Control:no-cache, no-store, must-revalidate" \
               cp "$WWW_DIR/models/$MODEL_ID/index.html" \
               "gs://weatherfiles.com/models/$MODEL_ID/"
    done

    echo "  root index.html..."
    gsutil -h "Content-Type:text/html" \
           -h "Cache-Control:no-cache, no-store, must-revalidate" \
           cp "$WWW_DIR/index.html" "gs://weatherfiles.com"

    echo "Purging Cloudflare cache..."
    source "$ROOT_DIR/.env"
    curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${CLOUDFLARE_ZONE_ID}/purge_cache" \
        -H "Authorization: Bearer ${CLOUDFLARE_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data '{"purge_everything":true}' | python3 -c "import sys,json; r=json.load(sys.stdin); print('Cache purged OK' if r['success'] else f'Cache purge failed: {r[\"errors\"]}')"

    echo "Upload complete."
else
    echo "Skipping upload."
fi

echo ""
echo "Done."
