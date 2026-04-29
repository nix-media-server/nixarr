from typing import Any, Union
from nixarr_py.clients import sonarr_client
import sonarr
import json
import argparse


def main(client: sonarr.ApiClient, kind: str) -> None:
    schema: Union[dict[str, Any], list[dict[str, Any]]] = []
    if kind == "download_client":
        schema = [
            schema.model_dump()
            for schema in sonarr.DownloadClientApi(client).list_download_client_schema()
        ]
    else:
        raise ValueError(f"Unknown schema kind: {kind}")
    print(json.dumps(schema, sort_keys=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Fetch and display Sonarr settings schemas as JSON"
    )
    parser.add_argument(
        "kind",
        choices=[
            "download_client",
        ],
        help="Kind of schema to fetch",
    )
    args = parser.parse_args()
    with sonarr_client() as client:
        main(client, args.kind)
