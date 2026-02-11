---
title: Running Services Not Covered by Nixarr Through a VPN
---

Nixarr reexports its VPN-submodule, meaning you can run your own services using
it. As an example, let's say you want to run a Monero node through a VPN, then
you could use the following configuration:

```nix {.numberLines}
  # Open vpnports, must also be opened by VPN-provider
  vpnnamespaces.wg = {
    openVPNPorts = [
      { port = xmrP2PPort; protocol = "both"; }
      { port = xmrRpcPort; protocol = "both"; }
    ];
  };

  # Force moneronode to VPN
  systemd.services.monero.vpnconfinement = {
    enable = true;
    vpnnamespace = "wg"; # This must be "wg", that's what nixarr uses
  };

  services.monero = {
    enable = true;
    # Run as public node
    extraConfig = ''
      p2p-bind-ip=0.0.0.0
      p2p-bind-port=${builtins.toString xmrP2PPort}

      rpc-restricted-bind-ip=0.0.0.0
      rpc-restricted-bind-port=${builtins.toString xmrRpcPort}

      # Disable UPnP port mapping
      no-igd=1

      # Public-node
      public-node=1

      # ZMQ configuration
      no-zmq=1

      # Block known-malicious nodes from a DNSBL
      enable-dns-blocklist=1
    '';
  };
```

> **Note:** that the submodule supports more namespaces than just one, but
> Nixarr uses the name `wg`, so you should use that too.

Services running over the VPN will have address `192.168.15.1` instead of
`127.0.0.1`. For more options and information on the VPN-submodule, check out
[the repo](https://github.com/Maroka-chan/VPN-Confinement)
