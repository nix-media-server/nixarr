{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.sonarr;
  globals = config.util-nixarr.globals;
  defaultPort = 8989;
  nixarr = config.nixarr;
in {
  imports = [./settings-sync];

  options.nixarr.sonarr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Sonarr service.
      '';
    };

    package = mkPackageOption pkgs "sonarr" {};

    port = mkOption {
      type = types.port;
      default = defaultPort;
      description = "Port for Sonarr to use.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/sonarr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/sonarr"'';
      example = "/nixarr/.state/sonarr";
      description = ''
        The location of the state directory for the Sonarr service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/sonarr
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Open firewall for Sonarr";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route Sonarr traffic through the VPN.
      '';
    };

    vpn.configureNginx = mkOption {
      type = types.bool;
      default = cfg.vpn.enable;
      example = false;
      description = ''
        **Required options:** [`nixarr.sonarr.vpn.enable`)(#nixarr.sonarr.vpn.enable)

        Configure nginx as a reverse proxy for the Sonarr web ui.
      '';
      defaultText = literalExpression "nixarr.sonarr.vpn.enable";
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.sonarr.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
      {
        assertion = cfg.vpn.configureNginx -> cfg.vpn.enable;
        message = ''
          The nixarr.sonarr.vpn.configureNginx option requires the
          nixarr.sonarr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    users = {
      groups.${globals.sonarr.group}.gid = globals.gids.${globals.sonarr.group};
      users.${globals.sonarr.user} = {
        isSystemUser = true;
        group = globals.sonarr.group;
        uid = globals.uids.${globals.sonarr.user};
      };
    };

    systemd.tmpfiles.rules = [
      "d '${nixarr.mediaDir}/library'        0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/shows'  0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
    ];

    services.sonarr = {
      enable = cfg.enable;
      package = cfg.package;
      user = globals.sonarr.user;
      group = globals.sonarr.group;
      settings.server.port = cfg.port;
      openFirewall = cfg.openFirewall;
      dataDir = cfg.stateDir;
    };

    # Set UMask to 0002 so directories are created with group write permission (775)
    # This allows other services in the media group (like Jellyfin) to modify files
    systemd.services.sonarr.serviceConfig.UMask = lib.mkForce "0002";

    # Enable and specify VPN namespace to confine service in.
    systemd.services.sonarr.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = "wg";
    };

    # Port mappings
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
            addr = nixarr.vpn.proxyListenAddr;
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
