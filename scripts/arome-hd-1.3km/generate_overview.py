import json
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent
ROOT_DIR = SCRIPT_DIR.parent.parent
WWW_DIR = ROOT_DIR / "www"

# File sizes are fixed for a given area/time/param selection and don't change between runs.
# Update after first full pipeline run.
FILE_SIZES = {
    "AROME-ModelArea-alltime-allparams.grib2":      "",
    "AROME-ModelArea-alltime-windonly.grib2":        "",
    "AROME-ModelArea-nextday-allparams.grib2":       "",
    "AROME-ModelArea-nextday-windonly.grib2":        "",
    "AROME-NorthSea-alltime-allparams.grib2":        "",
    "AROME-NorthSea-alltime-windonly.grib2":         "",
    "AROME-NorthSea-nextday-allparams.grib2":        "",
    "AROME-NorthSea-nextday-windonly.grib2":         "",
    "AROME-NorthSeaSouth-alltime-allparams.grib2":   "",
    "AROME-NorthSeaSouth-alltime-windonly.grib2":    "",
    "AROME-NorthSeaSouth-nextday-allparams.grib2":   "",
    "AROME-NorthSeaSouth-nextday-windonly.grib2":    "",
    "AROME-Channel-alltime-allparams.grib2":         "",
    "AROME-Channel-alltime-windonly.grib2":          "",
    "AROME-Channel-nextday-allparams.grib2":         "",
    "AROME-Channel-nextday-windonly.grib2":          "",
    "AROME-Zealand-alltime-allparams.grib2":         "",
    "AROME-Zealand-alltime-windonly.grib2":          "",
    "AROME-Zealand-nextday-allparams.grib2":         "",
    "AROME-Zealand-nextday-windonly.grib2":          "",
    "AROME-LakeIJssel-alltime-allparams.grib2":      "",
    "AROME-LakeIJssel-alltime-windonly.grib2":       "",
    "AROME-LakeIJssel-nextday-allparams.grib2":      "",
    "AROME-LakeIJssel-nextday-windonly.grib2":       "",
    "AROME-WaddenSea-alltime-allparams.grib2":       "",
    "AROME-WaddenSea-alltime-windonly.grib2":        "",
    "AROME-WaddenSea-nextday-allparams.grib2":       "",
    "AROME-WaddenSea-nextday-windonly.grib2":        "",
}


def format_utc(iso_string):
    dt = datetime.fromisoformat(iso_string).astimezone(timezone.utc)
    return dt.strftime("%Y-%m-%d %H:%M UTC")


def file_link(area, timewindow, paramset):
    filename = f"AROME-{area}-{timewindow}-{paramset}.grib2"
    size = FILE_SIZES.get(filename, "")
    size_str = f' <span style="color:#888;font-size:0.85em">({size})</span>' if size else ""
    return f'<a href="downloads/{filename}">{filename}</a>{size_str}'


def row(area, img, label):
    img_tag = f'<img src="img/{img}" width="100" height="100" /><br />' if img else ""
    return f"""
    <tr>
      <td rowspan="2">{img_tag}{label}</td>
      <td>All params</td>
      <td>{file_link(area, "alltime", "allparams")}</td>
      <td>{file_link(area, "nextday", "allparams")}</td>
    </tr>
    <tr>
      <td>Wind only</td>
      <td>{file_link(area, "alltime", "windonly")}</td>
      <td>{file_link(area, "nextday", "windonly")}</td>
    </tr>"""


def main():
    with open(SCRIPT_DIR / "pipeline_meta.json") as f:
        meta = json.load(f)

    model_reference_time = format_utc(meta["model_reference_time"])
    mf_publication_time = format_utc(meta["mf_publication_time"])
    weatherfiles_publication_time = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

    areas = [
        ("ModelArea",    None,                "Model Area"),
        ("NorthSea",     "NorthSea.png",      "North Sea"),
        ("NorthSeaSouth","NorthSeaSouth.png",  "North Sea South"),
        ("Channel",      "Channel.png",        "Channel"),
        ("Zealand",      "Zealand.png",        "Zealand"),
        ("LakeIJssel",   "LakeIJssel.png",     "Lake IJssel"),
        ("WaddenSea",    "WaddenSea.png",      "Wadden Sea"),
    ]

    rows = "".join(row(area, img, label) for area, img, label in areas)

    html = f"""<!DOCTYPE html>
<html>
<head>
  <title>AROME HD 1.3km Downloads</title>
</head>
<body>
  <h1>AROME HD 1.3km Downloads</h1>

  <table border="0" cellpadding="5" cellspacing="0">
    <tr><td><b>Model reference time:</b></td><td>{model_reference_time}</td></tr>
    <tr><td><b>Météo-France publication time:</b></td><td>{mf_publication_time}</td></tr>
    <tr><td><b>Weatherfiles publication time:</b></td><td>{weatherfiles_publication_time}</td></tr>
  </table>

  <br />

  <table border="1" cellpadding="5" cellspacing="0">
    <tr>
      <th>Region</th>
      <th></th>
      <th>All time (51h)</th>
      <th>Next Day Only (0–30h)</th>
    </tr>
    {rows}
  </table>
</body>
</html>
"""

    out_path = WWW_DIR / "models" / "arome-hd-1.3km" / "index.html"
    with open(out_path, "w") as f:
        f.write(html)

    print("Generated index.html")


if __name__ == "__main__":
    main()
