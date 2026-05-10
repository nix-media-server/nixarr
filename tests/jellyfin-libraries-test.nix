{
  pkgs,
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "jellyfin-libraries-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: let
    nixarr-py = config.nixarr.nixarr-py.package;
    test-runner = pkgs.writers.writePython3Bin "jellyfin-libraries-test" {
      libraries = [nixarr-py];
      flakeIgnore = ["E501"];
    } (builtins.readFile ./jellyfin-libraries-test.py);
  in {
    imports = [
      nixosModules.default
    ];

    virtualisation.cores = 2;

    # 3GB disk; Jellyfin refuses to start with less than 2GB free space
    virtualisation.diskSize = 3 * 1024;

    networking.firewall.enable = false;

    nixarr = {
      enable = true;

      jellyfin = {
        enable = true;
        libraries = [
          {
            name = "Movies";
            type = "movies";
            paths = ["/media/library/movies"];
          }
          {
            name = "TV Shows";
            type = "tvshows";
            paths = ["/media/library/shows"];
          }
          {
            name = "Music";
            type = "music";
            paths = ["/media/library/music"];
          }
        ];
      };
    };

    environment.systemPackages = [
      test-runner
    ];
  };

  testScript = ''
    machine.succeed("systemctl start jellyfin-api.service")

    machine.wait_for_unit("multi-user.target")

    # Check that main services are active
    machine.succeed("systemctl is-active jellyfin")

    # Wait for jellyfin-api service (sets up initial user and completes wizard)
    machine.wait_for_unit("jellyfin-api.service")

    # Wait for jellyfin-libraries-sync service
    machine.wait_for_unit("jellyfin-libraries-sync.service")

    # Run the test to verify libraries were created correctly
    machine.succeed("jellyfin-libraries-test")
    print("\n=== Jellyfin Libraries Test Completed ===")
  '';
}
