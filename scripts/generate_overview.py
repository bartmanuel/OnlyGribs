"""
Central generator for model download index pages.

Reads models_meta.json to find which models to generate, then for each model
reads <model-id>/model_meta.json and renders overview_template.html using
Python's string.Template (${variable} placeholders).

Run from any directory:
    python scripts/generate_overview.py
"""

import html
import json
from datetime import datetime, timezone
from pathlib import Path
from string import Template

SCRIPTS_DIR = Path(__file__).resolve().parent
ROOT_DIR = SCRIPTS_DIR.parent
WWW_DIR = ROOT_DIR / "www"
TEMPLATE_FILE = SCRIPTS_DIR / "overview_template.html"
HOMEPAGE_TEMPLATE_FILE = SCRIPTS_DIR / "homepage_template.html"


def format_utc(iso_string):
    dt = datetime.fromisoformat(iso_string).astimezone(timezone.utc)
    return dt.strftime("%Y-%m-%d %H:%M UTC")


def dl_cell(filename, size, primary):
    label = f"↓ {size}" if size else "↓"
    color = "text-primary font-bold" if primary else "text-on-surface hover:text-primary"
    return (
        f'<a class="dl" href="downloads/{filename}" title="{html.escape(filename)}">'
        f'<span class="dl-size {color}">{label}</span>'
        f'</a>'
    )


def render_card(area, prefix, ext, file_sizes, alltime_col, nextday_col):
    key = area["key"]
    img = area.get("img")
    label = html.escape(area["label"])
    subtitle = html.escape(area["subtitle"])

    fn_at_ap = f"{prefix}-{key}-alltime-allparams.{ext}"
    fn_nd_ap = f"{prefix}-{key}-nextday-allparams.{ext}"
    fn_at_wo = f"{prefix}-{key}-alltime-windonly.{ext}"
    fn_nd_wo = f"{prefix}-{key}-nextday-windonly.{ext}"

    header_media = (
        f'<img src="img/{img}" width="56" height="56" '
        f'class="shrink-0 grayscale opacity-75" alt="{label} coverage"/>'
        if img else
        '<div class="w-14 h-14 shrink-0 bg-surface-container-highest border border-outline-variant/40 '
        'flex items-center justify-center">'
        '<span class="material-symbols-outlined text-on-surface-variant">map</span></div>'
    )

    return f"""
    <div class="bg-surface flex flex-col shadow-[0_4px_20px_rgba(0,0,0,0.08)] border border-outline-variant/30">
      <div class="p-5 flex items-center gap-4 border-b border-outline-variant/20 bg-surface-container-low min-h-[5rem]">
        {header_media}
        <div>
          <div class="font-bold text-base leading-tight">{label}</div>
          <div class="text-[10px] font-mono text-on-surface-variant uppercase tracking-tight mt-0.5">{subtitle}</div>
        </div>
      </div>
      <table class="w-full text-[11px] font-mono border-collapse">
        <thead>
          <tr class="bg-surface-container-highest">
            <th class="p-3 text-left text-[9px] font-black uppercase tracking-widest text-on-surface-variant w-1/3"></th>
            <th class="p-3 text-left text-[9px] font-black uppercase tracking-widest text-on-surface-variant border-l border-outline-variant/20">{alltime_col}</th>
            <th class="p-3 text-left text-[9px] font-black uppercase tracking-widest text-on-surface-variant border-l border-outline-variant/20">{nextday_col}</th>
          </tr>
        </thead>
        <tbody>
          <tr class="border-t border-outline-variant/20">
            <td class="p-3 text-[9px] font-bold uppercase tracking-wider text-primary bg-surface-container-low/50">All Params</td>
            <td class="p-3 border-l border-outline-variant/20">{dl_cell(fn_at_ap, file_sizes.get(fn_at_ap, ""), True)}</td>
            <td class="p-3 border-l border-outline-variant/20">{dl_cell(fn_nd_ap, file_sizes.get(fn_nd_ap, ""), True)}</td>
          </tr>
          <tr class="border-t border-outline-variant/20">
            <td class="p-3 text-[9px] font-bold uppercase tracking-wider text-on-surface-variant bg-surface-container-low/50">Wind Only</td>
            <td class="p-3 border-l border-outline-variant/20">{dl_cell(fn_at_wo, file_sizes.get(fn_at_wo, ""), False)}</td>
            <td class="p-3 border-l border-outline-variant/20">{dl_cell(fn_nd_wo, file_sizes.get(fn_nd_wo, ""), False)}</td>
          </tr>
        </tbody>
      </table>
    </div>"""


def generate_for_model(model_id):
    meta_path = SCRIPTS_DIR / model_id / "model_meta.json"
    with open(meta_path, encoding="utf-8") as f:
        meta = json.load(f)

    prefix = meta["file_prefix"]
    ext = meta["file_extension"]
    file_sizes = meta.get("file_sizes", {})
    alltime_col = html.escape(meta.get("alltime_col_label", "All Time"))
    nextday_col = html.escape(meta.get("nextday_col_label", "Next Day"))

    cards_html = "".join(
        render_card(area, prefix, ext, file_sizes, alltime_col, nextday_col)
        for area in meta["areas"]
    )

    model_reference_time = format_utc(meta["model_reference_time"])
    source_publication_time = format_utc(meta["source_publication_time"])
    weatherfiles_publication_time = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    template = Template(TEMPLATE_FILE.read_text(encoding="utf-8"))
    output = template.safe_substitute(
        page_title=f'{meta["model_name"]} | Weatherfiles.com',
        model_name=html.escape(meta["model_name"]),
        model_h1=html.escape(meta["model_h1"]),
        model_subtitle=html.escape(meta["model_subtitle"]),
        source_pub_label=html.escape(meta["source_pub_label"]),
        source_credit=html.escape(meta["source_credit"]),
        model_reference_time=model_reference_time,
        source_publication_time=source_publication_time,
        weatherfiles_publication_time=weatherfiles_publication_time,
        cards_html=cards_html,
    )

    out_path = WWW_DIR / "models" / model_id / "index.html"
    out_path.write_text(output, encoding="utf-8")
    print(f"  Generated {out_path.relative_to(ROOT_DIR)}")


def render_model_card(model_id, meta):
    name = html.escape(meta["model_h1"])
    subtitle = html.escape(meta["model_subtitle"])
    ref_time = format_utc(meta["model_reference_time"]) if meta.get("model_reference_time") else "—"
    n_areas = len([a for a in meta.get("areas", []) if a.get("bbox")])

    return f"""
    <a href="models/{model_id}/" class="group bg-surface flex flex-col shadow-[0_4px_20px_rgba(0,0,0,0.08)] border border-outline-variant/30 hover:border-primary/40 transition-colors">
      <div class="p-6 flex-1">
        <div class="text-[9px] font-mono uppercase tracking-widest text-on-surface-variant mb-3">{html.escape(model_id)}</div>
        <div class="text-xl font-extrabold tracking-tight leading-tight mb-2 group-hover:text-primary transition-colors">{name}</div>
        <div class="text-[11px] font-mono text-on-surface-variant leading-snug">{subtitle}</div>
      </div>
      <div class="border-t border-outline-variant/20 px-6 py-4 bg-surface-container-low flex justify-between items-end font-mono text-[10px]">
        <div>
          <div class="text-on-surface-variant uppercase tracking-wider mb-1">Latest Run</div>
          <div class="font-bold">{ref_time}</div>
        </div>
        <div class="text-right">
          <div class="text-on-surface-variant uppercase tracking-wider mb-1">Regions</div>
          <div class="font-bold">{n_areas}</div>
        </div>
      </div>
    </a>"""


def generate_homepage(models_cfg):
    cards_html = ""
    for model in models_cfg["models"]:
        model_id = model["id"]
        meta_path = SCRIPTS_DIR / model_id / "model_meta.json"
        with open(meta_path, encoding="utf-8") as f:
            meta = json.load(f)
        cards_html += render_model_card(model_id, meta)

    generated_time = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    template = Template(HOMEPAGE_TEMPLATE_FILE.read_text(encoding="utf-8"))
    output = template.safe_substitute(
        model_cards_html=cards_html,
        generated_time=generated_time,
    )

    out_path = WWW_DIR / "index.html"
    out_path.write_text(output, encoding="utf-8")
    print(f"  Generated {out_path.relative_to(ROOT_DIR)}")


def main():
    with open(SCRIPTS_DIR / "models_meta.json", encoding="utf-8") as f:
        models_cfg = json.load(f)

    models = models_cfg["models"]
    print(f"Generating overview pages for {len(models)} model(s)...")
    for model in models:
        generate_for_model(model["id"])
    generate_homepage(models_cfg)
    print("Done.")


if __name__ == "__main__":
    main()
