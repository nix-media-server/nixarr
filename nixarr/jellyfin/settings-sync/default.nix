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

  nixarr-utils = import ../../lib/utils.nix {inherit config lib pkgs;};
  inherit (nixarr-utils) waitForService;

  nixarr = config.nixarr;
  jellyfin = nixarr.jellyfin;
  cfg = jellyfin.settings-sync;
  nixarr-py = nixarr.nixarr-py.package;

  set-up-api = writePython3Bin "nixarr-set-up-jellyfin-api" {
    libraries = [nixarr-py];
    flakeIgnore = [
      "E501" # Line too long
    ];
  } (builtins.readFile ./set_up_api.py);
in {
  options = {
    nixarr.jellyfin.settings-sync = {
      username = mkOption {
        type = types.str;
        default = "jellyfin";
        description = ''
          The username of the Jellyfin user used by Nixarr scripts.
        '';
      };
      passwordFile = mkOption {
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
      autoCreatePasswordFile = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to automatically create the password file with a random
          password if it doesn't exist.
        '';
      };
      autoCreateUserAndCompleteWizard = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to create the configured user and complete the Jellyfin
          initial setup wizard automatically, if the wizard hasn't been
          completed.
        '';
      };
    };
  };

  config = mkIf (nixarr.enable && jellyfin.enable) {
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

        ExecStart = ''
          ${getExe set-up-api} \
            ${optionalString cfg.autoCreateUserAndCompleteWizard "--auto-create-user-and-complete-wizard"} \
            ${optionalString cfg.autoCreatePasswordFile "--auto-create-password-file"}
        '';
      };
    };
  };
}
