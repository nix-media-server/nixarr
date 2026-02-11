---
title: Example Configuration Where Port Forwarding Is Not an Option
---

<<<<<<< Updated upstream
An example where port forwarding is not an option. This is useful if,
for example, you're living in a dorm that does not allow it. This
example does the following:
=======
An example where port forwarding is not an option. This is useful if, for
example, you're living in a dorm that does not allow it. The example assumes you
have a VPN-provider that allows for port-forwarding. This example does the
following:
>>>>>>> Stashed changes

- Runs Jellyfin
- Starts openssh and runs it through the VPN so that it can be accessed outside
  your home network
- Runs all the supported "\*Arrs"

```nix {.numberLines}
  nixarr = {
    enable = true;

    vpn = {
      enable = true;
      wgConf = "/data/.secret/wg.conf";
    };

    jellyfin.enable = true;

    # Setup SSH service that runs through VPN.
    # Lets you connect through ssh from the internet without having access to
    # port forwarding
    openssh.expose.vpn.enable = true;

    transmission = {
      enable = true;
      vpn.enable = true;
      peerPort = 50000; # Set this to the port forwarded by your VPN
    };

    bazarr.enable = true;
    sonarr.enable = true;
    radarr.enable = true;
    prowlarr.enable = true;
    readarr.enable = true;
    lidarr.enable = true;
    jellyseerr.enable = true;
  };

  # The `openssh.vpn.enable` option does not enable openssh, so we do that here:
  # We disable password authentication as it's generally insecure.
  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
    # Get this port from your VPN provider
    ports = [ 34567 ]
  };
  # Adds your public keys as trusted devices
  users.extraUsers.username.openssh.authorizedKeys.keyFiles = [
    ./path/to/public/key/machine.pub
  ];
```

This example uses SSH tunneling to expose most of your services. See the
[expose](/wiki/expose) wiki page for more info on how to safely access your
services.

In this example, you don't have access to any services without being on your
home network or accessing them through localhost. If you have SSH setup you can
use SSH tunneling. Simply run:

```sh
  ssh -N user@ip \
    -L 6001:localhost:9091 \
    -L 6002:localhost:9696 \
    -L 6003:localhost:8989 \
    -L 6004:localhost:7878 \
    -L 6005:localhost:8686 \
    -L 6006:localhost:8787 \
    -L 6007:localhost:6767 \
    -L 6008:localhost:8096
```

Replace `user` with your user and `ip` with the VPN ip. This lets you access the
services on `localhost:6001` through `localhost:6008`.
