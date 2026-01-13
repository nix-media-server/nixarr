{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.whisparr;
  globals = config.util-nixarr.globals;
  defaultPort = 6969;
  nixarr = config.nixarr;
in {
  options.nixarr.whisparr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the whisparr service.
      '';
    };

    package = mkPackageOption pkgs "whisparr" {};

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/whisparr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/whisparr"'';
      example = "/nixarr/.state/whisparr";
      description = ''
        The location of the state directory for the whisparr service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/whisparr
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Open firewall for whisparr";
    };

    port = mkOption {
      type = types.port;
      default = defaultPort;
      description = "Port for Whisparr to use.";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route whisparr traffic through the VPN.
      '';
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.whisparr.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    users = {
      groups.${globals.whisparr.group}.gid = globals.gids.${globals.whisparr.group};
      users.${globals.whisparr.user} = {
        isSystemUser = true;
        group = globals.whisparr.group;
        uid = globals.uids.${globals.whisparr.user};
      };
    };

    systemd.tmpfiles.rules = [
      "d '${nixarr.mediaDir}/library'        0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/xxx'    0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
    ];

    services.whisparr = {
      enable = cfg.enable;
      package = cfg.package;
      user = globals.whisparr.user;
      group = globals.whisparr.group;
      settings.server.port = cfg.port;
      openFirewall = cfg.openFirewall;
      dataDir = cfg.stateDir;
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.whisparr.vpnConfinement = mkIf cfg.vpn.enable {
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

    services.nginx = mkIf cfg.vpn.enable {
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
