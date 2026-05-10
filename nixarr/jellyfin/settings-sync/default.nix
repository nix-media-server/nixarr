{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    concatMap
    flatten
    getExe
    mkDefault
    mkIf
    mkOption
    optionalString
    types
    unique
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
  globals = config.util-nixarr.globals;

  # Collect all unique paths from library configurations
  libraryPaths = unique (flatten (map (l: l.paths) jellyfin.libraries));

  sync-users = writePython3Bin "nixarr-sync-jellyfin-users" {
    libraries = [nixarr-py];
    flakeIgnore = [
      "E501" # Line too long
    ];
  } (builtins.readFile ./sync_users.py);

  sync-libraries = writePython3Bin "nixarr-sync-jellyfin-libraries" {
    libraries = [nixarr-py pkgs.python3Packages.requests];
    flakeIgnore = [
      "E501" # Line too long
    ];
  } (builtins.readFile ./sync_libraries.py);

  usersConfigFile = writeJSON "jellyfin-users.json" {
    users =
      map (u: {
        name = u.name;
        passwordFile = u.passwordFile;
        isAdministrator = u.isAdministrator;
      })
      jellyfin.users;
  };

  librariesConfigFile = writeJSON "jellyfin-libraries.json" {
    libraries =
      map (l: {
        name = l.name;
        type = l.type;
        paths = l.paths;
        enabled = l.enable;
      })
      jellyfin.libraries;
  };
in {
  options = {};

  config = mkIf (nixarr.enable && jellyfin.enable) {
    # Automatically enable the API when users or libraries are configured, since it's required
    nixarr.jellyfin.api.enable = mkIf (jellyfin.users != [] || jellyfin.libraries != []) (mkDefault true);

    # Create directories for library paths
    systemd.tmpfiles.rules = mkIf (jellyfin.libraries != []) (
      map (path: "d '${path}' 0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -") libraryPaths
    );

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

    # Library sync service - only created if libraries are configured
    systemd.services.jellyfin-libraries-sync = mkIf (jellyfin.libraries != []) {
      description = "Sync Jellyfin libraries from declarative configuration";
      after = ["jellyfin-api.service"];
      requires = ["jellyfin-api.service"];
      wantedBy = ["multi-user.target"];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = "10s";

        ExecStart = "${getExe sync-libraries} --config-file ${librariesConfigFile}";
      };
    };
  };
}
