from typing import Any
import argparse
import json
import logging
import pathlib
import urllib.request
import urllib.error

import pydantic


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class SonarrConfig(pydantic.BaseModel):
    ip: str = "127.0.0.1"
    port: int = 8989
    base_url: str = ""
    ssl: bool = False
    apiKeyFile: str = ""
    sync_only_monitored_series: bool = False
    sync_only_monitored_episodes: bool = False

    model_config = pydantic.ConfigDict(extra="allow")


class RadarrConfig(pydantic.BaseModel):
    ip: str = "127.0.0.1"
    port: int = 7878
    base_url: str = ""
    ssl: bool = False
    apiKeyFile: str = ""
    sync_only_monitored_movies: bool = False

    model_config = pydantic.ConfigDict(extra="allow")


class SettingsSyncConfig(pydantic.BaseModel):
    bazarr_base_url: str
    bazarr_api_key_file: str
    sonarr: SonarrConfig | None = None
    radarr: RadarrConfig | None = None

    model_config = pydantic.ConfigDict(extra="forbid")


def make_request(
    base_url: str,
    api_key: str,
    endpoint: str,
    method: str = "GET",
    data: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Make a request to the Bazarr API."""
    url = f"{base_url}/api{endpoint}"
    headers = {
        "X-API-KEY": api_key,
        "Content-Type": "application/json",
    }

    request_data = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=request_data, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req, timeout=30) as response:
            response_data = response.read().decode("utf-8")
            if response_data:
                return json.loads(response_data)
            return {}
    except urllib.error.HTTPError as e:
        error_body = e.read().decode("utf-8") if e.fp else ""
        raise RuntimeError(f"HTTP {e.code} error for {url}: {error_body}") from e


def get_current_settings(base_url: str, api_key: str) -> dict[str, Any]:
    """Get current Bazarr settings."""
    return make_request(base_url, api_key, "/system/settings")


def save_settings(base_url: str, api_key: str, settings: dict[str, Any]) -> None:
    """Save settings to Bazarr."""
    make_request(base_url, api_key, "/system/settings", method="POST", data=settings)


def sync_sonarr(
    bazarr_base_url: str,
    bazarr_api_key: str,
    sonarr_config: SonarrConfig,
) -> None:
    """Sync Sonarr settings to Bazarr."""
    logger.info("Syncing Sonarr configuration to Bazarr")

    # Read API key from file
    apikey = ""
    if sonarr_config.apiKeyFile:
        with open(sonarr_config.apiKeyFile, "r", encoding="utf-8") as f:
            apikey = f.read().strip()

    settings = {
        "settings-sonarr-ip": sonarr_config.ip,
        "settings-sonarr-port": sonarr_config.port,
        "settings-sonarr-base_url": sonarr_config.base_url,
        "settings-sonarr-ssl": sonarr_config.ssl,
        "settings-sonarr-apikey": apikey,
        "settings-sonarr-only_monitored": sonarr_config.sync_only_monitored_series,
        "settings-sonarr-series_sync": 60,
        "settings-sonarr-episodes_sync": 60,
    }

    save_settings(bazarr_base_url, bazarr_api_key, settings)
    logger.info("Sonarr configuration synced successfully")


def sync_radarr(
    bazarr_base_url: str,
    bazarr_api_key: str,
    radarr_config: RadarrConfig,
) -> None:
    """Sync Radarr settings to Bazarr."""
    logger.info("Syncing Radarr configuration to Bazarr")

    # Read API key from file
    apikey = ""
    if radarr_config.apiKeyFile:
        with open(radarr_config.apiKeyFile, "r", encoding="utf-8") as f:
            apikey = f.read().strip()

    settings = {
        "settings-radarr-ip": radarr_config.ip,
        "settings-radarr-port": radarr_config.port,
        "settings-radarr-base_url": radarr_config.base_url,
        "settings-radarr-ssl": radarr_config.ssl,
        "settings-radarr-apikey": apikey,
        "settings-radarr-only_monitored": radarr_config.sync_only_monitored_movies,
        "settings-radarr-movies_sync": 60,
    }

    save_settings(bazarr_base_url, bazarr_api_key, settings)
    logger.info("Radarr configuration synced successfully")


def main(config: SettingsSyncConfig) -> None:
    # Read Bazarr API key
    with open(config.bazarr_api_key_file, "r", encoding="utf-8") as f:
        bazarr_api_key = f.read().strip()

    if config.sonarr is not None:
        sync_sonarr(config.bazarr_base_url, bazarr_api_key, config.sonarr)

    if config.radarr is not None:
        sync_radarr(config.bazarr_base_url, bazarr_api_key, config.radarr)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Sync user-provided Nixarr settings to Bazarr"
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
    main(config)
