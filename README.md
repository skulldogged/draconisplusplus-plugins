# Draconis++ Official Plugins

Official extension plugins for Draconis++.

This repository is intentionally separate from the core Draconis++ repository:
the core project owns the plugin ABI, loader, and build harness, while this
repository owns first-party plugin implementations.

## Plugins

- `json_format` - JSON output formatter
- `markdown_format` - Markdown output formatter
- `now_playing` - current media information provider
- `weather` - weather information provider
- `yaml_format` - YAML output formatter

## Build With Core

From the core repository:

```bash
meson setup build -Dplugin_dirs=/path/to/draconisplusplus-plugins
meson compile -C build
```

To compile official plugins statically into the core binary:

```bash
meson setup build -Dplugin_dirs=/path/to/draconisplusplus-plugins -Dstatic_plugins=all
meson compile -C build
```

For one plugin:

```bash
meson setup build -Dplugin_dirs=/path/to/draconisplusplus-plugins -Dstatic_plugins=weather
meson compile -C build
```

Each plugin is a self-contained directory with a `plugin.json` manifest. The
core repository's `tools/plugin_helper.py` remains the source of truth for the
manifest schema and code generation.

## Nix

This flake exposes plugin-root packages. They do not compile plugins by
themselves; they provide the source layout that the core Draconis++ build
expects via `-Dplugin_dirs=`.

Available packages:

- `packages.${system}.all`
- `packages.${system}.json_format`
- `packages.${system}.markdown_format`
- `packages.${system}.now_playing`
- `packages.${system}.weather`
- `packages.${system}.yaml_format`

For precompiled plugin configuration, use `lib.${system}.mkPluginRoot` to
produce a configured plugin root. The generated config lives inside the copied
plugin source tree, e.g. `weather/config.hpp`.

With the core Home Manager module:

```nix
programs.draconisplusplus = {
  enable = true;
  configFormat = "hpp";
  pluginPackages = [
    (inputs.draconisplusplus-plugins.lib.${pkgs.system}.mkPluginRoot {
      weather = {
        provider = "openmeteo";
        units = "imperial";
        coords = {
          lat = 40.7128;
          lon = -74.0060;
        };
      };
    })
  ];
  staticPlugins = ["weather" "json_format"];
  pluginAutoLoad = ["weather"];
};
```

Third-party plugins do not need flakes. Users can still pass a plain plugin
root path to the core module:

```nix
programs.draconisplusplus.pluginDirs = [./my-draconis-plugins];
```
