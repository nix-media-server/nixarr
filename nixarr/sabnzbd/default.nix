{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.sabnzbd;
  globals = config.util-nixarr.globals;
  nixarr = config.nixarr;
in {
  options.nixarr.sabnzbd = {
    enable = mkEnableOption "Enable the SABnzbd service.";

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/sabnzbd";
      defaultText = literalExpression ''"''${nixarr.stateDir}/sabnzbd"'';
      example = "/nixarr/.state/sabnzbd";
      description = ''
        The location of the state directory for the SABnzbd service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/sabnzbd
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    package = mkPackageOption pkgs "sabnzbd" {};

    guiPort = mkOption {
      type = types.port;
      default = 6336;
      example = 9999;
      description = ''
        The port that SABnzbd's GUI will listen on for incomming connections.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = "Open firewall for SABnzbd";
    };

    whitelistHostnames = mkOption {
      type = types.listOf types.str;
      default = [config.networking.hostName];
      defaultText = literalExpression ''[ config.networking.hostName ]'';
      example = literalExpression ''[ "mediaserv" "media.example.com" ]'';
      description = ''
        A list that specifies what URLs that are allowed to represent your
        SABnzbd instance.

        > **Note:** If you see an error message like this when trying to connect to
        > SABnzbd from another device:
        >
        > ```
        > Refused connection with hostname "your.hostname.com"
        > ```
        >
        > Then you should add your hostname ("`hostname.com`" above) to
        > this list.
        >
        > SABnzbd only allows connections matching these URLs in order to prevent
        > DNS hijacking. See <https://sabnzbd.org/wiki/extra/hostname-check.html>
        > for more info.
      '';
    };

    whitelistRanges = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ''[ "192.168.1.0/24" "10.0.0.0/23" ]'';
      description = ''
        A list of IP ranges that will be allowed to connect to SABnzbd's
        web GUI. This only needs to be set if SABnzbd needs to be accessed
        from another machine besides its host.
      '';
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route SABnzbd traffic through the VPN.
      '';
    };

    vpn.configureNginx = mkOption {
      type = types.bool;
      default = cfg.vpn.enable;
      example = false;
      description = ''
        **Required options:** [`nixarr.sabnzbd.vpn.enable`)(#nixarr.sabnzbd.vpn.enable)

        Configure nginx as a reverse proxy for the Sabnzbd web ui.
      '';
      defaultText = literalExpression "nixarr.sabnzbd.vpn.enable";
    };
  };

  config = let
    ini-file-target = "${cfg.stateDir}/sabnzbd.ini";
    concatStringsCommaIfExists = with lib.strings;
      stringList: (
        optionalString (builtins.length stringList > 0) (
          concatStringsSep "," stringList
        )
      );

    user-configs = {
      misc = {
        host =
          if cfg.openFirewall
          then "0.0.0.0"
          else if cfg.vpn.enable
          then "192.168.15.1"
          else "127.0.0.1";
        port = cfg.guiPort;
        download_dir = "${nixarr.mediaDir}/usenet/.incomplete";
        complete_dir = "${nixarr.mediaDir}/usenet/manual";
        dirscan_dir = "${nixarr.mediaDir}/usenet/watch";
        host_whitelist = concatStringsCommaIfExists cfg.whitelistHostnames;
        local_ranges = concatStringsCommaIfExists cfg.whitelistRanges;
        permissions = "775";
      };
    };

    ini-base-config-file = pkgs.writeTextFile {
      name = "base-config.ini";
      text = lib.generators.toINI {} user-configs;
    };

    fix-config-permissions-script = pkgs.writeShellApplication {
      name = "sabnzbd-fix-config-permissions";
      runtimeInputs = with pkgs; [util-linux];
      text = ''
        if [ ! -f ${ini-file-target} ]; then
          echo 'FAILURE: cannot change permissions of ${ini-file-target}, file does not exist'
          exit 1
        fi

        chmod 600 ${ini-file-target}
        chown ${globals.sabnzbd.user}:${globals.sabnzbd.group} ${ini-file-target}
      '';
    };

    user-configs-to-python-list = with lib;
      attrsets.collect (f: !builtins.isAttrs f) (
        attrsets.mapAttrsRecursive (
          path: value:
            "sab_config_map['"
            + (lib.strings.concatStringsSep "']['" path)
            + "'] = '"
            + (builtins.toString value)
            + "'"
        )
        user-configs
      );

    apply-user-configs-script =
      pkgs.writers.writePython3Bin "sabnzbd-set-user-values" {
        libraries = [pkgs.python3Packages.configobj];
      } ''
        # flake8: noqa
        from pathlib import Path
        from configobj import ConfigObj

        sab_config_path = Path("${ini-file-target}")
        if not sab_config_path.is_file() or sab_config_path.suffix != ".ini":
            raise Exception(f"{sab_config_path} is not a valid config file path.")

        sab_config_map = ConfigObj(str(sab_config_path))

        ${lib.strings.concatStringsSep "\n" user-configs-to-python-list}

        sab_config_map.write()
      '';
  in
    mkIf (nixarr.enable && cfg.enable) {
      assertions = [
        {
          assertion = cfg.vpn.enable -> nixarr.vpn.enable;
          message = ''
            The nixarr.readarr.vpn.enable option requires the
            nixarr.vpn.enable option to be set, but it was not.
          '';
        }
        {
          assertion = cfg.vpn.configureNginx -> cfg.vpn.enable;
          message = ''
            The nixarr.sabnzbd.vpn.configureNginx option requires the
            nixarr.sabnzbd.vpn.enable option to be set, but it was not.
          '';
        }
      ];

      users = {
        groups.${globals.sabnzbd.group}.gid = globals.gids.${globals.sabnzbd.group};
        users.${globals.sabnzbd.user} = {
          isSystemUser = true;
          group = globals.sabnzbd.group;
          uid = globals.uids.${globals.sabnzbd.user};
        };
      };

      systemd.tmpfiles.rules = [
        "d '${cfg.stateDir}' 0700 ${globals.sabnzbd.user} root - -"
        "C ${cfg.stateDir}/sabnzbd.ini - - - - ${ini-base-config-file}"

        # Media dirs
        "d '${nixarr.mediaDir}/usenet'             0755 ${globals.sabnzbd.user} ${globals.sabnzbd.group} - -"
        "d '${nixarr.mediaDir}/usenet/.incomplete' 0755 ${globals.sabnzbd.user} ${globals.sabnzbd.group} - -"
        "d '${nixarr.mediaDir}/usenet/.watch'      0755 ${globals.sabnzbd.user} ${globals.sabnzbd.group} - -"
        "d '${nixarr.mediaDir}/usenet/manual'      0775 ${globals.sabnzbd.user} ${globals.sabnzbd.group} - -"
        "d '${nixarr.mediaDir}/usenet/lidarr'      0775 ${globals.sabnzbd.user} ${globals.sabnzbd.group} - -"
        "d '${nixarr.mediaDir}/usenet/radarr'      0775 ${globals.sabnzbd.user} ${globals.sabnzbd.group} - -"
        "d '${nixarr.mediaDir}/usenet/sonarr'      0775 ${globals.sabnzbd.user} ${globals.sabnzbd.group} - -"
        "d '${nixarr.mediaDir}/usenet/readarr'     0775 ${globals.sabnzbd.user} ${globals.sabnzbd.group} - -"
      ];

      services.sabnzbd = {
        enable = true;
        package = cfg.package;
        user = globals.sabnzbd.user;
        group = globals.sabnzbd.group;
        configFile = "${cfg.stateDir}/sabnzbd.ini";
      };

      networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.guiPort];

      systemd.services.sabnzbd.serviceConfig = {
        ExecStartPre = lib.mkBefore [
          ("+" + fix-config-permissions-script + "/bin/sabnzbd-fix-config-permissions")
          (apply-user-configs-script + "/bin/sabnzbd-set-user-values")
        ];
        Restart = "on-failure";
        StartLimitBurst = 5;
      };

      # Enable and specify VPN namespace to confine service in.
      systemd.services.sabnzbd.vpnConfinement = mkIf cfg.vpn.enable {
        enable = true;
        vpnNamespace = "wg";
      };

      # Port mappings
      vpnNamespaces.wg = mkIf cfg.vpn.enable {
        portMappings = [
          {
            from = cfg.guiPort;
            to = cfg.guiPort;
          }
        ];
      };

      services.nginx = mkIf cfg.vpn.configureNginx {
        enable = true;

        recommendedTlsSettings = true;
        recommendedOptimisation = true;
        recommendedGzipSettings = true;

        virtualHosts."127.0.0.1:${builtins.toString cfg.guiPort}" = {
          listen = [
            {
              addr = nixarr.vpn.proxyListenAddr;
              port = cfg.guiPort;
            }
          ];
          locations."/" = {
            recommendedProxySettings = true;
            proxyWebsockets = true;
            proxyPass = "http://192.168.15.1:${builtins.toString cfg.guiPort}";
          };
        };
      };
    };
}
