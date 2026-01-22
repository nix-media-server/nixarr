{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr;

  # Helper function to determine if a service is VPN-confined
  isVpnConfined = service: cfg.${service}.enable && cfg.${service}.vpn.enable;

  # Helper to determine if an exporter should be enabled
  shouldEnableExporter = service:
    cfg.${service}.enable && cfg.${service}.exporter.enable;

  # Helper to determine if wireguard exporter should be enabled
  shouldEnableWireguardExporter =
    cfg.vpn.enable && cfg.wireguard.exporter.enable;
in {
  # apis.nix is already imported in nixarr/default.nix

  options = {
    nixarr = {
      exporters = {
        enable = mkEnableOption "Enable Prometheus exporters for all supported nixarr services";
      };

      wireguard.exporter = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to enable the Wireguard Prometheus exporter.
            Only has an effect if nixarr.exporters.enable and nixarr.vpn.enable are true.
          '';
        };
        port = mkOption {
          type = types.port;
          default = 9586;
          description = "Port for Wireguard metrics";
        };
        listenAddr = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = "Address for Wireguard exporter to listen on";
        };
      };

      sonarr.exporter = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to enable the Sonarr Prometheus exporter.
            Only has an effect if nixarr.exporters.enable and nixarr.sonarr.enable are true.
          '';
        };
        port = mkOption {
          type = types.port;
          default = 9707;
          description = "Port for Sonarr metrics";
        };
        listenAddr = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = ''
            Address for Sonarr exporter to listen on.
            Note: This is forced to "0.0.0.0" if the service is VPN-confined.
          '';
        };
      };
      radarr.exporter = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to enable the Radarr Prometheus exporter.
            Only has an effect if nixarr.exporters.enable and nixarr.radarr.enable are true.
          '';
        };
        port = mkOption {
          type = types.port;
          default = 9708;
          description = "Port for Radarr metrics";
        };
        listenAddr = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = ''
            Address for Radarr exporter to listen on.
            Note: This is forced to "0.0.0.0" if the service is VPN-confined.
          '';
        };
      };
      lidarr.exporter = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to enable the Lidarr Prometheus exporter.
            Only has an effect if nixarr.exporters.enable and nixarr.lidarr.enable are true.
          '';
        };
        port = mkOption {
          type = types.port;
          default = 9709;
          description = "Port for Lidarr metrics";
        };
        listenAddr = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = ''
            Address for Lidarr exporter to listen on.
            Note: This is forced to "0.0.0.0" if the service is VPN-confined.
          '';
        };
      };
      readarr.exporter = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to enable the Readarr Prometheus exporter.
            Only has an effect if nixarr.exporters.enable and nixarr.readarr.enable are true.
          '';
        };
        port = mkOption {
          type = types.port;
          default = 9710;
          description = "Port for Readarr metrics";
        };
        listenAddr = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = ''
            Address for Readarr exporter to listen on.
            Note: This is forced to "0.0.0.0" if the service is VPN-confined.
          '';
        };
      };
      prowlarr.exporter = {
        enable = mkOption {
          type = types.bool;
          default = true;
          description = ''
            Whether to enable the Prowlarr Prometheus exporter.
            Only has an effect if nixarr.exporters.enable and nixarr.prowlarr.enable are true.
          '';
        };
        port = mkOption {
          type = types.port;
          default = 9711;
          description = "Port for Prowlarr metrics";
        };
        listenAddr = mkOption {
          type = types.str;
          default = "0.0.0.0";
          description = ''
            Address for Prowlarr exporter to listen on.
            Note: This is forced to "0.0.0.0" if the service is VPN-confined.
          '';
        };
      };
    };
  };

  config = mkIf (cfg.enable && cfg.exporters.enable) {
    # Configure Prometheus exporters
    services.prometheus = {
      exporters = {
        # Enable exportarr for each supported service if it's enabled
        exportarr-sonarr = mkIf (shouldEnableExporter "sonarr") {
          enable = true;
          url = "http://127.0.0.1:8989";
          apiKeyFile = "${cfg.stateDir}/secrets/sonarr.api-key";
          port = cfg.sonarr.exporter.port;
          listenAddress =
            if isVpnConfined "sonarr"
            then "0.0.0.0"
            else cfg.sonarr.exporter.listenAddr;
        };

        exportarr-radarr = mkIf (shouldEnableExporter "radarr") {
          enable = true;
          url = "http://127.0.0.1:7878";
          apiKeyFile = "${cfg.stateDir}/secrets/radarr.api-key";
          port = cfg.radarr.exporter.port;
          listenAddress =
            if isVpnConfined "radarr"
            then "0.0.0.0"
            else cfg.radarr.exporter.listenAddr;
        };

        exportarr-lidarr = mkIf (shouldEnableExporter "lidarr") {
          enable = true;
          url = "http://127.0.0.1:8686";
          apiKeyFile = "${cfg.stateDir}/secrets/lidarr.api-key";
          port = cfg.lidarr.exporter.port;
          listenAddress =
            if isVpnConfined "lidarr"
            then "0.0.0.0"
            else cfg.lidarr.exporter.listenAddr;
        };

        exportarr-readarr = mkIf (shouldEnableExporter "readarr") {
          enable = true;
          url = "http://127.0.0.1:8787";
          apiKeyFile = "${cfg.stateDir}/secrets/readarr.api-key";
          port = cfg.readarr.exporter.port;
          listenAddress =
            if isVpnConfined "readarr"
            then "0.0.0.0"
            else cfg.readarr.exporter.listenAddr;
        };

        exportarr-prowlarr = mkIf (shouldEnableExporter "prowlarr") {
          enable = true;
          url = "http://127.0.0.1:9696";
          apiKeyFile = "${cfg.stateDir}/secrets/prowlarr.api-key";
          port = cfg.prowlarr.exporter.port;
          listenAddress =
            if isVpnConfined "prowlarr"
            then "0.0.0.0"
            else cfg.prowlarr.exporter.listenAddr;
        };

        # Enable node and systemd exporters by default
        node = {
          enable = true;
          enabledCollectors = ["systemd" "tcpstat" "network_route"];
        };
        systemd.enable = true;

        # Configure wireguard exporter
        wireguard = mkIf shouldEnableWireguardExporter {
          enable = true;
          openFirewall = false;
          port = cfg.wireguard.exporter.port;
          listenAddress = cfg.wireguard.exporter.listenAddr;
        };
      };
    };

    # Add systemd services for VPN-confined exporters
    systemd.services = mkMerge [
      # VPN-confined exporters
      (mkIf cfg.vpn.enable (
        let
          # Create VPN-confined exporter services for each Arr service
          makeVpnExporterService = service:
            mkIf (isVpnConfined service && shouldEnableExporter service) {
              "prometheus-exportarr-${service}-exporter" = {
                vpnConfinement = {
                  enable = true;
                  vpnNamespace = "wg";
                };
                # Add dependency on API key extraction
                after = ["${service}-api.service"];
                requires = ["${service}-api.service"];
                serviceConfig = {
                  DynamicUser = true;
                  SupplementaryGroups = ["${service}-api"];
                };
              };
            };
        in
          lib.mkMerge [
            (makeVpnExporterService "sonarr")
            (makeVpnExporterService "radarr")
            (makeVpnExporterService "lidarr")
            (makeVpnExporterService "readarr")
            (makeVpnExporterService "prowlarr")
            {
              # Add wireguard exporter to the VPN namespace so that it can access wireguard
              prometheus-wireguard-exporter = {
                vpnConfinement = {
                  enable = true;
                  vpnNamespace = "wg";
                };
                serviceConfig = {
                  DynamicUser = true;
                };
              };
            }
          ]
      ))

      # Add dependencies for non-VPN exporters
      {
        "prometheus-exportarr-sonarr-exporter" = mkIf (shouldEnableExporter "sonarr" && !isVpnConfined "sonarr") {
          after = ["sonarr-api.service"];
          requires = ["sonarr-api.service"];
          serviceConfig.SupplementaryGroups = ["sonarr-api"];
        };
        "prometheus-exportarr-radarr-exporter" = mkIf (shouldEnableExporter "radarr" && !isVpnConfined "radarr") {
          after = ["radarr-api.service"];
          requires = ["radarr-api.service"];
          serviceConfig.SupplementaryGroups = ["radarr-api"];
        };
        "prometheus-exportarr-lidarr-exporter" = mkIf (shouldEnableExporter "lidarr" && !isVpnConfined "lidarr") {
          after = ["lidarr-api.service"];
          requires = ["lidarr-api.service"];
          serviceConfig.SupplementaryGroups = ["lidarr-api"];
        };
        "prometheus-exportarr-readarr-exporter" = mkIf (shouldEnableExporter "readarr" && !isVpnConfined "readarr") {
          after = ["readarr-api.service"];
          requires = ["readarr-api.service"];
          serviceConfig.SupplementaryGroups = ["readarr-api"];
        };
        "prometheus-exportarr-prowlarr-exporter" = mkIf (shouldEnableExporter "prowlarr" && !isVpnConfined "prowlarr") {
          after = ["prowlarr-api.service"];
          requires = ["prowlarr-api.service"];
          serviceConfig.SupplementaryGroups = ["prowlarr-api"];
        };
      }
    ];

    # Add port mappings for VPN-confined exporters
    vpnNamespaces.wg = mkIf cfg.vpn.enable {
      portMappings =
        (optional (shouldEnableExporter "sonarr" && isVpnConfined "sonarr") {
          from = cfg.sonarr.exporter.port;
          to = cfg.sonarr.exporter.port;
        })
        ++ (optional (shouldEnableExporter "radarr" && isVpnConfined "radarr") {
          from = cfg.radarr.exporter.port;
          to = cfg.radarr.exporter.port;
        })
        ++ (optional (shouldEnableExporter "lidarr" && isVpnConfined "lidarr") {
          from = cfg.lidarr.exporter.port;
          to = cfg.lidarr.exporter.port;
        })
        ++ (optional (shouldEnableExporter "readarr" && isVpnConfined "readarr") {
          from = cfg.readarr.exporter.port;
          to = cfg.readarr.exporter.port;
        })
        ++ (optional (shouldEnableExporter "prowlarr" && isVpnConfined "prowlarr") {
          from = cfg.prowlarr.exporter.port;
          to = cfg.prowlarr.exporter.port;
        })
        ++ (optional shouldEnableWireguardExporter {
          from = cfg.wireguard.exporter.port;
          to = cfg.wireguard.exporter.port;
        });
    };

    # Open firewall ports for non-VPN exporters
    networking.firewall.allowedTCPPorts = mkIf (!cfg.vpn.enable) (
      (optional (shouldEnableExporter "sonarr" && !isVpnConfined "sonarr") cfg.sonarr.exporter.port)
      ++ (optional (shouldEnableExporter "radarr" && !isVpnConfined "radarr") cfg.radarr.exporter.port)
      ++ (optional (shouldEnableExporter "lidarr" && !isVpnConfined "lidarr") cfg.lidarr.exporter.port)
      ++ (optional (shouldEnableExporter "readarr" && !isVpnConfined "readarr") cfg.readarr.exporter.port)
      ++ (optional (shouldEnableExporter "prowlarr" && !isVpnConfined "prowlarr") cfg.prowlarr.exporter.port)
      ++ (optional shouldEnableWireguardExporter cfg.wireguard.exporter.port)
    );

    # Optionally add Nginx proxy for the Wireguard exporter
    services.nginx = mkIf shouldEnableWireguardExporter {
      enable = true;
      virtualHosts."127.0.0.1:${toString cfg.wireguard.exporter.port}" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.wireguard.exporter.port;
          }
        ];
        locations."/" = {
          recommendedProxySettings = true;
          proxyPass = "http://192.168.15.1:${toString cfg.wireguard.exporter.port}";
        };
      };
    };
  };
}
