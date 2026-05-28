# flake8: noqa
import argparse
import json
from pathlib import Path
from configobj import ConfigObj


def main():
    parser = argparse.ArgumentParser(description="Sync server configuration to SABnzbd")
    parser.add_argument("--ini-file", type=Path, required=True)
    parser.add_argument("--servers-file", type=Path, required=True)
    args = parser.parse_args()

    servers = json.loads(args.servers_file.read_text())
    config = ConfigObj(str(args.ini_file))

    if "servers" in config:
        del config["servers"]
    config["servers"] = {}

    for server in servers:
        name = server["name"]
        config["servers"][name] = {
            "displayname": name,
            "host": server["host"],
            "port": str(server["port"]),
            "ssl": "1" if server.get("ssl", True) else "0",
            "ssl_verify": "3",
            "connections": str(server.get("connections", 8)),
            "username": "",
            "password": "",
            "enable": "1",
            "priority": str(server.get("priority", 0)),
            "retention": str(server.get("retention", 0)),
            "timeout": "120",
            "optional": "0",
        }
        username_file = server.get("usernameFile")
        if username_file:
            with open(username_file) as f:
                config["servers"][name]["username"] = f.read().strip()
        password_file = server.get("passwordFile")
        if password_file:
            with open(password_file) as f:
                config["servers"][name]["password"] = f.read().strip()

    config.write()


if __name__ == "__main__":
    main()
