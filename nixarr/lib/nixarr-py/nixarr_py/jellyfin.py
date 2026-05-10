import logging
import requests
from typing import Any, Optional

logger = logging.getLogger(__name__)


class JellyfinClient:
    def __init__(self, url: str, api_key: Optional[str] = None):
        self.url = url.rstrip("/")
        self.api_key = api_key
        self.headers = {"Content-Type": "application/json"}
        if api_key:
            self.headers["X-Emby-Token"] = api_key

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        pass

    def _get(self, endpoint: str) -> Any:
        response = requests.get(f"{self.url}{endpoint}", headers=self.headers)
        response.raise_for_status()
        return response.json()

    def _post(self, endpoint: str, json: Optional[dict] = None) -> Any:
        response = requests.post(
            f"{self.url}{endpoint}", headers=self.headers, json=json
        )
        response.raise_for_status()
        return response.json()

    def get_users(self) -> list[dict]:
        return self._get("/Users")

    def get_me(self) -> dict:
        return self._get("/Users/Me")

    def system_configuration(self, json: dict):
        return self._post("/System/Configuration", json=json)

    def create_user(self, name: str, password: Optional[str] = None) -> dict:
        # First create the user
        # The endpoint for creating a user is /Users/New
        # It expects a JSON body with Name and Password (optional)
        payload = {"Name": name}
        if password:
            payload["Password"] = password

        logger.info(f"Creating user '{name}'")
        user = self._post("/Users/New", json=payload)

        # If a password is provided, we might need to set it explicitly if the create endpoint doesn't handle it fully
        # But based on research, /Users/New should accept Password.
        # If we need to update password later, we can use /Users/{Id}/Password

        return user

    def update_user_password(
        self, user_id: str, current_password: Optional[str], new_password: str
    ) -> None:
        payload = {"Id": user_id, "NewPw": new_password}
        if current_password:
            payload["CurrentPw"] = current_password

        logger.info(f"Updating password for user {user_id}")
        self._post(f"/Users/{user_id}/Password", json=payload)

    def delete_user(self, user_id: str) -> None:
        logger.info(f"Deleting user {user_id}")
        requests.delete(
            f"{self.url}/Users/{user_id}", headers=self.headers
        ).raise_for_status()
