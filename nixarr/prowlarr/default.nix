{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.prowlarr;
  globals = config.util-nixarr.globals;
  nixarr = config.nixarr;
  port = 9696;
in {
  imports = [./settings-sync];

  options.nixarr.prowlarr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Prowlarr service. This has
        a seperate service since running two instances is the standard
        way of being able to query both ebooks and audiobooks.
      '';
    };

    package = mkPackageOption pkgs "prowlarr" {};

    port = mkOption {
      type = types.port;
      default = port;
      description = "Port for Prowlarr to use.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/prowlarr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/prowlarr"'';
      example = "/nixarr/.state/prowlarr";
      description = ''
        The location of the state directory for the Prowlarr service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/prowlarr
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Open firewall for Prowlarr";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route Prowlarr traffic through the VPN.
      '';
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.prowlarr.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0700 ${globals.prowlarr.user} root - -"
    ];

    services.prowlarr = {
      enable = cfg.enable;
      package = cfg.package;
      settings.server.port = cfg.port;
      openFirewall = cfg.openFirewall;
    };

    systemd.services.prowlarr.serviceConfig = {
      # `User` and `Group` override `DynamicUser = true` from the NixOS Prowlarr
      # module (because a user and group with those names exists).
      User = globals.prowlarr.user;
      Group = globals.prowlarr.group;
      ExecStart = mkForce "${lib.getExe cfg.package} -nobrowser -data=${cfg.stateDir}";
      ReadWritePaths = [cfg.stateDir];
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port];
    };

    users = {
      groups.${globals.prowlarr.group}.gid = globals.gids.${globals.prowlarr.group};
      users.${globals.prowlarr.user} = {
        isSystemUser = true;
        group = globals.prowlarr.group;
        uid = globals.uids.${globals.prowlarr.user};
      };
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.prowlarr.vpnConfinement = mkIf cfg.vpn.enable {
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
