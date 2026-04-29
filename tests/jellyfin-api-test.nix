{
  pkgs,
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "jellyfin-api-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: let
    nixarr-py = config.nixarr.nixarr-py.package;
    test-runner = pkgs.writers.writePython3Bin "jellyfin-api-test" {
      libraries = [nixarr-py];
    } (builtins.readFile ./jellyfin-api-test.py);
  in {
    imports = [
      nixosModules.default
    ];

    virtualisation.cores = 2; # one per service plus one for luck

    # 3GB disk; Jellyfin refuses to start with less than 2GB free space
    virtualisation.diskSize = 3 * 1024;

    networking.firewall.enable = false;

    nixarr = {
      enable = true;

      jellyfin = {
        enable = true;
        api.enable = true;
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

    # Wait for service APIs
    machine.wait_for_unit("jellyfin-api.service")

    # Run the sync test
    machine.succeed("jellyfin-api-test")
    print("\n=== Nixarr Sync Test Completed ===")
  '';
}
