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
