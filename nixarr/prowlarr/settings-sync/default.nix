{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    filter
    getExe
    literalExpression
    mkDefault
    mkIf
    mkOption
    toSentenceCase
    types
    ;

  inherit
    (pkgs.writers)
    writeJSON
    writePython3Bin
    ;

  nixarr = config.nixarr;
  cfg = nixarr.prowlarr.settings-sync;

  nixarr-utils = import ../../lib/utils.nix {inherit config lib pkgs;};
  inherit
    (nixarr-utils)
    arrCfgType
    arrFieldsType
    arrServiceNames
    mkArrLocalUrl
    toKebabSentenceCase
    ;

  nixarr-py = nixarr.nixarr-py.package;

  sync-settings = writePython3Bin "nixarr-sync-prowlarr-settings" {
    libraries = [nixarr-py];
    flakeIgnore = [
      "E501" # Line too long
    ];
  } (builtins.readFile ./sync_settings.py);

  appConfigModule = {
    freeformType = arrCfgType;
    options = {
      name = mkOption {
        type = types.str;
        description = ''
          The name Prowlarr uses for this instance of an application. Note
          that app names must be unique among *all* apps (not just apps of
          this type), *ignoring case*.
        '';
      };
      implementation = mkOption {
        type = types.str;
        description = ''
          The implementation name of the application in Prowlarr. This is used
          to find the default configuration when adding a new application, and
          must match the existing application's implementation name when
          overwriting an existing application.
        '';
      };
      tags = mkOption {
        type = with types; listOf str;
        default = [];
        description = ''
          List of tag labels to associate with this application. Overwrites
          any existing tags on the application.
        '';
      };
      fields = mkOption {
        type = arrFieldsType;
        default = {};
        description = ''
          Additional fields to set on the application configuration. Other
          configuration options are left unchanged from their defaults (for
          new applications) or existing values (for overwritten applications).

          In the schema, these are represented as an array of objects with
          `.name` and `.value` members. Each attribute in this config attrSset
          will update the `.value` member of the `fields` item with a matching
          `.name`. For more details on each field, check the schema.
        ''; # TODO: add schema to `nixarr` utility command?
        example = {
          syncCategories = [2030];
          syncRejectBlocklistedTorrentHashesWhileGrabbing = true;
          somePassword = {
            secret = "/path/to/secret/file";
          };
        };
      };
    };
  };

  appConfigType = types.submodule appConfigModule;

  mkNixarrAppOptions = {
    service,
    implementation ? toSentenceCase service,
  }: {
    enable = mkOption {
      type = types.bool;
      default = cfg.enable-nixarr-apps;
      description = ''
        Whether to sync the config for this Nixarr-managed application to
        Prowlarr.
      '';
    };
    config = mkOption {
      type = types.submodule [
        appConfigModule
        {
          config = {
            name = mkDefault (toKebabSentenceCase service);
            implementation = mkDefault implementation;
            fields = {
              prowlarrUrl = mkDefault (mkArrLocalUrl "prowlarr");
              baseUrl = mkDefault (mkArrLocalUrl service);
              apiKey.secret = mkDefault "${nixarr.stateDir}/secrets/${service}.api-key";
            };
          };
        }
      ];
      default = {};
      defaultText = literalExpression ''
        {
          name = "${toKebabSentenceCase service}";
          implementation = "${implementation}";
          fields = {
            prowlarrUrl = "http://127.0.0.1:<prowlarr port>/<prowlarr base-url>";
            baseUrl = "http://127.0.0.1:<${service} port>/<${service} base-url>";
            apiKey.secret = "''${nixarr.stateDir}/secrets/${service}.api-key";
          };
        }
      '';
      description = ''
        Configuration for this application in Prowlarr.

        To see available top-level properties and `fields` members, run `nixarr
        show-prowlarr-schemas application | jq '.[] | select(.implementation ==
        "${implementation}")'` as root.
      '';
      example = {
        name = "My special service name";
        tags = ["tag1" "tag2"];
        fields = {
          syncCategories = [2030];
        };
      };
    };
  };

  nixarrAppConfigs = map (name: cfg.${name}.config) syncServiceNames;

  mkNixarrAppAssertion = service: {
    assertion =
      cfg.${service}.enable
      -> (config ? services.${service}.settings.auth.required)
      && config.services.${service}.settings.auth.required == "DisabledForLocalAddresses";
    message = ''
      nixarr.prowlarr.settings-sync.apps.${service}.enable requires
      config.services.${service}.settings.auth.required to be set to
      "DisabledForLocalAddresses", but it is not set to that value.
    '';
  };

  prowlarrAssertion = {
    assertion =
      (cfg.indexers != [])
      || cfg.tags != []
      || cfg.apps != []
      || nixarrAppConfigs != []
      -> (config ? services.prowlarr.settings.auth.required)
      && config.services.prowlarr.settings.auth.required == "DisabledForLocalAddresses";
    message = ''
      When Prowlarr is configured to sync indexers, tags, or apps, we
      require config.services.prowlarr.settings.auth.required to be set
      to "DisabledForLocalAddresses", but it is not set to that value.
    '';
  };

  indexerConfigType = types.submodule {
    freeformType = arrCfgType;
    options = {
      name = mkOption {
        type = with types; nullOr str;
        default = null;
        description = ''
          The name Prowlarr uses for this indexer. If not provided, the default
          name from the indexer definition is used.

          Note that indexer names must be unique among *all indexers*, *ignoring
          case*.
        '';
      };
      sort_name = mkOption {
        type = types.str;
        description = ''
          The sort name of the indexer definition to base this indexer on. This
          is used to find the default configuration when adding a new indexer,
          and must match the existing indexer's sort name when overwriting an
          existing indexer.
        '';
      };
      app_profile_name = mkOption {
        type = types.str;
        default = "Standard";
        description = ''
          The app profile to associate with this indexer. Must already exist.
          We look up this profile by name to set the appProfileId field on the
          indexer configuration.
        '';
      };
      tags = mkOption {
        type = with types; listOf str;
        default = [];
        description = ''
          List of tag labels to associate with this indexer. Overwrites any
          existing tags on the indexer.
        '';
      };
      fields = mkOption {
        type = arrFieldsType;
        default = {};
        description = ''
          Fields to set on the configuration for an indexer. Other configuration
          options are left unchanged from their defaults (for new indexers) or
          existing values (for overwritten indexers).

          In the schema, these are represented as an array of objects with
          `.name` and `.value` members. Each attribute in this config attrSset
          will update the `.value` member of the `fields` item with a matching
          `.name`. For more details on each field, check the schema.
        '';
      };
    };
  };

  syncServiceNames =
    filter
    (name:
      name != "prowlarr" && nixarr.${name}.enable && cfg.${name}.enable)
    arrServiceNames;

  extraGroups =
    map (service: config.users.groups."${service}-api".name)
    (syncServiceNames ++ ["prowlarr"]);

  wantedServices =
    map (service: "${service}-api.service")
    (syncServiceNames ++ ["prowlarr"]);
in {
  options = {
    nixarr.prowlarr.settings-sync = {
      # TODO: add sync interval?
      # TODO: allow configuring whether to overwrite existing items?
      # TODO: allow *deleting* items not in the config?

      enable-nixarr-apps = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Enable syncing information about Nixarr-managed applications to
          Prowlarr by default. You can override this per application.
        '';
      };

      sonarr = mkNixarrAppOptions {service = "sonarr";};
      radarr = mkNixarrAppOptions {service = "radarr";};
      lidarr = mkNixarrAppOptions {service = "lidarr";};
      readarr = mkNixarrAppOptions {service = "readarr";};
      readarr-audiobook = mkNixarrAppOptions {
        service = "readarr-audiobook";
        implementation = "Readarr";
      };
      whisparr = mkNixarrAppOptions {service = "whisparr";};

      apps = mkOption {
        type = with types; listOf appConfigType;
        default = [];
        description = ''
          List of applications to configure in Prowlarr. This is in addition to
          the Nixarr-managed application sync options.
        '';
      };

      tags = mkOption {
        type = with types; listOf str;
        default = [];
        description = ''
          List of tag labels to create in Prowlarr. Note that tag labels must
          be unique *ignoring case*.
        '';
      };

      indexers = mkOption {
        type = with types; listOf indexerConfigType;
        default = [];
        description = ''
          List of indexers to configure in Prowlarr.

          To see available top-level properties and `fields` members for each
          indexer, run `nixarr show-prowlarr-schemas indexer | jq '.'` as root.
          You may want to filter by `sort_name` to find the indexer you want to
          configure.
        '';
        example = [
          {
            name = "My special indexer name";
            sort_name = "nzbgeek";
            tags = ["tag1" "tag2"];
            priority = 30;
            fields = {
              apiKey.secret = "/path/to/secret/file";
            };
          }
        ];
      };
    };
  };

  config = mkIf (nixarr.enable && nixarr.prowlarr.enable) {
    users.users.prowlarr.extraGroups = extraGroups;

    assertions = [prowlarrAssertion] ++ (map mkNixarrAppAssertion syncServiceNames);

    systemd.services.prowlarr-sync-config = {
      description = ''
        Sync Prowlarr configuration (tags, indexers, applications)
      '';
      after = wantedServices;
      wants = wantedServices;
      wantedBy = ["prowlarr.service"];
      serviceConfig = {
        Type = "oneshot";
        User = "prowlarr";
        Group = "prowlarr";
        RemainAfterExit = true;
        ExecStart = let
          config-file = writeJSON "prowlarr-sync-config.json" {
            tag_labels = cfg.tags;
            app_configs = cfg.apps ++ nixarrAppConfigs;
            indexer_configs = cfg.indexers;
          };
        in ''
          ${getExe sync-settings} --config-file ${config-file}
        '';
      };
    };
  };
}
