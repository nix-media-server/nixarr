---
title: Monitoring and qBittorrent Example
---

This example demonstrates how to set up Prometheus monitoring for your Nixarr
services and use qBittorrent as an alternative torrent client with VPN
confinement.

This example does the following:

- Runs a Jellyfin server.
- Runs qBittorrent through a VPN with the qui WebUI.
- Runs the supported "\*Arrs" with declarative settings-sync.
- Enables Prometheus exporters for all services.

```nix {.numberLines}
  nixarr = {
    enable = true;
    mediaDir = "/data/media";
    stateDir = "/data/media/.state/nixarr";

    vpn = {
      enable = true;
      wgConf = "/data/.secret/wg.conf";
    };

    jellyfin = {
      enable = true;
      expose.https = {
        enable = true;
        domainName = "your.domain.com";
        acmeMail = "your@email.com";
      };
    };

    # --- qBittorrent with VPN ---
    # qBittorrent is an alternative to Transmission with a more
    # feature-rich WebUI. The "qui" WebUI is enabled by default.
    qbittorrent = {
      enable = true;
      vpn.enable = true;
      peerPort = 50000; # Set this to the port forwarded by your VPN
      webuiPort = 5252; # Port for the qui WebUI (default)

      # Disable DHT/PeX for private trackers (optional)
      # privateTrackers.disableDhtPex = true;

      # Extra qBittorrent configuration (optional)
      # See: https://github.com/qbittorrent/qBittorrent/wiki/Explanation-of-Options-in-qBittorrent
      extraConfig = {
        BitTorrent = {
          "Session\\MaxActiveDownloads" = 3;
          "Session\\MaxActiveTorrents" = 5;
        };
      };
    };

    # Enable Arrs
    bazarr.enable = true;
    lidarr.enable = true;
    prowlarr.enable = true;
    radarr.enable = true;
    readarr.enable = true;
    sonarr.enable = true;
    jellyseerr.enable = true;

    # --- Prometheus Monitoring ---
    # Enable exporters for all services. This sets up:
    # - Exportarr for Sonarr, Radarr, Lidarr, Readarr, Prowlarr
    # - qBittorrent exporter
    # - Node and systemd exporters
    # - WireGuard exporter (when VPN is enabled)
    exporters.enable = true;

    # Per-service exporter configuration (all optional, shown with defaults):
    # sonarr.exporter = { enable = true; port = 9707; };
    # radarr.exporter = { enable = true; port = 9708; };
    # lidarr.exporter = { enable = true; port = 9709; };
    # readarr.exporter = { enable = true; port = 9710; };
    # prowlarr.exporter = { enable = true; port = 9711; };
    # qbittorrent.exporter = { enable = true; port = 9713; };
    # wireguard.exporter = { enable = true; port = 9586; };

    # Declarative settings (as shown in example-3)
    prowlarr.settings-sync.enable-nixarr-apps = true;
  };
```

## qBittorrent Details

qBittorrent runs with VPN confinement, meaning all torrent traffic is routed
through the VPN. The [qui](https://github.com/autobrr/qui) WebUI runs on the
host network and proxies requests to qBittorrent inside the VPN namespace.

**Default ports:**

| Service              | Port | Description                                               |
| -------------------- | ---- | --------------------------------------------------------- |
| qui WebUI            | 5252 | The web interface you access in your browser              |
| qBittorrent internal | 8085 | Internal port used by qui to communicate with qBittorrent |
| Peer traffic         | 6881 | BitTorrent peer connections (inside VPN)                  |
| Exporter             | 9713 | Prometheus metrics                                        |

**First-time setup:** After deployment, open `{URL}:5252` in your browser. qui
will ask you to configure the qBittorrent connection on first run. Point it to
`http://192.168.15.1:8085` (the VPN bridge address) if using VPN, or
`http://127.0.0.1:8085` otherwise.

**Download directories:** qBittorrent downloads to `/data/media/qbittorrent/`
with per-\*Arr subdirectories (e.g., `/data/media/qbittorrent/radarr/`).

## Monitoring Details

When `nixarr.exporters.enable = true`, Nixarr configures Prometheus exporters
for each enabled service. The exporters expose metrics that you can scrape with
a Prometheus server.

**Default exporter ports:**

| Exporter    | Port | Description             |
| ----------- | ---- | ----------------------- |
| Sonarr      | 9707 | TV show manager metrics |
| Radarr      | 9708 | Movie manager metrics   |
| Lidarr      | 9709 | Music manager metrics   |
| Readarr     | 9710 | Book manager metrics    |
| Prowlarr    | 9711 | Indexer manager metrics |
| qBittorrent | 9713 | Torrent client metrics  |
| WireGuard   | 9586 | VPN tunnel metrics      |

**VPN-aware exporters:** If a service runs through the VPN (e.g., Sonarr with
`vpn.enable = true`), its exporter is automatically confined to the VPN
namespace. Nixarr sets up nginx proxies so you can still scrape the metrics from
the host.

**Example Prometheus scrape config:**

```yaml {.numberLines}
scrape_configs:
  - job_name: "sonarr"
    static_configs:
      - targets: ["your-server:9707"]
  - job_name: "radarr"
    static_configs:
      - targets: ["your-server:9708"]
  - job_name: "qbittorrent"
    static_configs:
      - targets: ["your-server:9713"]
  - job_name: "wireguard"
    static_configs:
      - targets: ["your-server:9586"]
```

You can customize per-service exporter settings:

```nix
  # Disable a specific exporter
  nixarr.lidarr.exporter.enable = false;

  # Change an exporter's port
  nixarr.sonarr.exporter.port = 9800;

  # Change the listen address
  nixarr.radarr.exporter.listenAddr = "127.0.0.1";
```
