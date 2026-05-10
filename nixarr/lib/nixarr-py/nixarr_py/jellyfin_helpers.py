from typing import TextIO
import time
import jellyfin
import uuid


from nixarr_py.config import get_jellyfin_config


def unauthenticated_client() -> jellyfin.ApiClient:
    """Create an unauthenticated Jellyfin API client configured for use with Nixarr.

    Returns:
        jellyfin.ApiClient: API client instance configured to connect to
        the local Nixarr Jellyfin service without authentication.
    """
    cfg = get_jellyfin_config()
    client = jellyfin.ApiClient(
        jellyfin.Configuration(
            host=cfg.base_url,
        )
    )
    return client


def admin_user_client() -> jellyfin.ApiClient:
    """Create a Jellyfin API client configured for use with Nixarr, authenticated as an admin user.

    Note that Jellyfin only allows one active session per (user, device) pair,
    so using this client will invalidate any other sessions for the Nixarr user
    with the same device UUID (i.e. any other nixarr-py admin-user Jellyfin
    clients).

    Returns:
        jellyfin.ApiClient: API client instance configured to connect to
        the local Nixarr Jellyfin service as an admin user.
    """
    client = unauthenticated_client()
    cfg = get_jellyfin_config()
    with open(cfg.admin_password_file, "r", encoding="utf-8") as f:
        password = f.read().strip()
    assert password != ""
    with open(cfg.device_uuid_file, "r+", encoding="utf-8") as f:
        device_uuid = f.read().strip()
    uuid.UUID(device_uuid)  # Validate it's a proper UUID
    auth_header = f'MediaBrowser Client="nixarr-py", Device="nixarr-py", DeviceId="{device_uuid}", Version="1"'
    auth = jellyfin.UserApi(client).authenticate_user_by_name(
        jellyfin.AuthenticateUserByName(
            username=cfg.admin_username,
            pw=password,
        ),
        # The OpenAPI spec incorrectly says this endpoint doesn't require an
        # auth header, but Jellyfin will reject the request without one.
        _headers={"Authorization": auth_header},
    )
    auth_header += f', Token="{auth.access_token}"'
    assert isinstance(client.configuration, jellyfin.Configuration)
    client.configuration.api_key["CustomAuthentication"] = auth_header
    return client


def api_key_client() -> jellyfin.ApiClient:
    """Create a Jellyfin API client configured for use with Nixarr, using Nixarr's API key.

    Requires the Nixarr API key to have been created in Jellyfin, and stored in
    the configured file.

    Returns:
        jellyfin.ApiClient: API client instance configured to connect to
        the local Nixarr Jellyfin service.
    """
    cfg = get_jellyfin_config()
    with open(cfg.api_key_file, "r", encoding="utf-8") as f:
        api_key = f.read().strip()
    assert api_key != ""
    client = unauthenticated_client()
    assert isinstance(client.configuration, jellyfin.Configuration)
    client.configuration.api_key["CustomAuthentication"] = (
        f'MediaBrowser Token="{api_key}"'
    )
    return client


def ensure_api_key_and_file() -> None:
    """Create an API key for Nixarr in Jellyfin and store it in the configured file, if it doesn't already exist.

    Requires Jellyfin to be accessible, and for the admin user to exist.

    This uses an admin user client to fetch existing API keys and to create the
    Nixarr API key, so it will invalidate any other nixarr-py admin-user
    Jellyfin clients.
    """
    cfg = get_jellyfin_config()
    client = admin_user_client()
    api_keys = jellyfin.ApiKeyApi(client).get_keys()
    existing_api_key: str | None = None
    if cfg.api_key_file.is_file():
        with open(cfg.api_key_file, "r", encoding="utf-8") as f:
            existing_api_key = f.read().strip()
    if api_keys.items is not None:
        for item in api_keys.items:
            if item.app_name == "nixarr-py" and item.access_token is not None:
                # API key already exists
                if existing_api_key != item.access_token:
                    with open(cfg.api_key_file, "w", encoding="utf-8") as f:
                        f.write(item.access_token)
                    return

    # No existing API key found; create a new one
    jellyfin.ApiKeyApi(client).create_key("nixarr-py")
    api_keys = jellyfin.ApiKeyApi(client).get_keys()
    assert api_keys.items is not None
    for item in api_keys.items:
        if item.app_name == "nixarr-py" and item.access_token is not None:
            with open(cfg.api_key_file, "w", encoding="utf-8") as f:
                f.write(item.access_token)
            return


def ensure_admin_password_file() -> None:
    """Create the Jellyfin password file if it doesn't exist yet, and populate it with a random password if it's missing or empty.

    Doesn't require Jellyfin to be accessible, or for the admin user or Nixarr
    API key to exist.
    """
    cfg = get_jellyfin_config()
    file = cfg.admin_password_file

    def write_password(f: TextIO) -> None:
        import secrets
        import string

        alphabet = string.ascii_letters + string.digits + string.punctuation
        password = "".join(secrets.choice(alphabet) for _ in range(16))
        f.write(password)

    if file.is_file():
        with open(file, "r+", encoding="utf-8") as f:
            content = f.read().strip()
            if content == "":
                f.seek(0)
                f.truncate()
                write_password(f)
    else:
        with open(file, "w", encoding="utf-8") as f:
            write_password(f)


def ensure_device_uuid_file() -> None:
    """Create the Jellyfin device UUID file if it doesn't exist yet, and populate it with a random UUID if it's missing or empty.

    Doesn't require Jellyfin to be accessible, or for the admin user or Nixarr
    API key to exist.
    """
    cfg = get_jellyfin_config()
    file = cfg.device_uuid_file

    def write_device_uuid(f: TextIO) -> None:
        f.write(str(uuid.uuid4()))

    if file.is_file():
        with open(file, "r+", encoding="utf-8") as f:
            content = f.read().strip()
            if content == "":
                f.seek(0)
                f.truncate()
                write_device_uuid(f)
    else:
        with open(file, "w", encoding="utf-8") as f:
            write_device_uuid(f)


def ensure_admin_user_created_and_wizard_completed() -> None:
    """Create the Jellyfin user and complete the startup wizard if it hasn't been completed yet.

    This uses an admin user client to verify the user exists, so it will
    invalidate any other nixarr-py admin-user Jellyfin clients.
    """
    from jellyfin.exceptions import UnauthorizedException

    client = unauthenticated_client()
    wait_until_ready(client)

    startup_info = jellyfin.SystemApi(client).get_public_system_info()

    if startup_info.startup_wizard_completed is False:
        cfg = get_jellyfin_config()
        with open(cfg.admin_password_file, "r", encoding="utf-8") as f:
            password = f.read().strip()

        startup_api = jellyfin.StartupApi(client)
        # `get_first_user` creates the first user if it doesn't exist yet.
        startup_api.get_first_user()
        startup_api.update_startup_user(
            jellyfin.StartupUserDto(name=cfg.admin_username, password=password)
        )
        startup_api.complete_wizard()
        # Waiting *immediately* after completing the wizard seems to incorrectly
        # report that the server is ready, so we wait a bit before... waiting.
        time.sleep(5)
        wait_until_ready(client)

        # Verify admin user client works after completing wizard
        admin_user_client()
    else:
        # Wizard already completed - try to verify admin user client works
        # If authentication fails, it means the password file doesn't match
        # the actual Jellyfin user password (e.g., wizard was completed manually)
        try:
            admin_user_client()
        except UnauthorizedException:
            cfg = get_jellyfin_config()
            raise RuntimeError(
                f"Jellyfin wizard is already completed, but authentication failed. "
                f"The password in '{cfg.admin_password_file}' does not match the "
                f"password for the '{cfg.admin_username}' user in Jellyfin. "
                f"Please update the password file with the correct password."
            )


def wait_until_ready(client: jellyfin.ApiClient) -> None:
    """Wait until the Jellyfin server is ready to process requests.

    This function assumes that the Jellyfin server is already running and
    reachable, but may still be starting up. It polls the server until the
    server stops saying "try again later".

    Args:
        client: A Jellyfin API client (authorized or unauthorized).
    """
    from jellyfin.exceptions import ServiceException

    while True:
        try:
            jellyfin.SystemApi(client).get_public_system_info()
            break
        except ServiceException as e:
            # Jellyfin returns 503 to indicate that the server is still starting
            # up
            if e.status == 503:
                wait_secs = 5
                if e.headers and "Retry-After" in e.headers:
                    wait_secs = int(e.headers["Retry-After"])
                time.sleep(wait_secs)
            else:
                raise
