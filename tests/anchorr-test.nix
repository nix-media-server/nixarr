{
  pkgs,
  nixosModules,
  lib ? pkgs.lib,
}:
pkgs.testers.nixosTest {
  name = "anchorr-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules.default];

    networking.firewall.enable = false;

    nixarr = {
      enable = true;
      jellyseerr.enable = true;

      anchorr = {
        enable = true;
        discordTokenFile = pkgs.writeText "discord-token" "test-discord-token";
        tmdbApiKeyFile = pkgs.writeText "tmdb-api-key" "test-tmdb-api-key";
        configuration = {
          discord = {
            bot_id = "123456789";
            guild_id = "987654321";
          };
        };
      };
    };

    # Mock jellyseerr API key extraction since we don't want to run full jellyseerr
    systemd.services.jellyseerr-api-key = {
      serviceConfig.ExecStart = lib.mkForce (pkgs.writeShellScript "mock-jellyseerr-api-key" ''
        mkdir -p /data/.state/nixarr/api-keys
        echo "mock-jellyseerr-key" > /data/.state/nixarr/api-keys/jellyseerr.key
        chown root:jellyseerr-api /data/.state/nixarr/api-keys/jellyseerr.key
        chmod 640 /data/.state/nixarr/api-keys/jellyseerr.key
      '');
    };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("anchorr-setup.service")
    machine.wait_for_unit("anchorr.service")

    # Check that anchorr and its setup service are active/completed
    machine.succeed("systemctl is-active anchorr")

    # Verify config.json was generated and copied correctly
    machine.succeed("grep '123456789' /data/.state/nixarr/anchorr/config/config.json")
    machine.succeed("grep '987654321' /data/.state/nixarr/anchorr/config/config.json")

    # Verify env file was generated with secrets
    machine.succeed("grep 'DISCORD_TOKEN=test-discord-token' /data/.state/nixarr/anchorr/env")
    machine.succeed("grep 'TMDB_API_KEY=test-tmdb-api-key' /data/.state/nixarr/anchorr/env")

    # Verify Jellyseerr API key was pulled from the extracted key file
    machine.succeed("grep 'JELLYSEERR_API_KEY=mock-jellyseerr-key' /data/.state/nixarr/anchorr/env")

    # Verify permissions of the env file (should be 600 and owned by anchorr)
    # Note: stat -c %a might return 600
    machine.succeed("stat -c '%a %U:%G' /data/.state/nixarr/anchorr/env | grep '600 anchorr:anchorr'")

    print("\n=== Anchorr Test Completed Successfully ===")
  '';
}
