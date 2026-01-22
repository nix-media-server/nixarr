from typing import Any, Optional
import argparse
import prowlarr
import pydantic
import pathlib
import logging
from nixarr_py.clients import prowlarr_client
from nixarr_py.utils import apply_config


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class App(pydantic.BaseModel):
    name: str
    implementation: str
    tags: list[str] = []
    fields: dict[str, Any] = {}

    model_config = pydantic.ConfigDict(extra="allow")

    def extras(self) -> dict[str, Any]:
        return self.__pydantic_extra__ if self.__pydantic_extra__ is not None else {}


class Indexer(pydantic.BaseModel):
    sort_name: str
    name: Optional[str] = None
    app_profile_name: str = "Default"
    tags: list[str] = []
    fields: dict[str, Any] = {}

    model_config = pydantic.ConfigDict(extra="allow")

    def extras(self) -> dict[str, Any]:
        return self.__pydantic_extra__ if self.__pydantic_extra__ is not None else {}


class SettingsSyncConfig(pydantic.BaseModel):
    tag_labels: list[str] = []
    app_configs: list[App] = []
    indexer_configs: list[Indexer] = []

    model_config = pydantic.ConfigDict(extra="forbid")


def sync_tags(tag_labels: list[str], api_client: prowlarr.ApiClient) -> None:
    tag_api = prowlarr.TagApi(api_client)
    existing_tags = tag_api.list_tag()
    existing_tag_labels = {tag.label for tag in existing_tags}

    for label in tag_labels:
        if label in existing_tag_labels:
            continue
        logger.info(f"Creating tag '{label}'")
        tag_api.create_tag(prowlarr.TagResource(label=label))


def sync_apps(app_configs: list[App], api_client: prowlarr.ApiClient) -> None:
    tag_api = prowlarr.TagApi(api_client)
    app_api = prowlarr.ApplicationApi(api_client)
    tags_by_label = {tag.label: tag for tag in tag_api.list_tag()}
    apps_by_name = {app.name: app for app in app_api.list_applications()}
    schemas_by_implementation = {
        schema.implementation: schema for schema in app_api.list_applications_schema()
    }
    for user_cfg in app_configs:
        logger.info(f"Syncing app '{user_cfg.name}'")
        if user_cfg.name in apps_by_name:
            insert_or_update = "update"
            app = apps_by_name[user_cfg.name]
            assert app.implementation == user_cfg.implementation, (
                f"Cannot change implementation of existing app '{user_cfg.name}' from '{app.implementation}' to '{user_cfg.implementation}'. Please delete the existing app first."
            )
        else:
            insert_or_update = "insert"
            app = schemas_by_implementation[user_cfg.implementation]
        user_dict = user_cfg.model_dump(exclude={"tags"})
        user_dict["tags"] = [tags_by_label[label].id for label in user_cfg.tags]
        arr_dict = app.model_dump()
        apply_config(user_src=user_dict, arr_dst=arr_dict)
        app = prowlarr.ApplicationResource.model_validate(arr_dict)
        if insert_or_update == "insert":
            app_api.create_applications(application_resource=app)
        else:
            app_api.update_applications(id=str(app.id), application_resource=app)


def sync_indexers(
    indexer_configs: list[Indexer], api_client: prowlarr.ApiClient
) -> None:
    tag_api = prowlarr.TagApi(api_client)
    indexer_api = prowlarr.IndexerApi(api_client)
    profiles_api = prowlarr.AppProfileApi(api_client)
    tags_by_label = {tag.label: tag for tag in tag_api.list_tag()}
    indexers_by_name = {indexer.name: indexer for indexer in indexer_api.list_indexer()}
    schemas_by_sort_name = {
        schema.sort_name: schema for schema in indexer_api.list_indexer_schema()
    }
    app_profiles_by_name = {
        profile.name: profile.id for profile in profiles_api.list_app_profile()
    }
    for user_cfg in indexer_configs:
        schema = schemas_by_sort_name[user_cfg.sort_name]
        if user_cfg.name is None:
            user_cfg.name = schema.name
        logger.info(f"Syncing indexer '{user_cfg.name}'")
        if user_cfg.name in indexers_by_name:
            insert_or_update = "update"
            indexer = indexers_by_name[user_cfg.name]
            assert indexer.sort_name == user_cfg.sort_name, (
                f"Cannot change sortName of existing indexer '{user_cfg.name}' from '{indexer.sort_name}' to '{user_cfg.sort_name}'. Please delete the existing indexer first."
            )
        else:
            insert_or_update = "insert"
            indexer = schemas_by_sort_name[user_cfg.sort_name]
        user_dict = user_cfg.model_dump(exclude={"tags", "app_profile_name"})
        user_dict["tags"] = [tags_by_label[label].id for label in user_cfg.tags]
        user_dict["app_profile_id"] = app_profiles_by_name[user_cfg.app_profile_name]
        arr_dict = indexer.model_dump()
        apply_config(user_src=user_dict, arr_dst=arr_dict)
        indexer = prowlarr.IndexerResource.model_validate(arr_dict)
        if insert_or_update == "insert":
            indexer_api.create_indexer(indexer_resource=indexer)
        else:
            indexer_api.update_indexer(id=str(indexer.id), indexer_resource=indexer)


def main(config: SettingsSyncConfig, api_client: prowlarr.ApiClient) -> None:
    sync_tags(config.tag_labels, api_client)
    sync_apps(config.app_configs, api_client)
    sync_indexers(config.indexer_configs, api_client)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Sync user-provided Nixarr settings to Prowlarr"
    )
    parser.add_argument(
        "--config-file",
        type=pathlib.Path,
        required=True,
        help="Path to a config file containing the settings to sync. Must be a JSON file matching the SettingsSyncConfig schema.",
    )
    args = parser.parse_args()
    with open(args.config_file) as f:
        config_json = f.read()
    config = SettingsSyncConfig.model_validate_json(config_json)
    with prowlarr_client() as client:
        main(config, client)
