{
  pkgs,
  nixosModules,
}:
pkgs.testers.nixosTest {
  name = "transmission-sync-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules.default];

    networking.firewall.enable = false;

    virtualisation.cores = 4; # one per service plus one for luck

    nixarr = {
      enable = true;

      transmission = {
        enable = true;
      };

      sonarr = {
        enable = true;
        settings-sync.transmission.enable = true;
      };

      radarr = {
        enable = true;
        settings-sync.transmission.enable = true;
      };
    };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Check that main services are active
    machine.succeed("systemctl is-active transmission")
    machine.succeed("systemctl is-active sonarr")
    machine.succeed("systemctl is-active radarr")

    # Wait for service APIs
    machine.wait_for_unit("sonarr-api.service")
    machine.wait_for_unit("radarr-api.service")

    # Once the APIs are up, the sync services shouldn't take long
    machine.wait_for_unit("sonarr-sync-config.service", timeout=60)
    machine.wait_for_unit("radarr-sync-config.service", timeout=60)

    print("\n=== Transmission Sync Test Completed ===")
  '';
}
