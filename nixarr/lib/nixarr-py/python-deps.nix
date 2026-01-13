{
  fetchPypi,
  fetchFromGitHub,
  fetchurl,
  jellyfin,
  jq,
  lib,
  openapi-generator-cli,
  python3Packages,
  runCommand,
  writeTextFile,
}: let
  inherit
    (python3Packages)
    buildPythonPackage
    pydantic
    python-dateutil
    setuptools
    typing-extensions
    urllib3
    requests
    ;

  lazy-imports = buildPythonPackage rec {
    pname = "lazy-imports";
    version = "1.1.0"; # nixpkgs 25.05 only has 0.3.1
    pyproject = true;

    src = fetchPypi {
      inherit version;
      pname = "lazy_imports";
      hash = "sha256-5upaHk8JqGE1fmcLeqYe/Lzm/ik2F4XdJT32b43bw2s=";
    };

    build-system = [setuptools];
  };

  openapi-deps = [
    pydantic
    python-dateutil
    typing-extensions
    urllib3
  ];

  arr-deps = openapi-deps ++ [lazy-imports];

  lidarr-py = buildPythonPackage rec {
    pname = "lidarr";
    version = "1.2.1";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-TycyDD/O1jdljjT8hkFtYb2OHFWWHtm2C/AHJX2YbXQ=";
    };

    build-system = [setuptools];
    dependencies = arr-deps;
  };

  prowlarr-py = buildPythonPackage rec {
    pname = "prowlarr";
    version = "1.1.1";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-PiK4ZrORMV907wX9dPeO2tE97NSu6sCPfH7aUFkyRZk=";
    };

    build-system = [setuptools];
    dependencies = arr-deps;
  };

  radarr-py = buildPythonPackage rec {
    pname = "radarr";
    version = "1.2.1";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-suN16BYf/6gm8G/xA5S6wdYerTUq8Dy2yflWYIKLLBQ=";
    };

    build-system = [setuptools];
    dependencies = arr-deps;
  };

  readarr-py = buildPythonPackage rec {
    pname = "readarr";
    version = "1.2.0";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-vPjZShyIOcpF9/sFuviRtmTJGxJMhQ+bwHO4UYneMOs=";
    };

    build-system = [setuptools];
    dependencies = arr-deps;
  };

  sonarr-py = buildPythonPackage rec {
    pname = "sonarr";
    version = "1.1.1";
    pyproject = true;

    # Only one not on PyPI (!?)
    src = fetchFromGitHub {
      owner = "devopsarr";
      repo = "sonarr-py";
      rev = "v${version}";
      hash = "sha256-cqhdsos328jtUYw2HWaoQ95EPTnu3RYPWiyT5FqfTXk=";
    };

    build-system = [setuptools];
    dependencies = arr-deps;
  };

  whisparr-py = buildPythonPackage rec {
    pname = "whisparr";
    version = "1.1.1";
    pyproject = true;

    src = fetchPypi {
      inherit pname version;
      hash = "sha256-1jtLKpt7Ec806iiR8dMm+xsMMLozA7CyDw06CmsbMgo=";
    };

    build-system = [setuptools];
    dependencies = arr-deps;
  };

  jellyfin-py = let
    version = "0.1.0";

    openapi-spec = fetchurl {
      url = "https://repo.jellyfin.org/files/openapi/stable/jellyfin-openapi-${jellyfin.version}.json";
      hash =
        ({
          "10.10.0" = "sha256-c9KQv0TJFpGkmzWaUjhzsX9wO6gCNgkcVlJ30Lb936A=";
          "10.10.1" = "sha256-ppJ53lim1xJQ+BIwoG6V6pfX9S1qupXY+HWrxWyQ0pU=";
          "10.10.2" = "sha256-tN//WSYcfFKJod/KTrq7dO/RrGv3EGZdIo2CWe4Mprg=";
          "10.10.3" = "sha256-Sm8se2/W0IXDcafdab2/dJwpX76SeeMTSI8iy+ZC48Q=";
          "10.10.4" = "sha256-M0IzA70pkaLKyrC4xfeS+1oGw1X9/pmVkLiJfl98vLc=";
          "10.10.5" = "sha256-+0aDcR/f8za9IQicEcowEtekcIFVbpYZvx8xuJ5u37o=";
          "10.10.6" = "sha256-ExDLl5RrM9/ZSVLNVD2QYXO5r2qKuzYeR4QcNEVtfRU=";
          "10.10.7" = "sha256-rJFWlgSdXFRmREscAMGQb30CpU+Q5qe6EX+nvJkzJmQ=";
          "10.11.0" = "sha256-xzI5NrC9F+M8WEXMD0QWkhKWmfpJzUDnnEq/sMHfHcs=";
          "10.11.1" = "sha256-PV3MQwCBIhnRGaXDqV5S4rPBb/JrHLTPIx3i57b7Ssc=";
          "10.11.2" = "sha256-t7+8fT+o3djy+RmNxeFrevj99h/VqS4NsHJZpdFs/5s=";
          "10.11.3" = "sha256-KBMlCE55z2QZyXF5rpQWpR7Lklol0Z149uZu3e6GumU=";
          "10.11.4" = "sha256-xTwN7KR68Gb6+XGE6C3lT1Gg6Mq8MF7T73PfwgV/mYo=";
          "10.11.5" = "sha256-SgsOEDRGMU2uEO9+i2jouxJCqnejqDx9zSMep6rwXOQ=";
        })."${jellyfin.version}";
    };
    openapi-config = writeTextFile {
      name = "jellyfin-openapi-config.yaml";
      text = ''
        packageName: jellyfin
        packageVersion: ${version}
        projectName: jellyfin-py

        # The below is for consistency with the devopsarr libraries
        httpUserAgent: jellyfin-py/${version}
        enumClassPrefix: true
        disallowAdditionalPropertiesIfNotPresent: false
        structPrefix: false
      '';
    };
    src =
      runCommand "jellyfin-api-src" {
        nativeBuildInputs = [jq openapi-generator-cli];
      } ''
        # Fix up the plugin config POST endpoint (it's missing a requestBody)
        <'${openapi-spec}' >openapi-spec.json jq '
          .paths."/Plugins/{pluginId}/Configuration".post.requestBody = {
            "description": "Plugin configuration.",
            "required": true,
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/BasePluginConfiguration"
                }
              }
            }
          }
        '

        # Generate the client
        openapi-generator-cli generate \
          --generator-name python \
          --input-spec openapi-spec.json \
          --config ${openapi-config} \
          --output $out
      '';
  in
    buildPythonPackage {
      pname = "jellyfin";
      pyproject = true;

      inherit src version;

      build-system = [setuptools];
      dependencies = arr-deps;
    };
in [
  jellyfin-py
  lidarr-py
  prowlarr-py
  radarr-py
  readarr-py
  sonarr-py
  whisparr-py
]
