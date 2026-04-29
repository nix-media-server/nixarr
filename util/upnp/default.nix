# TODO: Dir creation and file permissions in nix
{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.util-nixarr.upnp;
in {
  options.util-nixarr.upnp = {
    enable = mkEnableOption "Enable port forwarding using UPNP.";

    openTcpPorts = mkOption {
      type = with types; listOf port;
      default = [];
      description = ''
        What TCP ports to open using UPNP.
      '';
      example = [46382 38473];
    };

    openUdpPorts = mkOption {
      type = with types; listOf port;
      default = [];
      description = ''
        What UDP ports to open using UPNP.
      '';
      example = [46382 38473];
    };
  };

  config = mkIf cfg.enable {
    # UPNPC firewall access, if not set, then upnpc will fail with "No IGD
    # UPnP Device found !"
    #
    # Alternatively, I also tried allowing all traffic from the router. But
    # I assume that the official way is cleaner/more secure:
    # ```nix
    #   networking.firewall.extraCommands = ''
    #     iptables -I INPUT -p udp -s 192.168.1.1 -j ACCEPT
    #     iptables -I OUTPUT -p udp -d  192.168.1.1 -j ACCEPT
    #   '';
    # ```
    #
    # See:
    # https://github.com/miniupnp/miniupnp/blob/8ced59d384de13689d3b1c32405bcb562030b241/miniupnpc/README
    #
    # TODO: Understand this properly
    networking.firewall.extraCommands = ''
      # Rules for IPv4:
      ${pkgs.ipset}/bin/ipset -exist create upnp hash:ip,port timeout 3
      iptables -A OUTPUT -d 239.255.255.250/32 -p udp -m udp --dport 1900 -j SET --add-set upnp src,src --exist
      iptables -A INPUT -p udp -m set --match-set upnp dst,dst -j ACCEPT
      iptables -A INPUT -d 239.255.255.250/32 -p udp -m udp --dport 1900 -j ACCEPT

      # Rules for IPv6:
      ${pkgs.ipset}/bin/ipset -exist create upnp6 hash:ip,port timeout 3 family inet6
      ip6tables -A OUTPUT -d ff02::c/128 -p udp -m udp --dport 1900 -j SET --add-set upnp6 src,src --exist
      ip6tables -A OUTPUT -d ff05::c/128 -p udp -m udp --dport 1900 -j SET --add-set upnp6 src,src --exist
      ip6tables -A INPUT -p udp -m set --match-set upnp6 dst,dst -j ACCEPT
      ip6tables -A INPUT -d ff02::c/128 -p udp -m udp --dport 1900 -j ACCEPT
      ip6tables -A INPUT -d ff05::c/128 -p udp -m udp --dport 1900 -j ACCEPT
    '';

    systemd = {
      services.upnpc = let
        upnp-ports = pkgs.writeShellApplication {
          name = "upnp-ports";

          runtimeInputs = with pkgs; [miniupnpc];

          text = (
            strings.concatMapStrings (x: "upnpc -r ${builtins.toString x} UDP" + "\n") cfg.openUdpPorts
            ++ strings.concatMapStrings (x: "upnpc -r ${builtins.toString x} TCP" + "\n") cfg.openTcpPorts
            ++ ''echo "Successfully requested upnp ports to be opened".''
          );
        };
      in
        mkIf cfg.enable {
          enable = true;
          description = "Sets port on router";
          script = "${upnp-ports}/bin/upnp-ports";

          serviceConfig = {
            User = "root";
            Type = "oneshot";
          };
        };

      timers = {
        upnpc = mkIf cfg.enable {
          description = "Sets port on router";
          wantedBy = ["timers.target"];

          timerConfig = {
            OnCalendar = "hourly";
            Persistent = "true"; # Run service immediately if last window was missed
            RandomizedDelaySec = "5m"; # Run service OnCalendar +- 1h
          };
        };
      };
    };
  };
}
