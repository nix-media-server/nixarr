{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    getExe
    mkDefault
    mkIf
    mkOption
    optionalString
    types
    ;

  inherit
    (pkgs.writers)
    writePython3Bin
    writeJSON
    ;

  nixarr-utils = import ../../lib/utils.nix {inherit config lib pkgs;};
  inherit (nixarr-utils) waitForService;

  nixarr = config.nixarr;
  jellyfin = nixarr.jellyfin;
  cfg = jellyfin.settings-sync;
  nixarr-py = nixarr.nixarr-py.package;

  sync-users = writePython3Bin "nixarr-sync-jellyfin-users" {
    libraries = [nixarr-py];
    flakeIgnore = [
      "E501" # Line too long
    ];
  } (builtins.readFile ./sync_users.py);

  usersConfigFile = writeJSON "jellyfin-users.json" {
    users =
      map (u: {
        name = u.name;
        passwordFile = u.passwordFile;
        isAdministrator = u.isAdministrator;
      })
      jellyfin.users;
  };
in {
  options = {};

  config = mkIf (nixarr.enable && jellyfin.enable) {
    # Automatically enable the API when users are configured, since it's required
    nixarr.jellyfin.api.enable = mkIf (jellyfin.users != []) (mkDefault true);

    # User sync service - only created if users are configured
    systemd.services.jellyfin-users-sync = mkIf (jellyfin.users != []) {
      description = "Sync Jellyfin users from declarative configuration";
      after = ["jellyfin-api.service"];
      requires = ["jellyfin-api.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "10s";

        ExecStart = "${getExe sync-users} --config-file ${usersConfigFile}";
      };
    };
  };
}
