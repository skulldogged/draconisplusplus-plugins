#include <Drac++/Core/Plugin.hpp>
#undef DRAC_PLUGIN
#define DRAC_PLUGIN(...)
#include "../weather/weather.cpp"
int main() {
  weather::WeatherConfig config;
  config.coords      = weather::Coords { 51.5, -0.1 };
  const auto initial = weather::CacheIdentity(config);
  config.units       = weather::UnitSystem::Imperial;
  if (initial == weather::CacheIdentity(config))
    return 1;
  const auto imperial = weather::CacheIdentity(config);
  config.coords->lat  = 42;
  if (imperial == weather::CacheIdentity(config))
    return 2;
  config.units  = weather::UnitSystem::Metric;
  config.coords = weather::Coords { 51.5, -0.1 };
  if (initial != weather::CacheIdentity(config))
    return 3;
  PluginCache          cache(std::filesystem::temp_directory_path() / "weather-key-test");
  weather::WeatherData seed;
  seed.temperature = 21;
  cache.set(initial, seed, 600);
  config.units = weather::UnitSystem::Imperial;
  if (cache.get<weather::WeatherData>(weather::CacheIdentity(config)))
    return 4;
  return cache.get<weather::WeatherData>(initial) ? 0 : 5;
}
