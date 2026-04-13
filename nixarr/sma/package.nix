{
  lib,
  python3Packages,
  python3,
  ffmpeg,
  makeWrapper,
  logDir ? "/tmp/sma",
  src,
}:
let
  deps = with python3Packages; [
    requests
    idna
    requests-cache
    babelfish
    tmdbsimple
    mutagen
    guessit
    subliminal
    python-dateutil
    stevedore
    cleanit
    plexapi
    setuptools
  ];

  pythonPath = python3Packages.makePythonPath deps;
in
  python3Packages.buildPythonApplication rec {
    pname = "sickbeard-mp4-automator";
    version = "0-unstable-${src.lastModifiedDate or "unknown"}";
    format = "other";

    inherit src;

    nativeBuildInputs = [makeWrapper];

    dontBuild = true;
    dontCheck = true;

    installPhase = ''
      runHook preInstall

      siteDir=$out/lib/sma
      mkdir -p $siteDir $out/bin

      # Copy all source files
      cp -r $src/autoprocess $siteDir/
      cp -r $src/converter $siteDir/
      cp -r $src/resources $siteDir/
      cp -r $src/config $siteDir/
      cp $src/manual.py $siteDir/
      cp $src/postSonarr.py $siteDir/
      cp $src/postRadarr.py $siteDir/

      # Create __init__.py for the package and subpackages
      touch $siteDir/__init__.py
      for dir in autoprocess converter resources config; do
        touch $siteDir/$dir/__init__.py
      done

      # Rewrite relative imports to absolute (sma.*)
      for f in $(find $siteDir -name "*.py"); do
        substituteInPlace "$f" \
          --replace-quiet "from autoprocess" "from sma.autoprocess" \
          --replace-quiet "from converter" "from sma.converter" \
          --replace-quiet "from resources" "from sma.resources" \
          --replace-quiet "import autoprocess" "import sma.autoprocess" \
          --replace-quiet "import converter" "import sma.converter" \
          --replace-quiet "import resources" "import sma.resources"
      done

      # Patch ffmpeg/ffprobe paths to use nix store paths
      substituteInPlace $siteDir/resources/readsettings.py \
        --replace-quiet "ffmpeg = os.path.join(config_path, config.get(section, 'ffmpeg'))" \
                        "ffmpeg = '${ffmpeg}/bin/ffmpeg'" \
        --replace-quiet "ffprobe = os.path.join(config_path, config.get(section, 'ffprobe'))" \
                        "ffprobe = '${ffmpeg}/bin/ffprobe'"

      # Patch log.py: redirect writable paths to the log dir, seed logging.ini
      cp $src/setup/logging.ini.sample $siteDir/logging.ini.default
      ${python3}/bin/python3 ${./patch-log.py} $siteDir/resources/log.py "${logDir}"

      # Create wrapper scripts with all Python deps on PYTHONPATH
      makeWrapper ${python3}/bin/python3 $out/bin/sma-manual \
        --prefix PYTHONPATH : "$siteDir/..:${pythonPath}" \
        --add-flags "$siteDir/manual.py"

      makeWrapper ${python3}/bin/python3 $out/bin/sma-postsonarr \
        --prefix PYTHONPATH : "$siteDir/..:${pythonPath}" \
        --add-flags "$siteDir/postSonarr.py"

      makeWrapper ${python3}/bin/python3 $out/bin/sma-postradarr \
        --prefix PYTHONPATH : "$siteDir/..:${pythonPath}" \
        --add-flags "$siteDir/postRadarr.py"

      runHook postInstall
    '';

    meta = with lib; {
      description = "Automatically convert video files to a standardized format with metadata tagging";
      homepage = "https://github.com/mdhiggins/sickbeard_mp4_automator";
      license = licenses.mit;
      maintainers = [];
    };
  }
