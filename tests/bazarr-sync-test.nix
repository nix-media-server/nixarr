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
    import json

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

    # The unit exiting 0 is not enough: Bazarr answers 204 to a request body it
    # could not parse, so a no-op sync also "succeeds". Read the settings back.
    api_key = machine.succeed(
        "cat /data/.state/nixarr/secrets/bazarr.api-key"
    ).strip()

    settings = json.loads(
        machine.succeed(
            "curl -sf -H 'X-API-KEY: "
            + api_key
            + "' http://127.0.0.1:6767/api/system/settings"
        )
    )

    assert settings["general"]["use_sonarr"], "Sonarr integration is not enabled in Bazarr"
    assert settings["general"]["use_radarr"], "Radarr integration is not enabled in Bazarr"

    assert settings["sonarr"]["apikey"], "Sonarr API key was not synced to Bazarr"
    assert settings["radarr"]["apikey"], "Radarr API key was not synced to Bazarr"

    assert settings["sonarr"]["port"] == 8989, (
        "unexpected Sonarr port: " + str(settings["sonarr"]["port"])
    )
    assert settings["radarr"]["port"] == 7878, (
        "unexpected Radarr port: " + str(settings["radarr"]["port"])
    )

    print("\n=== Bazarr Sync Test Completed ===")
  '';
}
