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
      defaultText = literalExpression ''!nixarr.sabnzbd.vpn.enable'';
      default = !cfg.vpn.enable;
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
  };

  config = let
    concatStringsCommaIfExists = with lib.strings;
      stringList: (
        optionalString (builtins.length stringList > 0) (
          concatStringsSep "," stringList
        )
      );
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
      ];

      users = {
        groups.${globals.sabnzbd.group}.gid = globals.gids.${globals.sabnzbd.group};
        users.${globals.sabnzbd.user} = {
          isSystemUser = true;
          group = globals.sabnzbd.group;
          uid = globals.uids.${globals.sabnzbd.user};
        };
      };

      systemd.tmpfiles.settings."10-nixarr-sabnzbd" = let
        sabnzbd-rule = perms: {
          user = globals.sabnzbd.user;
          group = globals.libraryOwner.group;
          mode = perm;
        };
      in {
        "${nixarr.mediaDir}/usenet".d = sabnzbd-rule "0755";
        "${nixarr.mediaDir}/usenet/.incomplete".d = sabnzbd-rule "0755";
        "${nixarr.mediaDir}/usenet/.watch".d = sabnzbd-rule "0755";
        "${nixarr.mediaDir}/usenet/manual".d = sabnzbd-rule "0775";
        "${nixarr.mediaDir}/usenet/lidarr".d = sabnzbd-rule "0775";
        "${nixarr.mediaDir}/usenet/radarr".d = sabnzbd-rule "0775";
        "${nixarr.mediaDir}/usenet/sonarr".d = sabnzbd-rule "0775";
        "${nixarr.mediaDir}/usenet/readarr".d = sabnzbd-rule "0775";
      };

      services.sabnzbd = {
        enable = true;
        package = cfg.package;
        user = globals.sabnzbd.user;
        group = globals.sabnzbd.group;

        settings = {
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
      };

      networking.firewall.allowedTCPPorts = mkIf cfg.openFirewall [cfg.guiPort];

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

      services.nginx = mkIf cfg.vpn.enable {
        enable = true;

        recommendedTlsSettings = true;
        recommendedOptimisation = true;
        recommendedGzipSettings = true;

        virtualHosts."127.0.0.1:${builtins.toString cfg.guiPort}" = {
          listen = [
            {
              addr = "0.0.0.0";
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
