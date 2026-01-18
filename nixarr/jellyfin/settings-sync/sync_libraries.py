"""Sync Jellyfin libraries from declarative configuration."""

import argparse
import json
import logging
import pathlib

import jellyfin
import pydantic

from nixarr_py.clients import jellyfin_client

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
    """Convert our library type to Jellyfin's content type."""
    type_map = {
        "movies": "movies",
        "tvshows": "tvshows",
        "music": "music",
        "books": "books",
        "mixed": "mixed",
    }
    return type_map.get(lib_type.lower(), "mixed")


def sync_libraries(config: JellyfinLibrariesConfig, client: jellyfin.ApiClient) -> None:
    """Sync libraries from configuration to Jellyfin.

    Creates libraries that don't exist and updates paths for existing libraries.
    """
    library_api = jellyfin.LibraryApi(client)

    # Get existing libraries
    try:
        media_folders_response = library_api.get_media_folders()
        # The response might be a tuple or have an items attribute
        if isinstance(media_folders_response, tuple):
            media_folders = media_folders_response[0] if media_folders_response else []
        elif hasattr(media_folders_response, 'items'):
            media_folders = media_folders_response.items or []
        else:
            media_folders = media_folders_response or []
        existing_libraries = {mf.name: mf for mf in media_folders}
    except Exception as e:
        logger.error(f"Failed to get existing libraries: {e}")
        logger.exception(e)
        return

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
                    logger.error(f"Failed to create path {path}: {e}")
                    continue

        if lib_cfg.name not in existing_libraries:
            logger.info(f"Creating library '{lib_cfg.name}' with type '{lib_cfg.type}'")
            try:
                # Create the library using raw HTTP API
                # Build query parameters - paths need to be a list
                params = {
                    "name": lib_cfg.name,
                    "collectionType": get_library_type_name(lib_cfg.type),
                    "refreshLibrary": "false",
                    "paths": path_strings,
                }

                # Make the POST request
                client.call_api(
                    resource_path="/Library/VirtualFolders",
                    method="POST",
                    query_params=params,
                )
                logger.info(f"Successfully created library '{lib_cfg.name}'")
            except Exception as e:
                logger.error(f"Failed to create library '{lib_cfg.name}': {e}")
                logger.exception(e)
        else:
            logger.info(f"Library '{lib_cfg.name}' already exists - skipping path updates for now")
            # TODO: Implement path updates for existing libraries


def main():
    parser = argparse.ArgumentParser(description="Sync Jellyfin libraries")
    parser.add_argument(
        "--config-file",
        type=pathlib.Path,
        required=True,
        help="Path to JSON config file containing libraries to sync",
    )
    args = parser.parse_args()

    config_json = args.config_file.read_text()
    config = JellyfinLibrariesConfig.model_validate(json.loads(config_json))

    if not config.libraries:
        logger.info("No libraries configured, nothing to do")
        return

    client = jellyfin_client()
    sync_libraries(config, client)


if __name__ == "__main__":
    main()
