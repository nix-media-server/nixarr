{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    genAttrs
    literalExpression
    mkIf
    mkOption
    optionalAttrs
    types
    ;

  inherit
    (pkgs.writers)
    writeJSON
    ;

  nixarr-utils = import ../utils.nix {inherit config lib pkgs;};
  inherit
    (nixarr-utils)
    arrServiceNames
    mkArrLocalUrl
    ;

  cfg = config.nixarr;

  nixarr-py-config = let
    arrs = genAttrs arrServiceNames (serviceName: {
      base_url = mkArrLocalUrl serviceName;
      api_key_file = "${cfg.stateDir}/secrets/${serviceName}.api-key";
    });
    jellyfin = optionalAttrs (cfg.jellyfin.enable && cfg.jellyfin.api.enable) {
      jellyfin = cfg.jellyfin.api.nixarr-py-config;
    };
  in
    arrs // jellyfin;

  nixarr-py-json = writeJSON "nixarr-py.json" nixarr-py-config;

  package = pkgs.callPackage ./. {jellyfin = cfg.jellyfin.package;};
in {
  imports = [./jellyfin_api_module.nix];

  options.nixarr.nixarr-py = {
    package = mkOption {
      type = types.package;
      default = package;
      defaultText = literalExpression "pkgs.callPackage ./. {}";
      description = "The nixarr-py package.";
    };
  };

  config = mkIf cfg.enable {
    environment.etc."nixarr/nixarr-py.json".source = nixarr-py-json;
  };
}
