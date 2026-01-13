{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    elem
    genAttrs
    getExe
    getExe'
    mkIf
    mkMerge
    ;

  nixarr-utils = import ./utils.nix {inherit config lib pkgs;};
  inherit
    (nixarr-utils)
    arrServiceNames
    waitForArrService
    ;

  cfg = config.nixarr;

  serviceCfgFile =
    {
      bazarr = "${cfg.bazarr.stateDir}/config/config.yaml";
      jellyseerr = "${cfg.jellyseerr.stateDir}/settings.json";
      sabnzbd = "${cfg.sabnzbd.stateDir}/sabnzbd.ini";
      transmission = "${cfg.transmission.stateDir}/.config/transmission-daemon/settings.json";
    }
    // genAttrs arrServiceNames (arr: "${cfg.${arr}.stateDir}/config.xml");

  printServiceApiKey = let
    yq = getExe' pkgs.yq "yq";
    xq = getExe' pkgs.yq "xq";
    grep = getExe pkgs.gnugrep;
    sed = getExe pkgs.gnused;
  in
    {
      bazarr = pkgs.writeShellScript "print-bazarr-api-key" ''
        ${yq} -r .auth.apiKey '${serviceCfgFile.bazarr}'
      '';
      jellyseerr = pkgs.writeShellScript "print-jellyseerr-api-key" ''
        ${yq} -r .main.apiKey '${serviceCfgFile.jellyseerr}'
      '';
      sabnzbd = pkgs.writeShellScript "print-sabnzbd-api-key" ''
        ${grep} api_key '${serviceCfgFile.sabnzbd}' | ${sed} 's/^api_key.*= *//g'
      '';
      transmission = pkgs.writeShellScript "print-transmission-api-key" ''
        ${yq} -r .["rpc-password"] '${serviceCfgFile.transmission}'
      '';
    }
    // genAttrs arrServiceNames (arr:
      pkgs.writeShellScript "print-${arr}-api-key" ''
        ${xq} -r .Config.ApiKey '${serviceCfgFile.${arr}}'
      '');

  waitForService = serviceName:
    if elem serviceName arrServiceNames
    then waitForArrService {service = serviceName;}
    else
      # TODO: wait for other services properly
      pkgs.writeShellScript "wait-for-${serviceName}-config" ''
        while [ ! -f '${serviceCfgFile.${serviceName}}' ]; do sleep 1; done
      '';

  serviceNames = builtins.attrNames printServiceApiKey;

  mkApiService = serviceName: {
    description = "Wait for ${serviceName} API and extract key";
    after = ["${serviceName}.service"];
    requires = ["${serviceName}.service"];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Group = "${serviceName}-api";
      UMask = "0027"; # Results in 0640 permissions

      ExecStartPre = [(waitForService serviceName)];
      ExecStart = pkgs.writeShellScript "extract-${serviceName}-api-key" ''
        ${printServiceApiKey.${serviceName}} > '${cfg.stateDir}/secrets/${serviceName}.api-key'
      '';
    };
  };
in {
  config = mkIf cfg.enable {
    # Create per-service API groups to control access to their API keys
    users.groups = mkMerge (
      builtins.map
      (serviceName: mkIf cfg.${serviceName}.enable {"${serviceName}-api" = {};})
      serviceNames
    );

    systemd.services = mkMerge (
      # Create API key extractors for enabled services
      builtins.map
      (serviceName: mkIf cfg.${serviceName}.enable {"${serviceName}-api" = mkApiService serviceName;})
      serviceNames
    );

    # Create the secrets directory
    systemd.tmpfiles.rules = [
      # Needs to be world-executable for members of the `*-api` groups to access
      # the files inside.
      "d ${cfg.stateDir}/secrets 0701 root root - -"
    ];
  };
}
