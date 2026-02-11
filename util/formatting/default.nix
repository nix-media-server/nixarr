{pkgs, ...}: {
  projectRootFile = "flake.nix";
  programs = {
    alejandra.enable = true;
    ruff-format.enable = true;
    prettier = {
      enable = true;
      includes = ["*.md"];
      settings = {
        proseWrap = "always";
      };
    };
  };
  settings.formatter."indent-codeblocks" = {
    command = "${pkgs.bash}/bin/bash";
    options = ["${./indent-codeblocks.sh}"];
    includes = ["*.md"];
    priority = 1;
  };
}
