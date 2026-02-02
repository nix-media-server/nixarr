{
  pkgs,
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "jellyfin-users-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: let
    nixarr-py = config.nixarr.nixarr-py.package;
    test-runner = pkgs.writers.writePython3Bin "jellyfin-users-test" {
      libraries = [nixarr-py];
      flakeIgnore = ["E501"];
    } (builtins.readFile ./jellyfin-users-test.py);
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
        users = [
          {
            name = "testadmin";
            passwordFile = "/etc/jellyfin-passwords/testadmin";
            isAdministrator = true;
          }
          {
            name = "testviewer";
            passwordFile = "/etc/jellyfin-passwords/testviewer";
            isAdministrator = false;
          }
        ];
      };
    };

    # Create password files
    systemd.tmpfiles.rules = [
      "d /etc/jellyfin-passwords 0755 root root - -"
      "f /etc/jellyfin-passwords/testadmin 0644 root root - adminpass123"
      "f /etc/jellyfin-passwords/testviewer 0644 root root - viewerpass456"
    ];

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

    # Wait for jellyfin-users-sync service
    machine.wait_for_unit("jellyfin-users-sync.service")

    # Run the test to verify users were created correctly
    machine.succeed("jellyfin-users-test")
    print("\n=== Jellyfin Users Test Completed ===")
  '';
}
