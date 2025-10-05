{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.nixarr.sonarr;
  globals = config.util-nixarr.globals;
  nixarr = config.nixarr;
  defaultPort = 8989;

  additionalInstancesRaw = mapAttrsToList (
    name: instanceCfg: instanceCfg // {__name = name;}
  )
  cfg.instances;

  normalizeInstance = index: inst: let
    name = inst.__name;
    computedPort =
      if inst.port != null
      then inst.port
      else cfg.port + index;
    computedPackage =
      if inst.package != null
      then inst.package
      else cfg.package;
    computedVpnEnable =
      if inst.vpn.enable != null
      then inst.vpn.enable
      else cfg.vpn.enable;
    computedOpenFirewall =
      if inst.openFirewall != null
      then inst.openFirewall
      else !computedVpnEnable;
    computedStateDir =
      if inst.stateDir != null
      then inst.stateDir
      else "${cfg.stateDir}-${name}";
    computedLibrarySubDir =
      if inst.librarySubDir != null
      then inst.librarySubDir
      else "${cfg.librarySubDir}-${name}";
  in {
    key = name;
    serviceName = "sonarr-${name}";
    enable = inst.enable;
    package = computedPackage;
    port = computedPort;
    stateDir = computedStateDir;
    librarySubDir = computedLibrarySubDir;
    vpnEnable = computedVpnEnable;
    openFirewall = computedOpenFirewall;
  };

  additionalInstances = imap1 normalizeInstance additionalInstancesRaw;

  baseInstance = {
    key = "default";
    serviceName = "sonarr";
    enable = cfg.enable;
    package = cfg.package;
    port = cfg.port;
    stateDir = cfg.stateDir;
    librarySubDir = cfg.librarySubDir;
    vpnEnable = cfg.vpn.enable;
    openFirewall = cfg.openFirewall;
  };

  allInstances = [baseInstance] ++ additionalInstances;

  enabledInstances = filter (instance: instance.enable) allInstances;

  vpnInstances =
    filter (
      instance: instance.enable && instance.vpnEnable
    )
    allInstances;

  openFirewallInstances =
    filter (
      instance: instance.enable && instance.openFirewall
    )
    allInstances;

  anyEnabled = enabledInstances != [];

  mediaLibraryDir = "${nixarr.mediaDir}/library";

  mediaSubDirs = unique (
    map (instance: "${mediaLibraryDir}/${instance.librarySubDir}") enabledInstances
  );

  stateDirs = unique (map (instance: instance.stateDir) enabledInstances);

  ports = map (instance: instance.port) enabledInstances;
in {
  options.nixarr.sonarr = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Sonarr service.
      '';
    };

    package = mkPackageOption pkgs "sonarr" {};

    port = mkOption {
      type = types.port;
      default = defaultPort;
      example = defaultPort;
      description = "Port for Sonarr to use.";
    };

    stateDir = mkOption {
      type = types.path;
      default = "${nixarr.stateDir}/sonarr";
      defaultText = literalExpression ''"''${nixarr.stateDir}/sonarr"'';
      example = "/nixarr/.state/sonarr";
      description = ''
        The location of the state directory for the Sonarr service.

        > **Warning:** Setting this to any path, where the subpath is not
        > owned by root, will fail! For example:
        >
        > ```nix
        >   stateDir = /home/user/nixarr/.state/sonarr
        > ```
        >
        > Is not supported, because `/home/user` is owned by `user`.
      '';
    };

    librarySubDir = mkOption {
      type = types.str;
      default = "shows";
      example = "shows-uhd";
      description = ''
        Subdirectory under `${nixarr.mediaDir}/library` that Sonarr manages.
      '';
    };

    openFirewall = mkOption {
      type = types.bool;
      defaultText = literalExpression ''!nixarr.sonarr.vpn.enable'';
      default = !cfg.vpn.enable;
      example = true;
      description = "Open firewall for Sonarr";
    };

    vpn.enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        **Required options:** [`nixarr.vpn.enable`](#nixarr.vpn.enable)

        Route Sonarr traffic through the VPN.
      '';
    };

    instances = mkOption {
      type = types.attrsOf (types.submodule ({name, ...}: {
        options = {
          enable = mkOption {
            type = types.bool;
            default = true;
            description = "Whether to enable this Sonarr instance.";
          };

          package = mkOption {
            type = types.nullOr types.package;
            default = null;
            description = "Package to use for this Sonarr instance.";
          };

          port = mkOption {
            type = types.nullOr types.port;
            default = null;
            description = ''
              Port for this Sonarr instance. If unset, one will be assigned
              automatically based on `nixarr.sonarr.port`.
            '';
          };

          stateDir = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = ''
              Override the state directory for this instance. Defaults to
              `"''${nixarr.stateDir}/sonarr-${name}"`.
            '';
          };

          librarySubDir = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = ''
              Override the media library subdirectory for this instance.
              Defaults to `"''${cfg.librarySubDir}-${name}"`.
            '';
          };

          openFirewall = mkOption {
            type = types.nullOr types.bool;
            default = null;
            description = ''
              Whether to open the firewall for this instance. Defaults to the
              inverse of the resolved VPN setting.
            '';
          };

          vpn.enable = mkOption {
            type = types.nullOr types.bool;
            default = null;
            description = ''
              Route traffic for this instance through the VPN. Defaults to
              `nixarr.sonarr.vpn.enable`.
            '';
          };
        };
      }));
      default = {};
      example = literalExpression ''
        {
          "4k" = {
            port = 8990;
            librarySubDir = "shows-4k";
          };
          anime.port = 8991;
        }
      '';
      description = ''
        Additional Sonarr instances keyed by a name that is appended to the
        service name (e.g. `sonarr-anime`).
      '';
    };
  };

  config = mkIf (nixarr.enable && anyEnabled) {
    assertions = [
      {
        assertion = (vpnInstances == []) || nixarr.vpn.enable;
        message = "All Sonarr instances that enable VPN require nixarr.vpn.enable.";
      }
      {
        assertion = length ports == length (unique ports);
        message = "Each Sonarr instance must use a unique port.";
      }
    ];

    users = {
      groups.${globals.sonarr.group}.gid = globals.gids.${globals.sonarr.group};
      users.${globals.sonarr.user} = {
        isSystemUser = true;
        group = globals.sonarr.group;
        uid = globals.uids.${globals.sonarr.user};
      };
    };

    systemd.tmpfiles.rules =
      [
        "d '${mediaLibraryDir}' 0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      ]
      ++ map (
        dir: "d '${dir}' 0775 ${globals.libraryOwner.user} ${globals.libraryOwner.group} - -"
      )
      mediaSubDirs
      ++ map (
        dir: "d '${dir}' 0700 ${globals.sonarr.user} root - -"
      )
      stateDirs;

    networking.firewall = mkIf (openFirewallInstances != []) {
      allowedTCPPorts = map (instance: instance.port) openFirewallInstances;
    };

    systemd.services = mkMerge (
      (map (
          instance: {
            ${instance.serviceName} = {
              description =
                "Sonarr"
                + (
                  if instance.serviceName != "sonarr"
                  then " (${instance.key})"
                  else ""
                );
              after = ["network.target"];
              wantedBy = ["multi-user.target"];
              environment.SONARR__SERVER__PORT = builtins.toString instance.port;
              serviceConfig = {
                Type = "simple";
                User = globals.sonarr.user;
                Group = globals.sonarr.group;
                ExecStart = "${lib.getExe instance.package} -nobrowser -data=${lib.escapeShellArg instance.stateDir}";
                Restart = "on-failure";
              };
            };
          }
        )
        enabledInstances)
      ++ (map (
          instance:
            mkIf instance.vpnEnable {
              ${instance.serviceName}.vpnConfinement = {
                enable = true;
                vpnNamespace = "wg";
              };
            }
        )
        enabledInstances)
    );

    vpnNamespaces.wg = mkIf (vpnInstances != []) {
      portMappings =
        map (
          instance: {
            from = instance.port;
            to = instance.port;
          }
        )
        vpnInstances;
    };

    services.nginx = mkIf (vpnInstances != []) {
      enable = true;

      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts = listToAttrs (
        map (
          instance: let
            portString = builtins.toString instance.port;
          in {
            name = "127.0.0.1:${portString}";
            value = {
              listen = [
                {
                  addr = "0.0.0.0";
                  port = instance.port;
                }
              ];
              locations."/" = {
                recommendedProxySettings = true;
                proxyWebsockets = true;
                proxyPass = "http://192.168.15.1:${portString}";
              };
            };
          }
        )
        vpnInstances
      );
    };
  };
}
