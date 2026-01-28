inputs: {
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.unmanic;
  globals = config.util-nixarr.globals;
  defaultPort = 8888;
  nixarr = config.nixarr;
in {
  options.nixarr.unmanic = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the unmanic service.
      '';
    };

    port = mkOption {
      type = types.port;
      default = defaultPort;
      description = "Port for unmanic to use.";
    };

    package = mkPackageOption inputs.unmanic-nix.packages."${pkgs.system}" "unmanic" {};

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/unmanic";
      defaultText = literalExpression ''"''${nixarr.stateDir}/unmanic"'';
      example = "/nixarr/.state/unmanic";
      description = ''
        The location of the state directory for the Unmanic service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/unmanic
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    users = {
      groups.${globals.unmanic.group}.gid = globals.gids.${globals.unmanic.group};
      users.${globals.unmanic.user} = {
        isSystemUser = true;
        group = globals.unmanic.group;
        uid = globals.uids.${globals.unmanic.user};
      };
    };

    systemd.tmpfiles.rules = [
      "d '${nixarr.mediaDir}/library'             0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/shows'       0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/movies'      0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/music'       0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/books'       0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      "d '${nixarr.mediaDir}/library/audiobooks'  0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
    ];

    systemd.services.unmanic = {
      description = "Unmanic";
      after = ["network.target"];
      wantedBy = ["multi-user.target"];

      environment = {
        HOME = cfg.stateDir;
      };

      serviceConfig = {
        Type = "simple";
        User = globals.unmanic.user;
        Group = globals.unmanic.group;
        ExecStart = "${cfg.package}/bin/unmanic --port ${toString cfg.port}";
        StateDirectory = cfg.stateDir;
        WorkingDirectory = cfg.stateDir;
        Restart = "on-failure";
        RestartSec = 5;

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
      };
    };
  };
}
