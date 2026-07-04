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
  }:
    {
      lib = {
        pluginNames = [
          "json_format"
          "markdown_format"
          "now_playing"
          "weather"
          "yaml_format"
        ];
      };
    }
    // utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
        };

        pluginNames = self.lib.pluginNames;

        mkPluginRoot = names:
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
            + ''
              runHook postInstall
            '';
          };

        allPlugins = mkPluginRoot pluginNames;
      in {
        packages =
          {
            all = allPlugins;
            default = allPlugins;
          }
          // builtins.listToAttrs (map (name: {
            inherit name;
            value = mkPluginRoot [name];
          }) pluginNames);

        checks = self.packages.${system};
      }
    );
}
