{...}: {
  projectRootFile = "flake.nix";
  programs = {
    alejandra.enable = true;
    ruff-format.enable = true;
  };
}
