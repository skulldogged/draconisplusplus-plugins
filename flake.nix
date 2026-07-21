{
  description = "Official Draconis++ plugins";

  inputs = {
    draconisplusplus.url = "github:skulldogged/draconisplusplus-monorepo";
    draconisplusplus.inputs.nixpkgs.follows = "nixpkgs";
    draconisplusplus.inputs.utils.follows = "utils";
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    draconisplusplus,
    nixpkgs,
    utils,
    ...
  }: let
    inherit (nixpkgs) lib;
    pluginNames = [
      "json_format"
      "markdown_format"
      "now_playing"
      "weather"
      "yaml_format"
    ];
  in
    {
      lib = {
        inherit pluginNames;
      };
    }
    // utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
        };

        dbusStatic = pkgs.pkgsStatic.dbus.overrideAttrs (old: let
          filterAuditApparmor = builtins.filter (package: let
            name = package.pname or "";
          in
            name != "audit" && name != "libapparmor");
        in {
          buildInputs = filterAuditApparmor (old.buildInputs or []);
          propagatedBuildInputs = filterAuditApparmor (old.propagatedBuildInputs or []);
          mesonFlags =
            builtins.filter
            (flag: !(lib.hasPrefix "-Dlibaudit" flag) && !(lib.hasPrefix "-Dapparmor" flag))
            (old.mesonFlags or [])
            ++ [
              "-Dlibaudit=disabled"
              "-Dapparmor=disabled"
            ];
          configureFlags =
            builtins.filter
            (flag: !(lib.hasPrefix "--enable-apparmor" flag) && !(lib.hasPrefix "--enable-libaudit" flag))
            (old.configureFlags or [])
            ++ [
              "--disable-apparmor"
              "--disable-libaudit"
            ];
        });

        pluginBuildInputsByName = {
          json_format = [];
          markdown_format = [];
          now_playing = lib.optionals pkgs.stdenv.hostPlatform.isLinux [dbusStatic];
          weather = [pkgs.pkgsStatic.curl];
          yaml_format = [];
        };
        pluginBuildInputs = lib.unique (lib.concatMap (name: pluginBuildInputsByName.${name}) pluginNames);

        escapeCppString = value:
          builtins.replaceStrings
          ["\\" "\""]
          ["\\\\" "\\\""]
          (toString value);

        weatherProviderToEnum = provider:
          if provider == "metno"
          then "MetNo"
          else if provider == "openweathermap"
          then "OpenWeatherMap"
          else "OpenMeteo";

        weatherUnitsToEnum = units:
          if units == "imperial"
          then "Imperial"
          else "Metric";

        weatherLocationCode = weather:
          if weather ? location
          then ''CityName { "${escapeCppString weather.location}" }''
          else let
            coords =
              weather.coords or {
                lat = 0.0;
                lon = 0.0;
              };
          in ''Coordinates { ${toString coords.lat}, ${toString coords.lon} }'';

        weatherConfigHeader = weather: ''
          #pragma once

          #include "WeatherConfig.hpp"

          namespace draconis::config {
            inline constexpr auto WEATHER_CONFIG = weather::config::MakeConfig(
              weather::config::Provider::${weatherProviderToEnum (weather.provider or "openmeteo")},
              weather::config::Units::${weatherUnitsToEnum (weather.units or "metric")},
              weather::config::${weatherLocationCode weather}${lib.optionalString ((weather ? apiKey) || (weather ? api_key)) ",\n              \"${escapeCppString (weather.apiKey or weather.api_key)}\""}
            );

            static_assert(
              weather::config::Validate(WEATHER_CONFIG),
              "Invalid weather config: OpenMeteo/MetNo require coordinates; OpenWeatherMap requires API key and supports city names"
            );
          } // namespace draconis::config
        '';

        mkPluginRoot = {
          names ? pluginNames,
          plugins ? null,
          weather ? null,
        }: let
          normalizePlugin = value:
            if builtins.isBool value
            then {
              enable = value;
              settings = null;
            }
            else {
              enable = value.enable or true;
              settings = value.settings or null;
            };
          requestedPlugins =
            if plugins == null
            then
              builtins.listToAttrs (map (name: {
                  inherit name;
                  value = {
                    enable = true;
                    settings = null;
                  };
                })
                names)
            else lib.mapAttrs (_: normalizePlugin) plugins;
          selectedPlugins = lib.filterAttrs (_: value: value.enable) requestedPlugins;
          selectedNames = builtins.attrNames selectedPlugins;
          unknownNames = builtins.filter (name: !(builtins.elem name pluginNames)) (builtins.attrNames requestedPlugins);
          weatherSettings =
            if weather != null
            then weather
            else selectedPlugins.weather.settings or null;
          selectedBuildInputs = lib.unique (lib.concatMap (name: pluginBuildInputsByName.${name} or []) selectedNames);
        in
          assert lib.assertMsg (unknownNames == []) "Unknown official Draconis++ plugins: ${lib.concatStringsSep ", " unknownNames}";
            pkgs.stdenvNoCC.mkDerivation {
              pname = "draconisplusplus-plugins";
              version = "0.1.0";
              src = self;

              dontConfigure = true;
              dontBuild = true;
              passthru = {
                pluginNames = selectedNames;
                pluginBuildInputs = selectedBuildInputs;
                inherit pluginBuildInputsByName;
              };

              installPhase =
                ''
                  runHook preInstall
                  mkdir -p "$out"
                ''
                + builtins.concatStringsSep "\n" (map (name: ''
                    cp -R "${name}" "$out/${name}"
                  '')
                  selectedNames)
                + lib.optionalString (weatherSettings != null && builtins.elem "weather" selectedNames) ''
                  cp ${pkgs.writeText "weather-config.hpp" (weatherConfigHeader weatherSettings)} "$out/weather/config.hpp"
                ''
                + ''
                  runHook postInstall
                '';
            };

        allPlugins = mkPluginRoot {};
        integrationCheck = name:
          draconisplusplus.lib.${system}.withPlugins {
            package = draconisplusplus.packages.${system}.generic;
            pluginPackages = [self.packages.${system}.${name}];
            staticPlugins = ["all"];
          };
        integrationChecks = builtins.listToAttrs (map (name: {
            name = "integration-${name}";
            value = integrationCheck name;
          })
          pluginNames);
      in {
        lib = {
          inherit mkPluginRoot pluginBuildInputs pluginBuildInputsByName;
        };

        packages =
          {
            all = allPlugins;
            default = allPlugins;
          }
          // builtins.listToAttrs (map (name: {
              inherit name;
              value = mkPluginRoot {names = [name];};
            })
            pluginNames);

        checks =
          self.packages.${system}
          // integrationChecks
          // {
            integration-all = draconisplusplus.lib.${system}.withPlugins {
              package = draconisplusplus.packages.${system}.generic;
              pluginPackages = [allPlugins];
              staticPlugins = ["all"];
            };
          };
      }
    );
}
