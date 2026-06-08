#ifndef DEEP_FILTER_PLUGIN_H
#define DEEP_FILTER_PLUGIN_H

#include <flutter/method_channel.h>
#include <flutter/plugin_registrar_windows.h>
#include <memory>

namespace deepfilter_livekit {

class DeepFilterPlugin : public flutter::Plugin {
 public:
  static void RegisterWithRegistrar(flutter::PluginRegistrarWindows* registrar);
  DeepFilterPlugin();
  virtual ~DeepFilterPlugin();

 private:
  void HandleMethodCall(
      const flutter::MethodCall<flutter::EncodableValue>& method_call,
      std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result);

  void* state_ = nullptr;
};

}  // namespace deepfilter_livekit

#endif
