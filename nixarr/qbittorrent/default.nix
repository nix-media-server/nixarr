{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.qbittorrent;
  globals = config.util-nixarr.globals;
  nixarr = config.nixarr;

  downloadDir = "${nixarr.mediaDir}/qbittorrent";

  # Helper to determine if exporter should be enabled
  shouldEnableExporter =
    cfg.enable && nixarr.exporters.enable && cfg.exporter.enable;

  # When qui is enabled, qBittorrent uses internal port; otherwise uses webuiPort
  qbittorrentPort =
    if cfg.qui.enable
    then cfg.qui.internalPort
    else cfg.webuiPort;

  # Generate qBittorrent configuration
  qbittorrentConfig =
    {
      BitTorrent = {
        # Download paths
        "Session\\DefaultSavePath" = downloadDir;
        "Session\\TempPath" = "${downloadDir}/.incomplete";
        "Session\\TempPathEnabled" = true;

        # Network
        "Session\\Port" = cfg.peerPort;
        "Session\\DHTEnabled" = !cfg.privateTrackers.disableDhtPex;
        "Session\\PeXEnabled" = !cfg.privateTrackers.disableDhtPex;
        "Session\\LSDEnabled" = !cfg.privateTrackers.disableDhtPex;

        # Security
        "Session\\Encryption" = 1; # Prefer encryption
        "Session\\AnonymousModeEnabled" = cfg.privateTrackers.disableDhtPex;

        # Performance / seeding
        "Session\\GlobalMaxRatio" = -1; # No ratio limit (let *arr apps manage)
        "Session\\MaxActiveDownloads" = 5;
        "Session\\MaxActiveTorrents" = 10;
        "Session\\MaxActiveUploads" = 10;
        "Session\\QueueingSystemEnabled" = true;
        "Session\\IgnoreSlowTorrentsForQueueing" = true;

        # Categories for *arr apps (paths relative to DefaultSavePath)
        "Session\\DisableAutoTMMByDefault" = false; # Enable automatic torrent management
        "Session\\DisableAutoTMMTriggers\\CategorySavePathChanged" = false;
        "Session\\DisableAutoTMMTriggers\\DefaultSavePathChanged" = false;
      };
      Preferences = {
        # WebUI - when qui is enabled, qBittorrent uses internal port
        "WebUI\\Port" = qbittorrentPort;
        "WebUI\\Address" =
          if cfg.vpn.enable
          then "192.168.15.1"
          else "*";
        "WebUI\\LocalHostAuth" = false;
        # Only enable alternative UI if explicitly set and qui is disabled
        "WebUI\\AlternativeUIEnabled" = cfg.webui.package != null && !cfg.qui.enable;
        "WebUI\\RootFolder" =
          if cfg.webui.package != null && !cfg.qui.enable
          then "${cfg.webui.package}/${cfg.webui.path}"
          else "";
        "WebUI\\HostHeaderValidation" = false; # Allow access from reverse proxy
        # Whitelist VPN subnet for authentication bypass (qui runs in same namespace)
        "WebUI\\AuthSubnetWhitelistEnabled" = cfg.vpn.enable;
        "WebUI\\AuthSubnetWhitelist" = "192.168.15.0/24";
        # Disable CSRF for API access from qui
        "WebUI\\CSRFProtection" = false;

        # Downloads
        "Downloads\\SavePath" = downloadDir;
        "Downloads\\TempPath" = "${downloadDir}/.incomplete";
        "Downloads\\TempPathEnabled" = true;
        "Downloads\\ScanDirsV2" = builtins.toJSON {
          "${downloadDir}/.watch" = 0; # Download to default save path
        };
        "Downloads\\PreAllocation" = true; # Pre-allocate disk space
      };
    }
    // cfg.extraConfig;
in {
  options.nixarr.qbittorrent = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the qBittorrent service.

        qBittorrent is a free, open source BitTorrent client with a
        feature-rich Web UI. This module configures qBittorrent-nox
        (headless version) with optional alternative WebUI support.
      '';
    };

    package = mkPackageOption pkgs "qbittorrent-nox" {};

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/qbittorrent";
      defaultText = literalExpression ''"''${nixarr.stateDir}/qbittorrent"'';
      example = "/nixarr/.state/qbittorrent";
      description = ''
        The location of the state directory for the qBittorrent service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/qbittorrent
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Open firewall for the WebUI port.";
    };

    extraAllowedIps = mkOption {
      type = with types; listOf str;
      default = [];
      example = ["10.19.5.10"];
      description = ''
        Extra IP addresses allowed to access the qBittorrent WebUI.
      '';
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route qBittorrent traffic through the VPN.
      '';
    };

    webui = {
      package = mkOption {
        type = types.nullOr types.package;
        default = null;
        example = literalExpression "pkgs.vuetorrent";
        description = ''
          Alternative static WebUI package to use. Set to `null` to use
          the default qBittorrent WebUI.

          Available options include:
          - `pkgs.vuetorrent` - VueTorrent WebUI (available in nixos-25.05)
          - `null` - Default qBittorrent WebUI (default)

          Note: For qui, use the `qui.enable` option instead as qui runs
          as a separate proxy service.
        '';
      };
      path = mkOption {
        type = types.str;
        default = "share/vuetorrent";
        description = ''
          Relative path within the WebUI package to the WebUI files.
        '';
      };
    };

    qui = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Enable qui as the WebUI for qBittorrent. qui is a modern WebUI
          by the autobrr team that runs as a separate proxy service.

          When enabled, qui will be available on the webuiPort and will
          proxy requests to qBittorrent's internal API.
        '';
      };
      package = mkPackageOption pkgs "qui" {};
      internalPort = mkOption {
        type = types.port;
        default = 8085;
        description = ''
          Internal port for qBittorrent's native WebUI. qui will proxy to this.
          This port is not exposed externally.
        '';
      };
    };

    privateTrackers = {
      disableDhtPex = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Disable DHT, PeX, and LSD, which is required by some private trackers.

          This also enables anonymous mode in qBittorrent.
        '';
      };
    };

    peerPort = mkOption {
      type = types.port;
      default = 6881;
      example = 50000;
      description = ''
        qBittorrent peer traffic port. If VPN is enabled, this port
        will be opened in the VPN namespace.
      '';
    };

    webuiPort = mkOption {
      type = types.port;
      default = 5252;
      example = 8080;
      description = "qBittorrent WebUI port.";
    };

    extraConfig = mkOption {
      type = types.attrs;
      default = {};
      example = {
        Preferences = {
          "Downloads\\PreAllocation" = true;
        };
      };
      description = ''
        Extra configuration options for qBittorrent.
        These are merged with the generated qBittorrent.conf settings.

        See the [qBittorrent wiki](https://github.com/qbittorrent/qBittorrent/wiki/Explanation-of-Options-in-qBittorrent)
        for available options.
      '';
    };

    exporter = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable the qBittorrent Prometheus exporter.
          Only has an effect if nixarr.exporters.enable and nixarr.qbittorrent.enable are true.
        '';
      };
      port = mkOption {
        type = types.port;
        default = 9713;
        description = "Port for qBittorrent exporter metrics";
      };
      listenAddr = mkOption {
        type = types.str;
        default = "0.0.0.0";
        description = ''
          Address for qBittorrent exporter to listen on.
          Note: This is forced to "0.0.0.0" if the service is VPN-confined.
        '';
      };
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.qbittorrent.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    users = {
      groups.${globals.qbittorrent.group}.gid = globals.gids.${globals.qbittorrent.group};
      users.${globals.qbittorrent.user} = {
        isSystemUser = true;
        group = globals.qbittorrent.group;
        uid = globals.uids.${globals.qbittorrent.user};
      };
    };

    systemd.tmpfiles.rules =
      [
        "d '${cfg.stateDir}'                         0750 ${globals.qbittorrent.user} ${globals.qbittorrent.group} - -"
        "d '${cfg.stateDir}/qBittorrent'             0750 ${globals.qbittorrent.user} ${globals.qbittorrent.group} - -"
        "d '${cfg.stateDir}/qBittorrent/config'      0750 ${globals.qbittorrent.user} ${globals.qbittorrent.group} - -"
      ]
      ++ optional cfg.qui.enable
      "d '${cfg.stateDir}/qui'                     0750 ${globals.qbittorrent.user} ${globals.qbittorrent.group} - -"
      ++ [
        # Media Dirs (0775 for group write access)
        "d '${nixarr.mediaDir}/qbittorrent'             0775 ${globals.qbittorrent.user} ${globals.qbittorrent.group} - -"
        "d '${nixarr.mediaDir}/qbittorrent/.incomplete' 0775 ${globals.qbittorrent.user} ${globals.qbittorrent.group} - -"
        "d '${nixarr.mediaDir}/qbittorrent/.watch'      0775 ${globals.qbittorrent.user} ${globals.qbittorrent.group} - -"
        "d '${nixarr.mediaDir}/qbittorrent/manual'      0775 ${globals.qbittorrent.user} ${globals.qbittorrent.group} - -"
        "d '${nixarr.mediaDir}/qbittorrent/lidarr'      0775 ${globals.qbittorrent.user} ${globals.qbittorrent.group} - -"
        "d '${nixarr.mediaDir}/qbittorrent/radarr'      0775 ${globals.qbittorrent.user} ${globals.qbittorrent.group} - -"
        "d '${nixarr.mediaDir}/qbittorrent/sonarr'      0775 ${globals.qbittorrent.user} ${globals.qbittorrent.group} - -"
        "d '${nixarr.mediaDir}/qbittorrent/readarr'     0775 ${globals.qbittorrent.user} ${globals.qbittorrent.group} - -"
      ];

    # Use NixOS qbittorrent service
    services.qbittorrent = {
      enable = true;
      package = cfg.package;
      user = globals.qbittorrent.user;
      group = globals.qbittorrent.group;
      profileDir = cfg.stateDir;
      webuiPort = qbittorrentPort; # Internal port when qui is enabled
      torrentingPort = cfg.peerPort;
      openFirewall = cfg.openFirewall && !cfg.vpn.enable && !cfg.qui.enable;

      serverConfig = qbittorrentConfig;
    };

    systemd.services.qbittorrent = {
      serviceConfig = {
        # Always prioritize all other services wrt. IO
        IOSchedulingPriority = 7;
      };
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.qbittorrent.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = "wg";
    };

    # qui WebUI proxy service
    # Note: qBittorrent instances are configured through qui's web UI on first run
    # Connect to: http://${if cfg.vpn.enable then "192.168.15.1" else "127.0.0.1"}:${toString qbittorrentPort}
    systemd.services.qui = mkIf cfg.qui.enable {
      description = "qui - Modern qBittorrent WebUI";
      wantedBy = ["multi-user.target"];
      after = ["qbittorrent.service"];
      requires = ["qbittorrent.service"];

      environment = {
        QUI__PORT = toString cfg.webuiPort;
        QUI__HOST = "0.0.0.0";
        QUI__DATA_DIR = "${cfg.stateDir}/qui";
        QUI__LOG_LEVEL = "INFO";
        # Disable update checks (NixOS handles updates)
        QUI__CHECK_FOR_UPDATES = "false";
        # Prevent qui from trying to write to /var/empty/.config
        HOME = "${cfg.stateDir}/qui";
        XDG_CONFIG_HOME = "${cfg.stateDir}/qui";
      };

      serviceConfig = {
        Type = "simple";
        User = globals.qbittorrent.user;
        Group = globals.qbittorrent.group;
        ExecStart = "${cfg.qui.package}/bin/qui serve";
        Restart = "on-failure";
        RestartSec = "5s";
        StateDirectory = ""; # We manage state via tmpfiles
      };

      # qui runs on host network to access other services (prowlarr, etc.)
      # It connects to qBittorrent via the VPN namespace bridge at 192.168.15.1
    };

    # VPN port mappings
    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      portMappings =
        # qui runs on host and connects to qBittorrent's internal port
        optional cfg.qui.enable {
          from = cfg.qui.internalPort;
          to = cfg.qui.internalPort;
        }
        ++ optional shouldEnableExporter {
          from = cfg.exporter.port;
          to = cfg.exporter.port;
        };
      openVPNPorts = [
        {
          port = cfg.peerPort;
          protocol = "both";
        }
      ];
    };

    # Nginx proxy for VPN-confined exporter (qui runs on host, no proxy needed)
    services.nginx = mkIf (cfg.vpn.enable && shouldEnableExporter) {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts = {
        # Exporter proxy
        "127.0.0.1:${toString cfg.exporter.port}" = {
          listen = [
            {
              addr = "0.0.0.0";
              port = cfg.exporter.port;
            }
          ];
          locations."/" = {
            recommendedProxySettings = true;
            proxyPass = "http://192.168.15.1:${toString cfg.exporter.port}";
          };
        };
      };
    };

    # qBittorrent Prometheus exporter
    systemd.services.prometheus-qbittorrent-exporter = mkIf shouldEnableExporter {
      description = "Prometheus qBittorrent Exporter";
      wantedBy = ["multi-user.target"];
      after = ["qbittorrent.service"];
      requires = ["qbittorrent.service"];

      environment = {
        # Point to qBittorrent's actual port (internal port when qui is enabled)
        QBITTORRENT_BASE_URL = "http://${
          if cfg.vpn.enable
          then "192.168.15.1"
          else "127.0.0.1"
        }:${toString qbittorrentPort}";
        EXPORTER_PORT = toString cfg.exporter.port;
        EXPORTER_LOG_LEVEL = "INFO";
        # QBITTORRENT_USERNAME and QBITTORRENT_PASSWORD can be set via EnvironmentFile if needed
      };

      serviceConfig = {
        Type = "simple";
        DynamicUser = true;
        ExecStart = "${pkgs.prometheus-qbittorrent-exporter}/bin/qbit-exp";
        Restart = "on-failure";
        RestartSec = "5s";
      };

      # VPN confinement for exporter
      vpnConfinement = mkIf cfg.vpn.enable {
        enable = true;
        vpnNamespace = "wg";
      };
    };

    # Open firewall for services
    networking.firewall.allowedTCPPorts =
      # qui runs on host, so open its port when enabled and openFirewall is set
      optional (cfg.openFirewall && cfg.qui.enable) cfg.webuiPort
      # Open exporter port if not VPN-confined
      ++ optional (shouldEnableExporter && !cfg.vpn.enable) cfg.exporter.port;
  };
}
