{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.seerr;
  globals = config.util-nixarr.globals;
  nixarr = config.nixarr;
  port = 5055;
in {
  options.nixarr.seerr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Seerr service.
      '';
    };

    package = mkPackageOption pkgs (
      if lib.versionAtLeast lib.version "26.05pre"
      then "seerr"
      else "jellyseerr"
    ) {};

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/seerr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/seerr"'';
      example = "/nixarr/.state/seerr";
      description = ''
        The location of the state directory for the Seerr service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/seerr
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    port = mkOption {
      type = types.port;
      default = port;
      example = 12345;
      description = "Seerr web-UI port.";
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Open firewall for Seerr";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        **Conflicting options:** [`nixarr.seerr.expose.https.enable`](#nixarr.seerr.expose.https.enable)

        Route Seerr traffic through the VPN.
      '';
    };

    vpn.configureNginx = mkOption {
      type = types.bool;
      default = cfg.vpn.enable;
      example = false;
      description = ''
        **Required options:** [`nixarr.seerr.vpn.enable`](#nixarr.seerr.vpn.enable)

        Configure nginx as a reverse proxy for the Seerr web ui.
      '';
      defaultText = literalExpression "nixarr.seerr.vpn.enable";
    };

    expose = {
      https = {
        enable = mkOption {
          type = types.bool;
          default = false;
          example = true;
          description = ''
            **Required options:**

            - [`nixarr.seerr.expose.https.acmeMail`](#nixarr.seerr.expose.https.acmemail)
            - [`nixarr.seerr.expose.https.domainName`](#nixarr.seerr.expose.https.domainname)

            **Conflicting options:** [`nixarr.seerr.vpn.enable`](#nixarr.seerr.vpn.enable)

            Expose the Seerr web service to the internet with https support,
            allowing anyone to access it.

            > **Warning:** Do _not_ enable this without setting up Seerr
            > authentication through localhost first!
          '';
        };

        upnp.enable = mkEnableOption "UPNP to try to open ports 80 and 443 on your router.";

        domainName = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "seerr.example.com";
          description = "The domain name to host Seerr on.";
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
          The nixarr.seerr.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
      {
        assertion = !(cfg.vpn.enable && cfg.expose.https.enable);
        message = ''
          The nixarr.seerr.vpn.enable option conflicts with the
          nixarr.seerr.expose.https.enable option. You cannot set both.
        '';
      }
      {
        assertion = cfg.vpn.configureNginx -> cfg.vpn.enable;
        message = ''
          The nixarr.seerr.vpn.configureNginx option requires the
          nixarr.seerr.vpn.enable option to be set, but it was not.
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
          The nixarr.seerr.expose.https.enable option requires the
          following options to be set, but one of them were not:

          - nixarr.seerr.expose.https.domainName
          - nixarr.seerr.expose.https.acmeMail
        '';
      }
    ];

    system.activationScripts.migrate-seerr-user = {
      deps = [];
      text = ''
        if ${pkgs.gnugrep}/bin/grep -q '^jellyseerr:' /etc/passwd && ! ${pkgs.gnugrep}/bin/grep -q '^seerr:' /etc/passwd; then
          echo "nixarr: renaming jellyseerr user to seerr in /etc/passwd"
          ${pkgs.gnused}/bin/sed -i --follow-symlinks 's/^jellyseerr:/seerr:/' /etc/passwd
        fi
        if ${pkgs.gnugrep}/bin/grep -q '^jellyseerr:' /etc/group && ! ${pkgs.gnugrep}/bin/grep -q '^seerr:' /etc/group; then
          echo "nixarr: renaming jellyseerr group to seerr in /etc/group"
          ${pkgs.gnused}/bin/sed -i --follow-symlinks 's/^jellyseerr:/seerr:/' /etc/group
        fi
      '';
    };

    system.activationScripts.users.deps = lib.mkAfter ["migrate-seerr-user"];

    system.activationScripts.migrate-seerr-state = {
      # Must run after user migration so the renamed seerr user owns the moved directory
      deps = ["users"];
      text = let
        oldDir = "${nixarr.stateDir}/jellyseerr";
      in ''
        if [ -d "${oldDir}" ] && [ ! -e "${cfg.stateDir}" ]; then
          echo "nixarr: migrating Seerr state directory from ${oldDir} to ${cfg.stateDir}"
          mv "${oldDir}" "${cfg.stateDir}"
        fi
      '';
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0700 ${globals.seerr.user} root - -"
    ];

    systemd.services.seerr = {
      description = "Open-source media request and discovery manager for Jellyfin, Plex, and Emby";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];
      environment = {
        PORT = toString cfg.port;
        CONFIG_DIRECTORY = cfg.stateDir;
      };

      serviceConfig = {
        Type = "exec";
        StateDirectory = "seerr";
        DynamicUser = false;
        User = globals.seerr.user;
        Group = globals.seerr.group;
        ExecStart = lib.getExe cfg.package;
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

    users = {
      groups.${globals.seerr.group}.gid = globals.gids.${globals.seerr.group};
      users.${globals.seerr.user} = {
        isSystemUser = true;
        group = globals.seerr.group;
        uid = globals.uids.${globals.seerr.user};
      };
    };

    networking.firewall = mkMerge [
      (mkIf cfg.expose.https.enable {
        allowedTCPPorts = [80 443];
      })
      (mkIf cfg.openFirewall {
        allowedTCPPorts = [cfg.port];
      })
    ];

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
      })
    ];

    security.acme = mkIf cfg.expose.https.enable {
      acceptTerms = true;
      defaults.email = cfg.expose.https.acmeMail;
    };

    # Enable and specify VPN namespace to confine service in.
    systemd.services.seerr.vpnConfinement = mkIf cfg.vpn.enable {
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
