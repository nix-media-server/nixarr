{
  pkgs,
  nixosModules,
  lib ? pkgs.lib,
}:
pkgs.testers.nixosTest {
  name = "simple-test";

  nodes.machine = {
    config,
    pkgs,
    ...
  }: {
    imports = [nixosModules.default];

    networking.firewall.enable = false;

    nixarr = {
      enable = true;

      jellyfin.enable = true;
      plex.enable = true;
      jellyseerr.enable = true;
      audiobookshelf.enable = true;

      transmission = {
        enable = true;
        privateTrackers.cross-seed.enable = true;
      };

      # Note: qbittorrent and transmission are mutually exclusive
      # (they share the same download directories)
      # qbittorrent.enable = true;

      autobrr.enable = true;
      bazarr.enable = true;
      sonarr.enable = true;
      radarr.enable = true;
      readarr.enable = true;
      readarr-audiobook.enable = true;
      sabnzbd.enable = true;
      lidarr.enable = true;
      prowlarr.enable = true;
      whisparr.enable = true;
      komga.enable = true;

      # recyclarr = {
      #   enable = true;
      #   configuration = {
      #     sonarr.series = {
      #       base_url = "http://localhost:8989";
      #       api_key = "!env_var SONARR_API_KEY";
      #       quality_definition.type = "series";
      #       delete_old_custom_formats = true;
      #       custom_formats = [
      #         {
      #           trash_ids = [
      #             "85c61753df5da1fb2aab6f2a47426b09" # BR-DISK
      #             "9c11cd3f07101cdba90a2d81cf0e56b4" # LQ
      #           ];
      #           assign_scores_to = [
      #             {
      #               name = "WEB-DL (1080p)";
      #               score = -10000;
      #             }
      #           ];
      #         }
      #       ];
      #     };
      #     radarr.movies = {
      #       base_url = "http://localhost:7878";
      #       api_key = "!env_var RADARR_API_KEY";
      #       quality_definition.type = "movie";
      #       delete_old_custom_formats = true;
      #       custom_formats = [
      #         {
      #           trash_ids = [
      #             "570bc9ebecd92723d2d21500f4be314c" # Remaster
      #             "eca37840c13c6ef2dd0262b141a5482f" # 4K Remaster
      #           ];
      #           assign_scores_to = [
      #             {
      #               name = "HD Bluray + WEB";
      #               score = 25;
      #             }
      #           ];
      #         }
      #       ];
      #     };
      #   };
      # };
    };

    # Create a test user to verify mediaUsers functionality
    users.users.testuser = {
      isNormalUser = true;
      home = "/home/testuser";
    };
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Check that all services are operational
    machine.succeed("systemctl is-active jellyfin")
    machine.succeed("systemctl is-active jellyseerr")
    machine.succeed("systemctl is-active audiobookshelf")
    machine.succeed("systemctl is-active plex")
    machine.succeed("systemctl is-active transmission")
    machine.succeed("systemctl is-active autobrr")
    machine.succeed("systemctl is-active bazarr")
    machine.succeed("systemctl is-active sonarr")
    machine.succeed("systemctl is-active radarr")
    machine.succeed("systemctl is-active readarr")
    machine.succeed("systemctl is-active readarr-audiobook")
    machine.succeed("systemctl is-active sabnzbd")
    machine.succeed("systemctl is-active lidarr")
    machine.succeed("systemctl is-active prowlarr")
    # machine.succeed("systemctl is-active recyclarr")

    print("\n=== Nixarr Simple Test Completed ===")
  '';
}
