/**
 * @file yaml_format.cpp
 * @brief YAML output format plugin for Draconis++
 * @author Draconis++ Team
 * @version 1.0.0
 *
 * @details This plugin provides YAML output formatting for system information
 * using the RapidYAML library (single-header amalgamation) for proper YAML generation.
 * It supports a single output mode:
 * - "yaml": Human-readable YAML output
 *
 * This file supports both dynamic (shared library) and static compilation.
 * When compiled as a static plugin (DRAC_STATIC_PLUGIN_BUILD defined),
 * it exports factory functions in a namespace instead of extern "C".
 */

#define RYML_SINGLE_HDR_DEFINE_NOW

#if defined(__MINGW32__) && defined(__clang__) && !defined(C4_MINGW)
  #define C4_MINGW
#endif

#include <Drac++/Core/Plugin.hpp>

#include <Drac++/Utils/Error.hpp>
#include <Drac++/Utils/Types.hpp>

#include "ryml_all.hpp"

namespace {
  using namespace draconis::utils::types;

  // RapidYAML overloads operator[] for map-key lookup, not unchecked indexing.
  // NOLINTBEGIN(cppcoreguidelines-pro-bounds-avoid-unchecked-container-access)
  class YamlFormatPlugin : public draconis::core::plugin::IOutputFormatPlugin {
   private:
    draconis::core::plugin::PluginMetadata m_metadata;
    bool                                   m_ready = false;

    static constexpr auto FORMAT_YAML = "yaml";

    /**
     * @brief Helper to get value from data map, returning pointer to the string if found
     * @note Returns pointer to the map's string which remains valid during formatOutput
     */
    static auto getValue(const Map<String, String>& data, const String& key) -> const String* {
      if (auto iter = data.find(key); iter != data.end() && !iter->second.empty())
        return &iter->second;
      return nullptr;
    }

    /**
     * @brief Add a key-value pair to a YAML node if value exists
     * @note The value pointer must remain valid for the lifetime of the tree
     */
    static auto addIfPresent(ryml::NodeRef node, const char* key, const String* value) -> void {
      if (value)
        node[ryml::to_csubstr(key)] = ryml::to_csubstr(*value);
    }

    static auto writeField(ryml::Tree& tree, ryml::NodeRef node, const draconis::core::plugin::PluginFieldValue& value) -> void {
      using namespace draconis::core::plugin;
      std::visit([&](const auto& inner) {
        using T = std::decay_t<decltype(inner)>;
        if constexpr (std::same_as<T, PluginFieldObject>) {
          node |= ryml::MAP;
          for (const auto& [key, child] : inner) {
            auto entry = node[tree.copy_to_arena(ryml::to_csubstr(key))];
            entry |= ryml::KEY_DQUO;
            writeField(tree, entry, child);
          }
        } else if constexpr (std::same_as<T, PluginFieldArray>) {
          node |= ryml::SEQ;
          for (const auto& child : inner)
            writeField(tree, node.append_child(), child);
        } else if constexpr (std::same_as<T, bool>) {
          node = inner ? ryml::csubstr("true") : ryml::csubstr("false");
        } else if constexpr (std::same_as<T, String>) {
          node = tree.copy_to_arena(ryml::to_csubstr(inner));
          node |= ryml::VAL_DQUO;
        } else {
          node << inner;
        }
      },
                 static_cast<const PluginFieldValueBase&>(value));
    }

   public:
    YamlFormatPlugin() {
      m_metadata = {
        .name         = "YAML Format",
        .version      = "1.0.0",
        .author       = "Draconis++ Team",
        .description  = "Provides YAML output formatting for system information using RapidYAML",
        .type         = draconis::core::plugin::PluginType::OutputFormat,
        .dependencies = {}
      };
    }

    [[nodiscard]] auto getMetadata() const -> const draconis::core::plugin::PluginMetadata& override {
      return m_metadata;
    }

    auto initialize(const draconis::core::plugin::PluginContext& /*ctx*/, ::PluginCache& /*cache*/) -> Result<Unit> override {
      m_ready = true;
      return {};
    }

    auto shutdown() -> Unit override {
      m_ready = false;
    }

    [[nodiscard]] auto isReady() const -> bool override {
      return m_ready;
    }

    [[nodiscard]] auto formatOutput(
      const String& /*formatName*/,
      const Map<String, String>&                data,
      const draconis::core::plugin::PluginData& pluginData
    ) const -> Result<String> override {
      if (!m_ready)
        return Err(draconis::utils::error::DracError { draconis::utils::error::DracErrorCode::Other, "YamlFormatPlugin is not ready." });

      ryml::Tree    tree;
      ryml::NodeRef root = tree.rootref();
      root |= ryml::MAP;

      // General section
      if (getValue(data, "date")) {
        ryml::NodeRef general = root["general"];
        general |= ryml::MAP;
        addIfPresent(general, "date", getValue(data, "date"));
      }

      // Weather section
      if (getValue(data, "weather_temperature")) {
        ryml::NodeRef weather = root["weather"];
        weather |= ryml::MAP;
        addIfPresent(weather, "temperature", getValue(data, "weather_temperature"));
        addIfPresent(weather, "town", getValue(data, "weather_town"));
        addIfPresent(weather, "description", getValue(data, "weather_description"));
      }

      // System section
      if (getValue(data, "host") || getValue(data, "os") || getValue(data, "kernel")) {
        ryml::NodeRef system = root["system"];
        system |= ryml::MAP;
        addIfPresent(system, "host", getValue(data, "host"));
        addIfPresent(system, "operating_system", getValue(data, "os"));
        addIfPresent(system, "os_name", getValue(data, "os_name"));
        addIfPresent(system, "os_version", getValue(data, "os_version"));
        addIfPresent(system, "os_id", getValue(data, "os_id"));
        addIfPresent(system, "kernel", getValue(data, "kernel"));
      }

      // Hardware section
      if (getValue(data, "ram") || getValue(data, "disk") || getValue(data, "cpu") || getValue(data, "gpu") || getValue(data, "uptime")) {
        ryml::NodeRef hardware = root["hardware"];
        hardware |= ryml::MAP;

        // Memory subsection
        if (getValue(data, "ram")) {
          ryml::NodeRef memory = hardware["memory"];
          memory |= ryml::MAP;
          addIfPresent(memory, "info", getValue(data, "ram"));
          addIfPresent(memory, "used_bytes", getValue(data, "memory_used_bytes"));
          addIfPresent(memory, "total_bytes", getValue(data, "memory_total_bytes"));
        }

        // Disk subsection
        if (getValue(data, "disk")) {
          ryml::NodeRef disk = hardware["disk"];
          disk |= ryml::MAP;
          addIfPresent(disk, "info", getValue(data, "disk"));
          addIfPresent(disk, "used_bytes", getValue(data, "disk_used_bytes"));
          addIfPresent(disk, "total_bytes", getValue(data, "disk_total_bytes"));
        }

        // CPU subsection
        if (getValue(data, "cpu")) {
          ryml::NodeRef cpu = hardware["cpu"];
          cpu |= ryml::MAP;
          addIfPresent(cpu, "model", getValue(data, "cpu"));
          addIfPresent(cpu, "cores_physical", getValue(data, "cpu_cores_physical"));
          addIfPresent(cpu, "cores_logical", getValue(data, "cpu_cores_logical"));
        }

        // GPU
        addIfPresent(hardware, "gpu", getValue(data, "gpu"));

        // Uptime subsection
        if (getValue(data, "uptime")) {
          ryml::NodeRef uptime = hardware["uptime"];
          uptime |= ryml::MAP;
          addIfPresent(uptime, "formatted", getValue(data, "uptime"));
          addIfPresent(uptime, "seconds", getValue(data, "uptime_seconds"));
        }
      }

      // Software section
      if (getValue(data, "shell") || getValue(data, "packages")) {
        ryml::NodeRef software = root["software"];
        software |= ryml::MAP;
        addIfPresent(software, "shell", getValue(data, "shell"));
        addIfPresent(software, "package_count", getValue(data, "packages"));
      }

      // Environment section
      if (getValue(data, "de") || getValue(data, "wm")) {
        ryml::NodeRef environment = root["environment"];
        environment |= ryml::MAP;
        addIfPresent(environment, "desktop_environment", getValue(data, "de"));
        addIfPresent(environment, "window_manager", getValue(data, "wm"));
      }

      // Plugin data section - use pluginData directly
      if (!pluginData.empty()) {
        ryml::NodeRef pluginsNode = root["plugins"];
        pluginsNode |= ryml::MAP;

        for (const auto& [pluginId, fields] : pluginData) {
          // Copy plugin ID to arena so it outlives the loop
          const ryml::csubstr arenaPluginId = tree.copy_to_arena(ryml::to_csubstr(pluginId));
          pluginsNode[arenaPluginId] |= ryml::MAP;

          for (const auto& [fieldName, value] : fields) {
            const ryml::csubstr arenaFieldName = tree.copy_to_arena(ryml::to_csubstr(fieldName));
            auto                field          = pluginsNode[arenaPluginId][arenaFieldName];
            field |= ryml::KEY_DQUO;
            writeField(tree, field, value);
          }
        }
      }

      // Emit YAML with document start marker
      String yaml = "---\n";
      yaml += ryml::emitrs_yaml<String>(tree);

      return yaml;
    }

    [[nodiscard]] auto getFormatNames() const -> Span<const String> override {
      static const Array<String, 1> FORMAT_NAMES = { FORMAT_YAML };
      return FORMAT_NAMES;
    }

    [[nodiscard]] auto getFileExtension(const String& /*formatName*/) const -> String override {
      return "yaml";
    }
  };
  // NOLINTEND(cppcoreguidelines-pro-bounds-avoid-unchecked-container-access)
} // anonymous namespace

DRAC_PLUGIN(YamlFormatPlugin)
