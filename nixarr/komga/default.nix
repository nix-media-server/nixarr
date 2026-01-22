{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.nixarr.komga;
  globals = config.util-nixarr.globals;
  defaultPort = 25600;
  nixarr = config.nixarr;
in {
  options.nixarr.komga = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Komga service.

        **Conflicting options:** [`nixarr.plex.enable`](#nixarr.plex.enable)
      '';
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/komga";
      defaultText = literalExpression ''"''${nixarr.stateDir}/komga"'';
      example = "/nixarr/.state/komga";
      description = ''
        The location of the state directory for the Komga service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/komga
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Open firewall for Komga";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        **Conflicting options:** [`nixarr.komga.expose.https.enable`](#nixarr.komga.expose.https.enable)

        Route Komga traffic through the VPN.
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

            - [`nixarr.komga.expose.https.acmeMail`](#nixarr.komga.expose.https.acmemail)
            - [`nixarr.komga.expose.https.domainName`](#nixarr.komga.expose.https.domainname)

            **Conflicting options:** [`nixarr.komga.vpn.enable`](#nixarr.komga.vpn.enable)

            Expose the Komga web service to the internet with https support,
            allowing anyone to access it.

            > **Warning:** Do _not_ enable this without setting up Komga
            > authentication through localhost first!
          '';
        };

        upnp.enable = mkEnableOption "UPNP to try to open ports 80 and 443 on your router.";

        domainName = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "komga.example.com";
          description = "The domain name to host Komga on.";
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
          The nixarr.komga.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
      {
        assertion = !(cfg.vpn.enable && cfg.expose.https.enable);
        message = ''
          The nixarr.komga.vpn.enable option conflicts with the
          nixarr.komga.expose.https.enable option. You cannot set both.
        '';
      }
      {
        assertion =
          cfg.expose.https.enable
          -> ((cfg.expose.https.domainName != null) && (cfg.expose.https.acmeMail != null));
        message = ''
          The nixarr.komga.expose.https.enable option requires the
          following options to be set, but one of them were not:

          - nixarr.komga.expose.domainName
          - nixarr.komga.expose.acmeMail
        '';
      }
    ];

    users = {
      groups.${globals.komga.group}.gid = globals.gids.${globals.komga.group};
      users.${globals.komga.user} = {
        isSystemUser = true;
        group = globals.komga.group;
        uid = globals.uids.${globals.komga.user};
      };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}'        0700 ${globals.komga.user} root - -"
      "d '${cfg.stateDir}/log'    0700 ${globals.komga.user} root - -"
      "d '${cfg.stateDir}/cache'  0700 ${globals.komga.user} root - -"
      "d '${cfg.stateDir}/data'   0700 ${globals.komga.user} root - -"
      "d '${cfg.stateDir}/config' 0700 ${globals.komga.user} root - -"

      # Media Dirs
      "d '${nixarr.mediaDir}/library'             0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/books'       0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
    ];

    services.komga = {
      enable = cfg.enable;
      user = globals.komga.user;
      group = globals.komga.group;
      openFirewall = cfg.openFirewall;
      stateDir = cfg.stateDir;
      settings.server.port = defaultPort;
    };

    networking.firewall = mkIf cfg.expose.https.enable {
      allowedTCPPorts = [
        80
        443
      ];
    };

    util-nixarr.upnp = mkIf cfg.expose.https.upnp.enable {
      enable = true;
      openTcpPorts = [
        80
        443
      ];
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
    systemd.services.komga.vpnConfinement = mkIf cfg.vpn.enable {
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
