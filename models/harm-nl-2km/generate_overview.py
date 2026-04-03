import json
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).parent

# File sizes are fixed for a given area/time/param selection and don't change between runs.
FILE_SIZES = {
    "KNMI43-ModelArea-alltime-allparams.grib":      "177 MiB",
    "KNMI43-ModelArea-alltime-windonly.grib":        "35 MiB",
    "KNMI43-ModelArea-nextday-allparams.grib":       "103 MiB",
    "KNMI43-ModelArea-nextday-windonly.grib":        "18 MiB",
    "KNMI43-NorthSea-alltime-allparams.grib":        "95 MiB",
    "KNMI43-NorthSea-alltime-windonly.grib":         "20 MiB",
    "KNMI43-NorthSea-nextday-allparams.grib":        "58 MiB",
    "KNMI43-NorthSea-nextday-windonly.grib":         "10 MiB",
    "KNMI43-NorthSeaSouth-alltime-allparams.grib":   "32 MiB",
    "KNMI43-NorthSeaSouth-alltime-windonly.grib":    "6.7 MiB",
    "KNMI43-NorthSeaSouth-nextday-allparams.grib":   "19 MiB",
    "KNMI43-NorthSeaSouth-nextday-windonly.grib":    "3.4 MiB",
    "KNMI43-Channel-alltime-allparams.grib":         "7.2 MiB",
    "KNMI43-Channel-alltime-windonly.grib":          "1.5 MiB",
    "KNMI43-Channel-nextday-allparams.grib":         "4.3 MiB",
    "KNMI43-Channel-nextday-windonly.grib":          "799 KiB",
    "KNMI43-Zealand-alltime-allparams.grib":         "2.5 MiB",
    "KNMI43-Zealand-alltime-windonly.grib":          "555 KiB",
    "KNMI43-Zealand-nextday-allparams.grib":         "1.5 MiB",
    "KNMI43-Zealand-nextday-windonly.grib":          "282 KiB",
    "KNMI43-LakeIJssel-alltime-allparams.grib":      "1.7 MiB",
    "KNMI43-LakeIJssel-alltime-windonly.grib":       "379 KiB",
    "KNMI43-LakeIJssel-nextday-allparams.grib":      "1.1 MiB",
    "KNMI43-LakeIJssel-nextday-windonly.grib":       "193 KiB",
    "KNMI43-WaddenSea-alltime-allparams.grib":       "5.7 MiB",
    "KNMI43-WaddenSea-alltime-windonly.grib":        "1.2 MiB",
    "KNMI43-WaddenSea-nextday-allparams.grib":       "3.5 MiB",
    "KNMI43-WaddenSea-nextday-windonly.grib":        "629 KiB",
}


def format_utc(iso_string):
    dt = datetime.fromisoformat(iso_string).astimezone(timezone.utc)
    return dt.strftime("%Y-%m-%d %H:%M UTC")


def file_link(area, timewindow, paramset):
    filename = f"KNMI43-{area}-{timewindow}-{paramset}.grib"
    size = FILE_SIZES.get(filename, "")
    size_str = f' <span style="color:#888;font-size:0.85em">({size})</span>' if size else ""
    return f'<a href="{filename}">{filename}</a>{size_str}'


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
    knmi_publication_time = format_utc(meta["knmi_publication_time"])
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
  <title>Weather File Downloads</title>
</head>
<body>
  <h1>Weather File Downloads</h1>

  <table border="0" cellpadding="5" cellspacing="0">
    <tr><td><b>KNMI model reference time:</b></td><td>{model_reference_time}</td></tr>
    <tr><td><b>KNMI model publication time:</b></td><td>{knmi_publication_time}</td></tr>
    <tr><td><b>Weatherfiles publication time:</b></td><td>{weatherfiles_publication_time}</td></tr>
  </table>

  <br />

  <table border="1" cellpadding="5" cellspacing="0">
    <tr>
      <th>Region</th>
      <th></th>
      <th>All time</th>
      <th>Next Day Only</th>
    </tr>
    {rows}
  </table>
</body>
</html>
"""

    with open(SCRIPT_DIR / "downloadoverview.html", "w") as f:
        f.write(html)

    print("Generated downloadoverview.html")


if __name__ == "__main__":
    main()
