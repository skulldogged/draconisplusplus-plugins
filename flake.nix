{
  description = "Official Draconis++ plugins";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
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

        escapeCppString =
          value:
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
            coords = weather.coords or {
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
          weather ? null,
        }:
          pkgs.stdenvNoCC.mkDerivation {
            pname = "draconisplusplus-plugins";
            version = "0.1.0";
            src = self;

            dontConfigure = true;
            dontBuild = true;

            installPhase = ''
              runHook preInstall
              mkdir -p "$out"
            ''
            + builtins.concatStringsSep "\n" (map (name: ''
              cp -R "${name}" "$out/${name}"
            '') names)
            + lib.optionalString (weather != null) ''
              cp ${pkgs.writeText "weather-config.hpp" (weatherConfigHeader weather)} "$out/weather/config.hpp"
            ''
            + ''
              runHook postInstall
            '';
          };

        allPlugins = mkPluginRoot {};
      in {
        lib = {
          inherit mkPluginRoot;
        };

        packages =
          {
            all = allPlugins;
            default = allPlugins;
          }
          // builtins.listToAttrs (map (name: {
            inherit name;
            value = mkPluginRoot {names = [name];};
          }) pluginNames);

        checks = self.packages.${system};
      }
    );
}
