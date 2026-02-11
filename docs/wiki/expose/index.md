---
title: Exposing Services Safely
---

The concept of "exposing" will in this context mean to access your services
outside your home network. The simplest and safest way to access your services
is from inside your home network, please consider if this covers your needs. If
not, keep reading.

## VPN

The safest way to expose your services is through a VPN. I suggest you use
[tailscale](https://tailscale.com/) or to setup your own VPN
[manually with wireguard](https://nixos.wiki/wiki/WireGuard).

## SSH Tunneling

A practically equally safe way to expose your services is with SSH tunneling.
You will either need to port forward on your router, or
[run the openssh service through a VPN](/options.html#nixarr.openssh.expose.vpn.enable),
and port forward through your VPN-provider. Then you can access your services
from a remote machine using the following command:

```sh
  ssh -N user@ip \
    -L 6001:localhost:9091 \
    -L 6002:localhost:9696 \
    -L 6003:localhost:8989 \
    -L 6004:localhost:7878 \
    -L 6005:localhost:8686 \
    -L 6006:localhost:8787 \
    -L 6007:localhost:6767
```

Replace `user` with your user and `ip` with the public ip, or domain if set up,
of your server. This lets you access the services on `localhost:6001` through
`localhost:6007`. [Example 2](/wiki/examples/example-2) has an example
configuration for this.

> **Warning:** Disable password authentication if you use SSH, it's insecure!

## Without Authentication

The most unsafe way, is to expose your services to the internet without SSH
tunneling or VPN. This lets anyone on the internet connect to your services, and
you rely solely on the security of said services, not the much more robust
public key cryptogaphy of the solutions above! While it is not recommended, it
may be necessary depending on your setup.

The Jellyfin module, helpfully, has options for this, the
[`nixarr.jellyfin.expose.https.enable`](/options.html#nixarr.jellyfin.expose.https.enable)
and the
[`nixarr.jellyfin.expose.vpn.enable`](/options.html#nixarr.jellyfin.expose.vpn.enable)
options. Read the related documentation for more information.
