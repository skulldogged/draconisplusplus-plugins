# ================================ #
#   Draconis++ Plugin Build System #
# ================================ #

# Plugin build configuration
plugin_cpp_args = []
plugin_base_deps = [draconis_dep, glaze_dep]

# Compiler-specific plugin arguments
if cpp.get_id() in ['msvc', 'clang-cl']
  plugin_cpp_args += [
    '/DDRAC_PLUGIN_BUILD=1',
    '/DNDEBUG',
    '/O2',
  ]
else
  plugin_cpp_args += [
    '-DDRAC_PLUGIN_BUILD=1',
    '-DNDEBUG',
    '-fvisibility=default', # Plugins need visible symbols
    '-O3',
  ]
endif

# Platform-specific plugin settings
if host_system == 'windows'
  plugin_suffix = '.dll'
  if cpp.get_id() in ['msvc', 'clang-cl']
    plugin_cpp_args += '/DDRAC_PLUGIN_WINDOWS=1'
  else
    plugin_cpp_args += '-DDRAC_PLUGIN_WINDOWS=1'
  endif
elif host_system == 'darwin'
  plugin_suffix = '.dylib'
  plugin_cpp_args += '-DDRAC_PLUGIN_MACOS=1'
else
  plugin_suffix = '.so'
  plugin_cpp_args += '-DDRAC_PLUGIN_UNIX=1'
endif

# Plugin installation directory
plugin_install_dir = get_option('libdir') / 'draconis++' / 'plugins'

# Track built plugins for summary
plugins_built = []

# ========================== #
#   Plugin Definitions       #
# ========================== #

# JSON Format Plugin
if get_option('json_format')
  subdir('json_format')
  shared_library(
    plugin_name,
    plugin_sources,
    name_prefix: '',
    name_suffix: plugin_suffix.substring(1),
    dependencies: plugin_base_deps + plugin_deps,
    cpp_args: plugin_cpp_args,
    install: true,
    install_dir: plugin_install_dir,
  )
  plugins_built += plugin_name
endif

# Markdown Format Plugin
if get_option('markdown_format')
  subdir('markdown_format')
  shared_library(
    plugin_name,
    plugin_sources,
    name_prefix: '',
    name_suffix: plugin_suffix.substring(1),
    dependencies: plugin_base_deps + plugin_deps,
    cpp_args: plugin_cpp_args,
    install: true,
    install_dir: plugin_install_dir,
  )
  plugins_built += plugin_name
endif

# Now Playing Plugin
if get_option('now_playing')
  subdir('now_playing')
  shared_library(
    plugin_name,
    plugin_sources,
    name_prefix: '',
    name_suffix: plugin_suffix.substring(1),
    dependencies: plugin_base_deps + plugin_deps,
    cpp_args: plugin_cpp_args,
    install: true,
    install_dir: plugin_install_dir,
  )
  plugins_built += plugin_name
endif

# Weather Plugin
if get_option('weather')
  subdir('weather')
  shared_library(
    plugin_name,
    plugin_sources,
    name_prefix: '',
    name_suffix: plugin_suffix.substring(1),
    dependencies: plugin_base_deps + plugin_deps,
    cpp_args: plugin_cpp_args,
    install: true,
    install_dir: plugin_install_dir,
  )
  plugins_built += plugin_name
endif

# YAML Format Plugin
if get_option('yaml_format')
  subdir('yaml_format')
  shared_library(
    plugin_name,
    plugin_sources,
    name_prefix: '',
    name_suffix: plugin_suffix.substring(1),
    dependencies: plugin_base_deps + plugin_deps,
    cpp_args: plugin_cpp_args,
    install: true,
    install_dir: plugin_install_dir,
  )
  plugins_built += plugin_name
endif

