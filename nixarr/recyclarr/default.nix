{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.recyclarr;
  globals = config.util-nixarr.globals;
  nixarr = config.nixarr;
  # This is a carbon copy of the yaml implementation in nixpkgs https://github.com/NixOS/nixpkgs/blob/fde6c4aec177afa2d0248b1c5983e2a72a231442/pkgs/pkgs-lib/formats.nix#L210-L231
  # except we've replaced json2yaml for yq-go to allow it to parse custom yaml tags
  # ideally this would some day be upstreamed, see https://github.com/NixOS/nix/issues/4910 and https://github.com/rasmus-kirk/nixarr/issues/91
  yamlGenerator = {preserved-tags ? []}: let
    selectors =
      pkgs.lib.strings.concatStringsSep "|"
      (builtins.map (
          # this is yq for "for all the scalers, if they match this regex, do a regex substitution and set the tag"
          x: ''
            with((.. | select(kind == "scalar") | select(tag == "!!str") | select(test("^!${x} .*"))); . = sub("!${x} ", "") | . tag="!${x}")
          ''
        )
        preserved-tags);
  in {
    generate = name: value:
      pkgs.callPackage (
        {
          runCommand,
          yq-go,
        }:
          runCommand name
          {
            nativeBuildInputs = [yq-go];
            value = builtins.toJSON value;
            passAsFile = ["value"];
            preferLocalBuild = true;
          }
          ''
            yq '${selectors}' "$valuePath" -o yaml > $out
          ''
      ) {};
    type = let
      baseType = pkgs.lib.types.oneOf [
        pkgs.lib.types.bool
        pkgs.lib.types.int
        pkgs.lib.types.float
        pkgs.lib.types.str
        (pkgs.lib.types.attrsOf valueType)
        (pkgs.lib.types.listOf valueType)
      ];
      valueType =
        (pkgs.lib.types.nullOr baseType)
        // {
          description = "Yaml value";
        };
    in
      valueType;
  };
  format = yamlGenerator {
    preserved-tags = ["env_var"];
  };

  # Generate configuration file from Nix attribute set if provided
  generatedConfigFile = format.generate "recyclarr-config.yml" cfg.configuration;

  # Determine which config file to use
  effectiveConfigFile =
    if cfg.configFile != null
    then cfg.configFile
    else generatedConfigFile;
in {
  options.nixarr.recyclarr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Recyclarr service. This service does not need to be run behind a VPN.
      '';
    };

    package = mkPackageOption pkgs "recyclarr" {};

    schedule = lib.mkOption {
      type = lib.types.str;
      default = "daily";
      description = "When to run recyclarr in systemd calendar format.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/recyclarr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/recyclarr"'';
      example = "/nixarr/.state/recyclarr";
      description = "The location of the state directory for the Recyclarr service.";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to the recyclarr YAML configuration file. See [Recyclarr's
        documentation](https://recyclarr.dev/wiki/yaml/config-reference)
        for more information.

        The API keys for Radarr and Sonarr can be referenced in the config
        file using the `RADARR_API_KEY` and `SONARR_API_KEY` environment
        variables (with macro `!env_var`).

        Note: You cannot set both `configFile` and `configuration` options.
      '';
      example = "./recyclarr.yaml";
    };

    configuration = mkOption {
      type = types.nullOr format.type;
      default = null;
      example = literalExpression ''
        {
          sonarr = {
            series = {
              base_url = "http://localhost:8989";
              api_key = "!env_var SONARR_API_KEY";
              quality_definition = {
                type = "series";
              };
              delete_old_custom_formats = true;
              custom_formats = [
                {
                  trash_ids = [
                    "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
                    "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
                  ];
                  assign_scores_to = [
                    {
                      name = "WEB-DL (1080p)";
                      score = -10000;
                    }
                  ];
                }
              ];
            };
          };
          radarr = {
            movies = {
              base_url = "http://localhost:7878";
              api_key = "!env_var RADARR_API_KEY";
              quality_definition = {
                type = "movie";
              };
              delete_old_custom_formats = true;
              custom_formats = [
                {
                  trash_ids = [
                    "570bc9ebecd92723d2d21500f4be314c" # Remaster
                    "eca37840c13c6ef2dd0262b141a5482f" # 4K Remaster
                  ];
                  assign_scores_to = [
                    {
                      name = "HD Bluray + WEB";
                      score = 25;
                    }
                  ];
                }
              ];
            };
          };
        }
      '';
      description = ''
        Recyclarr YAML configuration as a Nix attribute set. For detailed configuration options and examples,
        see the [official configuration reference](https://recyclarr.dev/wiki/yaml/config-reference/).

        The API keys for Radarr and Sonarr can be referenced using the `RADARR_API_KEY` and `SONARR_API_KEY`
        environment variables (with the string "!env_var RADARR_API_KEY").

        Note: You cannot set both `configFile` and `configuration` options.
      '';
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.enable -> (nixarr.radarr.enable || nixarr.sonarr.enable);
        message = ''
          The nixarr.recyclarr.enable option requires at least one of nixarr.radarr.enable
          or nixarr.sonarr.enable to be set, but neither was enabled.
        '';
      }
      {
        assertion = !(cfg.configFile != null && cfg.configuration != null);
        message = ''
          You cannot set both nixarr.recyclarr.configFile and nixarr.recyclarr.configuration.
          Please choose one method to configure Recyclarr.
        '';
      }
      {
        assertion = cfg.configFile != null || cfg.configuration != null;
        message = ''
          You must set either nixarr.recyclarr.configFile or nixarr.recyclarr.configuration.
        '';
      }
    ];

    users = {
      groups.${globals.recyclarr.group}.gid = globals.gids.${globals.recyclarr.group};
      users.${globals.recyclarr.user} = {
        isSystemUser = true;
        group = globals.recyclarr.group;
        uid = globals.uids.${globals.recyclarr.user};
        extraGroups =
          (optional nixarr.radarr.enable "radarr-api")
          ++ (optional nixarr.sonarr.enable "sonarr-api");
      };
    };

    services.recyclarr = {
      enable = true;
      package = cfg.package;
      schedule = cfg.schedule;
    };

    systemd.services.recyclarr-setup = {
      description = "Setup Recyclarr environment";
      requiredBy = ["recyclarr.service"];
      before = ["recyclarr.service"];
      requires =
        (optional nixarr.radarr.enable "radarr-api.service")
        ++ (optional nixarr.sonarr.enable "sonarr-api.service");
      after =
        (optional nixarr.radarr.enable "radarr-api.service")
        ++ (optional nixarr.sonarr.enable "sonarr-api.service");
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077"; # Results in 0600 permissions
        User = config.services.recyclarr.user;
        ExecStart = pkgs.writeShellScript "recyclar-setup" ''
          set -euo pipefail
          echo -n > '${cfg.stateDir}/env'
          ${optionalString nixarr.radarr.enable ''
            printf RADARR_API_KEY= >> '${cfg.stateDir}/env'
            cat '${nixarr.stateDir}/secrets/radarr.api-key' >> '${cfg.stateDir}/env'
          ''}
          ${optionalString nixarr.sonarr.enable ''
            printf SONARR_API_KEY= >> '${cfg.stateDir}/env'
            cat '${nixarr.stateDir}/secrets/sonarr.api-key' >> '${cfg.stateDir}/env'
          ''}
        '';
      };
    };

    systemd.services.recyclarr = {
      requires = ["recyclarr-setup.service"];
      after = ["recyclarr-setup.service"];
      serviceConfig = {
        ExecStart = lib.mkForce "${cfg.package}/bin/recyclarr sync --app-data ${cfg.stateDir} --config ${effectiveConfigFile}";
        EnvironmentFile = "${cfg.stateDir}/env";
        ReadWritePaths = [cfg.stateDir];
      };
    };

    systemd.tmpfiles.rules = [
      "d '${cfg.stateDir}' 0750 ${config.services.recyclarr.user} root - -"
      "f '${cfg.stateDir}/env' 0600 ${config.services.recyclarr.user} ${config.services.recyclarr.group} - -"
    ];
  };
}
