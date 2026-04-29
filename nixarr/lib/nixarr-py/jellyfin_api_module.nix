{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    getExe
    mkIf
    mkOption
    optionalString
    types
    ;

  inherit
    (pkgs.writers)
    writePython3Bin
    ;

  nixarr-utils = import ../utils.nix {inherit config lib pkgs;};
  inherit (nixarr-utils) waitForService;

  nixarr = config.nixarr;
  jellyfin = nixarr.jellyfin;
  cfg = jellyfin.api;
  nixarr-py = nixarr.nixarr-py.package;

  set-up-api = getExe (writePython3Bin "nixarr-set-up-jellyfin-api" {
      libraries = [nixarr-py];
      flakeIgnore = [
        "E501" # Line too long
        "F401" # Imported but unused
        "W391" # Blank line at end of file
      ];
    } ''
      from nixarr_py.jellyfin_helpers import (
          ensure_admin_password_file,
          ensure_device_uuid_file,
          ensure_admin_user_created_and_wizard_completed,
          ensure_api_key_and_file,
      )


      ${optionalString cfg.autoCreateAdminPasswordFile ''
        ensure_admin_password_file()
      ''}
      ${optionalString cfg.autoCreateDeviceUuidFile ''
        ensure_device_uuid_file()
      ''}
      ${optionalString cfg.autoCreateAdminUserAndCompleteWizard ''
        ensure_admin_user_created_and_wizard_completed()
      ''}
      ${optionalString cfg.autoCreateApiKeyAndFile ''
        ensure_api_key_and_file()
      ''}
    '');
in {
  options = {
    nixarr.jellyfin.api = {
      enable = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          Whether or not to enable the Jellyfin API setup service for use with
          `nixarr-py`.
        '';
      };
      adminUsername = mkOption {
        type = types.str;
        default = "jellyfin";
        description = ''
          The username of the Jellyfin user used by Nixarr scripts.
        '';
      };
      adminPasswordFile = mkOption {
        type = types.pathWith {
          absolute = true;
          inStore = false;
        };
        default = "${nixarr.stateDir}/secrets/jellyfin.pw";
        description = ''
          Path to a file containing the password of the Jellyfin user used by
          Nixarr scripts.
        '';
      };
      apiKeyFile = mkOption {
        type = types.pathWith {
          absolute = true;
          inStore = false;
        };
        default = "${nixarr.stateDir}/secrets/jellyfin.api-key";
        description = ''
          Path to a file containing the Jellyfin API key used by Nixarr
          scripts.
        '';
      };
      deviceUuidFile = mkOption {
        type = types.pathWith {
          absolute = true;
          inStore = false;
        };
        default = "${nixarr.stateDir}/secrets/jellyfin.device-uuid";
        description = ''
          Path to a file containing the Jellyfin device UUID used by Nixarr
          scripts.
        '';
      };
      autoCreateAdminPasswordFile = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to automatically create the password file with a random
          password if it doesn't exist or is empty.
        '';
      };
      autoCreateApiKeyAndFile = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to automatically create the Jellyfin API key for Nixarr if it
          doesn't exist, and populate the API key file if it doesn't exist or is
          empty.
        '';
      };
      autoCreateAdminUserAndCompleteWizard = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to create the configured admin user and complete the Jellyfin
          initial setup wizard automatically, if the wizard hasn't been
          completed.
        '';
      };
      autoCreateDeviceUuidFile = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to automatically create the device UUID file with a random
          UUID if it doesn't exist or is empty.
        '';
      };
      nixarr-py-config = mkOption {
        type = types.attrsOf types.anything;
        default = {
          base_url = "http://localhost:${builtins.toString jellyfin.port}";
          admin_username = cfg.adminUsername;
          admin_password_file = cfg.adminPasswordFile;
          api_key_file = cfg.apiKeyFile;
          device_uuid_file = cfg.deviceUuidFile;
        };
        readOnly = true;
        description = ''
          The configuration for the Jellyfin section of the `nixarr-py` config
          file. Derived from other options.
        '';
      };
    };
  };

  config = mkIf (nixarr.enable && jellyfin.enable && cfg.enable) {
    users.groups.jellyfin-api = {};

    systemd.services.jellyfin-api = {
      description = "Wait for jellyfin API";
      after = ["jellyfin.service"];
      requires = ["jellyfin.service"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Group = "jellyfin-api";
        UMask = "0027"; # Results in 0640 permissions

        ExecStartPre = [
          (waitForService
            {
              service = "jellyfin";
              url = "http://localhost:${builtins.toString jellyfin.port}/System/Ping";
            })
        ];

        ExecStart = set-up-api;
      };
    };
  };
}
