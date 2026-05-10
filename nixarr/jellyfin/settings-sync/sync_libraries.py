"""Sync Jellyfin libraries from declarative configuration."""

import argparse
import json
import logging
import pathlib
import urllib.parse

import jellyfin
import pydantic
import requests

from nixarr_py.clients import jellyfin_client
from nixarr_py.config import get_jellyfin_config

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class LibraryConfig(pydantic.BaseModel):
    name: str
    type: str  # "movies", "tvshows", "music", "books", "mixed"
    paths: list[pathlib.Path]
    enabled: bool = True


class JellyfinLibrariesConfig(pydantic.BaseModel):
    libraries: list[LibraryConfig] = []


def get_library_type_name(lib_type: str) -> str:
    """Convert library type to Jellyfin collection type name."""
    type_map = {
        "movies": "movies",
        "tvshows": "tvshows",
        "music": "music",
        "books": "books",
        "mixed": "mixed",
    }
    return type_map.get(lib_type.lower(), "mixed")


def sync_libraries(config: JellyfinLibrariesConfig, client: jellyfin.ApiClient) -> int:
    """Sync libraries from configuration to Jellyfin.

    Creates libraries that don't exist and updates paths for existing libraries.

    Returns:
        0 on success, 1 on failure
    """
    library_api = jellyfin.LibraryApi(client)

    # Get existing libraries
    try:
        media_folders_response = library_api.get_media_folders()
        # The response might be a tuple or have an items attribute
        if isinstance(media_folders_response, tuple):
            media_folders = media_folders_response[0] if media_folders_response else []
        elif hasattr(media_folders_response, "items"):
            media_folders = media_folders_response.items or []
        else:
            media_folders = media_folders_response or []
        existing_libraries = {mf.name: mf for mf in media_folders}
    except Exception as e:
        logger.error(f"Failed to get existing libraries: {e}")
        logger.exception(e)
        return 1

    errors = []

    for lib_cfg in config.libraries:
        # Convert paths to strings
        path_strings = [str(p.resolve()) for p in lib_cfg.paths]

        # Ensure all paths exist
        for path in lib_cfg.paths:
            if not path.exists():
                logger.warning(
                    f"Path {path} for library '{lib_cfg.name}' does not exist. "
                    f"Creating it..."
                )
                try:
                    path.mkdir(parents=True, exist_ok=True)
                except Exception as e:
                    error_msg = f"Failed to create path {path}: {e}"
                    logger.error(error_msg)
                    errors.append(error_msg)
                    continue

        if lib_cfg.name not in existing_libraries:
            logger.info(f"Creating library '{lib_cfg.name}' with type '{lib_cfg.type}'")
            try:
                # Create the library using direct HTTP request
                # The generated Jellyfin SDK has a bug where pydantic validation
                # converts the CollectionTypeOptions enum to a string before the
                # serialization method can call .value on it, causing an AttributeError.
                cfg = get_jellyfin_config()
                with open(cfg.api_key_file, "r", encoding="utf-8") as f:
                    api_key = f.read().strip()

                # Build query string with multiple paths parameters
                query_parts = [
                    f"name={urllib.parse.quote(lib_cfg.name)}",
                    f"collectionType={get_library_type_name(lib_cfg.type)}",
                    "refreshLibrary=false",
                ]
                for path in path_strings:
                    query_parts.append(f"paths={urllib.parse.quote(path)}")

                url = f"{cfg.base_url}/Library/VirtualFolders?{'&'.join(query_parts)}"

                response = requests.post(
                    url,
                    headers={
                        "X-Emby-Token": api_key,
                        "Content-Type": "application/json",
                    },
                )
                response.raise_for_status()
                logger.info(f"Successfully created library '{lib_cfg.name}'")
            except Exception as e:
                error_msg = f"Failed to create library '{lib_cfg.name}': {e}"
                logger.error(error_msg)
                logger.exception(e)
                errors.append(error_msg)
        else:
            logger.info(
                f"Library '{lib_cfg.name}' already exists - skipping path updates for now"
            )
            # TODO: Implement path updates for existing libraries

    if errors:
        logger.error(f"Library sync completed with {len(errors)} error(s):")
        for error in errors:
            logger.error(f"  - {error}")
        return 1

    logger.info("Library sync completed successfully")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Sync Jellyfin libraries")
    parser.add_argument(
        "--config-file",
        type=pathlib.Path,
        required=True,
        help="Path to JSON config file containing libraries to sync",
    )
    args = parser.parse_args()

    try:
        config_json = args.config_file.read_text()
        config = JellyfinLibrariesConfig.model_validate(json.loads(config_json))
    except Exception as e:
        logger.error(f"Failed to load configuration: {e}")
        logger.exception(e)
        return 1

    if not config.libraries:
        logger.info("No libraries configured, nothing to do")
        return 0

    try:
        client = jellyfin_client()
    except Exception as e:
        logger.error(f"Failed to create Jellyfin client: {e}")
        logger.exception(e)
        return 1

    return sync_libraries(config, client)


if __name__ == "__main__":
    exit(main())
