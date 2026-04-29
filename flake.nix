{
  description = "The Nixarr Media Server Nixos Module";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";

    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";

    vpnconfinement.url = "github:Maroka-chan/VPN-Confinement";

    website-builder.url = "github:rasmus-kirk/website-builder";
    website-builder.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    nixpkgs,
    treefmt-nix,
    vpnconfinement,
    website-builder,
    self,
    ...
  } @ inputs: let
    # Systems supported
    supportedSystems = [
      "x86_64-linux" # 64-bit Intel/AMD Linux
      "aarch64-linux" # 64-bit ARM Linux
      "x86_64-darwin" # 64-bit Intel macOS
      "aarch64-darwin" # 64-bit ARM macOS
    ];

    # Helper to provide system-specific attributes
    forAllSystems = f:
      nixpkgs.lib.genAttrs supportedSystems (
        system:
          f {
            pkgs = import nixpkgs {
              inherit system;
              config.allowUnfree = true;
            };
          }
      );
  in {
    nixosModules.default.imports = [
      ./nixarr
      vpnconfinement.nixosModules.default
    ];

    # Add tests attribute to the flake outputs
    # To run interactively run:
    # > nix build .#checks.x86_64-linux.monitoring-test.driver -L
    checks = forAllSystems ({pkgs}: {
      permissions-test = pkgs.callPackage ./tests/permissions-test.nix {
        inherit (self) nixosModules;
      };
      simple-test = pkgs.callPackage ./tests/simple-test.nix {
        inherit (self) nixosModules;
      };
      transmission-sync-test = pkgs.callPackage ./tests/transmission-sync-test.nix {
        inherit (self) nixosModules;
      };
      # vpn-confinement-test = pkgs.callPackage ./tests/vpn-confinement-test.nix {
      #   inherit (self) nixosModules;
      # };
      prowlarr-sync-test = pkgs.callPackage ./tests/prowlarr-sync-test.nix {
        inherit (self) nixosModules;
      };
      bazarr-sync-test = pkgs.callPackage ./tests/bazarr-sync-test.nix {
        inherit (self) nixosModules;
      };
      jellyfin-api-test = pkgs.callPackage ./tests/jellyfin-api-test.nix {
        inherit (self) nixosModules;
      };
    });

    devShells = forAllSystems ({pkgs}: let
      nixarr-py-deps = pkgs.callPackage ./nixarr/lib/nixarr-py/python-deps.nix {};
    in {
      default = pkgs.mkShell {
        venvDir = "./.venv";
        packages = with pkgs;
          [
            alejandra
            nixd
            python3Packages.python
            python3Packages.venvShellHook
          ]
          ++ nixarr-py-deps;
        postVenvCreation = ''
          python -m pip install --editable ./nixarr/lib/nixarr-py
        '';
      };
    });

    packages = forAllSystems ({pkgs}: let
      website = website-builder.lib {
        pkgs = pkgs;
        src = "${self}";
        timestamp = self.lastModified;
        headerTitle = "Nixarr";
        standalonePages = [
          {
            title = "Nixarr - Media Server Nixos Module";
            inputFile = ./README.md;
            outputFile = "index.html";
          }
        ];
        includedDirs = ["docs"];
        articleDirs = ["docs/wiki"];
        navbar = [
          {
            title = "Home";
            location = "/";
          }
          {
            title = "Options";
            location = "/nixos-options";
          }
          {
            title = "Wiki";
            location = "/wiki";
          }
          {
            title = "Github";
            location = "https://github.com/nix-media-server/nixarr";
          }
        ];
        favicons = {
          # For all browsers
          "16x16" = "/docs/img/favicons/16x16.png";
          "32x32" = "/docs/img/favicons/32x32.png";
          # For Google and Android
          "48x48" = "/docs/img/favicons/48x48.png";
          "192x192" = "/docs/img/favicons/192x192.png";
          # For iPad
          "167x167" = "/docs/img/favicons/167x167.png";
          # For iPhone
          "180x180" = "/docs/img/favicons/180x180.png";
        };
        nixosModules = ./nixarr;
      };
    in {
      default = website.package;
      debug = website.loop;
      nixarr-py = pkgs.callPackage ./nixarr/lib/nixarr-py {};
    });

    formatter =
      forAllSystems ({pkgs}:
        treefmt-nix.lib.mkWrapper pkgs ./util/formatting);
  };
}
