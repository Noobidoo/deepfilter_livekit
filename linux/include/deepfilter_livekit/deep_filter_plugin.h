#ifndef DEEP_FILTER_PLUGIN_H
#define DEEP_FILTER_PLUGIN_H

#include <flutter_linux/flutter_linux.h>
#include <memory>

namespace deepfilter_livekit {

class DeepFilterPlugin {
 public:
  static void RegisterWithRegistrar(FlPluginRegistrar* registrar);
  DeepFilterPlugin();
  ~DeepFilterPlugin();

 private:
  static void HandleMethodCall(
      FlMethodChannel* channel,
      FlMethodCall* method_call,
      gpointer user_data);

  void* state_ = nullptr;
};

}  // namespace deepfilter_livekit

G_MODULE_EXPORT extern "C" void deep_filter_plugin_register_with_registrar(
    FlPluginRegistrar* registrar);

#endif
