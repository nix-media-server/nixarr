{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.nixarr.ddns;
  nixarr = config.nixarr;
  ddns-njalla = pkgs.writeShellApplication {
    name = "ddns-njalla";

    runtimeInputs = with pkgs; [curl jq];

    # Thanks chatgpt...
    text = ''
      # Path to the JSON file
      json_file="$1"

      # Convert the JSON object into a series of tab-separated key-value pairs using jq
      # - `to_entries[]`: Convert the object into an array of key-value pairs.
      # - `[.key, .value]`: For each pair, create an array containing the key and the value.
      # - `@tsv`: Convert the array to a tab-separated string.
      # The output will be a series of lines, each containing a key and a value separated by a tab.
      jq_command='to_entries[] | [.key, .value] | @tsv'

      # Read the converted output line by line
      # - `IFS=$'\t'`: Use the tab character as the field separator.
      # - `read -r key val`: For each line, split it into `key` and `val` based on the tab separator.
      while IFS=$'\t' read -r key val; do
        # For each key-value pair, execute the curl command
        # Replace `''${key}` and `''${val}` in the URL with the actual key and value.
        curl -4 --connect-timeout 5 -s "https://njal.la/update/?h=''${key}&k=''${val}&auto" || echo "Error: Failed updating IPV4 record."
        curl -6 --connect-timeout 5 -s "https://njal.la/update/?h=''${key}&k=''${val}&auto" || echo "Error: Failed updating IPV6 record."
      done < <(jq -r "$jq_command" "$json_file")
    '';
  };
in {
  options.nixarr.ddns = {
    njalla = {
      vpn = {
        enable = mkOption {
          type = types.bool;
          default = false;
          example = true;
          description = ''
            **Required options:**

            - [`nixarr.ddns.njalla.vpn.keysFile`](#nixarr.ddns.njalla.keysfile)
            - [`nixarr.vpn.enable`](#nixarr.vpn.enable)

            Whether or not to enable DDNS over VPN for a
            [Njalla](https://njal.la/) domain. Setting this will point to
            the public ip of your VPN. Useful if you're running services
            over VPN and want a domain that points to the corresponding ip.

            > **Note:** You can enable both this and the regular njalla DDNS
            > service.
          '';
        };

        keysFile = mkOption {
          type = with types; nullOr path;
          default = null;
          example = "/data/.secret/njalla/keys-file.json";
          description = ''
            See [`nixarr.ddns.njalla.keysFile`](#nixarr.ddns.njalla.keysfile)
          '';
        };
      };
      enable = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          **Required options:**

          - [`nixarr.ddns.njalla.keysFile`](#nixarr.ddns.njalla.keysfile)

          Whether or not to enable DDNS for a [Njalla](https://njal.la/)
          domain.
        '';
      };

      keysFile = mkOption {
        type = with types; nullOr path;
        default = null;
        example = "/data/.secret/njalla/keys-file.json";
        description = ''
          A path to a JSON-file containing key value pairs of domains and keys.

          To get the keys, create a dynamic njalla record. Upon creation
          you should see something like the following command suggested:

          ```sh
            curl "https://njal.la/update/?h=jellyfin.example.com&k=zeubesojOLgC2eJC&auto"
          ```

          Then the JSON-file you pass here should contain:

          ```json
            {
              "jellyfin.example.com": "zeubesojOLgC2eJC"
            }
          ```

          You can, of course, add more key-value pairs than just one.
        '';
      };
    };
  };

  config = mkIf nixarr.enable {
    assertions = [
      {
        assertion = cfg.njalla.enable -> cfg.njalla.keysFile != null;
        message = ''
          The nixarr.ddns.njalla.enable option requires the
          nixarr.ddns.njalla.keysFile option to be set, but it was not.
        '';
      }
      {
        assertion = cfg.njalla.vpn.enable -> cfg.njalla.vpn.keysFile != null;
        message = ''
          The nixarr.ddns.njalla.enable option requires the nixarr.vpn.keysFile
          option to be set (not null), but it was not.
        '';
      }
      {
        assertion = cfg.njalla.vpn.enable -> config.nixarr.vpn.enable;
        message = ''
          The nixarr.ddns.njalla.enable option requires the nixarr.vpn.enable
          option to be set, but it was not.
        '';
      }
    ];

    systemd.timers = mkMerge [
      (mkIf cfg.njalla.enable {
        ddnsNjalla = {
          description = "Timer for setting the Njalla DDNS records";

          timerConfig = {
            OnBootSec = "30"; # Run 30 seconds after system boot
            OnCalendar = "hourly";
            Persistent = true; # Run service immediately if last window was missed
            RandomizedDelaySec = "5min"; # Run service OnCalendar +- 5min
          };

          wantedBy = ["multi-user.target"];
        };
      })
      (mkIf cfg.njalla.vpn.enable {
        ddnsNjallaVpn = {
          description = "Timer for setting the Njalla DDNS records over VPN";

          timerConfig = {
            OnBootSec = "30"; # Run 30 seconds after system boot
            OnCalendar = "hourly";
            Persistent = true; # Run service immediately if last window was missed
            RandomizedDelaySec = "5min"; # Run service OnCalendar +- 5min
          };

          wantedBy = ["multi-user.target"];
        };
      })
    ];

    systemd.services = mkMerge [
      (mkIf cfg.njalla.enable {
        ddnsNjalla = {
          description = "Sets the Njalla DDNS records";

          serviceConfig = {
            ExecStart = ''${getExe ddns-njalla} "${cfg.njalla.keysFile}"'';
            Type = "oneshot";
          };
        };
      })
      (mkIf (cfg.njalla.vpn.enable && config.nixarr.vpn.enable) {
        ddnsNjallaVpn = {
          description = "Sets the Njalla DDNS records over VPN";

          vpnConfinement = {
            enable = true;
            vpnNamespace = "wg";
          };

          serviceConfig = {
            ExecStart = ''${getExe ddns-njalla} "${cfg.njalla.vpn.keysFile}"'';
            Type = "oneshot";
          };
        };
      })
    ];
  };
}
