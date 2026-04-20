{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.shelfmark;
  globals = config.util-nixarr.globals;
  nixarr = config.nixarr;
  port = 8084;
in {
  options.nixarr.shelfmark = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Shelfmark service.
      '';
    };

    package = mkPackageOption pkgs "shelfmark" {};

    port = mkOption {
      type = types.port;
      default = port;
      description = "Port for Shelfmark to use.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/shelfmark";
      defaultText = literalExpression ''"''${nixarr.stateDir}/shelfmark"'';
      example = "/nixarr/.state/shelfmark";
      description = ''
        The location of the state directory for the Shelfmark service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/shelfmark
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Open firewall for Shelfmark.";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route Shelfmark traffic through the VPN.
      '';
    };

    vpn.configureNginx = mkOption {
      type = types.bool;
      default = cfg.vpn.enable;
      example = false;
      description = ''
        **Required options:** [`nixarr.shelfmark.vpn.enable`](#nixarr.shelfmark.vpn.enable)

        Configure nginx as a reverse proxy for the Shelfmark web UI.
      '';
      defaultText = literalExpression "nixarr.shelfmark.vpn.enable";
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.shelfmark.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
      {
        assertion = cfg.vpn.configureNginx -> cfg.vpn.enable;
        message = ''
          The nixarr.shelfmark.vpn.configureNginx option requires the
          nixarr.shelfmark.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    users = {
      groups.${globals.shelfmark.group}.gid = globals.gids.${globals.shelfmark.group};
      users.${globals.shelfmark.user} = {
        isSystemUser = true;
        group = globals.shelfmark.group;
        uid = globals.uids.${globals.shelfmark.user};
      };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0700 ${globals.shelfmark.user} root - -"

      "d '${nixarr.mediaDir}/library'            0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/books'      0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/audiobooks' 0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
    ];

    services.shelfmark = {
      enable = true;
      package = cfg.package;
      openFirewall = cfg.openFirewall;
      environment = {
        FLASK_HOST = if cfg.vpn.enable then "192.168.15.1" else "127.0.0.1";
        FLASK_PORT = cfg.port;
        CONFIG_DIR = cfg.stateDir;
      };
    };

    systemd.services.shelfmark.serviceConfig = {
      DynamicUser = mkForce false;
      User = globals.shelfmark.user;
      Group = globals.shelfmark.group;
      StateDirectory = mkForce "";
      ReadWritePaths = [cfg.stateDir nixarr.mediaDir];
    };

    systemd.services.shelfmark.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = "wg";
    };

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
