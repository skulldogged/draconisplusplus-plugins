#include <Drac++/Core/Plugin.hpp>
#undef DRAC_PLUGIN
#define DRAC_PLUGIN(...)
#include "../yaml_format/yaml_format.cpp"
int main() {
  using namespace draconis::core::plugin;
  PluginCache cache(std::filesystem::temp_directory_path() / "yaml-test");
  YamlFormatPlugin plugin;
  if (!plugin.initialize({}, cache)) return 1;
  PluginData data{{"fixture", {{"object", PluginFieldObject{{"enabled", true}, {"count", draconis::utils::types::i64(2)}}}, {"array", PluginFieldArray{draconis::utils::types::String("true"), false}}}}};
  auto output = plugin.formatOutput("yaml", {}, data);
  if (!output) return 2;
  auto tree = ryml::parse_in_arena(ryml::to_csubstr(*output));
  const auto root = tree.rootref().is_stream() ? tree.rootref().first_child() : tree.rootref();
  const auto fixture = root["plugins"]["fixture"];
  if (!fixture["object"].is_map() || !fixture["array"].is_seq()) return 3;
  if (fixture["object"]["enabled"].val() != "true" || fixture["object"]["count"].val() != "2") return 4;
  if (!fixture["array"].first_child().is_val_quoted()) return 5;
  return 0;
}
