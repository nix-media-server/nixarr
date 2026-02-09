---
title: Declarative Configuration Example
---

This example demonstrates how to use the declarative configuration options in
Nixarr to minimize manual post-deployment setup. It leverages `settings-sync`
to automatically configure Prowlarr, Sonarr, Radarr, and Bazarr on boot.

This example does the following:

- Runs a Jellyfin server with HTTPS.
- Runs Transmission through a VPN.
- Runs all supported "*Arrs".
- Declaratively syncs Prowlarr indexers, tags, and applications.
- Declaratively adds Transmission as a download client in Sonarr and Radarr.
- Declaratively connects Bazarr to Sonarr and Radarr.

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

    transmission = {
      enable = true;
      vpn.enable = true;
      peerPort = 50000; # Set this to the port forwarded by your VPN
    };

    # Enable all Arrs
    bazarr.enable = true;
    lidarr.enable = true;
    radarr.enable = true;
    readarr.enable = true;
    sonarr.enable = true;
    jellyseerr.enable = true;

    # --- Declarative Prowlarr Settings ---
    prowlarr = {
      enable = true;

      settings-sync = {
        # Automatically sync all enabled Nixarr apps to Prowlarr.
        # This adds Sonarr, Radarr, Lidarr, and Readarr as applications
        # with the correct URLs and API keys — no manual setup needed.
        enable-nixarr-apps = true;

        # Define tags for organizing indexers
        tags = [ "usenet" "torrent" "private" ];

        # Define indexers directly in Nix
        indexers = [
          {
            sort_name = "nzbgeek";
            tags = [ "usenet" ];
            fields = {
              # Secrets are read from files at runtime, not stored in the Nix store
              apiKey.secret = "/data/.secret/nzbgeek-api-key";
            };
          }
          {
            sort_name = "torznab";
            name = "Jackett";
            tags = [ "torrent" ];
            fields = {
              baseUrl = "http://localhost:9117/api/v2.0/indexers/all/results/torznab/";
              apiKey.secret = "/data/.secret/jackett-api-key";
            };
          }
        ];
      };
    };

    # --- Declarative Sonarr Download Clients ---
    sonarr.settings-sync = {
      # Automatically configure Transmission as a download client.
      # Uses the correct port and localhost (works even across VPN boundaries
      # because Nixarr sets up nginx proxies automatically).
      transmission.enable = true;
    };

    # --- Declarative Radarr Download Clients ---
    radarr.settings-sync = {
      transmission.enable = true;
    };

    # --- Declarative Bazarr Connections ---
    bazarr.settings-sync = {
      # Automatically configure the Sonarr connection in Bazarr.
      # API keys and ports are filled in from Nixarr's configuration.
      sonarr.enable = true;
      sonarr.config = {
        # Optionally only sync subtitles for monitored content
        sync_only_monitored_series = true;
        sync_only_monitored_episodes = true;
      };

      # Same for Radarr
      radarr.enable = true;
      radarr.config = {
        sync_only_monitored_movies = true;
      };
    };
  };
```

With this configuration, after deployment:

1. **Prowlarr** will automatically add Sonarr, Radarr, Lidarr, and Readarr as
   applications, create the specified tags, and configure the indexers.
2. **Sonarr and Radarr** will have Transmission pre-configured as a download
   client — no need to manually add it in the web UI.
3. **Bazarr** will have its Sonarr and Radarr connections pre-configured,
   so it can immediately start managing subtitles.

The only remaining manual steps are:

- Set up your Jellyfin media libraries.
- Configure subtitle providers in Bazarr.
- Add media to your *Arrs.

### How Settings-Sync Works

The settings-sync system uses oneshot systemd services that run after each
application starts. These services use the application's REST API to apply
your Nix configuration. This means:

- Settings are applied **after** the service boots, not via config files.
- API keys are automatically extracted and shared between services.
- The sync runs once per boot (services are marked `RemainAfterExit`).
- Secret values (like indexer API keys) are read from files at runtime, keeping
  them out of the Nix store.

### Finding Available Schemas

To discover what indexers, download clients, or applications are available for
configuration, use the `nixarr` CLI:

```bash
  # Show available Prowlarr indexer schemas
  sudo nixarr show-prowlarr-schemas indexer | jq '.[].sort_name'

  # Show Prowlarr application schemas
  sudo nixarr show-prowlarr-schemas application | jq '.[].implementation'

  # Show Sonarr download client schemas
  sudo nixarr show-sonarr-schemas download_client | jq '.[].implementation'

  # Show Radarr download client schemas
  sudo nixarr show-radarr-schemas download_client | jq '.[].implementation'
```

### Requirements

For settings-sync to work, authentication must be set to allow local
API access:

```nix
  services.prowlarr.settings.auth.required = "DisabledForLocalAddresses";
  services.sonarr.settings.auth.required = "DisabledForLocalAddresses";
  services.radarr.settings.auth.required = "DisabledForLocalAddresses";
```
