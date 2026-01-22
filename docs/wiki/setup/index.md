---
title: Setup the applications
---

Here are some guides to help you set up the applications. We assume you left the
default ports; if you changed them, you will need to change the ports in the
URLs. Same if you are using a domain name—change the URLs to match. We assume
you are using the [first example](/wiki/examples/example-1) in your Nix
configuration. Replace {URL} in this document with your server IP or domain.

In the below setup, we assume you also didn't set the `nixarr.mediaDir`
option, which by default is set to `/data/media`.

## Jellyfin

- Open your browser and go to `{URL}:8096`.
- Click `Add Server` and put your server address
- Follow the setup wizard:
  - Create your administrator account.
  - Setup two libraries:
    - Movies: Choose "Movies" as content type, then add the
      `/data/media/library/movies` folder.
    - TV Shows: Same with `/data/media/library` as the folder.
    - You can add music, books, etc.
  - Continue the setup.

**Recommendations:**:

- Reduce the scan media library interval for small libraries: See
  `Scheduled Tasks`: {URL}:8096/web/index.html#/dashboard/tasks/

## Transmission

Transmission should already be setup and running since it's configured
with JSON, and can therefore be configured with nix. The most basic settings are already set. See the following links for more info:

- [The configured Nixarr defaults for transmission](https://github.com/rasmus-kirk/nixarr/blob/28d1be070deb1a064c1967889c11c8921752fa09/nixarr/transmission/default.nix#L355)
- [The `nixarr.transmission` options](https://nixarr.com/nixos-options/#nixarr.transmission.enable)
- [Settings that can be passed through `nixarr.transmission.settings`]

## Radarr

- Open your browser and go to `{URL}:7878`.
- You will be asked to set up a new account.
  - Choose `Forms` as the auth method and choose a username & password.
  - You can now log in.
- Go to "Settings" > "Media Management":
  - Click on `Show Advanced`
  - Under `Importing`, enable `Use Hardlinks instead of Copy`
  - Under `Permissions`, change `chmod Folder` to `775`
  - Under `Root Folders`, click `Add Root Folder`. Add
  `/data/media/library/movies/`, then click `Save Changes`.
- Go to "Settings" > "Download Clients" and add Transmission. Change the
  category to `radarr`.

**Recommendations:**:

- Go to {URL}:7878/settings/mediamanagement and set `Unmonitor Deleted Movies`
  to true.

## Sonarr

- Open your browser and go to `{URL}:8989`.
- You will be asked to set up a new account.
  - Choose `Forms` as the auth method and choose a username & password.
  - You can now log in.
- Go to "Settings" > "Media Management":
  - Click on `Show Advanced`
  - Under `Importing`, enable `Use Hardlinks instead of Copy`
  - Under `Permissions`, change `chmod Folder` to `775`
  - Under `Root Folders`, click `Add Root Folder`. Add
  `/data/media/library/shows/`, then click `Save Changes`.
- Go to "Settings" > "Download Clients" and add Transmission. Change the
  category to `sonarr`.

**Recommendations:**:

- Go to {URL}:8989/settings/mediamanagement and set `Unmonitor Deleted Episodes`
  to true.

## Jellyseerr

- Open your browser and go to `{URL}:5055`.
- Follow the installation wizard:
  - Choose Jellyfin (or Plex).
  - Add your Jellyfin URL, username & password (you can leave the path
    empty and use a dummy email).
  - Click on `Sync Libraries` and toggle `Movies` and `Shows`, click `Next`.
  - Add your Radarr and Sonarr apps.
  - Get the API key by typing `sudo nixarr list-api-keys` in your terminal.

## Bazarr

- Open your browser and go to `{URL}:6767`.
- Go to "Settings" > "Languages":
  - select your preferred languages for subtitles in "Languages Filter", then
    add a languages profile
  - Add a "Default Language Profile" for "Series" and "Movies"
- Go to "Settings" > "Sonarr" and "Settings" > "Radarr" to add your respective
  Sonarr and Radarr instances.
  - Get the API key by typing `sudo nixarr list-api-keys` in your terminal.
  - Click `Test` to ensure the connection works, then `Save`.
- Go to "Settings" > "Providers" and enable the subtitle providers you want.

**Recommendations:**:

- Go to {URL}:6767/settings/general and set `Unmonitor Deleted Subtitles` to
  true.
- Go to "Settings" > "Subtitles" > "Audio Synchronization / Alignment" and enable "Automatic
  Subtitles Audio Synchronization"

## Prowlarr

**Initial setup**:

- Open your browser and go to `{URL}:9696`.
- You will be asked to set up a new account.
  - Choose `Forms` as the auth method and choose a username & password.
  - You can now log in.
- Go to "Settings" > "Apps" and add your _Arrs_.
  - Get the API key by typing `sudo nixarr list-api-keys` in your terminal.

### Declarative Configuration

Instead of manually configuring Prowlarr, you can use the `nixarr.prowlarr.settings-sync` options to declaratively manage your configuration.

**Sync Applications**:
Automatically sync your enabled Arr applications (Sonarr, Radarr, Lidarr, Readar, Readarr-Audiobook) to Prowlarr:

```nix
nixarr.prowlarr.settings-sync.enable-nixarr-apps = true;
```

**Configure Indexers**:
Define your indexers directly in Nix:

```nix
nixarr.prowlarr.settings-sync.indexers = [
  {
    sort_name = "nzbgeek";
    fields = {
      apiKey.secret = "/path/to/api/key";
    };
  }
];
```

**Manage Tags**:
Define tags to be created in Prowlarr:

```nix
nixarr.prowlarr.settings-sync.tags = [ "iso" "remux" ];
```
