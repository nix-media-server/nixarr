# Changelog

## Unreleased

Added:
- qBittorrent service with VPN support, qui WebUI, and Prometheus exporter
- Added a `configureNginx` option to support users who would rather not
  use Nginx.
- Prowlarr, Radarr, Sonarr:
  - Options for syncing configuration from Nixarr to apps (e.g. specifying
    indexers in Nixarr and having them automatically added to Prowlarr).
    See individual app config docs for what is supported.
- `nixarr` command:
  - `nixarr show-prowlarr-schemas`, `nixarr show-radarr-schemas`,
    `nixarr show-sonarr-schemas`
    - Show what schemas are supported/expected by those apps for syncing. See
      individual app config docs for how to use these schemas when writing your
      Nixarr config.
- Python library `lib/nixarr-py`: helpers for making
  [devopsarr](https://github.com/devopsarr) clients configured to connect to
  Nixarr services.

## 2025-11-15

Changed:
- Firewall is now enabled per default for all services, unless explicitly
  set otherwise. Except for the Transmission peer-port for which the firewall
  is disabled if the port is set.

## 2025-10-29

Added:
- `whisparr` service
- `komgarr` service

Fixed:
- Cross-seed now uses `transmission` user.
- Added port options to some relevant services.
- UPNP

## 2025-06-03

Added:
- `nixarr` command
  - `nixarr fix-permissions`
    - Sets correct permissions for any directory managed by Nixarr.
  - `nixarr list-api-keys`
    - Lists API keys of supported enabled services.
  - `nixarr list-unlinked <path>`
    - Lists unlinked directories and files, in the given directory. Use the
      jdupes command to hardlink duplicates from there.
  - `wipe-uids-gids`
    - The update on 2025-06-03 causes issues with UID/GIDs, see the below
      migration section.
- Added Readarr Audiobook for running two readarr instances (one intended
  for audiobooks, one intended for regular books)
- Audiobookshelf service, with expose options
- Port configurations on:
  - Radarr
  - Sonarr
  - Prowlarr
  - Readarr
  - Lidarr
- UID/GID's are now static, this should make future backups and migrations more predictable.

Migration:
- Due to how UID/GID's are handled in this new version, certain services
  may break. To ammend this, run:
  ```bash
    sudo nixarr wipe-uids-gids
    sudo nixos-rebuild ...
    sudo nixarr fix-permissions
  ```

## 2025-05-28

Added:
- Plex service
- Autobrr service
- Sandboxed Jellyseerr module and added expose option (fully resolves #22)
- accessibleFrom option to VPN-submodule (see #51)

Updated:
- If `nixarr.enable` is not enabled other services will automatically now
  be disabled, instead of throwing an assertion error.

Fixed:
- Airvpn DNS bug (Fixed #51)
- Cross-seed now uses the nixpkgs package (fixed #51)
- Default Transmission umask set to "002", meaning 664/775 permissions (fixed #56)

## 2025-03-17

Added:
- Recyclarr service

Removed:
- Sonarr default package now defaults to current nixpkgs sonarr package again.

## 2025-01-18

Added:
- Jellyseer service
- Sonarr default package, pinned to older working sonarr package

Removed:
- Jellyfin expose VPN options

## 2024-09-19

Added:
- Options to control the package of each service
- sub-merge package to systemPkgs

Updated:
- All submodules (notably VPNConfinement)

## 2024-06-11

Updated:
- VPNConfinement submodule

## 2024-05-09

Fixed:
- Jellyfin now has highest IO priority and transmission has lowest

## 2024-03-12

Added:
- `fix-permissions` script, that sets correct permissions for all directories
  and files in the state and media library

Fixed:
- Some permission issues here and there

## 2024-03-12

Added:
- bazarr
- njalla-vpn-ddns (ddns to public vpn ip)

Fixed:
- Cross-seed (wrong torrentdir)
- Opened firewall for services by default if you're not using vpn, this prevented users from connecting to services over local networks

Updated:
- Docs (stateDirs and mediaDir cannot be home!)
- vpn submodule (adds firewall and DNS-leak killswitch)

## 2024-03-14

Added:
- Reexported VPN-submodule, allowing users to run services, not supported by this module, through the VPN
