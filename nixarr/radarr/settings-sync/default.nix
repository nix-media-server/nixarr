{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    types
    mkOption
    getExe
    mkIf
    ;

  inherit
    (pkgs.writers)
    writeJSON
    writePython3Bin
    ;

  nixarr = config.nixarr;
  globals = config.util-nixarr.globals;
  cfg = nixarr.radarr.settings-sync;

  nixarr-utils = import ../../lib/utils.nix {inherit pkgs lib config;};
  inherit (nixarr-utils) arrDownloadClientConfigType arrDownloadClientConfigModule;

  sync-settings = writePython3Bin "nixarr-sync-radarr-settings" {
    libraries = [nixarr.nixarr-py.package];
    flakeIgnore = [
      "E501" # Line too long
    ];
  } (builtins.readFile ./sync_settings.py);

  wantedServices = ["radarr-api.service"];
in {
  options = {
    nixarr.radarr.settings-sync = {
      downloadClients = mkOption {
        type = types.listOf (arrDownloadClientConfigType "radarr");
        default = [];
        description = ''
          List of download clients to configure in Radarr.

          To see available top-level properties and `fields` members for each
          download client, run `nixarr show-radarr-schemas download_client | jq
          '.'` as root.
        '';
      };

      transmission = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Automatically configure Transmission as a download client in Radarr.
          '';
        };
        config = mkOption {
          type = types.submodule [
            (arrDownloadClientConfigModule "radarr")
            {
              config = {
                name = "Transmission";
                implementation = "Transmission";
                enable = true;
                fields = {
                  # We can use localhost even if Sonarr or Transmission are in
                  # the VPN because nginx proxies the Transmission port when
                  # needed.
                  host = "localhost";
                  port = nixarr.transmission.uiPort;
                  useSsl = false;
                };
              };
            }
          ];
          default = {};
          defaultText = lib.literalExpression ''
            {
              name = "Transmission";
                implementation = "Transmission";
                enable = true;
                fields = {
                  host = "localhost";
                  port = nixarr.transmission.uiPort;
                  useSsl = false;
                };
              }
          '';
          description = ''
            Configuration for Transmission as a download client in Radarr.
          '';
        };
      };
    };
  };

  config = mkIf (nixarr.enable && nixarr.radarr.enable) {
    assertions = [
      {
        assertion = cfg.transmission.enable -> nixarr.transmission.enable;
        message = "nixarr.radarr.settings-sync.transmission.enable requires nixarr.transmission.enable to be true";
      }
    ];

    # Add Transmission config if enabled
    nixarr.radarr.settings-sync.downloadClients = mkIf cfg.transmission.enable [
      cfg.transmission.config
    ];

    users.users.radarr.extraGroups = ["radarr-api"];

    systemd.services.radarr-sync-config = {
      description = ''
        Sync Radarr configuration (download clients)
      '';
      after = wantedServices;
      wants = wantedServices;
      wantedBy = ["radarr.service"];
      serviceConfig = {
        Type = "oneshot";
        User = globals.radarr.user;
        Group = globals.radarr.group;
        RemainAfterExit = true;
        ExecStart = let
          config-file = writeJSON "radarr-sync-config.json" {
            download_clients = cfg.downloadClients;
          };
        in ''
          ${getExe sync-settings} --config-file ${config-file}
        '';
      };
    };
  };
}
