{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.anchorr;
  globals = config.util-nixarr.globals;
  nixarr = config.nixarr;
  port = 8282;

  settingsFormat = pkgs.formats.json {};
  generatedConfigFile = settingsFormat.generate "anchorr-config.json" cfg.configuration;

  effectiveConfigFile =
    if cfg.configFile != null
    then cfg.configFile
    else generatedConfigFile;
in {
  options.nixarr.anchorr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Anchorr service.
      '';
    };

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix {};
      defaultText = literalExpression "pkgs.callPackage ./package.nix {}";
      description = "The package used for the Anchorr service.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/anchorr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/anchorr"'';
      example = "/nixarr/.state/anchorr";
      description = ''
        The location of the state directory for the Anchorr service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/anchorr
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    port = mkOption {
      type = types.port;
      default = port;
      example = 12345;
      description = "Anchorr web-UI port.";
    };

    discordTokenFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/data/.secret/anchorr/discord-token";
      description = "Path to a file containing the Discord bot token.";
    };

    tmdbApiKeyFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/data/.secret/anchorr/tmdb-api-key";
      description = "Path to a file containing the TMDB API key.";
    };

    jellyseerr = {
      url = mkOption {
        type = types.str;
        default = "http://localhost:5055";
        example = "http://192.168.1.50:5055";
        description = "URL of the Jellyseerr instance.";
      };
      apiKeyFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        example = "/data/.secret/anchorr/jellyseerr-api-key";
        description = "Path to a file containing the Jellyseerr API key.";
      };
    };

    environmentFiles = mkOption {
      type = types.listOf types.path;
      default = [];
      example = literalExpression "[ config.sops.secrets.anchorr_env.path ]";
      description = "List of environment files (e.g., from sops-nix) containing secrets.";
    };

    secretsFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = "/data/.secret/anchorr/env";
      description = "Environment file containing secrets like DISCORD_TOKEN, TMDB_API_KEY, etc. This is a legacy option, prefer environmentFiles.";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to a custom config.json for Anchorr.";
    };

    configuration = mkOption {
      type = settingsFormat.type;
      default = {};
      example = literalExpression ''
        {
          discord = {
            bot_id = "123456789";
            guild_id = "987654321";
          };
        }
      '';
      description = "Anchorr configuration as a Nix attribute set. Generated as config.json.";
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.anchorr.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for Anchorr";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        **Conflicting options:** [`nixarr.anchorr.expose.https.enable`](#nixarr.anchorr.expose.https.enable)

        Route Anchorr traffic through the VPN.
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

            - [`nixarr.anchorr.expose.https.acmeMail`](#nixarr.anchorr.expose.https.acmemail)
            - [`nixarr.anchorr.expose.https.domainName`](#nixarr.anchorr.expose.https.domainname)

            **Conflicting options:** [`nixarr.anchorr.vpn.enable`](#nixarr.anchorr.vpn.enable)

            Expose the Anchorr web service to the internet with https support,
            allowing anyone to access it.

            > **Warning:** Do _not_ enable this without setting up Anchorr
            > authentication through localhost first!
          '';
        };

        upnp.enable = mkEnableOption "UPNP to try to open ports 80 and 443 on your router.";

        domainName = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "anchorr.example.com";
          description = "The domain name to host Anchorr on.";
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
          The nixarr.anchorr.vpn.enable option requires the
          nixarr.vpn.enable option to be set, but it was not.
        '';
      }
      {
        assertion = !(cfg.vpn.enable && cfg.expose.https.enable);
        message = ''
          The nixarr.anchorr.vpn.enable option conflicts with the
          nixarr.anchorr.expose.https.enable option. You cannot set both.
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
          The nixarr.anchorr.expose.https.enable option requires the
          following options to be set, but one of them were not:

          - nixarr.anchorr.expose.https.domainName
          - nixarr.anchorr.expose.https.acmeMail
        '';
      }
    ];

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}'        0750 ${globals.anchorr.user} ${globals.anchorr.group} - -"
      "d '${cfg.stateDir}/logs'   0750 ${globals.anchorr.user} ${globals.anchorr.group} - -"
      "d '${cfg.stateDir}/config' 0750 ${globals.anchorr.user} ${globals.anchorr.group} - -"
    ];

    systemd.services.anchorr-setup = {
      description = "Setup Anchorr configuration and environment";
      requiredBy = ["anchorr.service"];
      before = ["anchorr.service"];
      requires = optional nixarr.jellyseerr.enable "jellyseerr-api-key.service";
      after = optional nixarr.jellyseerr.enable "jellyseerr-api-key.service";

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
        # Setup runs as anchorr user to have access to its own secrets
        # (e.g. from sops-nix) which might be restricted to that user.
        User = globals.anchorr.user;
        Group = globals.anchorr.group;
        ExecStart = pkgs.writeShellScript "anchorr-setup" ''
          set -euo pipefail

          # Handle config.json
          cp '${effectiveConfigFile}' '${cfg.stateDir}/config/config.json'

          # Generate environment file with secrets from single files
          ENV_FILE='${cfg.stateDir}/env'
          echo "# Generated by nixarr-anchorr-setup" > "$ENV_FILE"

          ${optionalString (cfg.discordTokenFile != null) ''
            printf "DISCORD_TOKEN=" >> "$ENV_FILE"
            cat '${cfg.discordTokenFile}' >> "$ENV_FILE"
            echo "" >> "$ENV_FILE"
          ''}

          ${optionalString (cfg.tmdbApiKeyFile != null) ''
            printf "TMDB_API_KEY=" >> "$ENV_FILE"
            cat '${cfg.tmdbApiKeyFile}' >> "$ENV_FILE"
            echo "" >> "$ENV_FILE"
          ''}

          ${optionalString (cfg.jellyseerr.apiKeyFile != null) ''
            printf "JELLYSEERR_API_KEY=" >> "$ENV_FILE"
            cat '${cfg.jellyseerr.apiKeyFile}' >> "$ENV_FILE"
            echo "" >> "$ENV_FILE"
          ''}

          ${optionalString (nixarr.jellyseerr.enable && cfg.jellyseerr.apiKeyFile == null) ''
            if [[ -f '${nixarr.stateDir}/api-keys/jellyseerr.key' ]]; then
              printf "JELLYSEERR_API_KEY=" >> "$ENV_FILE"
              cat '${nixarr.stateDir}/api-keys/jellyseerr.key' >> "$ENV_FILE"
              echo "" >> "$ENV_FILE"
            fi
          ''}

          chmod 600 "$ENV_FILE"
        '';
      };
    };

    systemd.services.anchorr = {
      description = "Anchorr, a Discord bot for media requests";
      after = ["network.target" "anchorr-setup.service"];
      requires = ["anchorr-setup.service"];
      wantedBy = ["multi-user.target"];

      environment = {
        JELLYSEERR_URL = cfg.jellyseerr.url;
        WEBHOOK_PORT = toString cfg.port;
      };

      serviceConfig = {
        Type = "exec";
        StateDirectory = "anchorr";
        WorkingDirectory = cfg.stateDir;
        ExecStartPre = [
          (pkgs.writeShellScript "anchorr-pre-start" ''
            mkdir -p '${cfg.stateDir}'
            touch '${cfg.stateDir}/env'
          '')
        ];
        EnvironmentFile =
          ["-${cfg.stateDir}/env"]
          ++ (map (f: "-${toString f}") cfg.environmentFiles)
          ++ (optional (cfg.secretsFile != null) "-${toString cfg.secretsFile}");
        DynamicUser = false;
        User = globals.anchorr.user;
        Group = globals.anchorr.group;
        ExecStart = "${lib.getExe cfg.package}";
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
      groups.${globals.anchorr.group}.gid = globals.gids.${globals.anchorr.group};
      users.${globals.anchorr.user} = {
        isSystemUser = true;
        group = globals.anchorr.group;
        uid = globals.uids.${globals.anchorr.user};
        extraGroups = optional nixarr.jellyseerr.enable "jellyseerr-api";
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
            proxyPass = "http://127.0.0.1:${builtins.toString cfg.port}";
          };
        };
      })
      (mkIf cfg.vpn.enable {
        virtualHosts."127.0.0.1:${builtins.toString cfg.port}" = {
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
    systemd.services.anchorr.vpnConfinement = mkIf cfg.vpn.enable {
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
