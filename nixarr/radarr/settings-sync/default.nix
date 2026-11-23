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

      rootFolders = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["/data/media/library/movies"];
        description = ''
          List of root folders to configure in Radarr.

          Folders that don't already exist as a root folder in Radarr are
          added; existing root folders are left untouched, unless
          `pruneRootFolders` is enabled.
        '';
      };

      pruneRootFolders = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Whether to remove root folders from Radarr that aren't listed in
          `rootFolders`.

          This only removes the root folder registration in Radarr; it
          never deletes any files on disk, and movies already tracked under
          the removed path stay in Radarr's library.
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
        Sync Radarr configuration (download clients, root folders)
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
            root_folders = cfg.rootFolders;
            prune_root_folders = cfg.pruneRootFolders;
          };
        in ''
          ${getExe sync-settings} --config-file ${config-file}
        '';
      };
    };
  };
}
