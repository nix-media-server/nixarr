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

      IP4=$(curl -s -4 --connect-timeout 5 https://icanhazip.com || echo "")
      IP6=$(curl -s -6 --connect-timeout 5 https://icanhazip.com || echo "")

      # Read the converted output line by line
      # - `IFS=$'\t'`: Use the tab character as the field separator.
      # - `read -r key val`: For each line, split it into `key` and `val` based on the tab separator.
      while IFS=$'\t' read -r key val; do
        # Construct the base URL
        URL="https://njal.la/update/?h=''${key}&k=''${val}"

        # Append IPv4 if found
        if [ -n "$IP4" ]; then
          URL="''${URL}&a=''${IP4}"
        fi

        # Append IPv6 if found
        if [ -n "$IP6" ]; then
          URL="''${URL}&aaaa=''${IP6}"
        fi

        curl --connect-timeout 5 -s "$URL"
      done < <(jq -r "$jq_command" "$json_file")
    '';
  ddns-1984 = pkgs.writeShellApplication {
    name = "ddns-1984";

    runtimeInputs = with pkgs; [curl jq];

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
        # Construct the base URL
        URL="https://api.1984.is/1.0/freedns/?apikey=''${val}&domain=''${key}&ip="""

        curl --connect-timeout 5 -s "$URL"
      done < <(jq -r "$jq_command" "$json_file")
    '';
  };
in {
  options.nixarr.ddns = {
    njalla = {
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
    nineteenEightyFour = {
      enable = mkOption {
        type = types.bool;
        default = false;
        example = true;
        description = ''
          **Required options:**

          - [`nixarr.ddns.nineteenEightyFour.keysFile`](#nixarr.ddns.nineteenEightyFour.keysfile)

          Whether or not to enable DDNS for a [1984](https://1984.hosting/)
          domain.
        '';
      };

      keysFile = mkOption {
        type = with types; nullOr path;
        default = null;
        example = "/data/.secret/1984/keys-file.json";
        description = ''
          A path to a JSON-file containing key value pairs of domains and keys.

          To get the keys, create an A record. Remember to enable DDNS on
          that record. Then get your key at:

          https://1984.hosting/domains/freednsapi/

          The JSON-file you pass in this option should contain:

          ```json
            {
              "jellyfin.example.com": "E9L3eWL81e0IMwUNQrCvnA9KchBgLw9IUZb3Tb7156VdPtkyMjOEvx0KB97r5RgC"
            }
          ```

          You can, of course, add more key-value pairs than just one. However
          for this provider, all the API keys should be the same.
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
        assertion = cfg.nineteenEightyFour.enable -> cfg.nineteenEightyFour.keysFile != null;
        message = ''
          The nixarr.nineteenEightyFour.njalla.enable option requires the
          nixarr.nineteenEightyFour.keysFile option to be set (not null),
          but it was not.
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
      (mkIf cfg.nineteenEightyFour.enable {
        ddnsNjallaVpn = {
          description = "Timer for setting the 1984 DDNS records over VPN";
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
      (mkIf cfg.nineteenEightyFour.vpn.enable {
        ddnsNjallaVpn = {
          description = "Sets the 1984 DDNS records over VPN";
          serviceConfig = {
            ExecStart = ''${getExe ddns-1984} "${cfg.nineteenEightyFour.keysFile}"'';
            Type = "oneshot";
          };
        };
      })
    ];
  };
}
