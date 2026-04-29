{
  pkgs,
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "bazarr-sync-test";

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

      bazarr = {
        enable = true;
        settings-sync = {
          sonarr.enable = true;
          radarr.enable = true;
        };
      };

      sonarr = {
        enable = true;
      };

      radarr = {
        enable = true;
      };
    };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Check that main services are active
    machine.succeed("systemctl is-active bazarr")
    machine.succeed("systemctl is-active sonarr")
    machine.succeed("systemctl is-active radarr")

    # Wait for service APIs
    machine.wait_for_unit("bazarr-api.service")
    machine.wait_for_unit("sonarr-api.service")
    machine.wait_for_unit("radarr-api.service")

    # Once the APIs are up, the sync service shouldn't take long
    machine.wait_for_unit("bazarr-sync-config.service", timeout=60)

    print("\n=== Bazarr Sync Test Completed ===")
  '';
}
