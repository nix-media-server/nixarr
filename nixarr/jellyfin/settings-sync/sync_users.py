"""Sync Jellyfin users from declarative configuration."""

import argparse
import json
import logging
import pathlib
from typing import Optional

import jellyfin
import pydantic

from nixarr_py.clients import jellyfin_client

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class UserConfig(pydantic.BaseModel):
    name: str
    passwordFile: Optional[pathlib.Path] = None
    isAdministrator: bool = False


class JellyfinUsersConfig(pydantic.BaseModel):
    users: list[UserConfig] = []


def sync_users(config: JellyfinUsersConfig, client: jellyfin.ApiClient) -> int:
    """Sync users from configuration to Jellyfin.

    Creates users that don't exist and updates passwords for existing users.

    Returns:
        0 on success, 1 on failure
    """
    user_api = jellyfin.UserApi(client)

    # Get existing users
    try:
        existing_users = {u.name: u for u in user_api.get_users()}
    except Exception as e:
        logger.error(f"Failed to get existing users: {e}")
        logger.exception(e)
        return 1

    errors = []

    for user_cfg in config.users:
        password = None
        if user_cfg.passwordFile:
            try:
                password = user_cfg.passwordFile.read_text().strip()
            except Exception as e:
                error_msg = f"Failed to read password file for user {user_cfg.name}: {e}"
                logger.error(error_msg)
                errors.append(error_msg)
                continue

        if user_cfg.name not in existing_users:
            logger.info(f"Creating user '{user_cfg.name}'")
            try:
                new_user = user_api.create_user_by_name(
                    jellyfin.CreateUserByName(name=user_cfg.name)
                )

                # Set password if provided
                if password:
                    user_api.update_user_password(
                        user_id=new_user.id,
                        update_user_password=jellyfin.UpdateUserPassword(
                            current_pw="",  # Empty for new users
                            new_pw=password,
                        ),
                    )

                # Set admin status if needed
                if user_cfg.isAdministrator:
                    # Get current policy and update it
                    policy = new_user.policy
                    if policy:
                        policy.is_administrator = True
                        user_api.update_user_policy(
                            user_id=new_user.id, user_policy=policy
                        )

                logger.info(f"Successfully created user '{user_cfg.name}'")
            except Exception as e:
                error_msg = f"Failed to create user '{user_cfg.name}': {e}"
                logger.error(error_msg)
                logger.exception(e)
                errors.append(error_msg)
        else:
            logger.info(f"User '{user_cfg.name}' already exists")
            existing_user = existing_users[user_cfg.name]

            # Update password if provided
            if password:
                try:
                    user_api.update_user_password(
                        user_id=existing_user.id,
                        update_user_password=jellyfin.UpdateUserPassword(
                            current_pw="",  # Empty when resetting as admin
                            new_pw=password,
                        ),
                    )
                    logger.info(f"Updated password for user '{user_cfg.name}'")
                except Exception as e:
                    error_msg = f"Failed to update password for user '{user_cfg.name}': {e}"
                    logger.error(error_msg)
                    logger.exception(e)
                    errors.append(error_msg)

            # Update admin status if needed
            current_is_admin = (
                existing_user.policy and existing_user.policy.is_administrator
            )
            if user_cfg.isAdministrator != current_is_admin:
                try:
                    policy = existing_user.policy or jellyfin.UserPolicy()
                    policy.is_administrator = user_cfg.isAdministrator
                    user_api.update_user_policy(
                        user_id=existing_user.id, user_policy=policy
                    )
                    logger.info(
                        f"Updated admin status for user '{user_cfg.name}' "
                        f"to {user_cfg.isAdministrator}"
                    )
                except Exception as e:
                    error_msg = f"Failed to update admin status for user '{user_cfg.name}': {e}"
                    logger.error(error_msg)
                    logger.exception(e)
                    errors.append(error_msg)

    if errors:
        logger.error(f"User sync completed with {len(errors)} error(s):")
        for error in errors:
            logger.error(f"  - {error}")
        return 1

    logger.info("User sync completed successfully")
    return 0


def main():
    parser = argparse.ArgumentParser(description="Sync Jellyfin users")
    parser.add_argument(
        "--config-file",
        type=pathlib.Path,
        required=True,
        help="Path to JSON config file containing users to sync",
    )
    args = parser.parse_args()

    try:
        config_json = args.config_file.read_text()
        config = JellyfinUsersConfig.model_validate(json.loads(config_json))
    except Exception as e:
        logger.error(f"Failed to load configuration: {e}")
        logger.exception(e)
        return 1

    if not config.users:
        logger.info("No users configured, nothing to do")
        return 0

    try:
        client = jellyfin_client()
    except Exception as e:
        logger.error(f"Failed to create Jellyfin client: {e}")
        logger.exception(e)
        return 1

    return sync_users(config, client)


if __name__ == "__main__":
    exit(main())
