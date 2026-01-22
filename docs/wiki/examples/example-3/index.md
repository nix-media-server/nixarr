---
title: Declarative Configuration Example
---

This example demonstrates how to use the declarative configuration options in Nixarr to minimize manual setup. It leverages the `settings-sync` feature for Prowlarr to automatically configure applications, indexers, and tags.

This example does the following:

- Runs a Jellyfin server.
- Runs Transmission through a VPN.
- Runs all supported "*Arrs".
- Declaratively configures Prowlarr to sync settings to the *Arrs and manage indexers.

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
      peerPort = 50000;
    };

    # Enable all Arrs
    bazarr.enable = true;
    lidarr.enable = true;
    radarr.enable = true;
    readarr.enable = true;
    sonarr.enable = true;
    jellyseerr.enable = true;

    prowlarr = {
      enable = true;

      # Declarative Settings Sync
      settings-sync = {
        # Automatically sync enabled apps (Sonarr, Radarr, Lidarr, Readarr, Readarr-Audiobook)
        enable-nixarr-apps = true;

        # Define tags
        tags = [ "iso" "remux" "web-dl" ];

        # Define indexers
        indexers = [
          {
            sort_name = "nzbgeek";
            fields = {
              apiKey.secret = "/path/to/nzbgeek/api/key";
            };
          }
          {
            sort_name = "example";
            tags = [ "iso" ];
            fields = {
              baseUrl = "https://example.org";
            };
          }
        ];
      };
    };
  };
```

With this configuration, Prowlarr will automatically:
1.  Add Sonarr, Radarr, and Lidarr as applications.
2.  Create the specified tags.
3.  Add and configure the specified indexers.

This significantly reduces the manual steps required after deployment.
