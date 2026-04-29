import jellyfin

from nixarr_py.clients import jellyfin_client

# Ensure that multiple clients can be created and used independently

client1 = jellyfin_client()
client2 = jellyfin_client()

jellyfin.SystemApi(client1).get_system_info()
jellyfin.SystemApi(client2).get_system_info()
