{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit (lib) types mkOption mkIf;

  nixarr = config.nixarr;
  cfg = nixarr.sabnzbd.settings-sync;
  cfg-sab = nixarr.sabnzbd;

  ini-file = "${cfg-sab.stateDir}/sabnzbd.ini";

  sync-servers = pkgs.writers.writePython3Bin "nixarr-sync-sabnzbd-servers" {
    libraries = [pkgs.python3Packages.configobj];
  } (builtins.readFile ./sync_servers.py);

  servers-json = pkgs.writers.writeJSON "sabnzbd-servers.json" (
    map (s: {
      inherit (s) name host port ssl connections priority retention usernameFile passwordFile;
    })
    cfg.servers
  );
in {
  options.nixarr.sabnzbd.settings-sync = {
    servers = mkOption {
      default = [];
      description = ''
        Usenet servers for SABnzbd. When non-empty, **replaces** all
        server configuration on every service start.

        Example:

        ```nix
        nixarr.sabnzbd.settings-sync.servers = [
          {
            name = "my-provider";
            host = "news.example.com";
            usernameFile = config.sops.secrets."myprovider-user".path;
            passwordFile = config.sops.secrets."myprovider-pass".path;
          }
        ];
        ```
      '';
      type = types.listOf (types.submodule {
        options = {
          name = mkOption {
            type = types.str;
            example = "my-provider";
            description = "Unique display name for this server.";
          };
          host = mkOption {
            type = types.str;
            example = "news.example.com";
            description = "Hostname of the usenet server.";
          };
          port = mkOption {
            type = types.port;
            default = 563;
            description = "Port to connect on.";
          };
          ssl = mkOption {
            type = types.bool;
            default = true;
            description = "Use SSL/TLS.";
          };
          connections = mkOption {
            type = types.int;
            default = 1;
            description = "Number of simultaneous connections.";
          };
          usernameFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to a file containing the server username.";
          };
          passwordFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "Path to a file containing the server password.";
          };
          priority = mkOption {
            type = types.int;
            default = 0;
            description = "Server priority (0 = highest).";
          };
          retention = mkOption {
            type = types.int;
            default = 0;
            description = "Retention in days (0 = unlimited).";
          };
        };
      });
    };
  };

  config = mkIf (nixarr.enable && cfg-sab.enable && cfg.servers != []) {
    systemd.services.sabnzbd.serviceConfig.ExecStartPre = lib.mkAfter [
      "${sync-servers}/bin/nixarr-sync-sabnzbd-servers --ini-file ${ini-file} --servers-file ${servers-json}"
    ];
  };
}
