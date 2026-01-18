"""Test that Jellyfin users are created correctly from declarative configuration."""

import jellyfin

from nixarr_py.clients import jellyfin_client, jellyfin_client_unauthorized
from nixarr_py.config import get_jellyfin_config

# Get an authenticated client
client = jellyfin_client()

# Get all users
user_api = jellyfin.UserApi(client)
users = user_api.get_users()

# Build a dict of users by name for easier lookup
users_by_name = {u.name: u for u in users}

print(f"Found {len(users)} users: {list(users_by_name.keys())}")

# Verify testadmin exists and is an administrator
assert "testadmin" in users_by_name, "testadmin user should exist"
testadmin = users_by_name["testadmin"]
assert testadmin.policy is not None, "testadmin should have a policy"
assert testadmin.policy.is_administrator is True, "testadmin should be an administrator"
print("testadmin: verified as administrator")

# Verify testviewer exists and is NOT an administrator
assert "testviewer" in users_by_name, "testviewer user should exist"
testviewer = users_by_name["testviewer"]
assert testviewer.policy is not None, "testviewer should have a policy"
assert testviewer.policy.is_administrator is False, "testviewer should NOT be an administrator"
print("testviewer: verified as non-administrator")

# Verify we can authenticate as testadmin with the correct password
# This tests that the password was set correctly
cfg = get_jellyfin_config()
unauth_client = jellyfin_client_unauthorized()

# Create auth header required by Jellyfin
auth_header = 'MediaBrowser Client="nixarr-py-test", Device="nixarr-py-test", DeviceId="test-device-id", Version="1"'

# Try to authenticate as testadmin
auth_result = jellyfin.UserApi(unauth_client).authenticate_user_by_name(
    jellyfin.AuthenticateUserByName(
        username="testadmin",
        pw="adminpass123",
    ),
    _headers={"Authorization": auth_header},
)
assert auth_result.access_token is not None, "Should be able to authenticate as testadmin"
print("testadmin: password authentication successful")

# Try to authenticate as testviewer
unauth_client2 = jellyfin_client_unauthorized()
auth_result2 = jellyfin.UserApi(unauth_client2).authenticate_user_by_name(
    jellyfin.AuthenticateUserByName(
        username="testviewer",
        pw="viewerpass456",
    ),
    _headers={"Authorization": auth_header},
)
assert auth_result2.access_token is not None, "Should be able to authenticate as testviewer"
print("testviewer: password authentication successful")

print("\nAll Jellyfin users tests passed!")
