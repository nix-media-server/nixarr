import time

import jellyfin

from nixarr_py.clients import jellyfin_client_unauthorized
from nixarr_py.config import get_jellyfin_config


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


def create_password_file() -> None:
    """Create the Jellyfin password file if it doesn't exist yet."""
    cfg = get_jellyfin_config()
    try:
        with open(cfg.password_file, "x", encoding="utf-8") as f:
            import secrets
            import string

            alphabet = string.ascii_letters + string.digits + string.punctuation
            password = "".join(secrets.choice(alphabet) for _ in range(16))
            f.write(password)
    except FileExistsError:
        pass


def create_user_and_complete_wizard() -> None:
    """Create the Jellyfin user and complete the startup wizard if it hasn't been completed yet."""
    client = jellyfin_client_unauthorized()
    wait_until_ready(client)

    startup_info = jellyfin.SystemApi(client).get_public_system_info()

    if startup_info.startup_wizard_completed is True:
        return

    cfg = get_jellyfin_config()
    with open(cfg.password_file, "r", encoding="utf-8") as f:
        password = f.read().strip()

    startup_api = jellyfin.StartupApi(client)
    # `get_first_user` creates the first user if it doesn't exist yet.
    startup_api.get_first_user()
    startup_api.update_startup_user(
        jellyfin.StartupUserDto(name=cfg.username, password=password)
    )
    startup_api.complete_wizard()
    # Waiting *immediately* after completing the wizard seems to incorrectly
    # report that the server is ready, so we wait a bit before... waiting.
    time.sleep(5)
    wait_until_ready(client)


if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(
        description="Set up the Jellyfin server for use with Nixarr."
    )
    parser.add_argument(
        "--auto-create-password-file",
        action="store_true",
        help="Automatically create the password file if it doesn't exist yet.",
    )
    parser.add_argument(
        "--auto-create-user-and-complete-wizard",
        action="store_true",
        help="Automatically create the user and complete the startup wizard if it hasn't been completed yet.",
    )
    args = parser.parse_args()

    if args.auto_create_password_file:
        create_password_file()

    if args.auto_create_user_and_complete_wizard:
        create_user_and_complete_wizard()
