"""
Pre-configured API clients for Nixarr-managed services.

Example usage:
    >>> from nixarr_py.clients import radarr_client
    >>> import radarr
    >>>
    >>> with radarr_client() as client:
    ...     api_info = radarr.ApiInfoApi(client).get_api()
"""

import jellyfin
import lidarr
import prowlarr
import radarr
import readarr
import sonarr
import whisparr

from nixarr_py.config import get_simple_service_config as _get_simple_service_config
from nixarr_py.jellyfin_helpers import (
    api_key_client as _jellyfin_api_key_client,
    unauthenticated_client as _jellyfin_unauthenticated_client,
)


def jellyfin_client() -> jellyfin.ApiClient:
    """Create a Jellyfin API client configured for use with Nixarr, using Nixarr's API key.

    Returns:
        jellyfin.ApiClient: API client instance configured to connect to
        the local Nixarr Jellyfin service.
    Example:
        >>> import jellyfin
        >>> from nixarr_py.clients import jellyfin_client
        >>> with jellyfin_client() as client:
        ...     system_client = jellyfin.SystemApi(client)
        ...     system_info = system_client.get_system_info()
    """
    return _jellyfin_api_key_client()


def jellyfin_client_unauthorized() -> jellyfin.ApiClient:
    """Create an unauthenticated Jellyfin API client configured for use with Nixarr.

    Returns:
        jellyfin.ApiClient: API client instance configured to connect to
        the local Nixarr Jellyfin service without authentication.
    Example:
        >>> import jellyfin
        >>> from nixarr_py.clients import jellyfin_client_unauthorized
        >>> with jellyfin_client_unauthorized() as client:
        ...     auth_header = 'MediaBrowser Client="app", Device="device", DeviceId="id", Version="1"'
        ...     auth_result = jellyfin.UserApi(client).authenticate_user_by_name(
        ...         jellyfin.AuthenticateUserByName(username="user", pw="password"),
        ...         _headers={"Authorization": auth_header}
        ...     )
    """
    return _jellyfin_unauthenticated_client()


def _make_arr_client(service: str, module):
    """Factory for creating *arr API clients.

    Args:
        service: The service name (e.g., "radarr", "sonarr")
        module: The devopsarr module (e.g., radarr, sonarr)

    Returns:
        An ApiClient instance configured for the service.
    """
    cfg = _get_simple_service_config(service)

    with open(cfg.api_key_file, "r", encoding="utf-8") as f:
        api_key = f.read().strip()

    configuration = module.Configuration(
        host=cfg.base_url,
        api_key={"X-Api-Key": api_key},
    )

    return module.ApiClient(configuration)


def lidarr_client() -> lidarr.ApiClient:
    """Create a Lidarr API client configured for use with Nixarr.

    Returns:
        lidarr.ApiClient: API client instance configured to connect to
        the local Nixarr Lidarr service.

    Example:
        >>> import lidarr
        >>> from nixarr_py.clients import lidarr_client
        >>>
        >>> with lidarr_client() as client:
        ...     api_info_client = lidarr.ApiInfoApi(client)
        ...     api_info = api_info_client.get_api()
    """
    return _make_arr_client("lidarr", lidarr)


def prowlarr_client() -> prowlarr.ApiClient:
    """Create a Prowlarr API client configured for use with Nixarr.

    Returns:
        prowlarr.ApiClient: API client instance configured to connect to
        the local Nixarr Prowlarr service.

    Example:
        >>> import prowlarr
        >>> from nixarr_py.clients import prowlarr_client
        >>>
        >>> with prowlarr_client() as client:
        ...     api_info_client = prowlarr.ApiInfoApi(client)
        ...     api_info = api_info_client.get_api()
    """
    return _make_arr_client("prowlarr", prowlarr)


def radarr_client() -> radarr.ApiClient:
    """Create a Radarr API client configured for use with Nixarr.

    Returns:
        radarr.ApiClient: API client instance configured to connect to
        the local Nixarr Radarr service.

    Example:
        >>> import radarr
        >>> from nixarr_py.clients import radarr_client
        >>>
        >>> with radarr_client() as client:
        ...     api_info_client = radarr.ApiInfoApi(client)
        ...     api_info = api_info_client.get_api()
    """
    return _make_arr_client("radarr", radarr)


def readarr_client() -> readarr.ApiClient:
    """Create a Readarr API client configured for use with Nixarr.

    Returns:
        readarr.ApiClient: API client instance configured to connect to
        the local Nixarr Readarr service.

    Example:
        >>> import readarr
        >>> from nixarr_py.clients import readarr_client
        >>>
        >>> with readarr_client() as client:
        ...     api_info_client = readarr.ApiInfoApi(client)
        ...     api_info = api_info_client.get_api()
    """
    return _make_arr_client("readarr", readarr)


def readarr_audiobook_client() -> readarr.ApiClient:
    """Create a Readarr-Audiobook API client configured for use with Nixarr.

    Returns:
        readarr.ApiClient: API client instance configured to connect to
        the local Nixarr Readarr-Audiobook service.

    Example:
        >>> import readarr
        >>> from nixarr_py.clients import readarr_audiobook_client
        >>>
        >>> with readarr_audiobook_client() as client:
        ...     api_info_client = readarr.ApiInfoApi(client)
        ...     api_info = api_info_client.get_api()
    """
    return _make_arr_client("readarr-audiobook", readarr)


def sonarr_client() -> sonarr.ApiClient:
    """Create a Sonarr API client configured for use with Nixarr.

    Returns:
        sonarr.ApiClient: API client instance configured to connect to
        the local Nixarr Sonarr service.

    Example:
        >>> import sonarr
        >>> from nixarr_py.clients import sonarr_client
        >>>
        >>> with sonarr_client() as client:
        ...     api_info_client = sonarr.ApiInfoApi(client)
        ...     api_info = api_info_client.get_api()
    """
    return _make_arr_client("sonarr", sonarr)


def whisparr_client() -> whisparr.ApiClient:
    """Create a Whisparr API client configured for use with Nixarr.

    Returns:
        whisparr.ApiClient: API client instance configured to connect to
        the local Nixarr Whisparr service.

    Example:
        >>> import whisparr
        >>> from nixarr_py.clients import whisparr_client
        >>>
        >>> with whisparr_client() as client:
        ...     api_info_client = whisparr.ApiInfoApi(client)
        ...     api_info = api_info_client.get_api()
    """
    return _make_arr_client("whisparr", whisparr)
