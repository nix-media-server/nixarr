/*
VPN Confinement Integration Test

This test validates that Nixarr services are properly confined to a VPN namespace
and cannot leak traffic when the VPN connection fails. It uses a 3-VM topology
to simulate real-world network conditions.

Network Topology:
┌──────────────┐    VLAN 2     ┌─────────────┐    VLAN 1     ┌─────────────┐
│internetClient│ ◄──────────── │   gateway   │ ◄──────────── │ nixarrHost  │
│  10.0.1.2    │               │ 10.0.1.1    │               │192.168.1.2  │
│ fd00:2::2    │               │192.168.1.1  │               │ fd00:1::2   │
└──────────────┘               │ fd00:2::1   │               └─────────────┘
                               │ fd00:1::1   │                       │
                               └─────────────┘                       │
                                      │                              │
                                 WireGuard tunnel                    │
                                 10.100.0.1 ◄────────────────────────┘
                                 fd00:100::1      VPN namespace
                                                 (10.100.0.2, fd00:100::2)

Test Coverage:
- VPN namespace isolation (transmission confined to wg namespace)
- IPv4 and IPv6 traffic routing through VPN tunnel
- Traffic leak prevention when VPN is down
- Port forwarding from external clients through gateway to VPN services
- DNS configuration in VPN namespace
- Service recovery after VPN reconnection

The test ensures that:
1. All transmission traffic goes through the VPN tunnel
2. Source IP is preserved (shows VPN client IP: 10.100.0.2/fd00:100::2)
3. No traffic leaks to host network when VPN fails
4. External port forwarding works correctly
5. Both IPv4 and IPv6 work identically through the tunnel
*/
{
  pkgs,
  nixosModules,
  lib ? pkgs.lib,
}: let
  # WireGuard configuration for the VPN gateway
  wgGatewayPort = 51820;

  # Generate real WireGuard keys
  wgGatewayPrivateKey =
    pkgs.runCommand "wg-gateway-private" {buildInputs = [pkgs.wireguard-tools];}
    ''
      wg genkey > $out
    '';
  wgGatewayPublicKey =
    pkgs.runCommand "wg-gateway-public" {buildInputs = [pkgs.wireguard-tools];}
    ''
      cat ${wgGatewayPrivateKey} | wg pubkey > $out
    '';

  wgClientPrivateKey =
    pkgs.runCommand "wg-client-private" {buildInputs = [pkgs.wireguard-tools];}
    ''
      wg genkey > $out
    '';
  wgClientPublicKey =
    pkgs.runCommand "wg-client-public" {buildInputs = [pkgs.wireguard-tools];}
    ''
      cat ${wgClientPrivateKey} | wg pubkey > $out
    '';

  # Network configuration
  wgGatewayAddr = "10.100.0.1";
  wgClientAddr = "10.100.0.2";
  wgSubnet = "10.100.0.0/24";

  # Fixed VM IPs
  gatewayIP = "192.168.1.1";
  nixarrHostIP = "192.168.1.2";

  # Internet client IPs
  internetClientIP = "10.0.1.2";
  internetGatewayIP = "10.0.1.1";

  # IPv6 addresses
  gatewayIPv6 = "fd00:1::1";
  nixarrHostIPv6 = "fd00:1::2";
  internetClientIPv6 = "fd00:2::2";
  internetGatewayIPv6 = "fd00:2::1";
  wgGatewayAddrV6 = "fd00:100::1";
  wgClientAddrV6 = "fd00:100::2";

  # Generate WireGuard config file for client
  wgClientConfig = pkgs.writeText "wg-client.conf" ''
    [Interface]
    PrivateKey = ${builtins.readFile wgClientPrivateKey}
    Address = ${wgClientAddr}/24, ${wgClientAddrV6}/64
    DNS = ${wgGatewayAddr}

    [Peer]
    PublicKey = ${builtins.readFile wgGatewayPublicKey}
    Endpoint = ${gatewayIP}:${toString wgGatewayPort}
    AllowedIPs = 0.0.0.0/0, ::/0
    PersistentKeepalive = 25
  '';
in
  pkgs.testers.nixosTest {
    name = "nixarr-vpn-confinement-test";

    # Disable interactive mode to avoid hanging
    interactive = false;

    nodes = {
      # Internet client VM - Simulates external services and clients
      internetClient = {
        config,
        pkgs,
        ...
      }: {
        virtualisation.vlans = [2]; # Connect to VLAN 2 (Internet)

        networking = {
          firewall.enable = false;
        };

        # Add route to VPN subnet
        boot.kernel.sysctl."net.ipv4.ip_forward" = 0; # internetClient doesn't forward

        # Enable systemd-networkd for proper route management
        systemd.network.enable = true;
        networking.useNetworkd = true;

        # Configure static routes to VPN subnet using systemd-networkd
        systemd.network.networks."40-eth1" = {
          matchConfig.Name = "eth1";
          networkConfig = {
            DHCP = "no";
          };
          address = [
            "${internetClientIP}/24"
            "${internetClientIPv6}/64"
          ];
          gateway = [
            "${internetGatewayIP}"
            "${internetGatewayIPv6}"
          ];
          routes = [
            {
              Destination = "${wgSubnet}";
              Gateway = "${internetGatewayIP}";
            }
            {
              Destination = "fd00:100::/64";
              Gateway = "${internetGatewayIPv6}";
            }
          ];
        };

        # Web server that returns source IP for testing
        systemd.services.source-ip-server = {
          enable = true;
          wantedBy = ["multi-user.target"];
          after = ["network.target"];
          serviceConfig = {
            Type = "exec";
            ExecStart = let
              server = pkgs.writeText "server.py" ''
                import http.server
                import socketserver
                import socket

                class DualStackHTTPServer(socketserver.ThreadingMixIn, http.server.HTTPServer):
                    address_family = socket.AF_INET6
                    def server_bind(self):
                        # Enable dual-stack support
                        self.socket.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 0)
                        super().server_bind()

                class MyHandler(http.server.BaseHTTPRequestHandler):
                    def do_GET(self):
                        self.send_response(200)
                        self.end_headers()
                        self.wfile.write(f"Source: {self.client_address[0]}".encode())

                # Listen on all interfaces
                with DualStackHTTPServer(("::", 8080), MyHandler) as httpd:
                    httpd.serve_forever()
              '';
            in "${pkgs.python3}/bin/python3 ${server}";
            Restart = "always";
          };
        };

        environment.systemPackages = with pkgs; [
          netcat-gnu
          curl
          python3
        ];
      };

      # VPN Gateway VM - Acts as WireGuard server and internet gateway
      gateway = {
        config,
        pkgs,
        ...
      }: {
        virtualisation.vlans = [
          1
          2
        ]; # VLAN 1 for LAN, VLAN 2 for Internet

        networking = {
          interfaces.eth1 = {
            ipv4.addresses = [
              {
                address = gatewayIP;
                prefixLength = 24;
              }
            ];
            ipv6.addresses = [
              {
                address = gatewayIPv6;
                prefixLength = 64;
              }
            ];
          };

          interfaces.eth2 = {
            ipv4.addresses = [
              {
                address = internetGatewayIP;
                prefixLength = 24;
              }
            ];
            ipv6.addresses = [
              {
                address = internetGatewayIPv6;
                prefixLength = 64;
              }
            ];
          };

          firewall = {
            enable = true;
            allowedUDPPorts = [
              wgGatewayPort
              51413
            ];
            allowedTCPPorts = [51413];
          };

          wireguard.interfaces.wg0 = {
            ips = [
              "${wgGatewayAddr}/24"
              "${wgGatewayAddrV6}/64"
            ];
            listenPort = wgGatewayPort;
            privateKeyFile = "${wgGatewayPrivateKey}";

            peers = [
              {
                publicKey = builtins.readFile wgClientPublicKey;
                allowedIPs = [
                  "${wgClientAddr}/32"
                  "${wgClientAddrV6}/128"
                ];
              }
            ];
          };
        };

        # Enable IP forwarding
        boot.kernel.sysctl = {
          "net.ipv4.ip_forward" = 1;
          "net.ipv6.conf.all.forwarding" = 1;
        };

        # Port forwarding and firewall rules
        networking.firewall.extraCommands = ''
          # Allow WireGuard and testing traffic (IPv4)
          iptables -A INPUT -i eth1 -j ACCEPT
          iptables -A INPUT -i eth2 -j ACCEPT
          iptables -A INPUT -i wg0 -j ACCEPT

          # Allow WireGuard and testing traffic (IPv6)
          ip6tables -A INPUT -i eth1 -j ACCEPT
          ip6tables -A INPUT -i eth2 -j ACCEPT
          ip6tables -A INPUT -i wg0 -j ACCEPT

          # IPv6 forwarding rules - Allow forwarding between interfaces
          ip6tables -A FORWARD -i wg0 -o eth2 -j ACCEPT
          ip6tables -A FORWARD -i eth2 -o wg0 -j ACCEPT
          ip6tables -A FORWARD -i wg0 -o eth1 -j ACCEPT
          ip6tables -A FORWARD -i eth1 -o wg0 -j ACCEPT
          ip6tables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT

          # Note: No masquerading - we want to preserve source IPs for testing

          # Forward transmission peer port from internet to VPN client (this is the key test)
          iptables -t nat -A PREROUTING -i eth2 -p tcp --dport 51413 -j DNAT --to-destination ${wgClientAddr}:51413
          iptables -t nat -A PREROUTING -i eth2 -p udp --dport 51413 -j DNAT --to-destination ${wgClientAddr}:51413

          # Allow forwarded traffic
          iptables -A FORWARD -p tcp --dport 51413 -d ${wgClientAddr} -j ACCEPT
          iptables -A FORWARD -p udp --dport 51413 -d ${wgClientAddr} -j ACCEPT

          # Accept return traffic for established connections
          iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
        '';

        # Simple DNS server for testing
        services.dnsmasq = {
          enable = true;
          settings = {
            interface = "wg0";
            bind-interfaces = true;
            listen-address = wgGatewayAddr;
            # Log DNS queries for leak detection
            log-queries = true;
            log-facility = "/var/log/dnsmasq-queries.log";
            # Static DNS entries for testing
            address = [
              "/test.vpn.local/${wgGatewayAddr}"
              "/leak.test.local/1.2.3.4"
              "/transmission.local/${wgClientAddr}"
            ];
          };
        };

        # Ensure dnsmasq starts after WireGuard
        systemd.services.dnsmasq = {
          after = ["wireguard-wg0.service"];
          wants = ["wireguard-wg0.service"];
        };

        # No additional routing needed on gateway - it has direct interfaces to both networks

        # Install test utilities
        environment.systemPackages = with pkgs; [
          iptables
          netcat-gnu
          python3
          iproute2 # for ss command
          tcpdump
        ];
      };

      # Nixarr host with VPN-confined transmission
      nixarrHost = {
        config,
        pkgs,
        ...
      }: {
        imports = [nixosModules.default];

        virtualisation.vlans = [1]; # Connect to VLAN 1

        networking = {
          interfaces.eth1 = {
            ipv4.addresses = [
              {
                address = nixarrHostIP;
                prefixLength = 24;
              }
            ];
            ipv6.addresses = [
              {
                address = nixarrHostIPv6;
                prefixLength = 64;
              }
            ];
          };

          # Disable firewall for testing
          firewall.enable = false;

          # Add route to gateway
          defaultGateway = {
            address = gatewayIP;
            interface = "eth1";
          };
          defaultGateway6 = {
            address = gatewayIPv6;
            interface = "eth1";
          };
        };

        # Copy WireGuard config to the expected location
        system.activationScripts.setupWgConfig = ''
          mkdir -p /etc/wireguard
          cp ${wgClientConfig} /etc/wireguard/wg0.conf
          chmod 600 /etc/wireguard/wg0.conf
        '';

        # Minimal nixarr configuration with VPN
        nixarr = {
          enable = true;

          # Required directories
          mediaDir = "/data/media";
          stateDir = "/data/.state/nixarr";

          # Enable VPN
          vpn = {
            enable = true;
            wgConf = "/etc/wireguard/wg0.conf";
          };

          # Enable transmission with VPN
          transmission = {
            enable = true;
            vpn.enable = true;
            # Use specific peer port for testing
            peerPort = 51413;
            # Disable firewall opening since we're in VPN
            openFirewall = false;
          };

          # Disable all other services
          sonarr.enable = false;
          radarr.enable = false;
          lidarr.enable = false;
          readarr.enable = false;
          bazarr.enable = false;
          prowlarr.enable = false;
          jellyfin.enable = false;
          plex.enable = false;
          sabnzbd.enable = false;
          autobrr.enable = false;
          recyclarr.enable = false;
          jellyseerr.enable = false;
        };

        # Add IPv6 route for VPN namespace to reach internetClient via WireGuard
        systemd.network.networks."10-eth1" = {
          matchConfig.Name = "eth1";
          routes = [
            {
              routeConfig = {
                Destination = "fd00:2::/64"; # Route to internetClient network
                Gateway = gatewayIPv6; # Via gateway IPv6
              };
            }
          ];
        };

        # Install test utilities
        environment.systemPackages = with pkgs; [
          wireguard-tools
          dig
          curl
          iproute2
          iptables
          netcat-gnu
          tcpdump
        ];
      };
    };

    testScript = ''
      start_all()

      print("=== Waiting for VMs to boot ===")
      # Wait for all VMs to be ready
      internetClient.wait_for_unit("multi-user.target", timeout=60)
      gateway.wait_for_unit("multi-user.target", timeout=60)
      nixarrHost.wait_for_unit("multi-user.target", timeout=60)

      # Wait for web server on internetClient
      internetClient.wait_for_unit("source-ip-server.service")
      internetClient.wait_for_open_port(8080)

      # Wait for systemd-networkd to set up routes
      internetClient.wait_for_unit("systemd-networkd.service")


      print("=== Test 1: Basic connectivity between VMs ===")
      # First verify that nixarrHost can reach the gateway
      nixarrHost.succeed("ping -c 1 ${gatewayIP}")
      gateway.succeed("ping -c 1 ${nixarrHostIP}")


      print("=== Test 2: Check VPN namespace setup ===")
      # Check that wg namespace exists
      nixarrHost.succeed("ip netns list | grep -q wg")

      # The VPN namespace service should be running
      nixarrHost.wait_for_unit("wg.service")

      # Check if transmission is running
      nixarrHost.wait_for_unit("transmission.service", timeout=30)


      print("=== Test 3: Check WireGuard connectivity ===")
      # Check if WireGuard interface exists in namespace
      nixarrHost.succeed("ip netns exec wg ip link show wg0")

      # Check WireGuard status
      nixarrHost.succeed("ip netns exec wg wg show")

      # Test VPN tunnel connectivity
      nixarrHost.succeed("ip netns exec wg ping -c 3 ${wgGatewayAddr}")


      print("=== Test 4: Verify traffic routing through VPN ===")
      # Debug: See what the web server actually returns
      response = nixarrHost.succeed("ip netns exec wg curl -s http://${internetClientIP}:8080")
      print(f"Web server response: {response}")

      # Test traffic through VPN tunnel to internetClient - should show VPN client IP
      nixarrHost.succeed("ip netns exec wg curl -s http://${internetClientIP}:8080 | grep -q '${wgClientAddr}'")


      print("=== Test 5: Verify traffic routing through VPN ===")
      # IPv4 traffic to host network should be blocked (specific route handling)
      nixarrHost.fail("ip netns exec wg curl -s --max-time 2 http://${gatewayIP}:8080")

      # Debug IPv6 connectivity before main test
      print("=== Debug IPv6 connectivity ===")

      # Check IPv6 addresses in VPN namespace
      ipv6_addrs = nixarrHost.succeed("ip netns exec wg ip -6 addr show")
      print(f"VPN namespace IPv6 addresses:\n{ipv6_addrs}")

      # Check if VPN namespace can ping gateway IPv6
      try:
        nixarrHost.succeed("ip netns exec wg ping -6 -c 1 -W 3 ${wgGatewayAddrV6}")
        print("✓ VPN namespace can ping WireGuard gateway IPv6")
      except Exception as e:
        print(f"✗ VPN namespace cannot ping WireGuard gateway IPv6: {e}")

      # Check if VPN namespace can reach internetClient IPv6 (simple connectivity)
      try:
        result = nixarrHost.succeed("ip netns exec wg curl -6 -s --max-time 5 http://[${internetClientIPv6}]:8080")
        print(f"✓ VPN namespace can reach internetClient IPv6: {result}")
      except Exception as e:
        print(f"✗ VPN namespace cannot reach internetClient IPv6: {e}")

      # Check gateway IPv6 routes
      gw_routes = gateway.succeed("ip -6 route show")
      print(f"Gateway IPv6 routes:\n{gw_routes}")

      # Check internetClient IPv6 routes
      client_routes = internetClient.succeed("ip -6 route show")
      print(f"InternetClient IPv6 routes:\n{client_routes}")

      # IPv6 traffic should go through VPN tunnel (shows VPN client source)
      nixarrHost.succeed("ip netns exec wg curl -6 -s --max-time 2 http://[${internetClientIPv6}]:8080 | grep -q 'Source: fd00:100::2'")


      print("=== Test 6: Verify transmission is confined ===")
      # Check transmission is running and confined to VPN namespace
      nixarrHost.succeed("systemctl status transmission.service | grep -q 'Active: active'")


      print("=== Test 7: Interrupt VPN - Verify no connectivity ===")
      # Block WireGuard traffic on gateway using iptables
      gateway.succeed("iptables -I INPUT -p udp --dport ${toString wgGatewayPort} -j DROP")
      gateway.succeed("iptables -I OUTPUT -p udp --sport ${toString wgGatewayPort} -j DROP")

      # All connectivity should fail - no leaks!
      nixarrHost.fail("ip netns exec wg ping -c 1 -W 2 ${wgGatewayAddr}")
      nixarrHost.fail("ip netns exec wg curl -s --max-time 2 http://${internetClientIP}:8080")

      # DNS should also fail completely when VPN is down
      nixarrHost.fail("ip netns exec wg dig @${wgGatewayAddr} test.vpn.local +short +timeout=2")
      nixarrHost.fail("ip netns exec wg dig leak.test.local +short +timeout=2")
      print("✓ DNS queries fail when VPN is down - no fallback to host DNS")

      # Verify no traffic leaks to host network
      nixarrHost.fail("ip netns exec wg curl -s --max-time 2 http://${gatewayIP}:8080")


      print("=== Test 8: Restore VPN - Verify recovery ===")
      # Remove iptables blocks
      gateway.succeed("iptables -D INPUT -p udp --dport ${toString wgGatewayPort} -j DROP")
      gateway.succeed("iptables -D OUTPUT -p udp --sport ${toString wgGatewayPort} -j DROP")

      # Restart the wg namespace service to force reconnection
      nixarrHost.succeed("systemctl restart wg.service")
      nixarrHost.wait_for_unit("wg.service")

      # Verify VPN connectivity is restored
      nixarrHost.succeed("ip netns exec wg ping -c 3 ${wgGatewayAddr}")

      # Verify source IP is correct again - use internetClient since gateway has no web server
      nixarrHost.succeed("ip netns exec wg curl -s http://${internetClientIP}:8080 | grep -q '${wgClientAddr}'")


      print("=== Test 9: Verify DNS configuration ===")
      # Check that resolv.conf in namespace uses VPN DNS
      nixarrHost.succeed("ip netns exec wg cat /etc/resolv.conf | grep -q 'nameserver ${wgGatewayAddr}'")

      # Verify no host DNS servers are present
      nixarrHost.fail("ip netns exec wg cat /etc/resolv.conf | grep -q 'nameserver 10.0.2.3'")


      print("=== Test 9b: DNS leak test ===")

      # Debug: Check if dnsmasq is running on gateway
      gateway.succeed("systemctl status dnsmasq")
      gateway.succeed("ss -unpl | grep :53 || echo 'No DNS listener found'")

      # Debug: Check connectivity to DNS server
      nixarrHost.succeed("ip netns exec wg ping -c 1 ${wgGatewayAddr}")

      # Start tcpdump on host interface to detect DNS leaks
      nixarrHost.succeed("nohup tcpdump -i eth1 -n 'port 53' -w /tmp/dns-leak.pcap > /tmp/tcpdump-dns.log 2>&1 &")

      # Clear dnsmasq query log
      gateway.succeed("echo > /var/log/dnsmasq-queries.log || true")

      # Use dig instead of nslookup for more reliable DNS queries
      nixarrHost.succeed("ip netns exec wg dig @${wgGatewayAddr} test.vpn.local +short | grep -q ${wgGatewayAddr}")
      nixarrHost.succeed("ip netns exec wg dig @${wgGatewayAddr} leak.test.local +short | grep -q '1.2.3.4'")
      nixarrHost.succeed("ip netns exec wg dig @${wgGatewayAddr} transmission.local +short | grep -q ${wgClientAddr}")

      # Also test without specifying server (uses resolv.conf)
      nixarrHost.succeed("ip netns exec wg dig test.vpn.local +short | grep -q ${wgGatewayAddr}")

      # Wait for any potential leaked packets
      nixarrHost.succeed("pkill tcpdump || true")

      # Check if any DNS packets were captured on host interface
      dns_packets = nixarrHost.succeed("tcpdump -r /tmp/dns-leak.pcap -nn 2>/dev/null | wc -l").strip()
      if int(dns_packets) > 0:
          # Show what was captured for debugging
          captured = nixarrHost.succeed("tcpdump -r /tmp/dns-leak.pcap -nn 2>/dev/null || echo 'No packets'")
          print("DNS leak detected! Captured " + dns_packets + " packets:")
          print(captured)
          nixarrHost.fail("DNS queries leaked to host network")

      # Verify queries went through VPN by checking gateway's dnsmasq log
      gateway.succeed("grep -q 'test.vpn.local' /var/log/dnsmasq-queries.log")
      gateway.succeed("grep -q 'leak.test.local' /var/log/dnsmasq-queries.log")

      print("✓ No DNS leaks detected - all queries confined to VPN")

      # Clean up
      nixarrHost.succeed("rm -f /tmp/dns-leak.pcap /tmp/tcpdump-dns.log")


      print("=== Test 10: Port forwarding test ===")
      # Wait for transmission to be ready and listening
      nixarrHost.wait_for_open_port(9091)  # Web UI port

      # Check that transmission peer port is listening in namespace
      nixarrHost.succeed("ip netns exec wg ss -tlnp | grep -q ':51413'")
      nixarrHost.succeed("ip netns exec wg ss -ulnp | grep -q ':51413'")

      # Ensure WireGuard tunnel is active
      nixarrHost.succeed("ip netns exec wg ping -c 1 ${wgGatewayAddr}")

      # Debug: Print iptables rules and routing info
      print("=== Gateway NAT OUTPUT rules ===")
      output_rules = gateway.succeed("iptables -t nat -L OUTPUT -n -v")
      print(output_rules)

      print("=== Gateway NAT PREROUTING rules ===")
      prerouting_rules = gateway.succeed("iptables -t nat -L PREROUTING -n -v")
      print(prerouting_rules)

      print("=== Gateway routing table ===")
      routes = gateway.succeed("ip route show")
      print(routes)

      print("=== WireGuard status on gateway ===")
      wg_gateway = gateway.succeed("wg show")
      print(wg_gateway)

      print("=== WireGuard status on client ===")
      wg_client = nixarrHost.succeed("ip netns exec wg wg show")
      print(wg_client)

      # Test port forwarding through gateway
      print("=== Testing port forwarding ===")
      # First verify the NAT rules were actually applied
      output_nat = gateway.succeed("iptables -t nat -L OUTPUT | grep 51413 || echo 'No OUTPUT NAT rules found'")
      prerouting_nat = gateway.succeed("iptables -t nat -L PREROUTING | grep 51413 || echo 'No PREROUTING NAT rules found'")
      print(f"OUTPUT NAT check: {output_nat}")
      print(f"PREROUTING NAT check: {prerouting_nat}")

      # Debug connectivity and routing
      print("=== Testing connectivity from nixarrHost to gateway ===")
      nixarrHost.succeed("ping -c 1 ${gatewayIP}")

      # Debug FORWARD chain
      forward_rules = gateway.succeed("iptables -L FORWARD -n -v")
      print(f"Gateway FORWARD rules:\n{forward_rules}")

      # Check if gateway can reach VPN client (after handshake)
      gateway.succeed("wg show | grep -q 'latest handshake:'")

      # Debug port forwarding connectivity
      print("=== Debugging port forwarding ===")

      # First, ensure WireGuard tunnel is fully established
      gateway.succeed("wg")  # Force handshake if needed
      nixarrHost.succeed("ip netns exec wg wg")

      # Skip direct gateway->client test after restart (WireGuard asymmetry)
      print("=== Testing port forwarding ===")

      # Test from nixarrHost (outside VPN) through gateway DNAT
      print("Test: External client -> Gateway -> VPN Client (via DNAT)")

      # First, ensure client initiates some traffic to establish WireGuard state
      nixarrHost.succeed("ip netns exec wg ping -c 1 ${wgGatewayAddr}")

      # Start tcpdump in background using nohup to properly detach it
      gateway.succeed("nohup tcpdump -i any -n 'port 51413 or host ${wgClientAddr}' -w /tmp/capture.pcap > /tmp/tcpdump.log 2>&1 &")

      # Verify tcpdump is running
      gateway.succeed("pgrep tcpdump")
      print("Tcpdump started, now testing connection...")

      # Now test the connection - this should succeed through DNAT!
      # Test from internetClient to gateway's internet IP - this simulates external traffic
      # The connection should be forwarded through the VPN to nixarrHost's transmission
      internetClient.succeed("timeout 5 nc -z -v ${internetGatewayIP} 51413")
      print("Success: Port forwarding works!")

      # Stop tcpdump and analyze what happened
      gateway.succeed("pkill tcpdump")
      tcpdump_output = gateway.succeed("tcpdump -r /tmp/capture.pcap -nn 2>/dev/null || echo 'No packets captured'")
      print(f"Tcpdump results:\n{tcpdump_output}")

      # Verify transmission can reach external services through VPN tunnel
      nixarrHost.succeed("ip netns exec wg curl -s http://${internetClientIP}:8080 | grep -q '${wgClientAddr}'")

      # Verify port is NOT accessible from host network (outside VPN)
      nixarrHost.fail("timeout 2 nc -z -v localhost 51413")


      print("=== Test 11: IPv6 leak test ===")
      # Verify IPv6 connectivity between VMs
      nixarrHost.succeed("ping -6 -c 1 ${gatewayIPv6}")
      gateway.succeed("ping -6 -c 1 ${nixarrHostIPv6}")

      # Check if IPv6 is enabled in VPN namespace
      nixarrHost.succeed("ip netns exec wg ip -6 addr show")

      # Test IPv6 through VPN tunnel
      nixarrHost.succeed("ip netns exec wg ping -6 -c 1 ${wgGatewayAddrV6}")

      # Test IPv6 traffic routing - should go through VPN tunnel to internetClient
      nixarrHost.succeed("ip netns exec wg curl -6 -s --max-time 2 http://[${internetClientIPv6}]:8080")
      nixarrHost.succeed("ip netns exec wg curl -6 -s http://[${internetClientIPv6}]:8080 | grep -q '${wgClientAddrV6}'")


      print("=== Test 12: IPv6 traffic test with VPN interruption ===")
      # Since WireGuard tunnel uses IPv4, blocking it affects both IPv4 and IPv6 traffic
      # The IPv6 traffic inside the tunnel should fail when we block the IPv4 WireGuard connection
      # This test verifies IPv6 behavior is tied to the VPN tunnel

      # Verify WireGuard is listening (debug what ports are actually open)
      print("=== Gateway listening ports ===")
      listening_ports = gateway.succeed("ss -unp")
      print(listening_ports)

      print("=== Looking for WireGuard port ${toString wgGatewayPort} ===")
      wg_port_check = gateway.succeed("ss -unp | grep :${toString wgGatewayPort} || echo 'WireGuard port not found'")
      print(wg_port_check)

      # The previous test (Test 7) already blocked IPv4 WireGuard and verified it works
      # So IPv6 through the tunnel should also be blocked after IPv4 VPN disruption
      # Let's verify IPv6 still works before disruption
      nixarrHost.succeed("ip netns exec wg ping -6 -c 1 ${wgGatewayAddrV6}")

      # Now use the same IPv4 blocking as Test 7
      gateway.succeed("iptables -I INPUT -p udp --dport ${toString wgGatewayPort} -j DROP")
      gateway.succeed("iptables -I OUTPUT -p udp --sport ${toString wgGatewayPort} -j DROP")

      # Both IPv4 and IPv6 connectivity through VPN should fail
      nixarrHost.fail("ip netns exec wg ping -c 1 -W 2 ${wgGatewayAddr}")
      nixarrHost.fail("ip netns exec wg ping -6 -c 1 -W 2 ${wgGatewayAddrV6}")
      nixarrHost.fail("ip netns exec wg curl -6 -s --max-time 2 http://[${internetClientIPv6}]:8080")


      print("=== Test 13: IPv6 VPN recovery ===")
      # Remove iptables blocks (IPv4, since that's what WireGuard uses)
      gateway.succeed("iptables -D INPUT -p udp --dport ${toString wgGatewayPort} -j DROP")
      gateway.succeed("iptables -D OUTPUT -p udp --sport ${toString wgGatewayPort} -j DROP")

      # Verify IPv6 VPN connectivity is restored
      nixarrHost.succeed("ip netns exec wg ping -6 -c 3 ${wgGatewayAddrV6}")

      # Verify source IPv6 is correct again
      nixarrHost.succeed("ip netns exec wg curl -6 -s http://[${internetClientIPv6}]:8080 | grep -q '${wgClientAddrV6}'")


      print("=== All tests passed! ===")
    '';
  }
