# Changelog

## Unreleased

Added:
- **Declarative settings-sync** for multiple services, allowing configuration
  via Nix options instead of manual UI setup:
  - **Prowlarr:** Declaratively manage indexers, applications (Sonarr, Radarr,
    Lidarr, Readarr, Readarr-Audiobook, Whisparr), and tags. Use
    `nixarr.prowlarr.settings-sync` to configure. Set `enable-nixarr-apps = true`
    to automatically sync all enabled *Arrs.
  - **Sonarr:** Declaratively configure download clients. Use
    `nixarr.sonarr.settings-sync.transmission.enable = true` to automatically
    add Transmission, or specify custom clients via `downloadClients`.
  - **Radarr:** Same as Sonarr — declaratively configure download clients via
    `nixarr.radarr.settings-sync`.
  - **Bazarr:** Declaratively configure Sonarr/Radarr connections. Use
    `nixarr.bazarr.settings-sync.sonarr.enable = true` and
    `nixarr.bazarr.settings-sync.radarr.enable = true` with optional filtering
    for monitored content only.
- **qBittorrent service** with VPN confinement support, [qui](https://github.com/autobrr/qui)
  WebUI (enabled by default), private tracker mode, Prometheus exporter, and
  `extraConfig` for declarative configuration.
- **Prometheus monitoring** for *Arr services:
  - Exportarr-based exporters for Sonarr, Radarr, Lidarr, Readarr, and Prowlarr.
  - qBittorrent Prometheus exporter.
  - Node, systemd, and WireGuard exporters.
  - VPN-aware: exporters are automatically confined to the VPN namespace when
    the monitored service is VPN-confined.
  - Enable with `nixarr.exporters.enable = true`.
- **Jellyfin Python API client** (`nixarr-py`): a standalone Python library for
  interacting with Nixarr services via [devopsarr](https://github.com/devopsarr)
  clients. Includes Jellyfin API authentication via API key or username/password.
- **`configureNginx` option** for services, to support users who would rather
  not use Nginx.
- `nixarr` command additions:
  - `nixarr show-prowlarr-schemas`, `nixarr show-radarr-schemas`,
    `nixarr show-sonarr-schemas` — show what schemas are supported/expected by
    those apps for settings-sync configuration.
- **Nginx localhost option:** `proxyListenAddr` and `exposeOnLAN` options to
  restrict nginx to listen on `127.0.0.1` only, allowing reverse proxies like
  Caddy or Tailscale to front services.
- **Audiobookshelf:** exposed `host` option for configuring listen address,
  fixed `openFirewall` to actually open ports.

Changed:
- Formatting now uses `treefmt-nix` with `alejandra` (Nix) and `ruff-format`
  (Python).
- CI modernized: pinned action versions, magic Nix cache for faster builds,
  automatic flake update PRs.
- `show-schemas` commands moved from individual services to the `nixarr` command.
- Python package renamed from `nixarr` to `nixarr_py` to avoid import conflicts.
- `nixarr-py` split into standalone library plus system config module.

Fixed:
- *Arr services (Radarr, Sonarr, Lidarr, Bazarr) now set `UMask = "0002"` in
  systemd, ensuring directories are created with 775 permissions for proper
  group access.
- qBittorrent `fix-permissions` now uses the correct download path.
- Jellyfin authentication cleaned up: uses shared API key instead of creating
  a new device UUID per connection.

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
