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
  cfg = nixarr.sonarr.settings-sync;

  nixarr-utils = import ../../lib/utils.nix {inherit pkgs lib config;};
  inherit (nixarr-utils) arrDownloadClientConfigType arrDownloadClientConfigModule;

  sync-settings = writePython3Bin "nixarr-sync-sonarr-settings" {
    libraries = [nixarr.nixarr-py.package];
    flakeIgnore = [
      "E501" # Line too long
    ];
  } (builtins.readFile ./sync_settings.py);

  wantedServices = ["sonarr-api.service"];
in {
  options = {
    nixarr.sonarr.settings-sync = {
      downloadClients = mkOption {
        type = types.listOf (arrDownloadClientConfigType "sonarr");
        default = [];
        description = ''
          List of download clients to configure in Sonarr.

          To see available top-level properties and `fields` members for each
          download client, run `nixarr show-sonarr-schemas download_client | jq '.'` as root.
        '';
      };

      rootFolders = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["/data/media/library/shows"];
        description = ''
          List of root folders to configure in Sonarr.

          Folders that don't already exist as a root folder in Sonarr are
          added; existing root folders are left untouched, unless
          `pruneRootFolders` is enabled.
        '';
      };

      pruneRootFolders = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Whether to remove root folders from Sonarr that aren't listed in
          `rootFolders`.

          This only removes the root folder registration in Sonarr; it
          never deletes any files on disk, and shows already tracked under
          the removed path stay in Sonarr's library.
        '';
      };

      transmission = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = ''
            Automatically configure Transmission as a download client in Sonarr.
          '';
        };
        config = mkOption {
          type = types.submodule [
            (arrDownloadClientConfigModule "sonarr")
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
            Configuration for Transmission as a download client in Sonarr.
          '';
        };
      };
    };
  };

  config = mkIf (nixarr.enable && nixarr.sonarr.enable) {
    assertions = [
      {
        assertion = cfg.transmission.enable -> nixarr.transmission.enable;
        message = "nixarr.sonarr.settings-sync.transmission.enable requires nixarr.transmission.enable to be true";
      }
    ];

    # Add Transmission config if enabled
    nixarr.sonarr.settings-sync.downloadClients = mkIf cfg.transmission.enable [
      cfg.transmission.config
    ];

    users.users.sonarr.extraGroups = ["sonarr-api"];

    systemd.services.sonarr-sync-config = {
      description = ''
        Sync Sonarr configuration (download clients, root folders)
      '';
      after = wantedServices;
      wants = wantedServices;
      wantedBy = ["sonarr.service"];
      serviceConfig = {
        Type = "oneshot";
        User = globals.sonarr.user;
        Group = globals.sonarr.group;
        RemainAfterExit = true;
        ExecStart = let
          config-file = writeJSON "sonarr-sync-config.json" {
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
