# Claude guidance

## Grib files
Never attempt to read a grib file directly (e.g. with the Read tool). Grib files are binary meteorological data files — reading them as text produces garbage. Only interact with them via tools that parse binary grib format (e.g. `eccodes`, `cfgrib`, `wgrib2`).
