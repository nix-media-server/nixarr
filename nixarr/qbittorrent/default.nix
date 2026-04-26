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

  downloadDir = "${nixarr.mediaDir}/torrents";
in {
  options.nixarr.qbittorrent = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Whether or not to enable the qBittorrent service.";
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
      defaultText = literalExpression ''!nixarr.qbittorrent.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for `peerPort` and `uiPort`.";
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

    peerPort = mkOption {
      type = types.port;
      default = 50000;
      example = 12345;
      description = "qBittorrent peer traffic port.";
    };

    uiPort = mkOption {
      type = types.port;
      default = 8080;
      example = 12345;
      description = "qBittorrent web-UI port.";
    };

    extraSettings = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        Extra config settings for the qBittorrent service passed to
        `services.qbittorrent.serverConfig`.

        See [Explanation-of-Options-in-qBittorrent](https://github.com/qbittorrent/qBittorrent/wiki/Explanation-of-Options-in-qBittorrent).
      '';
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

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0750 qbittorrent media - -"

      "d '${nixarr.mediaDir}/torrents'             0755 qbittorrent media - -"
      "d '${nixarr.mediaDir}/torrents/.incomplete' 0755 qbittorrent media - -"
      "d '${nixarr.mediaDir}/torrents/manual'      0755 qbittorrent media - -"
      "d '${nixarr.mediaDir}/torrents/lidarr'      0755 qbittorrent media - -"
      "d '${nixarr.mediaDir}/torrents/radarr'      0755 qbittorrent media - -"
      "d '${nixarr.mediaDir}/torrents/sonarr'      0755 qbittorrent media - -"
      "d '${nixarr.mediaDir}/torrents/readarr'     0755 qbittorrent media - -"
    ];

    services.qbittorrent = {
      enable = true;
      package = cfg.package;
      user = "qbittorrent";
      group = "media";
      profileDir = cfg.stateDir;
      webuiPort = cfg.uiPort;
      torrentingPort = cfg.peerPort;
      openFirewall = cfg.openFirewall;
      serverConfig =
        {
          LegalNotice.Accepted = true;
          BitTorrent.Session = {
            DefaultSavePath = downloadDir;
            TempPath = "${downloadDir}/.incomplete";
            TempPathEnabled = true;
            Port = cfg.peerPort;
            "BTProtocol" = "TCP";
          };
          Preferences = {
            WebUI = {
              Address =
                if cfg.vpn.enable
                then "192.168.15.1"
                else "0.0.0.0";
              Port = cfg.uiPort;
            };
            Downloads = {
              SavePath = downloadDir;
              TempPath = "${downloadDir}/.incomplete";
              TempPathEnabled = true;
            };
          };
        }
        // cfg.extraSettings;
    };

    users.users.qbittorrent = {
      isSystemUser = true;
      group = "media";
      uid = 71;
    };

    systemd.services.qbittorrent = {
      serviceConfig.IOSchedulingPriority = 7;

      vpnConfinement = mkIf cfg.vpn.enable {
        enable = true;
        vpnNamespace = "wg";
      };
    };

    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      portMappings = [
        {
          from = cfg.uiPort;
          to = cfg.uiPort;
        }
      ];
      openVPNPorts = [
        {
          port = cfg.peerPort;
          protocol = "both";
        }
      ];
    };

    services.nginx = mkIf cfg.vpn.enable {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."127.0.0.1:${builtins.toString cfg.uiPort}" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.uiPort;
          }
        ];
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://192.168.15.1:${builtins.toString cfg.uiPort}";
        };
      };
    };
  };
}
