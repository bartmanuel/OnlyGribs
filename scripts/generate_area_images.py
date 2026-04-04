"""
Generate map images for each geographic area defined in model_meta.json.

For each area this script renders an OSM base map composited with an
OpenSeaMap seamark overlay, draws the bounding box rectangle, and saves
a PNG to www/models/<model-id>/img/<area-key>.png.

ModelArea (bbox=null) gets an image derived from the union of all other
areas' bboxes, expanded by 20%, with no rectangle drawn.

Usage:
    python3 scripts/generate_area_images.py                  # all models
    python3 scripts/generate_area_images.py harm-nl-2km      # one model
"""

import json
import math
import sys
import warnings
from io import BytesIO
from pathlib import Path

import requests
from PIL import Image, ImageDraw

# Large canvases are expected — suppress the decompression bomb warning.
Image.MAX_IMAGE_PIXELS = None

SCRIPTS_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPTS_DIR.parent
WWW_DIR = ROOT_DIR / "www"

TILE_PX = 256
HEADERS = {"User-Agent": "WeatherfilesAreaMap/1.0 (weatherfiles.com)"}
OUT_W, OUT_H = 640, 260          # output image size in pixels
PRIMARY = (0, 84, 214)           # #0054d6


# ── Tile / projection math ───────────────────────────────────────────────────

def lon_to_tx(lon, z):
    return int((lon + 180) / 360 * 2**z)

def lat_to_ty(lat, z):
    lr = math.radians(lat)
    return int((1 - math.log(math.tan(lr) + 1 / math.cos(lr)) / math.pi) / 2 * 2**z)

def tx_to_lon(x, z):
    return x / 2**z * 360 - 180

def ty_to_lat(y, z):
    n = math.pi - 2 * math.pi * y / 2**z
    return math.degrees(math.atan(math.sinh(n)))


def choose_zoom(vlon_w, vlon_e, vlat_s, vlat_n, out_w, out_h, pad=1.2):
    """Pick the lowest zoom where the padded viewport still fills the output."""
    for z in range(4, 11):
        nx = lon_to_tx(vlon_e, z) - lon_to_tx(vlon_w, z) + 1
        ny = lat_to_ty(vlat_s, z) - lat_to_ty(vlat_n, z) + 1
        if nx * TILE_PX >= out_w / pad and ny * TILE_PX >= out_h / pad:
            return z
    return 10


# ── Tile fetching ────────────────────────────────────────────────────────────

def fetch_tile(url):
    r = requests.get(url, headers=HEADERS, timeout=15)
    r.raise_for_status()
    return Image.open(BytesIO(r.content)).convert("RGBA")


def stitch_layer(tx1, tx2, ty1, ty2, zoom, url_tpl, transparent_bg=False):
    """Fetch and stitch tiles into a single RGBA canvas."""
    nx = tx2 - tx1 + 1
    ny = ty2 - ty1 + 1
    bg = (0, 0, 0, 0) if transparent_bg else (249, 249, 249, 255)
    canvas = Image.new("RGBA", (nx * TILE_PX, ny * TILE_PX), bg)
    for ix, tx in enumerate(range(tx1, tx2 + 1)):
        for iy, ty in enumerate(range(ty1, ty2 + 1)):
            url = url_tpl.format(z=zoom, x=tx, y=ty)
            try:
                tile = fetch_tile(url)
                canvas.paste(tile, (ix * TILE_PX, iy * TILE_PX), tile if transparent_bg else None)
            except Exception as e:
                print(f"    tile {url}: {e}")
    return canvas


# ── Image generation ─────────────────────────────────────────────────────────

def generate_area_image(lon_w, lon_e, lat_s, lat_n, out_path, draw_box=True):
    pad_lon = (lon_e - lon_w) * 0.40
    pad_lat = (lat_n - lat_s) * 0.40
    vlon_w = lon_w - pad_lon
    vlon_e = lon_e + pad_lon
    vlat_s = lat_s - pad_lat
    vlat_n = lat_n + pad_lat

    z = choose_zoom(vlon_w, vlon_e, vlat_s, vlat_n, OUT_W, OUT_H)

    tx1 = lon_to_tx(vlon_w, z)
    tx2 = lon_to_tx(vlon_e, z)
    ty1 = lat_to_ty(vlat_n, z)
    ty2 = lat_to_ty(vlat_s, z)
    cw = (tx2 - tx1 + 1) * TILE_PX
    ch = (ty2 - ty1 + 1) * TILE_PX

    print(f"    zoom={z}, canvas={cw}x{ch}, tiles {tx2-tx1+1}x{ty2-ty1+1}")

    # OSM base
    osm_tpl = "https://tile.openstreetmap.org/{z}/{x}/{y}.png"
    base = stitch_layer(tx1, tx2, ty1, ty2, z, osm_tpl, transparent_bg=False)

    # OpenSeaMap seamark overlay
    sea_tpl = "https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png"
    seamarks = stitch_layer(tx1, tx2, ty1, ty2, z, sea_tpl, transparent_bg=True)
    base = Image.alpha_composite(base, seamarks)

    # Convert bbox coords → pixel coords on canvas
    canvas_lon_w = tx_to_lon(tx1, z)
    canvas_lon_e = tx_to_lon(tx2 + 1, z)
    canvas_lat_n = ty_to_lat(ty1, z)
    canvas_lat_s = ty_to_lat(ty2 + 1, z)
    lon_span = canvas_lon_e - canvas_lon_w
    lat_span = canvas_lat_n - canvas_lat_s

    def lpx(lon): return (lon - canvas_lon_w) / lon_span * cw
    def tpx(lat): return (canvas_lat_n - lat) / lat_span * ch

    x0, y0 = lpx(lon_w), tpx(lat_n)
    x1, y1 = lpx(lon_e), tpx(lat_s)

    if draw_box:
        # Semi-transparent fill
        overlay = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
        ImageDraw.Draw(overlay).rectangle([x0, y0, x1, y1], fill=(*PRIMARY, 30))
        base = Image.alpha_composite(base, overlay)
        # Solid outline
        ImageDraw.Draw(base).rectangle([x0, y0, x1, y1], outline=(*PRIMARY, 255), width=3)

    # Crop centred on bbox with generous context, then resize to output.
    # The crop box must have exactly OUT_W:OUT_H aspect ratio before resize
    # to avoid stretching the map.
    cx = (x0 + x1) / 2
    cy = (y0 + y1) / 2
    bbox_w = (x1 - x0) * 1.6
    bbox_h = (y1 - y0) * 1.6
    aspect = OUT_W / OUT_H
    cw2 = max(bbox_w, bbox_h * aspect)
    ch2 = cw2 / aspect

    # Clamp to canvas, then restore aspect ratio by expanding the short side
    left   = max(0, cx - cw2 / 2)
    top    = max(0, cy - ch2 / 2)
    right  = min(cw, cx + cw2 / 2)
    bottom = min(ch, cy + ch2 / 2)
    actual_w = right - left
    actual_h = bottom - top
    if actual_w / actual_h > aspect:
        # Too wide — trim width to match height
        excess = actual_w - actual_h * aspect
        left  += excess / 2
        right -= excess / 2
    else:
        # Too tall — trim height to match width
        excess = actual_h - actual_w / aspect
        top    += excess / 2
        bottom -= excess / 2

    box = (int(left), int(top), int(right), int(bottom))

    out_path.parent.mkdir(parents=True, exist_ok=True)
    base.crop(box).resize((OUT_W, OUT_H), Image.LANCZOS).convert("RGB").save(out_path, "PNG")
    print(f"    → {out_path.relative_to(ROOT_DIR)}")


# ── Main ─────────────────────────────────────────────────────────────────────

def union_bbox(areas):
    """Return (lon_w, lon_e, lat_s, lat_n) covering all bounded areas."""
    bboxes = [list(map(float, a["bbox"].split(","))) for a in areas if a.get("bbox")]
    lon_w = min(b[0] for b in bboxes)
    lon_e = max(b[1] for b in bboxes)
    lat_s = min(b[2] for b in bboxes)
    lat_n = max(b[3] for b in bboxes)
    # Expand 20% for context
    pad_lon = (lon_e - lon_w) * 0.20
    pad_lat = (lat_n - lat_s) * 0.20
    return lon_w - pad_lon, lon_e + pad_lon, lat_s - pad_lat, lat_n + pad_lat


def process_model(model_id):
    meta_path = SCRIPTS_DIR / model_id / "model_meta.json"
    with open(meta_path, encoding="utf-8") as f:
        meta = json.load(f)

    img_dir = WWW_DIR / "models" / model_id / "img"
    img_dir.mkdir(parents=True, exist_ok=True)

    all_areas = meta["areas"]
    print(f"  {len(all_areas)} areas")

    for area in all_areas:
        key = area["key"]
        out_file = img_dir / f"{key}.png"

        if area.get("bbox"):
            lon_w, lon_e, lat_s, lat_n = map(float, area["bbox"].split(","))
            draw_box = True
        else:
            # ModelArea: use the union of all other areas, no bbox rectangle
            lon_w, lon_e, lat_s, lat_n = union_bbox(all_areas)
            draw_box = False

        print(f"  [{key}] {'bbox=' + area['bbox'] if area.get('bbox') else 'union bbox'}")
        generate_area_image(lon_w, lon_e, lat_s, lat_n, out_file, draw_box=draw_box)


def main():
    with open(SCRIPTS_DIR / "models_meta.json", encoding="utf-8") as f:
        models_cfg = json.load(f)

    targets = sys.argv[1:] if len(sys.argv) > 1 else [m["id"] for m in models_cfg["models"]]

    for model_id in targets:
        print(f"\nModel: {model_id}")
        process_model(model_id)

    print("\nDone.")


if __name__ == "__main__":
    main()
