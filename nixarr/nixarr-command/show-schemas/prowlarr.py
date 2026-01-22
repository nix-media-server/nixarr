from typing import Any, Union
from nixarr_py.clients import prowlarr_client
import prowlarr
import json
import argparse


def main(client: prowlarr.ApiClient, kind: str) -> None:
    schema: Union[dict[str, Any], list[dict[str, Any]]] = []
    if kind == "application":
        schema = [
            schema.model_dump()
            for schema in prowlarr.ApplicationApi(client).list_applications_schema()
        ]
    elif kind == "app_profile":
        schema = prowlarr.AppProfileApi(client).get_app_profile_schema().model_dump()
    elif kind == "download_client":
        schema = [
            schema.model_dump()
            for schema in prowlarr.DownloadClientApi(
                client
            ).list_download_client_schema()
        ]
    elif kind == "indexer":
        schema = [
            schema.model_dump()
            for schema in prowlarr.IndexerApi(client).list_indexer_schema()
        ]
    elif kind == "indexer_proxy":
        schema = [
            schema.model_dump()
            for schema in prowlarr.IndexerProxyApi(client).list_indexer_proxy_schema()
        ]
    elif kind == "notification":
        schema = [
            schema.model_dump()
            for schema in prowlarr.NotificationApi(client).list_notification_schema()
        ]
    else:
        raise ValueError(f"Unknown schema kind: {kind}")
    print(json.dumps(schema, sort_keys=True))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Fetch and display Prowlarr settings schemas as JSON"
    )
    parser.add_argument(
        "kind",
        choices=[
            "application",
            "app_profile",
            "download_client",
            "indexer",
            "indexer_proxy",
            "notification",
        ],
        help="Kind of schema to fetch",
    )
    args = parser.parse_args()
    with prowlarr_client() as client:
        main(client, args.kind)
