{
  bash,
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs,
}:
buildNpmPackage rec {
  pname = "anchorr";
  version = "1.4.0";

  src = fetchFromGitHub {
    owner = "nairdahh";
    repo = "Anchorr";
    rev = "v${version}";
    hash = "sha256-8xlablHtBtJuOgm/7hl4XWmyWYD+fE7L9igRECErDX4=";
  };

  npmDepsHash = "sha256-YXPLHloxRci8PIDB5g+myxP36JFhQ2M54hQC86+1mMY=";

  dontNpmBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p "$out/lib/anchorr"
    cp -r . "$out/lib/anchorr/"

    mkdir -p "$out/bin"
    cat > "$out/bin/anchorr" <<EOF
    #!${lib.getExe bash}
    exec ${lib.getExe nodejs} "$out/lib/anchorr/app.js" "\$@"
    EOF
    chmod +x "$out/bin/anchorr"

    runHook postInstall
  '';

  meta = with lib; {
    description = "Discord bot for media requests via Jellyseerr and notifications for Jellyfin";
    homepage = "https://github.com/nairdahh/Anchorr";
    license = licenses.gpl3Only;
    maintainers = [];
    platforms = platforms.linux;
    mainProgram = "anchorr";
  };
}
