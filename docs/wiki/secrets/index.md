---
title: Recemmended Secrets Management
---

Secrets in nix can be difficult to handle. Your Nixos configuration is
world-readable in the nix store. This means that _any_ user can read your config
in `/nix/store` somewhere (_Not good!_). The way to solve this is to keep your
secrets in files and pass these to nix. Below, I will present two ways of
accomplishing this.

> **Warning:** Do _not_ let secrets live in your configuration directory either!

## The simple way

The simplest secrets management is to simply create a directory for all you
secrets, for example:

```sh
  sudo mkdir -p /data/.secret
  sudo chmod 700 /data/.secret
```

Then put your secrets, for example your wireguard configuration from your
VPN-provider, in this directory:

```sh
  sudo mkdir -p /data/.secret/vpn
  sudo mv /path/to/wireguard/config/wg.conf /data/.secret/vpn/wg.conf
```

And set the accompanying Nixarr option:

```nix
  nixarr.vpn = {
    enable = true;
    wgConf = "/data/.secret/vpn/wg.conf";
  };
```

> **Note:** This is "impure", meaning that since the file is not part of the nix
> store, a nixos rollback will not restore a previous secret (not a big problem
> if the secrets are not changed often). This also means you have to rebuild
> Nixos using the `--impure` flag set.

## Agenix - A Path to Purity

The "right way" to do secret management is to have your secrets encrypted in
your configuration directory. Doing it this way is "pure", and rollbacks will
once again function correctly. This can be accomplished using
[agenix](https://github.com/ryantm/agenix). I won't go into the details of how
to set it up since it's a more complex solution than the one above. However, if
you're a more advanced user and want to do things the "right way", then check
out their documentation.
