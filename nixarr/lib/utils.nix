{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    concatMapStringsSep
    filter
    getExe
    isString
    mkOption
    pipe
    split
    toSentenceCase
    types
    ;

  inherit
    (pkgs)
    writeShellApplication
    ;

  mkArrLocalUrl = service: let
    server =
      if (config ? services && config.services ? ${service} && config.services.${service} ? settings && config.services.${service}.settings ? server)
      then config.services.${service}.settings.server
      else {port = 0;};
  in "http://127.0.0.1:${toString server.port}${server.urlBase or ""}";

  # Turns `readarr` into `Readarr` and `readarr-audiobook` into
  # `Readarr-Audiobook`.
  toKebabSentenceCase = str:
    pipe str [
      (split "-")
      (filter isString)
      (concatMapStringsSep "-" toSentenceCase)
    ];

  secretFileType = types.submodule {
    options = {
      secret = mkOption {
        type = types.pathWith {
          inStore = false; # Secret files should not be in the Nix store
          absolute = true;
        };
        description = ''
          Path to a file containing a secret value. Must be readable by the
          relevant service user or group!
        '';
      };
    };
  };

  arrCfgType = with types; attrsOf (oneOf [str bool int secretFileType (listOf int) (listOf str)]);

  # Use submodule merge semantics for the fields attribute of *arr config
  # options. This lets us provide partial defaults.
  arrFieldsType = types.submodule {freeformType = arrCfgType;};

  waitForService = {
    service,
    url,
    max-secs-per-attempt ? 5,
    secs-between-attempts ? 5,
  }:
    getExe (writeShellApplication {
      name = "wait-for-${service}";
      runtimeInputs = [pkgs.curl];
      text = ''
        while ! curl \
            --silent \
            --fail \
            --max-time ${toString max-secs-per-attempt} \
            --output /dev/null \
            '${url}'; do
          echo "Waiting for ${service} at '${url}'..."
          sleep ${toString secs-between-attempts}
        done
        echo "${service} is available at '${url}'"
      '';
    });

  waitForArrService = args:
    waitForService (args
      // {
        url = args.url or mkArrLocalUrl args.service;
      });

  arrDownloadClientConfigModule = service: let
    Service = toKebabSentenceCase service;
  in {
    freeformType = arrCfgType;
    options = {
      name = mkOption {
        type = types.str;
        description = ''
          The name ${Service} uses for this download client. Note that names
          must be unique among *all download clients*, *ignoring case*.
        '';
      };
      implementation = mkOption {
        type = types.str;
        description = ''
          The implementation name of the download client in ${Service}. This is
          used to find the default configuration when adding a new download
          client, and must match the existing download client's implementation
          name when overwriting an existing download client.
        '';
      };
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether the download client is enabled. Note that this option is
          merely copied by Nixarr to ${Service}; it doesn't control any Nixarr
          behavior.
        '';
      };
      fields = mkOption {
        type = arrCfgType;
        default = {};
        description = ''
          Fields to set on the configuration for a download client. Other
          configuration options are left unchanged from their defaults (for new
          download clients) or existing values (for overwritten download
          clients).

          In the schema, these are represented as an array of objects with
          `.name` and `.value` members. Each attribute in this config attrset
          will update the `.value` member of the `fields` item with a matching
          `.name`. For more details on each field, check the schema.
        '';
      };
    };
  };

  arrDownloadClientConfigType = service:
    types.submodule (arrDownloadClientConfigModule service);

  arrServiceNames = [
    "lidarr"
    "prowlarr"
    "radarr"
    "readarr-audiobook"
    "readarr"
    "sonarr"
    "whisparr"
  ];
in {
  inherit
    arrCfgType
    arrDownloadClientConfigModule
    arrDownloadClientConfigType
    arrFieldsType
    arrServiceNames
    mkArrLocalUrl
    secretFileType
    toKebabSentenceCase
    waitForService
    waitForArrService
    ;
}
