{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.lidarr;
  globals = config.util-nixarr.globals;
  nixarr = config.nixarr;
  port = 8686;
in {
  options.nixarr.lidarr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Lidarr service.
      '';
    };

    package = mkPackageOption pkgs "lidarr" {};

    port = mkOption {
      type = types.port;
      default = port;
      description = "Port for Lidarr to use.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/lidarr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/lidarr"'';
      example = "/nixarr/.state/lidarr";
      description = ''
        The location of the state directory for the Lidarr service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/lidarr
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.lidarr.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for Lidarr";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route Lidarr traffic through the VPN.
      '';
    };

    vpn.configureNginx = mkOption {
      type = types.bool;
      default = cfg.vpn.enable;
      example = false;
      description = ''
        **Required options:** [`nixarr.lidarr.vpn.enable`)(#nixarr.lidarr.vpn.enable)

        Configure nginx as a reverse proxy for the Lidarr web ui.
      '';
      defaultText = literalExpression "nixarr.lidarr.vpn.enable";
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.lidarr.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
      {
        assertion = cfg.vpn.configureNginx -> cfg.vpn.enable;
        message = ''
          The nixarr.lidarr.vpn.configureNginx option requires the
          nixarr.lidarr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    users = {
      groups.${globals.lidarr.group}.gid = globals.gids.${globals.lidarr.group};
      users.${globals.lidarr.user} = {
        isSystemUser = true;
        group = globals.lidarr.group;
        uid = globals.uids.${globals.lidarr.user};
      };
    };

    systemd.tmpfiles.rules = [
      "d '${nixarr.mediaDir}/library'        0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/music'  0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
    ];

    services.lidarr = {
      enable = cfg.enable;
      package = cfg.package;
      user = globals.lidarr.user;
      group = globals.lidarr.group;
      settings.server.port = cfg.port;
      openFirewall = cfg.openFirewall;
      dataDir = cfg.stateDir;
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.lidarr.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = "wg";
    };

    # Port mappings
    # TODO: openports
    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      portMappings = [
        {
          from = cfg.port;
          to = cfg.port;
        }
      ];
    };

    services.nginx = mkIf cfg.vpn.configureNginx {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts."127.0.0.1:${builtins.toString cfg.port}" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.port;
          }
        ];
        locations."/" = {
          recommendedProxySettings = true;
          proxyWebsockets = true;
          proxyPass = "http://192.168.15.1:${builtins.toString cfg.port}";
        };
      };
    };
  };
}
