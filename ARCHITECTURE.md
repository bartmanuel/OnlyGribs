# Architecture

Python-based weather data pipeline orchestrated by `knmi-all-steps.sh`. Target audience: OpenPlotter/sailing users who need pre-sliced grib files.

## Tools used
- `eccodes` (`grib_copy`, `grib_filter`): grib extraction and field manipulation
- `cdo` (Climate Data Operators): geographic area subsetting (`sellonlatbox`)
- Python + `eccodes` library: custom transformations
- `gsutil`: upload to Google Cloud Storage (backend for weatherfiles.com)

## Pipeline stages

### 1. Download — `KNMI.py`
- Calls KNMI OpenData API (`harmonie_arome_cy43_p1`, version 1.0)
- Downloads latest file (sorted descending by creation date) as `KNMIdownload.tar`
- Currently commented out in the shell script (manual or separate run)

### 2. Extract
- `tar -xvf KNMIdownload.tar` → individual `HA43*.grib` files into `./extracted/`

### 3. Convert to standardized per-parameter grib files (root dir)
Each uses `grib_copy` or `grib_filter` + optional Python post-processing:

| Output file | Source param | Method | Notes |
|---|---|---|---|
| `KNMI43Wind.grib` | param 33/34, level 10 | `grib_copy` | U+V wind components |
| `KNMI43Temperature.grib` | param 11, level 2 | `grib_copy` | |
| `KNMI43DewPointTemp.grib` | param 17 | `grib_copy` | |
| `KNMI43Precipitation.grib` | param 61 | `grib_copy` | |
| `KNMI43Pressure.grib` | param 1 | `grib_filter` + `fix_pressure_filter.txt` | Reassigns level type to mean sea level |
| `KNMI43HumidityFraction.grib` | param 52 | `grib_copy` | Intermediate |
| `KNMI43Humidity.grib` | — | `ScaleFraction.py` | Multiplies fraction × 100 → percentage |
| `KNMI43GustU/V.grib` | param 162/163 | `grib_copy` | Intermediate U+V gust components |
| `KNMI43Gusts.grib` | — | `CombineGusts.py` | sqrt(U²+V²), sets param 180 / surface level 0 |
| `KNMI43CloudCoverRaw.grib` | param 71 | `grib_copy` | Intermediate |
| `KNMI43CloudCoverFraction.grib` | — | `grib_filter` + `fix_tcdc_filter.txt` | Sets shortName=tcc, typeOfLevel=entireAtmosphere |
| `KNMI43CloudCover.grib` | — | `ScaleFraction.py` | Multiplies fraction × 100 → percentage |

### 4. Combine into master file
`grib_copy` merges all 8 parameter files into:
`KNMI43-ModelArea-alltime-allparams.grib`

### 5. Slice by geographic area (`cdo sellonlatbox`)
6 regions, each producing `KNMI43-<Area>-alltime-allparams.grib`:

| Area | Lon | Lat |
|---|---|---|
| Zealand | 3–4.5 | 51.2–52 |
| NorthSea | 0–9 | 51–56 |
| Channel | 0–2 | 49.3–51 |
| WaddenSea | 4.5–7.5 | 52.9–53.8 |
| NorthSeaSouth | 0–5 | 51–54 |
| LakeIJssel | 5–5.9 | 52.2–53.1 |

### 6. Slice by time window
`grib_copy -w P1=0..30` applied to each area (and ModelArea) → `*-nextday-*` variants (P1 = forecast step hours 0–30)

### 7. Slice by parameter subset
`grib_copy -w indicatorOfParameter=33/34` applied to each area → `*-windonly.grib` variants (both alltime and nextday)

### 8. Move output files
All `KNMI43-*` files moved to `./downloads/` (28 files total: 7 areas × 2 time windows × 2 param sets)

### 9. Index
`downloadoverview.html` references all downloadable grib files.

### 10. Upload
`gsutil cp` uploads to `gs://weatherfiles.com` (Google Cloud Storage, backend of weatherfiles.com).
Upload step is currently TODO/commented out in the shell script.

## File naming convention
`KNMI43-<Area>-<timewindow>-<paramset>.grib`
- Area: ModelArea, Zealand, NorthSea, Channel, WaddenSea, NorthSeaSouth, LakeIJssel
- Time window: alltime, nextday (P1 0–30h)
- Param set: allparams, windonly

## Deployment note
Script has a `RUNNING_ON_PI` flag for Raspberry Pi deployment (sets `LD_LIBRARY_PATH`, loads Google Cloud SDK).
