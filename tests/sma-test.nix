{
  pkgs,
  nixosModules,
}:
pkgs.testers.nixosTest {
  name = "sma-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules.default];

    networking.firewall.enable = false;

    virtualisation.cores = 4;
    virtualisation.memorySize = 4096;

    services = {
      sonarr.settings.auth.required = "DisabledForLocalAddresses";
      radarr.settings.auth.required = "DisabledForLocalAddresses";
    };

    nixarr = {
      enable = true;

      transmission.enable = true;

      sonarr = {
        enable = true;
        settings-sync.transmission.enable = true;
      };

      radarr = {
        enable = true;
        settings-sync.transmission.enable = true;
      };

      sma = {
        enable = true;
        video-codecs = ["h264" "hevc"];
        output-format = "mkv";
        output-extension = "mkv";
        audio-languages = ["eng" "dan"];
        subtitle-languages = ["eng" "dan"];
        audio-default-language = "eng";
        subtitle-default-language = "eng";
      };
    };
  };

  testScript = ''
    import json

    machine.wait_for_unit("multi-user.target")

    # 1. Check core services are active
    machine.succeed("systemctl is-active transmission")
    machine.succeed("systemctl is-active sonarr")
    machine.succeed("systemctl is-active radarr")

    # 2. Wait for API key extraction
    machine.wait_for_unit("sonarr-api.service", timeout=120)
    machine.wait_for_unit("radarr-api.service", timeout=120)

    # 3. Wait for SMA setup service (generates autoProcess.ini)
    machine.wait_for_unit("sma-setup.service", timeout=120)

    # 4. Verify autoProcess.ini exists and contains real API keys (not placeholders)
    config_content = machine.succeed("cat /data/.state/nixarr/sma/autoProcess.ini")
    assert "__SONARR_API_KEY__" not in config_content, "Sonarr API key placeholder was not replaced"
    assert "__RADARR_API_KEY__" not in config_content, "Radarr API key placeholder was not replaced"

    # Verify the sonarr API key in the config matches the extracted key
    sonarr_key = machine.succeed("cat /data/.state/nixarr/secrets/sonarr.api-key").strip()
    assert sonarr_key in config_content, "Sonarr API key not found in config"
    assert len(sonarr_key) > 10, "Sonarr API key looks too short: " + sonarr_key

    radarr_key = machine.succeed("cat /data/.state/nixarr/secrets/radarr.api-key").strip()
    assert radarr_key in config_content, "Radarr API key not found in config"
    assert len(radarr_key) > 10, "Radarr API key looks too short: " + radarr_key

    # 5. Verify config has expected settings
    assert "codec = h264, hevc" in config_content, "Video codecs not set correctly"
    assert "languages = eng, dan" in config_content, "Languages not set correctly"
    assert "output-format = mkv" in config_content, "Output format not set correctly"

    print("=== autoProcess.ini verified ===")

    # 6. Wait for SMA registration in sonarr and radarr
    machine.wait_for_unit("sma-register-sonarr.service", timeout=120)
    machine.wait_for_unit("sma-register-radarr.service", timeout=120)

    # 7. Verify SMA is registered as a Connect notification in Sonarr
    sonarr_notifications = machine.succeed(
        f"curl -s -H 'X-Api-Key: {sonarr_key}' http://127.0.0.1:8989/api/v3/notification"
    )
    sonarr_notifs = json.loads(sonarr_notifications)
    sma_sonarr = [n for n in sonarr_notifs if n["name"] == "SMA"]
    assert len(sma_sonarr) == 1, f"Expected 1 SMA notification in Sonarr, got {len(sma_sonarr)}"
    assert sma_sonarr[0]["implementation"] == "CustomScript", "SMA should be a CustomScript"
    assert sma_sonarr[0]["onDownload"] is True, "SMA should trigger on download"
    assert sma_sonarr[0]["onUpgrade"] is True, "SMA should trigger on upgrade"

    print("=== SMA registered in Sonarr ===")

    # 8. Verify SMA is registered as a Connect notification in Radarr
    radarr_notifications = machine.succeed(
        f"curl -s -H 'X-Api-Key: {radarr_key}' http://127.0.0.1:7878/api/v3/notification"
    )
    radarr_notifs = json.loads(radarr_notifications)
    sma_radarr = [n for n in radarr_notifs if n["name"] == "SMA"]
    assert len(sma_radarr) == 1, f"Expected 1 SMA notification in Radarr, got {len(sma_radarr)}"
    assert sma_radarr[0]["implementation"] == "CustomScript", "SMA should be a CustomScript"
    assert sma_radarr[0]["onDownload"] is True, "SMA should trigger on download"
    assert sma_radarr[0]["onUpgrade"] is True, "SMA should trigger on upgrade"

    print("=== SMA registered in Radarr ===")

    # 9. Verify the sma CLI tool is available and works
    machine.succeed("sma --help")

    # 10. Verify idempotency: run registration again, should still have exactly 1
    machine.succeed("systemctl restart sma-register-sonarr.service")
    machine.succeed("systemctl restart sma-register-radarr.service")

    sonarr_notifications = machine.succeed(
        f"curl -s -H 'X-Api-Key: {sonarr_key}' http://127.0.0.1:8989/api/v3/notification"
    )
    sma_sonarr = [n for n in json.loads(sonarr_notifications) if n["name"] == "SMA"]
    assert len(sma_sonarr) == 1, f"Idempotency failed: expected 1 SMA in Sonarr, got {len(sma_sonarr)}"

    radarr_notifications = machine.succeed(
        f"curl -s -H 'X-Api-Key: {radarr_key}' http://127.0.0.1:7878/api/v3/notification"
    )
    sma_radarr = [n for n in json.loads(radarr_notifications) if n["name"] == "SMA"]
    assert len(sma_radarr) == 1, f"Idempotency failed: expected 1 SMA in Radarr, got {len(sma_radarr)}"

    print("=== Idempotency verified ===")

    print("\n=== SMA Test Completed Successfully ===")
  '';
}
