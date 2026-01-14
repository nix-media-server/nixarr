{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.audiobookshelf;
  globals = config.util-nixarr.globals;
  port = 9292;
  nixarr = config.nixarr;
in {
  options.nixarr.audiobookshelf = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Audiobookshelf service.

        **Conflicting options:** [`nixarr.plex.enable`](#nixarr.plex.enable)
      '';
    };

    package = mkPackageOption pkgs "audiobookshelf" {};

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/audiobookshelf";
      defaultText = literalExpression ''"''${nixarr.stateDir}/audiobookshelf"'';
      example = "/nixarr/.state/audiobookshelf";
      description = ''
        The location of the state directory for the Audiobookshelf service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/audiobookshelf
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    port = mkOption {
      type = types.port;
      default = port;
      example = 8000;
      description = ''
        Default port for Audiobookshelf. The default is 8000 in nixpkgs,
        but that's far too common a port to use.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.audiobookshelf.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for Audiobookshelf";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        **Conflicting options:** [`nixarr.audiobookshelf.expose.https.enable`](#nixarr.audiobookshelf.expose.https.enable)

        Route Audiobookshelf traffic through the VPN.
      '';
    };

    vpn.configureNginx = mkOption {
      type = types.bool;
      default = cfg.vpn.enable;
      example = false;
      description = ''
        **Required options:** [`nixarr.audiobookshelf.vpn.enable`)(#nixarr.audiobookshelf.vpn.enable)

        Configure nginx as a reverse proxy for the Audiobookshelf web ui.
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

            - [`nixarr.audiobookshelf.expose.https.acmeMail`](#nixarr.audiobookshelf.expose.https.acmemail)
            - [`nixarr.audiobookshelf.expose.https.domainName`](#nixarr.audiobookshelf.expose.https.domainname)

            **Conflicting options:** [`nixarr.audiobookshelf.vpn.enable`](#nixarr.audiobookshelf.vpn.enable)

            Expose the Audiobookshelf web service to the internet with https support,
            allowing anyone to access it.

            > **Warning:** Do _not_ enable this without setting up Audiobookshelf
            > authentication through localhost first!
          '';
        };

        upnp.enable = mkEnableOption "UPNP to try to open ports 80 and 443 on your router.";

        domainName = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "audiobookshelf.example.com";
          description = "The domain name to host Audiobookshelf on.";
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

  config = let
    host =
      if cfg.vpn.enable
      then "192.168.15.1"
      else "127.0.0.1";
  in
    mkIf (nixarr.enable && cfg.enable) {
      assertions = [
        {
          assertion = cfg.vpn.enable -> nixarr.vpn.enable;
          message = ''
            The nixarr.audiobookshelf.vpn.enable option requires the
            nixarr.vpn.enable option to be set, but it was not.
          '';
        }
        {
          assertion = !(cfg.vpn.enable && cfg.expose.https.enable);
          message = ''
            The nixarr.audiobookshelf.vpn.enable option conflicts with the
            nixarr.audiobookshelf.expose.https.enable option. You cannot set both.
          '';
        }
        {
          assertion = cfg.vpn.configureNginx -> cfg.vpn.enable;
          message = ''
            The nixarr.audiobookshelf.vpn.configureNginx option requires the
            nixarr.audiobookshelf.vpn.enable option to be set, but it was not.
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
            The nixarr.audiobookshelf.expose.https.enable option requires the
            following options to be set, but one of them were not:

            - nixarr.audiobookshelf.expose.domainName
            - nixarr.audiobookshelf.expose.acmeMail
          '';
        }
      ];

      users = {
        groups.${globals.audiobookshelf.group}.gid = globals.gids.${globals.audiobookshelf.group};
        users.${globals.audiobookshelf.user} = {
          isSystemUser = true;
          group = globals.audiobookshelf.group;
          uid = globals.uids.${globals.audiobookshelf.user};
        };
      };

      systemd.tmpfiles.rules = [
        "d '${cfg.stateDir}' 0700 ${globals.audiobookshelf.user} root - -"

        # Media Dirs
        "d '${nixarr.mediaDir}/library/audiobooks'  0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
        "d '${nixarr.mediaDir}/library/podcasts'    0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      ];

      systemd.services.audiobookshelf = {
        description = "Audiobookshelf is a self-hosted audiobook and podcast server";

        after = ["network.target"];
        wantedBy = ["multi-user.target"];

        serviceConfig = {
          IOSchedulingPriority = 0;
          Type = "simple";
          User = globals.audiobookshelf.user;
          Group = globals.audiobookshelf.group;
          StateDirectory = cfg.stateDir;
          WorkingDirectory = cfg.stateDir;
          ExecStart = "${cfg.package}/bin/audiobookshelf --host ${host} --port ${toString cfg.port}";
          Restart = "on-failure";

          # Security
          ProtectHome = true;
          PrivateTmp = true;
          PrivateDevices = true;
          ProtectHostname = true;
          ProtectClock = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectKernelLogs = true;
          ProtectControlGroups = true;
          NoNewPrivileges = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          RemoveIPC = true;
          PrivateMounts = true;
          ProtectSystem = "strict";
          ReadWritePaths = [cfg.stateDir];
        };
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
              proxyPass = "http://127.0.0.1:${builtins.toString cfg.port}";
            };
          };
        })
        (mkIf cfg.vpn.configureNginx {
          virtualHosts."127.0.0.1:${builtins.toString cfg.port}" = mkIf cfg.vpn.enable {
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
        })
      ];

      security.acme = mkIf cfg.expose.https.enable {
        acceptTerms = true;
        defaults.email = cfg.expose.https.acmeMail;
      };

      # Enable and specify VPN namespace to confine service in.
      systemd.services.audiobookshelf.vpnConfinement = mkIf cfg.vpn.enable {
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
    };
}
