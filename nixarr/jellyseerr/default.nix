{lib, ...}: {
  imports = [
    (lib.mkRenamedOptionModule ["nixarr" "jellyseerr" "enable"] ["nixarr" "seerr" "enable"])
    (lib.mkRenamedOptionModule ["nixarr" "jellyseerr" "package"] ["nixarr" "seerr" "package"])
    (lib.mkRenamedOptionModule ["nixarr" "jellyseerr" "stateDir"] ["nixarr" "seerr" "stateDir"])
    (lib.mkRenamedOptionModule ["nixarr" "jellyseerr" "port"] ["nixarr" "seerr" "port"])
    (lib.mkRenamedOptionModule ["nixarr" "jellyseerr" "openFirewall"] ["nixarr" "seerr" "openFirewall"])
    (lib.mkRenamedOptionModule ["nixarr" "jellyseerr" "vpn" "enable"] ["nixarr" "seerr" "vpn" "enable"])
    (lib.mkRenamedOptionModule ["nixarr" "jellyseerr" "vpn" "configureNginx"] ["nixarr" "seerr" "vpn" "configureNginx"])
    (lib.mkRenamedOptionModule ["nixarr" "jellyseerr" "expose" "https" "enable"] ["nixarr" "seerr" "expose" "https" "enable"])
    (lib.mkRenamedOptionModule ["nixarr" "jellyseerr" "expose" "https" "upnp" "enable"] ["nixarr" "seerr" "expose" "https" "upnp" "enable"])
    (lib.mkRenamedOptionModule ["nixarr" "jellyseerr" "expose" "https" "domainName"] ["nixarr" "seerr" "expose" "https" "domainName"])
    (lib.mkRenamedOptionModule ["nixarr" "jellyseerr" "expose" "https" "acmeMail"] ["nixarr" "seerr" "expose" "https" "acmeMail"])
  ];
}
