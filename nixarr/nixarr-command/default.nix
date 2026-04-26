{
  inputs,
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  nixarr = config.nixarr;
  globals = config.util-nixarr.globals;
  nixarr-command = pkgs.writeShellApplication {
    name = "nixarr";
    runtimeInputs = with pkgs; [
      util-linux
      yq
      gnugrep
      gnused
    ];
    text = ''
      command="''${1:-}"

      # Check if a parameter is provided
      if [ -z "$command" ]; then
        echo "Usage: nixarr <command>"
        echo ""
        echo "Commands:"
        echo "  fix-permissions       Sets correct permissions for any directory managed by Nixarr."
        echo "  list-api-keys         Lists API keys of supported enabled services."
        echo "  list-unlinked <path>  Lists unlinked directories and files, in the given directory."
        echo "                        Use the jdupes command to hardlink duplicates from there."
        echo "  wipe-uids-gids        The update on 2025-06-03 causes issues with UID/GIDs,"
        echo "                        run this command, then rebuild and finally run"
        echo "                        nixarr fix-permissions, to fix these issues."
        exit 1
      fi

      fix-permissions() {
        if [ "$EUID" -ne 0 ]; then
          echo "Please run as root"
          exit
        fi

        find "${nixarr.mediaDir}" \( -type d -exec chmod 0775 {} + -true \) -o \( -exec chmod 0664 {} + \)
        mkdir -p "${nixarr.mediaDir}/library"
        chown -R ${globals.libraryOwner.user}:${globals.libraryOwner.group} "${nixarr.mediaDir}/library"

        ${strings.optionalString nixarr.jellyfin.enable ''
        chown -R ${globals.jellyfin.user}:root "${nixarr.jellyfin.stateDir}"
        find "${nixarr.jellyfin.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.plex.enable ''
        chown -R ${globals.plex.user}:root "${nixarr.plex.stateDir}"
        find "${nixarr.plex.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.audiobookshelf.enable ''
        chown -R ${globals.audiobookshelf.user}:root "${nixarr.audiobookshelf.stateDir}"
        find "${nixarr.audiobookshelf.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.anchorr.enable ''
        chown -R ${globals.anchorr.user}:root "${nixarr.anchorr.stateDir}"
        find "${nixarr.anchorr.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.transmission.enable ''
        chown -R ${globals.transmission.user}:${globals.transmission.group} "${nixarr.mediaDir}/torrents"
        chown -R ${globals.transmission.user}:${globals.cross-seed.group} "${nixarr.transmission.stateDir}"
        find "${nixarr.transmission.stateDir}" \( -type d -exec chmod 0750 {} + -true \) -o \( -exec chmod 0640 {} + \)
      ''}
        ${strings.optionalString nixarr.sabnzbd.enable ''
        chown -R ${globals.sabnzbd.user}:${globals.sabnzbd.group} "${nixarr.mediaDir}/usenet"
        chown -R ${globals.sabnzbd.user}:root "${nixarr.sabnzbd.stateDir}"
        find "${nixarr.sabnzbd.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.transmission.privateTrackers.cross-seed.enable ''
        chown -R ${globals.cross-seed.user}:root "${nixarr.transmission.privateTrackers.cross-seed.stateDir}"
        find "${nixarr.transmission.privateTrackers.cross-seed.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.prowlarr.enable ''
        chown -R ${globals.prowlarr.user}:root "${nixarr.prowlarr.stateDir}"
        find "${nixarr.prowlarr.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.sonarr.enable ''
        chown -R ${globals.sonarr.user}:root "${nixarr.sonarr.stateDir}"
        find "${nixarr.sonarr.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.radarr.enable ''
        chown -R ${globals.radarr.user}:root "${nixarr.radarr.stateDir}"
        find "${nixarr.radarr.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.lidarr.enable ''
        chown -R ${globals.lidarr.user}:root "${nixarr.lidarr.stateDir}"
        find "${nixarr.lidarr.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.bazarr.enable ''
        chown -R ${globals.bazarr.user}:root "${nixarr.bazarr.stateDir}"
        find "${nixarr.bazarr.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.readarr.enable ''
        chown -R ${globals.readarr.user}:root "${nixarr.readarr.stateDir}"
        find "${nixarr.readarr.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.readarr-audiobook.enable ''
        chown -R ${globals.readarr-audiobook.user}:root "${nixarr.readarr-audiobook.stateDir}"
        find "${nixarr.readarr-audiobook.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.jellyseerr.enable ''
        chown -R ${globals.jellyseerr.user}:root "${nixarr.jellyseerr.stateDir}"
        find "${nixarr.jellyseerr.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.autobrr.enable ''
        chown -R ${globals.autobrr.user}:root "${nixarr.autobrr.stateDir}"
        find "${nixarr.autobrr.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.recyclarr.enable ''
        chown -R ${globals.recyclarr.user}:root "${nixarr.recyclarr.stateDir}"
        find "${nixarr.recyclarr.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.whisparr.enable ''
        chown -R ${globals.whisparr.user}:root "${nixarr.whisparr.stateDir}"
        find "${nixarr.whisparr.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
        ${strings.optionalString nixarr.komga.enable ''
        chown -R ${globals.komga.user}:root "${nixarr.komga.stateDir}"
        find "${nixarr.komga.stateDir}" \( -type d -exec chmod 0700 {} + -true \) -o \( -exec chmod 0600 {} + \)
      ''}
      }

      list-unlinked() {
        if [ "$#" -ne 1 ]; then
            echo "Illegal number of parameters. Usage: nixarr list-unlinked <path>"
        fi
        find "$1" -type f -links 1 -exec du -h {} + | sort -h
      }

      list-api-keys() {
        if [ "$EUID" -ne 0 ]; then
          echo "Please run as root"
          exit
        fi

        ${strings.optionalString nixarr.bazarr.enable ''
        BAZARR=$(yq '.auth.apikey' "${nixarr.bazarr.stateDir}/config/config.yaml")
        echo "Bazarr api-key: $BAZARR"
      ''}
        ${strings.optionalString nixarr.jellyseerr.enable ''
        JELLYSEERR=$(yq '.main.apiKey' "${nixarr.jellyseerr.stateDir}/settings.json")
        echo "Jellyseerr api-key: $JELLYSEERR"
      ''}
        ${strings.optionalString nixarr.lidarr.enable ''
        LIDARR=$(xq '.Config.ApiKey' "${nixarr.lidarr.stateDir}/config.xml")
        echo "Lidarr api-key: $LIDARR"
      ''}
        ${strings.optionalString nixarr.prowlarr.enable ''
        PROWLARR=$(xq '.Config.ApiKey' "${nixarr.prowlarr.stateDir}/config.xml")
        echo "Prowlarr api-key: $PROWLARR"
      ''}
        ${strings.optionalString nixarr.radarr.enable ''
        RADARR=$(xq '.Config.ApiKey' "${nixarr.radarr.stateDir}/config.xml")
        echo "Radarr api-key: $RADARR"
      ''}
        ${strings.optionalString nixarr.readarr.enable ''
        READARR=$(xq '.Config.ApiKey' "${nixarr.readarr.stateDir}/config.xml")
        echo "Readarr api-key: $READARR"
      ''}
        ${strings.optionalString nixarr.readarr-audiobook.enable ''
        READARR_AUDIOBOOK=$(xq -r '.Config.ApiKey' "${nixarr.readarr-audiobook.stateDir}/config.xml")
        echo "Readarr Audiobook api-key: $READARR_AUDIOBOOK"
      ''}
        ${strings.optionalString nixarr.sabnzbd.enable ''
        SABNZBD=$(grep api_key ${nixarr.sabnzbd.stateDir}/sabnzbd.ini | sed 's/^api_key.*= *//g')
        echo "Sabnzbd api-key: \"$SABNZBD\""
      ''}
        ${strings.optionalString nixarr.sonarr.enable ''
        SONARR=$(xq '.Config.ApiKey' "${nixarr.sonarr.stateDir}/config.xml")
        echo "Sonarr api-key: $SONARR"
      ''}
        ${strings.optionalString nixarr.whisparr.enable ''
        WHISPARR=$(xq '.Config.ApiKey' "${nixarr.whisparr.stateDir}/config.xml")
        echo "Whisparr api-key: $WHISPARR"
      ''}
        ${strings.optionalString nixarr.sonarr.enable ''
        TRANSMISSION_RPC_USER=$(yq '.["rpc-username"]' "${nixarr.transmission.stateDir}/.config/transmission-daemon/settings.json")
        TRANSMISSION_RPC_PASS=$(yq '.["rpc-password"]' "${nixarr.transmission.stateDir}/.config/transmission-daemon/settings.json")
        echo "Transmission rpc-username: $TRANSMISSION_RPC_USER"
        echo "Transmission rpc-password: $TRANSMISSION_RPC_PASS"
      ''}
      }

      wipe-uids-gids() {
        if [ "$EUID" -ne 0 ]; then
          echo "Please run as root"
          exit
        fi

        echo "Backing up /etc/passwd and /etc/group..."

        mkdir -p "${nixarr.stateDir}/migration-backup"
        cp /etc/passwd "${nixarr.stateDir}/migration-backup/passwd.bak"
        cp /etc/group "${nixarr.stateDir}/migration-backup/group.bak"

        echo "Wiping all nixarr users and groups from /etc/passwd and /etc/group..."

        sed -i -E '/^(anchorr|audiobookshelf|autobrr|bazarr|cross-seed|jellyfin|jellyseerr|lidarr|plex|prowlarr|radarr|readarr|recyclarr|sabnzbd|sonarr|streamer|torrenter|transmission|usenet|whisparr|komgarr)/d' /etc/passwd
        sed -i -E '/^(anchorr|autobrr|cross-seed|jellyseerr|media|prowlarr|recyclarr|sabnzbd|streamer|torrenter|transmission|usenet)/d' /etc/group

        echo ""
        echo "Done, please rebuild your configuration to get back the users and groups. This time, they will have the correct permissions."
        echo "After rebuilding, make sure to run: nixarr fix-permissions"
      }

      COMMAND="$1"
      shift
      case "$COMMAND" in
        fix-permissions)
          fix-permissions
          ;;
        list-unlinked)
          list-unlinked "$@"
          ;;
        list-api-keys)
          list-api-keys
          ;;
        wipe-uids-gids)
          wipe-uids-gids
          ;;
      esac
    '';
  };
in {
  config = mkIf nixarr.enable {
    environment.systemPackages = [nixarr-command];
  };
}
