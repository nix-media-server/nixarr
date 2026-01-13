{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.jellyfin;
  globals = config.util-nixarr.globals;
  defaultPort = 8096;
  nixarr = config.nixarr;
in {
  imports = [./settings-sync];

  options.nixarr.jellyfin = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Jellyfin service.

        **Conflicting options:** [`nixarr.plex.enable`](#nixarr.plex.enable)
      '';
    };

    package = mkPackageOption pkgs "jellyfin" {};

    port = mkOption {
      type = types.port;
      default = defaultPort;
      readOnly = true; # The Jellyfin port is weirdly hard to change.
      description = "Port for Jellyfin to use.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/jellyfin";
      defaultText = literalExpression ''"''${nixarr.stateDir}/jellyfin"'';
      example = "/nixarr/.state/jellyfin";
      description = ''
        The location of the state directory for the Jellyfin service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/jellyfin
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Open firewall for Jellyfin";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        **Conflicting options:** [`nixarr.jellyfin.expose.https.enable`](#nixarr.jellyfin.expose.https.enable)

        Route Jellyfin traffic through the VPN.
      '';
    };

    expose = {
      https = {
        enable = mkOption {
          type = types.bool;
          default = false;
          example = true;
          description = ''
            **Required options:**

            - [`nixarr.jellyfin.expose.https.acmeMail`](#nixarr.jellyfin.expose.https.acmemail)
            - [`nixarr.jellyfin.expose.https.domainName`](#nixarr.jellyfin.expose.https.domainname)

            **Conflicting options:** [`nixarr.jellyfin.vpn.enable`](#nixarr.jellyfin.vpn.enable)

            Expose the Jellyfin web service to the internet with https support,
            allowing anyone to access it.

            > **Warning:** Do _not_ enable this without setting up Jellyfin
            > authentication through localhost first!
          '';
        };

        upnp.enable = mkEnableOption "UPNP to try to open ports 80 and 443 on your router.";

        domainName = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "jellyfin.example.com";
          description = "The domain name to host Jellyfin on.";
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
          The nixarr.jellyfin.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
      {
        assertion = !(cfg.vpn.enable && cfg.expose.https.enable);
        message = ''
          The nixarr.jellyfin.vpn.enable option conflicts with the
          nixarr.jellyfin.expose.https.enable option. You cannot set both.
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
          The nixarr.jellyfin.expose.https.enable option requires the
          following options to be set, but one of them were not:

          - nixarr.jellyfin.expose.domainName
          - nixarr.jellyfin.expose.acmeMail
        '';
      }
    ];

    users = {
      groups.${globals.jellyfin.group}.gid = globals.gids.${globals.jellyfin.group};
      users.${globals.jellyfin.user} = {
        isSystemUser = true;
        group = globals.jellyfin.group;
        uid = globals.uids.${globals.jellyfin.user};
      };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}'        0700 ${globals.jellyfin.user} root - -"
      "d '${cfg.stateDir}/log'    0700 ${globals.jellyfin.user} root - -"
      "d '${cfg.stateDir}/cache'  0700 ${globals.jellyfin.user} root - -"
      "d '${cfg.stateDir}/data'   0700 ${globals.jellyfin.user} root - -"
      "d '${cfg.stateDir}/config' 0700 ${globals.jellyfin.user} root - -"

      # Media Dirs
      "d '${nixarr.mediaDir}/library'             0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/shows'       0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/movies'      0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/music'       0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/books'       0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/audiobooks'  0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
    ];

    # Always prioritise Jellyfin IO
    systemd.services.jellyfin.serviceConfig.IOSchedulingPriority = 0;

    services.jellyfin = {
      enable = cfg.enable;
      package = cfg.package;
      user = globals.jellyfin.user;
      group = globals.jellyfin.group;
      openFirewall = cfg.openFirewall;
      logDir = "${cfg.stateDir}/log";
      cacheDir = "${cfg.stateDir}/cache";
      dataDir = "${cfg.stateDir}/data";
      configDir = "${cfg.stateDir}/config";
    };

    networking.firewall = mkIf cfg.expose.https.enable {
      allowedTCPPorts = [80 443];
    };

    util-nixarr.upnp = mkIf cfg.expose.https.upnp.enable {
      enable = true;
      openTcpPorts = [80 443];
    };

    services.nginx = mkMerge [
      (mkIf (cfg.expose.https.enable || cfg.vpn.enable) {
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
      (mkIf cfg.vpn.enable {
        virtualHosts."127.0.0.1:${builtins.toString defaultPort}" = mkIf cfg.vpn.enable {
          listen = [
            {
              addr = nixarr.vpn.proxyListenAddr;
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
    systemd.services.jellyfin.vpnConfinement = mkIf cfg.vpn.enable {
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
