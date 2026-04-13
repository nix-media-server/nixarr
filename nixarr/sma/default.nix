{
  config,
  lib,
  pkgs,
  sickbeard-mp4-automator-src,
  ...
}:
with lib; let
  cfg = config.nixarr.sma;
  nixarr = config.nixarr;
  globals = config.util-nixarr.globals;

  smaLogDir = "${smaStateDir}/logs";

  smaPackage = pkgs.callPackage ./package.nix {
    ffmpeg =
      if cfg.hardware-acceleration == "nvenc"
      then pkgs.ffmpeg-full
      else pkgs.ffmpeg;
    logDir = smaLogDir;
    src = sickbeard-mp4-automator-src;
  };

  smaStateDir = "${nixarr.stateDir}/sma";
  smaConfigPath = "${smaStateDir}/autoProcess.ini";

  # Wrapper scripts that set the config path via SMA_CONFIG env var
  sonarrScript = pkgs.writeShellScript "sma-postsonarr" ''
    export SMA_CONFIG="${smaConfigPath}"
    exec ${smaPackage}/bin/sma-postsonarr
  '';

  radarrScript = pkgs.writeShellScript "sma-postradarr" ''
    export SMA_CONFIG="${smaConfigPath}"
    exec ${smaPackage}/bin/sma-postradarr
  '';

  # Config template with __SONARR_API_KEY__ and __RADARR_API_KEY__ placeholders
  # These get substituted at runtime by sma-setup.service
  autoProcessIniTemplate = pkgs.writeText "autoProcess.ini.template" ''
    [Converter]
    ffmpeg = ffmpeg
    ffprobe = ffprobe
    threads = ${toString cfg.threads}
    hwaccels = ${cfg.hardware-acceleration}
    hwaccel-decoders = ${concatStringsSep ", " cfg.hwaccel-decoders}
    hwoutputfmt = nv12
    output-directory = ${cfg.output-directory}
    output-format = ${cfg.output-format}
    output-extension = ${cfg.output-extension}
    temp-extension =
    minimum-size = ${toString cfg.minimum-size}
    ignored-extensions = nfo, ds_store
    copy-to =
    move-to =
    delete-original = ${boolToString cfg.delete-original}
    sort-streams = true
    process-same-extensions = ${boolToString cfg.process-same-extensions}
    force-convert = false
    post-process = false
    preopts =
    postopts =
    preset =

    [Permissions]
    chmod = 0664
    uid = -1
    gid = -1

    [Metadata]
    download-artwork = poster
    relocate-moov = true
    tag = ${boolToString cfg.tag-metadata}
    tag-language = en

    [Video]
    codec = ${concatStringsSep ", " cfg.video-codecs}
    max-bitrate = ${toString cfg.video-max-bitrate}
    crf = ${toString cfg.video-crf}
    crf-profiles =
    max-width = ${toString cfg.video-max-width}
    profile =
    max-level =
    pix-fmt =

    [HDR]
    codec =
    pix-fmt =
    space = bt2020nc
    transfer = smpte2084
    primaries = bt2020
    preset =
    filter =
    force-filter = false
    profile =

    [Audio]
    codec = ${concatStringsSep ", " cfg.audio-codecs}
    languages = ${concatStringsSep ", " cfg.audio-languages}
    default-language = ${cfg.audio-default-language}
    first-stream-of-language = false
    allow-language-relax = true
    channel-bitrate = 128
    max-bitrate = 0
    max-channels = 0
    prefer-more-channels = true
    default-more-channels = true
    copy-original = ${boolToString cfg.audio-copy-original}
    aac-adtstoasc = false
    ignore-truehd = mp4
    ignored-dispositions =
    unique-dispositions = false

    [Audio.Sorting]
    sorting =

    [Universal Audio]
    codec = aac
    channel-bitrate = 128
    first-stream-only = false
    move-after = false
    filter =

    [Audio.ChannelFilters]

    [Subtitle]
    codec = ${concatStringsSep ", " cfg.subtitle-codecs}
    codec-image-based =
    languages = ${concatStringsSep ", " cfg.subtitle-languages}
    default-language = ${cfg.subtitle-default-language}
    first-stream-of-language = false
    encoding =
    burn-subtitles = false
    download-subtitles = ${boolToString cfg.download-subtitles}
    embed-subs = true
    embed-image-subs = false
    embed-only-internal-subs = false
    attachment-codec =
    remove-bitstream-subs = false
    ignored-dispositions =
    unique-dispositions = false

    [Subtitle.Sorting]
    sorting =

    [Subtitle.CleanIt]
    config =

    [Subtitle.FFSubsync]
    enabled = false

    [Subtitle.Subliminal]
    ${optionalString cfg.download-subtitles "providers = opensubtitles, podnapisi"}

    [Sonarr]
    host = localhost
    port = ${toString nixarr.sonarr.port}
    apikey = __SONARR_API_KEY__
    ssl = false
    webroot =
    force-rename = false
    force-rescan = true
    in-progress-check = true

    [Radarr]
    host = localhost
    port = ${toString nixarr.radarr.port}
    apikey = __RADARR_API_KEY__
    ssl = false
    webroot =
    force-rename = false
    force-rescan = true
    in-progress-check = true

    [Plex]
    enabled = false
  '';

  # Script to register SMA as a Connect notification in an *arr service
  mkRegisterScript = {
    service,
    scriptPath,
  }: let
    curl = getExe pkgs.curl;
    jq = getExe pkgs.jq;
    port = toString nixarr.${service}.port;
    apiKeyFile = "${nixarr.stateDir}/secrets/${service}.api-key";
  in
    pkgs.writeShellScript "sma-register-${service}" ''
      set -euo pipefail
      API_KEY=$(cat '${apiKeyFile}')
      BASE_URL="http://127.0.0.1:${port}/api/v3"

      # Check if SMA connect already exists
      EXISTING=$(${curl} -s -f \
        -H "X-Api-Key: $API_KEY" \
        "$BASE_URL/notification" | ${jq} -r '[.[] | select(.name == "SMA") | .id] | first // empty')

      PAYLOAD=$(${jq} -n '{
        name: "SMA",
        implementation: "CustomScript",
        configContract: "CustomScriptSettings",
        onDownload: true,
        onUpgrade: true,
        supportsOnDownload: true,
        supportsOnUpgrade: true,
        fields: [
          {name: "path", value: $script_path},
          {name: "arguments", value: ""}
        ]
      }' --arg script_path "${scriptPath}")

      if [ -n "$EXISTING" ]; then
        echo "Updating existing SMA connect (id=$EXISTING) in ${service}"
        ${curl} -s -f -X PUT \
          -H "X-Api-Key: $API_KEY" \
          -H "Content-Type: application/json" \
          -d "$(echo "$PAYLOAD" | ${jq} --argjson id "$EXISTING" '. + {id: $id}')" \
          "$BASE_URL/notification/$EXISTING" > /dev/null
      else
        echo "Creating SMA connect in ${service}"
        ${curl} -s -f -X POST \
          -H "X-Api-Key: $API_KEY" \
          -H "Content-Type: application/json" \
          -d "$PAYLOAD" \
          "$BASE_URL/notification" > /dev/null
      fi
      echo "SMA connect configured in ${service}"
    '';

  # Services that must be ready before SMA setup can run
  requiredApiServices =
    (optional cfg.sonarr.enable "sonarr-api.service")
    ++ (optional cfg.radarr.enable "radarr-api.service");
in {
  options.nixarr.sma = {
    enable = mkOption {
      type = types.bool;
      default = false;
      example = true;
      description = ''
        Whether or not to enable the Sickbeard MP4 Automator (SMA) integration.
        SMA automatically converts video files downloaded by Sonarr/Radarr to a
        standardized format using FFmpeg.

        When enabled, SMA is registered as a Custom Script connect notification
        in Sonarr and/or Radarr, which triggers automatic conversion on
        download and upgrade events.
      '';
    };

    hardware-acceleration = mkOption {
      type = types.enum ["" "nvenc" "vaapi" "qsv"];
      default = "";
      example = "nvenc";
      description = ''
        Hardware acceleration method to use for encoding.
        Set to "" for software encoding.
      '';
    };

    hwaccel-decoders = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["h264_cuvid" "hevc_cuvid"];
      description = "Hardware-accelerated decoders to use.";
    };

    threads = mkOption {
      type = types.int;
      default = 0;
      description = "Number of FFmpeg threads. 0 = auto.";
    };

    output-directory = mkOption {
      type = types.str;
      default = "";
      description = "Output directory for converted files. Empty = convert in-place.";
    };

    output-format = mkOption {
      type = types.enum ["mp4" "mkv" "mov"];
      default = "mkv";
      description = "Output container format.";
    };

    output-extension = mkOption {
      type = types.str;
      default = "mkv";
      description = "Output file extension.";
    };

    minimum-size = mkOption {
      type = types.int;
      default = 0;
      description = "Minimum file size in bytes to process. 0 = no minimum.";
    };

    delete-original = mkOption {
      type = types.bool;
      default = true;
      description = "Delete the original file after conversion.";
    };

    process-same-extensions = mkOption {
      type = types.bool;
      default = false;
      description = "Process files even if they already have the target extension.";
    };

    tag-metadata = mkOption {
      type = types.bool;
      default = false;
      description = "Tag files with metadata from TMDB.";
    };

    video-codecs = mkOption {
      type = types.listOf types.str;
      default = ["h264" "hevc"];
      example = ["hevc" "av1"];
      description = ''
        Accepted video codecs. Files with other codecs will be re-encoded
        to the first codec in the list.
      '';
    };

    video-max-bitrate = mkOption {
      type = types.int;
      default = 0;
      description = "Maximum video bitrate in Kbps. 0 = no limit.";
    };

    video-crf = mkOption {
      type = types.int;
      default = 23;
      description = "Constant Rate Factor for video encoding. Lower = better quality, bigger files.";
    };

    video-max-width = mkOption {
      type = types.int;
      default = 0;
      description = "Maximum video width. 0 = no limit. Set to 1920 to cap at 1080p.";
    };

    audio-codecs = mkOption {
      type = types.listOf types.str;
      default = ["aac" "ac3" "eac3"];
      description = "Accepted audio codecs.";
    };

    audio-languages = mkOption {
      type = types.listOf types.str;
      default = ["eng"];
      description = "Audio languages to keep.";
    };

    audio-default-language = mkOption {
      type = types.str;
      default = "eng";
      description = "Default audio language.";
    };

    audio-copy-original = mkOption {
      type = types.bool;
      default = true;
      description = "Keep a copy of the original audio stream alongside the converted one.";
    };

    subtitle-codecs = mkOption {
      type = types.listOf types.str;
      default = ["srt" "ass" "subrip" "mov_text"];
      description = "Accepted subtitle codecs.";
    };

    subtitle-languages = mkOption {
      type = types.listOf types.str;
      default = ["eng"];
      description = "Subtitle languages to keep.";
    };

    subtitle-default-language = mkOption {
      type = types.str;
      default = "eng";
      description = "Default subtitle language.";
    };

    download-subtitles = mkOption {
      type = types.bool;
      default = false;
      description = "Download subtitles using subliminal.";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Path to a custom autoProcess.ini file. If set, this overrides
        all other SMA configuration options. You are responsible for
        including the correct API keys in the file.
      '';
    };

    sonarr.enable = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = "Enable SMA post-import processing for Sonarr.";
    };

    radarr.enable = mkOption {
      type = types.bool;
      default = true;
      example = false;
      description = "Enable SMA post-import processing for Radarr.";
    };
  };

  config = mkIf (nixarr.enable && cfg.enable) {
    assertions = [
      {
        assertion = cfg.sonarr.enable -> nixarr.sonarr.enable;
        message = "nixarr.sma.sonarr.enable requires nixarr.sonarr.enable to be true.";
      }
      {
        assertion = cfg.radarr.enable -> nixarr.radarr.enable;
        message = "nixarr.sma.radarr.enable requires nixarr.radarr.enable to be true.";
      }
      {
        assertion = cfg.sonarr.enable || cfg.radarr.enable;
        message = "nixarr.sma requires at least one of sonarr or radarr to be enabled.";
      }
    ];

    systemd.tmpfiles.rules = [
      "d '${smaStateDir}' 0775 root ${globals.libraryOwner.group} - -"
      "d '${smaLogDir}' 0775 root ${globals.libraryOwner.group} - -"
      "C '${smaLogDir}/logging.ini' 0664 root ${globals.libraryOwner.group} - ${smaPackage}/lib/sma/logging.ini.default"
    ];

    # CLI tool for manual conversions
    environment.systemPackages = let
      smaWithConfig = pkgs.writeShellScriptBin "sma" ''
        exec ${smaPackage}/bin/sma-manual -c "${smaConfigPath}" "$@"
      '';
    in [smaWithConfig];

    # Setup service: generates autoProcess.ini with real API keys
    systemd.services.sma-setup = mkIf (cfg.configFile == null) {
      description = "Generate SMA autoProcess.ini with API keys";
      after = requiredApiServices;
      requires = requiredApiServices;
      wantedBy =
        (optional cfg.sonarr.enable "sonarr.service")
        ++ (optional cfg.radarr.enable "radarr.service");
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0022";
        ExecStart = let
          sed = getExe pkgs.gnused;
          sonarrKeyFile = "${nixarr.stateDir}/secrets/sonarr.api-key";
          radarrKeyFile = "${nixarr.stateDir}/secrets/radarr.api-key";
        in
          pkgs.writeShellScript "sma-setup" ''
            set -euo pipefail
            cp '${autoProcessIniTemplate}' '${smaConfigPath}'
            chmod 644 '${smaConfigPath}'

            ${optionalString cfg.sonarr.enable ''
              SONARR_KEY=$(cat '${sonarrKeyFile}')
              ${sed} -i "s/__SONARR_API_KEY__/$SONARR_KEY/" '${smaConfigPath}'
            ''}
            ${optionalString cfg.radarr.enable ''
              RADARR_KEY=$(cat '${radarrKeyFile}')
              ${sed} -i "s/__RADARR_API_KEY__/$RADARR_KEY/" '${smaConfigPath}'
            ''}
            echo "SMA config generated at ${smaConfigPath}"
          '';
      };
    };

    # If custom config file is provided, just symlink it
    systemd.services.sma-setup-custom = mkIf (cfg.configFile != null) {
      description = "Symlink custom SMA config";
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = pkgs.writeShellScript "sma-setup-custom" ''
          ln -sf '${cfg.configFile}' '${smaConfigPath}'
        '';
      };
    };

    # Register SMA as a Connect notification in Sonarr
    systemd.services.sma-register-sonarr = mkIf cfg.sonarr.enable {
      description = "Register SMA as a Connect notification in Sonarr";
      after = ["sonarr-api.service" "sma-setup.service"];
      requires = ["sonarr-api.service"];
      wants = ["sma-setup.service"];
      wantedBy = ["sonarr.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = mkRegisterScript {
          service = "sonarr";
          scriptPath = toString sonarrScript;
        };
      };
    };

    # Register SMA as a Connect notification in Radarr
    systemd.services.sma-register-radarr = mkIf cfg.radarr.enable {
      description = "Register SMA as a Connect notification in Radarr";
      after = ["radarr-api.service" "sma-setup.service"];
      requires = ["radarr-api.service"];
      wants = ["sma-setup.service"];
      wantedBy = ["radarr.service"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = mkRegisterScript {
          service = "radarr";
          scriptPath = toString radarrScript;
        };
      };
    };
  };
}
