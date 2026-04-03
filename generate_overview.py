import json
from datetime import datetime, timezone


def format_utc(iso_string):
    dt = datetime.fromisoformat(iso_string).astimezone(timezone.utc)
    return dt.strftime("%Y-%m-%d %H:%M UTC")


def file_link(area, timewindow, paramset):
    filename = f"KNMI43-{area}-{timewindow}-{paramset}.grib"
    return f'<a href="{filename}">{filename}</a>'


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
    with open("pipeline_meta.json") as f:
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

    with open("downloadoverview.html", "w") as f:
        f.write(html)

    print("Generated downloadoverview.html")


if __name__ == "__main__":
    main()
