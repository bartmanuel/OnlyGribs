import json
import logging
import os
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path
import requests
import xml.etree.ElementTree as ET

SCRIPT_DIR = Path(__file__).parent
EXTRACTED_DIR = SCRIPT_DIR / "extracted"
BUCKET_BASE = "https://object.data.gouv.fr/meteofrance-pnt"
S3_NS = {"s3": "http://s3.amazonaws.com/doc/2006-03-01/"}

logging.basicConfig()
logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", logging.INFO))


def list_bucket(prefix, start_after=None, max_keys=100):
    params = f"list-type=2&max-keys={max_keys}&delimiter=/&prefix={prefix}"
    if start_after:
        params += f"&start-after={start_after}"
    resp = requests.get(f"{BUCKET_BASE}/?{params}")
    resp.raise_for_status()
    return ET.fromstring(resp.text)


def find_latest_run():
    """Return the S3 prefix for the most recent model run."""
    # Start 14 days ago to stay within one paginated response
    start = (datetime.now(timezone.utc) - timedelta(days=14)).strftime("%Y-%m-%d")
    start_after = f"pnt/{start}"

    all_prefixes = []
    token = None
    while True:
        params = f"list-type=2&max-keys=200&delimiter=/&prefix=pnt/&start-after={start_after}"
        if token:
            params += f"&continuation-token={token}"
        root = ET.fromstring(requests.get(f"{BUCKET_BASE}/?{params}").text)
        prefixes = [p.text for p in root.findall(".//s3:CommonPrefixes/s3:Prefix", S3_NS)]
        all_prefixes.extend(prefixes)
        truncated = root.findtext(".//s3:IsTruncated", namespaces=S3_NS)
        token = root.findtext(".//s3:NextContinuationToken", namespaces=S3_NS)
        if truncated != "true" or not token:
            break

    runs = sorted(p for p in all_prefixes if p != "pnt/")
    if not runs:
        raise RuntimeError("No model runs found in bucket")
    return runs[-1]  # e.g. 'pnt/2026-04-03T12:00:00Z/'


def list_package_files(run_prefix, package):
    prefix = f"{run_prefix}arome/001/{package}/"
    params = f"list-type=2&max-keys=100&prefix={prefix}"
    root = ET.fromstring(requests.get(f"{BUCKET_BASE}/?{params}").text)
    return [k.text for k in root.findall(".//s3:Contents/s3:Key", S3_NS)]


def download_file(key, dest_path):
    url = f"{BUCKET_BASE}/{key}"
    with requests.get(url, stream=True) as r:
        r.raise_for_status()
        with open(dest_path, "wb") as f:
            for chunk in r.iter_content(chunk_size=65536):
                f.write(chunk)


def main():
    EXTRACTED_DIR.mkdir(exist_ok=True)

    logger.info("Finding latest AROME HD run...")
    run_prefix = find_latest_run()
    run_dt_str = run_prefix.rstrip("/").split("/")[-1]  # '2026-04-03T12:00:00Z'
    logger.info(f"Latest run: {run_dt_str}")

    for package in ["SP1", "SP2"]:
        logger.info(f"Downloading {package} files...")
        keys = list_package_files(run_prefix, package)
        logger.info(f"  {len(keys)} files to download")
        for key in keys:
            filename = key.split("/")[-1]
            dest = EXTRACTED_DIR / filename
            if dest.exists():
                logger.info(f"  Skipping {filename} (exists)")
                continue
            logger.info(f"  {filename}")
            download_file(key, dest)

    meta = {
        "model_reference_time": run_dt_str,
        "mf_publication_time": datetime.now(timezone.utc).isoformat(),
        "run_prefix": run_prefix,
    }
    with open(SCRIPT_DIR / "pipeline_meta.json", "w") as f:
        json.dump(meta, f, indent=2)
    logger.info(f"Saved pipeline metadata: {meta}")


if __name__ == "__main__":
    main()
