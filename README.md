![Logo](./docs/img/logo-2.png)

This is a Nixos module that aims to make the installation and management of
a home media server as easy, and pain free, as possible.

If you have problems or feedback, feel free to join [the
discord](https://discord.gg/n9ga99KwWC).

Note that this is still not 100% stable, so it is possible, but very unlikely,
that I will remove or change options in a non-backwards-compatible way.

## Features

- **Run services through a VPN:** You can run any service that this module
  supports through a VPN, fx `nixarr.transmission.vpn.enable = true;`
- **Declarative Settings Sync:** Configure Prowlarr indexers/apps, Sonarr/Radarr
  download clients, and Bazarr connections directly in Nix -- no manual UI
  setup required. See the [declarative configuration example](https://nixarr.com/wiki/examples/example-3).
- **Automatic Directories, Users and Permissions:** The module automatically
  creates directories and users for your media library. It also sets sane
  permissions.
- **State Management:** All services support state management and all state
  that they manage is located by default in `/data/.state/nixarr/*`. This means
  that you only have to backup your media directory and `/data/.state/nixarr`.
- **Prometheus Monitoring:** Optional Prometheus exporters for all \*Arr services,
  qBittorrent, WireGuard, and system metrics. Enable with
  `nixarr.exporters.enable = true`.
- **Optional Dynamic DNS support:** If you use [Njalla](https://njal.la/)
  and don't have a static IP, you can use the `nixarr.ddns.njalla.enable`
  option to dynamically update a DNS record that points to the dynamic public
  IP of your server or your public VPN IP.
- **Optional Automatic Port Forwarding:** This module has a UPNP support that
  lets services request ports from your router automatically, if you enable it.

To run services through a VPN, you must provide a wg-quick config file,
that is provided by most VPN providers:

```nix {.numberLines}
  nixarr.vpn = {
    enable = true;
    # WARNING: This file must _not_ be in the config git directory
    # You can usually get this wireguard file from your VPN provider
    wgConf = "/data/.secret/wg.conf";
  }
```

It is possible, _but not recommended_, to run the "*Arrs" behind a VPN,
because it can cause rate limiting issues.

## Options

The documentation for the options can be found
[here](https://nixarr.com/nixos-options/)

## The Wiki

If you want to know how to setup DDNS with Njalla, how to manage secrets in
nix or examples, check out the [wiki](https://nixarr.com/wiki/)

## Examples

See the [wiki](https://nixarr.com/wiki).

## Importing this module

To use this module, add it to your flake inputs in your nix flake file,
like shown in this example flake:

```nix {.numberLines}
  {
    description = "Your nix flake";

    inputs = {
      nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
      nixarr.url = "github:nix-media-server/nixarr";
    };

    outputs = { 
      nixpkgs,
      nixarr,
      ...
    }@inputs: {
      nixosConfigurations = {
        servarr = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";

          modules = [
            ./nixos/servarr/configuration.nix
            nixarr.nixosModules.default
          ];

          specialArgs = { inherit inputs; };
        };
      };
    };
  }
```

## VPN Providers

Your VPN-provider should at the very least support wg-quick configurations,
this module does not, and will not, support any other setup. Most VPN-providers
should support this ATM.

Secondly, it's recommended that the VPN you're using has support for _static_
port forwarding as this module has no builtin support for dynamic port
forwarding. I suggest [AirVpn](https://airvpn.org/), since they support
static port forwarding, support wg-quick configurations and accept Monero,
but you can use whatever you want.

## Domain Registrars

If you need a domain registrar I suggest [Njalla](https://njal.la/),
they are privacy-oriented, support DDNS and accept Monero. Note that you
don't technically "own" the domain for privacy reasons, they "lease" it to
you. However, this also means that you don't have to give _any_ personal data.

## Thanks

A big thanks to [Maroka-chan](https://github.com/Maroka-chan) for the heavy
lifting on the [VPN-submodule](https://github.com/Maroka-chan/VPN-Confinement),
that was integral to making this project possible.

I would also like to thank [Lasse](https://github.com/lassebomh) for helping
out with the website.
