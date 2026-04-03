import json
import logging
import os
import re
import sys
from datetime import datetime, timezone

import requests

logging.basicConfig()
logger = logging.getLogger(__name__)
logger.setLevel(os.environ.get("LOG_LEVEL", logging.INFO))


class OpenDataAPI:
    def __init__(self, api_token: str):
        self.base_url = "https://api.dataplatform.knmi.nl/open-data/v1"
        self.headers = {"Authorization": api_token}

    def __get_data(self, url, params=None):
        return requests.get(url, headers=self.headers, params=params).json()

    def list_files(self, dataset_name: str, dataset_version: str, params: dict):
        return self.__get_data(
            f"{self.base_url}/datasets/{dataset_name}/versions/{dataset_version}/files",
            params=params,
        )

    def get_file_url(self, dataset_name: str, dataset_version: str, file_name: str):
        return self.__get_data(
            f"{self.base_url}/datasets/{dataset_name}/versions/{dataset_version}/files/{file_name}/url"
        )


def download_file_from_temporary_download_url(download_url, filename):
    try:
        with requests.get(download_url, stream=True) as r:
            r.raise_for_status()
            with open(filename, "wb") as f:
                for chunk in r.iter_content(chunk_size=8192):
                    f.write(chunk)
    except Exception:
        logger.exception("Unable to download file using download URL")
        sys.exit(1)

    logger.info(f"Successfully downloaded dataset file to {filename}")


def main():
    api_key = "eyJvcmciOiI1ZTU1NGUxOTI3NGE5NjAwMDEyYTNlYjEiLCJpZCI6ImQzZTJkMDk5ZmNiODRlOGI4ZmE4YmJhNWU3ZmJhYmZkIiwiaCI6Im11cm11cjEyOCJ9"
    dataset_name = "harmonie_arome_cy43_p1"
#    dataset_name = "weather_maps"
    dataset_version = "1.0"
    logger.info(f"Fetching latest file of {dataset_name} version {dataset_version}")

    api = OpenDataAPI(api_token=api_key)

    # sort the files in descending order and only retrieve the first file
    params = {"maxKeys": 1, "orderBy": "created", "sorting": "desc"}
    response = api.list_files(dataset_name, dataset_version, params)
    logger.info(response)
    if "error" in response:
        logger.error(f"Unable to retrieve list of files: {response['error']}")
        sys.exit(1)

    for responseitem in response["files"]:
        latest_file = responseitem.get("filename")
        knmi_publication_time = responseitem.get("created")
        logger.info(f"Latest file is: {latest_file}")

        # Extract model reference time from filename e.g. HARM43_V1_P1_2026040312.tar
        match = re.search(r'(\d{10})\.tar$', latest_file)
        if match:
            dt_str = match.group(1)  # e.g. 2026040312
            model_reference_time = datetime.strptime(dt_str, "%Y%m%d%H").replace(tzinfo=timezone.utc).isoformat()
        else:
            model_reference_time = None

        # Save metadata for use by generate_overview.py
        meta = {
            "model_reference_time": model_reference_time,
            "knmi_publication_time": knmi_publication_time,
            "latest_filename": latest_file,
        }
        with open("pipeline_meta.json", "w") as f:
            json.dump(meta, f, indent=2)
        logger.info(f"Saved pipeline metadata: {meta}")

        # fetch the download url and download the file
        response2 = api.get_file_url(dataset_name, dataset_version, latest_file)
        download_file_from_temporary_download_url(response2["temporaryDownloadUrl"], "KNMIdownload.tar")



if __name__ == "__main__":
    main()




