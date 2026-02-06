{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.plex;
  globals = config.util-nixarr.globals;
  defaultPort = 32400;
  nixarr = config.nixarr;
in {
  options.nixarr.plex = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Plex service.

        **Conflicting options:** [`nixarr.jellyfin.enable`](#nixarr.jellyfin.enable)
      '';
    };

    package = mkPackageOption pkgs "plex" {};

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/plex";
      defaultText = literalExpression ''"''${nixarr.stateDir}/plex"'';
      example = "/nixarr/.state/plex";
      description = ''
        The location of the state directory for the Plex service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/plex
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.plex.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for Plex";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        **Conflicting options:** [`nixarr.plex.expose.https.enable`](#nixarr.plex.expose.https.enable)

        Route Plex traffic through the VPN.
      '';
    };

    vpn.configureNginx = mkOption {
      type = types.bool;
      default = cfg.vpn.enable;
      example = false;
      description = ''
        **Required options:** [`nixarr.plex.vpn.enable`)(#nixarr.lidarr.vpn.enable)

        Configure nginx as a reverse proxy for the Plex web ui.
      '';
      defaultText = literalExpression "nixarr.plex.vpn.enable";
    };

    expose = {
      https = {
        enable = mkOption {
          type = types.bool;
          default = false;
          example = true;
          description = ''
            **Required options:**

            - [`nixarr.plex.expose.https.acmeMail`](#nixarr.plex.expose.https.acmemail)
            - [`nixarr.plex.expose.https.domainName`](#nixarr.plex.expose.https.domainname)

            **Conflicting options:** [`nixarr.plex.vpn.enable`](#nixarr.plex.vpn.enable)

            Expose the Plex web service to the internet with https support,
            allowing anyone to access it.

            > **Warning:** Do _not_ enable this without setting up Plex
            > authentication through localhost first!
          '';
        };

        upnp.enable = mkEnableOption "UPNP to try to open ports 80 and 443 on your router.";

        domainName = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "plex.example.com";
          description = "The domain name to host Plex on.";
        };

        acmeMail = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "mail@example.com";
          description = "The ACME mail required for the letsencrypt bot.";
        };
      };
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.vpn.enable -> nixarr.vpn.enable;
        message = ''
          The nixarr.plex.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
      {
        assertion = !(cfg.vpn.enable && cfg.expose.https.enable);
        message = ''
          The nixarr.plex.vpn.enable option conflicts with the
          nixarr.plex.expose.https.enable option. You cannot set both.
        '';
      }
      {
        assertion = cfg.vpn.configureNginx -> cfg.vpn.enable;
        message = ''
          The nixarr.komga.vpn.configureNginx option requires the
          nixarr.komga.vpn.enable option to be set, but it was not.
        '';
      }
      {
        assertion =
          cfg.expose.https.enable
          -> (
            (cfg.expose.https.domainName != null)
            && (cfg.expose.https.acmeMail != null)
          );
        message = ''
          The nixarr.plex.expose.https.enable option requires the
          following options to be set, but one of them were not:

          - nixarr.plex.expose.domainName
          - nixarr.plex.expose.acmeMail
        '';
      }
    ];

    users = {
      groups.${globals.plex.group}.gid = globals.gids.${globals.plex.group};
      users.${globals.plex.user} = {
        isSystemUser = true;
        group = globals.plex.group;
        uid = globals.uids.${globals.plex.user};
      };
    };

    systemd.tmpfiles.rules = [
      "d '${nixarr.mediaDir}/library'             0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/shows'       0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/movies'      0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/music'       0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/books'       0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/audiobooks'  0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
    ];

    # Always prioritise Plex IO
    systemd.services.plex.serviceConfig.IOSchedulingPriority = 0;

    services.plex = {
      enable = cfg.enable;
      package = cfg.package;
      user = globals.plex.user;
      group = globals.plex.group;
      openFirewall = cfg.openFirewall;
      dataDir = cfg.stateDir;
    };

    networking.firewall = mkIf cfg.expose.https.enable {
      allowedTCPPorts = [80 443];
    };

    util-nixarr.upnp = mkIf cfg.expose.https.upnp.enable {
      enable = true;
      openTcpPorts = [80 443];
    };

    services.nginx = mkMerge [
      (mkIf (cfg.expose.https.enable || cfg.vpn.configureNginx) {
        enable = true;

        recommendedTlsSettings = true;
        recommendedOptimisation = true;
        recommendedGzipSettings = true;
      })
      (mkIf cfg.expose.https.enable {
        virtualHosts."${builtins.replaceStrings ["\n"] [""] cfg.expose.https.domainName}" = {
          enableACME = true;
          forceSSL = true;
          locations."/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://127.0.0.1:${builtins.toString defaultPort}";
          };
        };
      })
      (mkIf cfg.vpn.configureNginx {
        virtualHosts."127.0.0.1:${builtins.toString defaultPort}" = mkIf cfg.vpn.enable {
          listen = [
            {
              addr = "0.0.0.0";
              port = defaultPort;
            }
          ];
          locations."/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://192.168.15.1:${builtins.toString defaultPort}";
          };
        };
      })
    ];

    security.acme = mkIf cfg.expose.https.enable {
      acceptTerms = true;
      defaults.email = cfg.expose.https.acmeMail;
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.plex.vpnConfinement = mkIf cfg.vpn.enable {
      enable = true;
      vpnNamespace = "wg";
    };

    # Port mappings
    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      portMappings = [
        {
          from = defaultPort;
          to = defaultPort;
        }
      ];
    };
  };
}
