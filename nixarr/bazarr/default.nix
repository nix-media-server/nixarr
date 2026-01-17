{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.bazarr;
  globals = config.util-nixarr.globals;
  port = 6767;
  nixarr = config.nixarr;
in {
  options.nixarr.bazarr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Bazarr service.
      '';
    };

    package = mkPackageOption pkgs "bazarr" {};

    port = mkOption {
      type = types.port;
      default = port;
      description = "Port for Bazarr to use.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/bazarr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/bazarr"'';
      example = "/nixarr/.state/bazarr";
      description = ''
        The location of the state directory for the Bazarr service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/bazarr
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Open firewall for Bazarr";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route Bazarr traffic through the VPN.
      '';
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.bazarr.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
    ];

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0700 ${globals.bazarr.user} root - -"
    ];

    systemd.services.bazarr = {
      description = "bazarr";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "simple";
        User = globals.bazarr.user;
        Group = globals.bazarr.group;
        # Set UMask to 0002 so directories are created with group write permission (775)
        # This allows other services in the media group (like Jellyfin) to modify files
        UMask = "0002";
        SyslogIdentifier = "bazarr";
        ExecStart = pkgs.writeShellScript "start-bazarr" ''
          ${pkgs.bazarr}/bin/bazarr \
            --config '${cfg.stateDir}' \
            --port ${toString cfg.port} \
            --no-update True
        '';
        Restart = "on-failure";
        KillSignal = "SIGINT";
        SuccessExitStatus = "0 156";
      };
    };

    networking.firewall = mkIf cfg.openFirewall {
      allowedTCPPorts = [cfg.port];
    };

    users = {
      groups.${globals.bazarr.group}.gid = globals.gids.${globals.bazarr.group};
      users.${globals.bazarr.user} = {
        isSystemUser = true;
        group = globals.bazarr.group;
        uid = globals.uids.${globals.bazarr.user};
      };
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.bazarr.vpnConfinement = mkIf cfg.vpn.enable {
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
