# Comprehensive test for Nixarr file permissions, user/group creation, and directory structure
{
  pkgs,
  nixosModules,
  lib ? pkgs.lib,
}:
pkgs.testers.nixosTest {
  name = "nixarr-permissions-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules.default];

    virtualisation.memorySize = 4096; # 4GB for multiple services
    networking.firewall.enable = false;

    nixarr = {
      enable = true;
      stateDir = "/data/.state/nixarr";
      mediaDir = "/data/media";
      mediaUsers = ["testuser"];

      # Enable key services to trigger tmpfiles directory creation
      jellyfin.enable = true;

      transmission = {
        enable = true;
        vpn.enable = false;
        privateTrackers.cross-seed.enable = true;
      };

      sonarr = {
        enable = true;
        vpn.enable = false;
      };

      radarr = {
        enable = true;
        vpn.enable = false;
      };

      lidarr = {
        enable = true;
        vpn.enable = false;
      };

      prowlarr = {
        enable = true;
        vpn.enable = false;
      };
    };

    # Create a test user to verify mediaUsers functionality
    users.users.testuser = {
      isNormalUser = true;
      home = "/home/testuser";
    };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    print("Starting Nixarr permissions test...")

    # Test 1: Verify key users and groups exist
    print("\n=== Testing User/Group Creation ===")

    # Check essential users exist
    key_users = ["jellyfin", "transmission", "sonarr", "radarr", "testuser"]
    for user in key_users:
        machine.succeed(f"id {user}")
        print(f"✓ User {user} exists")

    # Check media group exists and has correct members
    media_members = machine.succeed("getent group media | cut -d: -f4").strip()
    expected_members = ["jellyfin", "transmission", "sonarr", "radarr", "lidarr", "testuser"]
    for member in expected_members:
        if member in media_members:
            print(f"✓ {member} is in media group")
        else:
            machine.fail(f"{member} not in media group")

    # Test 2: Verify directory structure and ownership
    print("\n=== Testing Directory Permissions ===")

    def check_dir(path, expected_user, expected_group, description):
        stat_output = machine.succeed(f"stat -c '%U:%G' '{path}'").strip()
        user, group = stat_output.split(":")
        if user == expected_user and group == expected_group:
            print(f"✓ {description}: {user}:{group}")
        else:
            machine.fail(f"{description} has wrong ownership: {user}:{group}, expected {expected_user}:{expected_group}")

    # Check key directories exist with correct ownership
    check_dir("/data/media", "root", "media", "Media root directory")
    check_dir("/data/media/library/movies", "root", "media", "Movies directory")
    check_dir("/data/media/library/shows", "root", "media", "Shows directory")
    check_dir("/data/media/library/music", "root", "media", "Music directory")
    check_dir("/data/media/torrents", "transmission", "media", "Torrents directory")

    # Test 3: Verify service file access
    print("\n=== Testing Service File Access ===")

    # Test Jellyfin can write to media directories
    test_dirs = ["/data/media/library/movies", "/data/media/library/shows"]
    for test_dir in test_dirs:
        if machine.succeed(f"test -d '{test_dir}' && echo 'exists' || echo 'missing'").strip() == "exists":
            test_file = f"{test_dir}/jellyfin-test.txt"
            machine.succeed(f"sudo -u jellyfin touch '{test_file}'")
            machine.succeed(f"sudo -u jellyfin sh -c 'echo test > {test_file}'")
            content = machine.succeed(f"cat '{test_file}'").strip()
            if content != "test":
                machine.fail(f"Expected 'test' but got '{content}'")
            machine.succeed(f"sudo -u jellyfin rm '{test_file}'")
            print(f"✓ Jellyfin can write/read/delete in {test_dir}")

    # Test 4: Verify fix-permissions command
    print("\n=== Testing fix-permissions Command ===")

    # Create file with wrong permissions
    test_file = "/data/media/library/movies/test-wrong-perms.txt"
    if machine.succeed("test -d '/data/media/library/movies' && echo 'exists' || echo 'missing'").strip() == "exists":
        machine.succeed(f"umask 077 && touch '{test_file}'")

        # Verify initial permissions are wrong
        initial_perms = machine.succeed(f"stat -c '%a' '{test_file}'").strip()
        if initial_perms != "600":
            machine.fail(f"Expected 600 permissions, got {initial_perms}")

        machine.succeed("nixarr fix-permissions")

        # Verify permissions were fixed
        fixed_perms = machine.succeed(f"stat -c '%a' '{test_file}'").strip()
        if fixed_perms not in ["644", "664"]:
            machine.fail(f"fix-permissions failed: permissions are {fixed_perms}, expected 644 or 664")

        machine.succeed(f"rm '{test_file}'")
        print(f"✓ fix-permissions corrected file permissions from 600 to {fixed_perms}")

    print("\n=== All Permission Tests Completed ===")
  '';
}
