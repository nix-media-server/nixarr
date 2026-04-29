{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    getExe
    literalExpression
    mkIf
    mkOption
    types
    ;

  inherit
    (pkgs.writers)
    writeJSON
    writePython3Bin
    ;

  nixarr = config.nixarr;
  globals = config.util-nixarr.globals;
  cfg = nixarr.bazarr.settings-sync;

  sync-settings = writePython3Bin "nixarr-sync-bazarr-settings" {
    libraries = [nixarr.nixarr-py.package];
    flakeIgnore = [
      "E501" # Line too long
    ];
  } (builtins.readFile ./sync_settings.py);

  wantedServices =
    ["bazarr-api.service"]
    ++ (lib.optional cfg.sonarr.enable "sonarr-api.service")
    ++ (lib.optional cfg.radarr.enable "radarr-api.service");

  sonarrConfigModule = {
    options = {
      ip = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "IP address or hostname of the Sonarr server.";
      };
      port = mkOption {
        type = types.port;
        default = nixarr.sonarr.port;
        defaultText = literalExpression "nixarr.sonarr.port";
        description = "Port of the Sonarr server.";
      };
      base_url = mkOption {
        type = types.str;
        default = "";
        description = "Base URL path for Sonarr (without leading/trailing slashes).";
      };
      ssl = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to use SSL when connecting to Sonarr.";
      };
      apiKeyFile = mkOption {
        type = types.path;
        default = "${nixarr.stateDir}/secrets/sonarr.api-key";
        defaultText = literalExpression ''"''${nixarr.stateDir}/secrets/sonarr.api-key"'';
        description = ''
          Path to file containing the API key for Sonarr.
        '';
      };
      sync_only_monitored_series = mkOption {
        type = types.bool;
        default = false;
        description = "Only sync monitored series from Sonarr.";
      };
      sync_only_monitored_episodes = mkOption {
        type = types.bool;
        default = false;
        description = "Only sync monitored episodes from Sonarr.";
      };
    };
  };

  radarrConfigModule = {
    options = {
      ip = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "IP address or hostname of the Radarr server.";
      };
      port = mkOption {
        type = types.port;
        default = nixarr.radarr.port;
        defaultText = literalExpression "nixarr.radarr.port";
        description = "Port of the Radarr server.";
      };
      base_url = mkOption {
        type = types.str;
        default = "";
        description = "Base URL path for Radarr (without leading/trailing slashes).";
      };
      ssl = mkOption {
        type = types.bool;
        default = false;
        description = "Whether to use SSL when connecting to Radarr.";
      };
      apiKeyFile = mkOption {
        type = types.path;
        default = "${nixarr.stateDir}/secrets/radarr.api-key";
        defaultText = literalExpression ''"''${nixarr.stateDir}/secrets/radarr.api-key"'';
        description = ''
          Path to file containing the API key for Radarr.
        '';
      };
      sync_only_monitored_movies = mkOption {
        type = types.bool;
        default = false;
        description = "Only sync monitored movies from Radarr.";
      };
    };
  };
in {
  options = {
    nixarr.bazarr.settings-sync = {
      sonarr = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Automatically configure Sonarr connection in Bazarr.
          '';
        };
        config = mkOption {
          type = types.submodule sonarrConfigModule;
          default = {};
          description = ''
            Configuration for Sonarr connection in Bazarr.
          '';
        };
      };

      radarr = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Automatically configure Radarr connection in Bazarr.
          '';
        };
        config = mkOption {
          type = types.submodule radarrConfigModule;
          default = {};
          description = ''
            Configuration for Radarr connection in Bazarr.
          '';
        };
      };
    };
  };

  config = mkIf (nixarr.enable && nixarr.bazarr.enable && (cfg.sonarr.enable || cfg.radarr.enable)) {
    assertions = [
      {
        assertion = cfg.sonarr.enable -> nixarr.sonarr.enable;
        message = "nixarr.bazarr.settings-sync.sonarr.enable requires nixarr.sonarr.enable to be true";
      }
      {
        assertion = cfg.radarr.enable -> nixarr.radarr.enable;
        message = "nixarr.bazarr.settings-sync.radarr.enable requires nixarr.radarr.enable to be true";
      }
    ];

    users.users.${globals.bazarr.user}.extraGroups =
      ["bazarr-api"]
      ++ (lib.optional cfg.sonarr.enable "sonarr-api")
      ++ (lib.optional cfg.radarr.enable "radarr-api");

    systemd.services.bazarr-sync-config = {
      description = ''
        Sync Bazarr configuration (Sonarr/Radarr connections)
      '';
      after = wantedServices;
      wants = wantedServices;
      wantedBy = ["bazarr.service"];
      serviceConfig = {
        Type = "oneshot";
        User = globals.bazarr.user;
        Group = globals.bazarr.group;
        RemainAfterExit = true;
        ExecStart = let
          config-file = writeJSON "bazarr-sync-config.json" ({
              bazarr_base_url = "http://127.0.0.1:${toString nixarr.bazarr.port}";
              bazarr_api_key_file = "${nixarr.stateDir}/secrets/bazarr.api-key";
            }
            // lib.optionalAttrs cfg.sonarr.enable {sonarr = cfg.sonarr.config;}
            // lib.optionalAttrs cfg.radarr.enable {radarr = cfg.radarr.config;});
        in ''
          ${getExe sync-settings} --config-file ${config-file}
        '';
      };
    };
  };
}
