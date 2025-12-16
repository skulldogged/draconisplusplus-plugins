# ================================ #
#   Draconis++ Plugins Project     #
# ================================ #

project('draconis-plugins', 'cpp',
  version: '0.1.0',
  meson_version: '>=1.1.0',
  default_options: [
    'default_library=shared',
    'buildtype=release',
    'b_vscrt=mt',
  ]
)

cpp = meson.get_compiler('cpp')
host_system = host_machine.system()
fs = import('fs')

# ========================== #
#   Compiler Configuration   #
# ========================== #
cpp_args = []

if cpp.get_id() in ['msvc', 'clang-cl']
  cpp_args += '/std:c++latest'
  cpp_args += cpp.get_supported_arguments(
    '/Zc:__cplusplus',
    '/Zc:preprocessor',
    '/external:W0',
    '/external:anglebrackets',
    '/DNOMINMAX',
    '/DWIN32_LEAN_AND_MEAN',
    '/DDRAC_ENABLE_CACHING=1',
    '/DDRAC_ENABLE_PLUGINS=1',
  )
else
  cpp_args += '-std=c++26'
  cpp_args += '-DDRAC_ENABLE_CACHING=1'
  cpp_args += '-DDRAC_ENABLE_PLUGINS=1'
endif

add_project_arguments(cpp_args, language: 'cpp')

# ================ #
#   Dependencies   #
# ================ #

# Import draconis as subproject
drac_proj = subproject('draconis', default_options: [
  'plugins=disabled',
  'build_examples=false',
  'build_tests=false',
  'build_cli=false'
])

draconis_dep = drac_proj.get_variable('draconis_dep')
glaze_dep = drac_proj.get_variable('glaze_dep')

# ================ #
#   Build Plugins  #
# ================ #
subdir('plugins')

# ================ #
#   Summary        #
# ================ #
summary(
  {
    'JSON Format': get_option('json_format'),
    'Markdown Format': get_option('markdown_format'),
    'Now Playing': get_option('now_playing'),
    'Weather': get_option('weather'),
    'YAML Format': get_option('yaml_format'),
  },
  section: 'Plugins',
  bool_yn: true,
)

summary(
  {
    'C++ Compiler': cpp.get_id(),
    'Host system': host_system,
    'Build type': get_option('buildtype'),
  },
  section: 'System',
)
