{
  pkgs,
  nixosModules,
}:
pkgs.testers.runNixOSTest {
  name = "prowlarr-sync-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [
      nixosModules.default
    ];

    services = {
      prowlarr.settings.auth.required = "DisabledForLocalAddresses";
      sonarr.settings.auth.required = "DisabledForLocalAddresses";
      radarr.settings.auth.required = "DisabledForLocalAddresses";
    };

    virtualisation.cores = 4; # one per service plus one for luck
    virtualisation.memorySize = 4096; # 4GB for multiple *arr services

    networking.firewall.enable = false;

    nixarr = {
      enable = true;

      prowlarr = {
        enable = true;
        settings-sync = {
          enable-nixarr-apps = true;
          tags = ["a" "b"];
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
    machine.succeed("systemctl is-active prowlarr")
    machine.succeed("systemctl is-active sonarr")
    machine.succeed("systemctl is-active radarr")

    # Wait for service APIs
    machine.wait_for_unit("prowlarr-api.service")
    machine.wait_for_unit("sonarr-api.service")
    machine.wait_for_unit("radarr-api.service")

    # Once the APIs are up, the sync service shouldn't take long
    machine.wait_for_unit("prowlarr-sync-config.service", timeout=120)

    print("\n=== Prowlarr Sync Test Completed ===")
  '';
}
