---
title: Setup the applications
---

Here are some guides to help you set up the applications. We assume you left the
default ports; if you changed them, you will need to change the ports in the
URLs. Same if you are using a domain name—change the URLs to match. We assume
you are using the [first example](/wiki/examples/example-1) in your Nix
configuration. Replace {URL} in this document with your server IP or domain.

In the below setup, we assume you also didn't set the `nixarr.mediaDir`
option, which by default is set to `/data/media`.

## Jellyfin

- Open your browser and go to `{URL}:8096`.
- Click `Add Server` and put your server address
- Follow the setup wizard:
  - Create your administrator account.
  - Setup two libraries:
    - Movies: Choose "Movies" as content type, then add the
      `/data/media/library/movies` folder.
    - TV Shows: Same with `/data/media/library` as the folder.
    - You can add music, books, etc.
  - Continue the setup.

**Recommendations:**:

- Reduce the scan media library interval for small libraries: See
  `Scheduled Tasks`: {URL}:8096/web/index.html#/dashboard/tasks/

## Transmission

Transmission should already be setup and running since it's configured
with JSON, and can therefore be configured with nix. The most basic settings are already set. See the following links for more info:

- [The configured Nixarr defaults for transmission](https://github.com/rasmus-kirk/nixarr/blob/28d1be070deb1a064c1967889c11c8921752fa09/nixarr/transmission/default.nix#L355)
- [The `nixarr.transmission` options](https://nixarr.com/nixos-options/#nixarr.transmission.enable)
- [Settings that can be passed through `nixarr.transmission.settings`]

## Radarr

- Open your browser and go to `{URL}:7878`.
- You will be asked to set up a new account.
  - Choose `Forms` as the auth method and choose a username & password.
  - You can now log in.
- Go to "Settings" > "Media Management":
  - Click on `Show Advanced`
  - Under `Importing`, enable `Use Hardlinks instead of Copy`
  - Under `Permissions`, change `chmod Folder` to `775`
  - Under `Root Folders`, click `Add Root Folder`. Add
  `/data/media/library/movies/`, then click `Save Changes`.
- Go to "Settings" > "Download Clients" and add Transmission. Change the
  category to `radarr`.

**Recommendations:**:

- Go to {URL}:7878/settings/mediamanagement and set `Unmonitor Deleted Movies`
  to true.

### Declarative Download Clients

Instead of manually adding download clients, you can configure them
declaratively:

```nix
nixarr.radarr.settings-sync = {
  # Automatically add Transmission with the correct settings
  transmission.enable = true;

  # Or add custom download clients
  downloadClients = [
    {
      name = "NZBGet";
      implementation = "Nzbget";
      fields = {
        host = "localhost";
        port = 6789;
      };
    }
  ];
};
```

To see available download client schemas, run:
```bash
sudo nixarr show-radarr-schemas download_client | jq '.[].implementation'
```

## Sonarr

- Open your browser and go to `{URL}:8989`.
- You will be asked to set up a new account.
  - Choose `Forms` as the auth method and choose a username & password.
  - You can now log in.
- Go to "Settings" > "Media Management":
  - Click on `Show Advanced`
  - Under `Importing`, enable `Use Hardlinks instead of Copy`
  - Under `Permissions`, change `chmod Folder` to `775`
  - Under `Root Folders`, click `Add Root Folder`. Add
  `/data/media/library/shows/`, then click `Save Changes`.
- Go to "Settings" > "Download Clients" and add Transmission. Change the
  category to `sonarr`.

**Recommendations:**:

- Go to {URL}:8989/settings/mediamanagement and set `Unmonitor Deleted Episodes`
  to true.

### Declarative Download Clients

Instead of manually adding download clients, you can configure them
declaratively:

```nix
nixarr.sonarr.settings-sync = {
  # Automatically add Transmission with the correct settings
  transmission.enable = true;

  # Or add custom download clients
  downloadClients = [
    {
      name = "SABnzbd";
      implementation = "Sabnzbd";
      fields = {
        host = "localhost";
        port = 8080;
        apiKey.secret = "/data/.secret/sabnzbd-api-key";
      };
    }
  ];
};
```

To see available download client schemas, run:
```bash
sudo nixarr show-sonarr-schemas download_client | jq '.[].implementation'
```

## Jellyseerr

- Open your browser and go to `{URL}:5055`.
- Follow the installation wizard:
  - Choose Jellyfin (or Plex).
  - Add your Jellyfin URL, username & password (you can leave the path
    empty and use a dummy email).
  - Click on `Sync Libraries` and toggle `Movies` and `Shows`, click `Next`.
  - Add your Radarr and Sonarr apps.
  - Get the API key by typing `sudo nixarr list-api-keys` in your terminal.

## Bazarr

- Open your browser and go to `{URL}:6767`.
- Go to "Settings" > "Languages":
  - select your preferred languages for subtitles in "Languages Filter", then
    add a languages profile
  - Add a "Default Language Profile" for "Series" and "Movies"
- Go to "Settings" > "Sonarr" and "Settings" > "Radarr" to add your respective
  Sonarr and Radarr instances.
  - Get the API key by typing `sudo nixarr list-api-keys` in your terminal.
  - Click `Test` to ensure the connection works, then `Save`.
- Go to "Settings" > "Providers" and enable the subtitle providers you want.

**Recommendations:**:

- Go to {URL}:6767/settings/general and set `Unmonitor Deleted Subtitles` to
  true.
- Go to "Settings" > "Subtitles" > "Audio Synchronization / Alignment" and enable "Automatic
  Subtitles Audio Synchronization"

### Declarative Configuration

Instead of manually configuring the Sonarr and Radarr connections, you can set
them up declaratively:

```nix
nixarr.bazarr.settings-sync = {
  # Automatically configure the Sonarr connection
  sonarr.enable = true;
  sonarr.config = {
    # Only sync subtitles for monitored content (optional)
    sync_only_monitored_series = true;
    sync_only_monitored_episodes = true;
  };

  # Automatically configure the Radarr connection
  radarr.enable = true;
  radarr.config = {
    sync_only_monitored_movies = true;
  };
};
```

API keys and ports are filled in automatically from Nixarr's configuration.
You still need to manually configure languages and subtitle providers.

## Prowlarr

**Initial setup**:

- Open your browser and go to `{URL}:9696`.
- You will be asked to set up a new account.
  - Choose `Forms` as the auth method and choose a username & password.
  - You can now log in.
- Go to "Settings" > "Apps" and add your _Arrs_.
  - Get the API key by typing `sudo nixarr list-api-keys` in your terminal.

### Declarative Configuration

Instead of manually configuring Prowlarr, you can use the `nixarr.prowlarr.settings-sync` options to declaratively manage your configuration.

**Sync Applications**:
Automatically sync your enabled *Arr applications (Sonarr, Radarr, Lidarr, Readarr, Readarr-Audiobook, Whisparr) to Prowlarr:

```nix
nixarr.prowlarr.settings-sync.enable-nixarr-apps = true;
```

You can also enable individual apps:

```nix
nixarr.prowlarr.settings-sync = {
  sonarr.enable = true;
  radarr.enable = true;
  # lidarr, readarr, readarr-audiobook, whisparr also available
};
```

**Configure Indexers**:
Define your indexers directly in Nix. Use `sort_name` to reference the indexer
definition, and pass secrets via file references:

```nix
nixarr.prowlarr.settings-sync.indexers = [
  {
    sort_name = "nzbgeek";
    tags = [ "usenet" ];
    fields = {
      apiKey.secret = "/path/to/api/key";
    };
  }
];
```

To find available indexer schemas, run:
```bash
sudo nixarr show-prowlarr-schemas indexer | jq '.[].sort_name'
```

**Manage Tags**:
Define tags to be created in Prowlarr:

```nix
nixarr.prowlarr.settings-sync.tags = [ "usenet" "torrent" "private" ];
```

**Add Custom Applications**:
Add non-Nixarr-managed applications:

```nix
nixarr.prowlarr.settings-sync.apps = [
  {
    name = "External Sonarr";
    implementation = "Sonarr";
    tags = [ "external" ];
    fields = {
      baseUrl = "http://192.168.1.100:8989";
      apiKey.secret = "/path/to/external-sonarr-api-key";
      prowlarrUrl = "http://localhost:9696";
    };
  }
];
```

## qBittorrent

qBittorrent is an alternative to Transmission with a feature-rich WebUI.
The [qui](https://github.com/autobrr/qui) WebUI is enabled by default as a
modern proxy frontend.

**First-time setup**:

- Open your browser and go to `{URL}:5252`.
- qui will ask you to configure the qBittorrent connection on first run:
  - If using VPN: set the URL to `http://192.168.15.1:8085`
  - If not using VPN: set the URL to `http://127.0.0.1:8085`
- You can now manage your torrents through the qui interface.

**Configuration example**:

```nix
nixarr.qbittorrent = {
  enable = true;
  vpn.enable = true;
  peerPort = 50000;

  # Disable DHT/PeX for private trackers (optional)
  # privateTrackers.disableDhtPex = true;

  # Extra configuration merged into qBittorrent.conf
  extraConfig = {
    BitTorrent = {
      "Session\\MaxActiveDownloads" = 3;
    };
  };
};
```

**Download directories**: qBittorrent downloads to `/data/media/qbittorrent/`
with per-*Arr subdirectories (`radarr/`, `sonarr/`, `lidarr/`, `readarr/`).

## Monitoring

Nixarr can set up Prometheus exporters for all supported services. This requires
a separate Prometheus server to scrape the metrics.

**Enable all exporters**:

```nix
nixarr.exporters.enable = true;
```

This configures:

- **Exportarr** for Sonarr (`:9707`), Radarr (`:9708`), Lidarr (`:9709`),
  Readarr (`:9710`), and Prowlarr (`:9711`)
- **qBittorrent exporter** (`:9713`) if qBittorrent is enabled
- **Node and systemd exporters** for system metrics
- **WireGuard exporter** (`:9586`) if VPN is enabled

Exporters for VPN-confined services are automatically placed in the VPN
namespace with nginx proxies so metrics remain accessible from the host.

**Customize per-service exporters**:

```nix
# Disable a specific exporter
nixarr.lidarr.exporter.enable = false;

# Change port or listen address
nixarr.sonarr.exporter.port = 9800;
nixarr.radarr.exporter.listenAddr = "127.0.0.1";
```
