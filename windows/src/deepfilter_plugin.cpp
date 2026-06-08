#include "deepfilter_livekit/deep_filter_plugin.h"

#include <flutter/encodable_value.h>
#include <flutter/standard_method_codec.h>

#include <sstream>
#include <string>
#include <vector>

using flutter::EncodableMap;
using flutter::EncodableValue;

extern "C" {
  typedef struct DeepFilter DeepFilter;
  DeepFilter* df_init(const char* model_path, int sample_rate);
  int df_process_frame(DeepFilter* df, const float* input, float* output, int num_samples);
  int df_get_frame_size(DeepFilter* df);
  int df_get_sample_rate(DeepFilter* df);
  void df_destroy(DeepFilter* df);
}

namespace deepfilter_livekit {

DeepFilterPlugin::DeepFilterPlugin() {}

DeepFilterPlugin::~DeepFilterPlugin() {
  if (state_) {
    df_destroy(static_cast<DeepFilter*>(state_));
    state_ = nullptr;
  }
}

void DeepFilterPlugin::RegisterWithRegistrar(
    flutter::PluginRegistrarWindows* registrar) {
  auto channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      registrar->messenger(), "io.deepfilter.livekit",
      &flutter::StandardMethodCodec::GetInstance());

  auto plugin = std::make_unique<DeepFilterPlugin>();
  channel->SetMethodCallHandler(
      [plugin_pointer = plugin.get()](const auto& call, auto result) {
        plugin_pointer->HandleMethodCall(call, std::move(result));
      });

  registrar->AddPlugin(std::move(plugin));
}

void DeepFilterPlugin::HandleMethodCall(
    const flutter::MethodCall<flutter::EncodableValue>& method_call,
    std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
  const auto& method = method_call.method_name();

  if (method == "isAvailable") {
    result->Success(EncodableValue(true));
  } else if (method == "init") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (!args) {
      result->Error("INVALID_ARGS", "Expected map");
      return;
    }

    std::string model_path;
    auto it = args->find(EncodableValue("modelPath"));
    if (it != args->end() && std::holds_alternative<std::string>(it->second)) {
      model_path = std::get<std::string>(it->second);
    }

    int sample_rate = 48000;
    it = args->find(EncodableValue("sampleRate"));
    if (it != args->end() && std::holds_alternative<int>(it->second)) {
      sample_rate = std::get<int>(it->second);
    }

    if (state_) {
      df_destroy(static_cast<DeepFilter*>(state_));
      state_ = nullptr;
    }

    state_ = df_init(model_path.empty() ? nullptr : model_path.c_str(), sample_rate);
    if (!state_) {
      result->Error("INIT_FAILED", "df_init returned null");
    } else {
      result->Success(EncodableValue("ok"));
    }
  } else if (method == "processFrame") {
    const auto* args = std::get_if<EncodableMap>(method_call.arguments());
    if (!args || !state_) {
      result->Error("INVALID_STATE", "Not initialized or invalid args");
      return;
    }

    auto input_it = args->find(EncodableValue("input"));
    if (input_it == args->end()) {
      result->Error("INVALID_ARGS", "input required");
      return;
    }

    const auto& input_val = input_it->second;

    if (!std::holds_alternative<std::vector<uint8_t>>(input_val)) {
      result->Error("INVALID_ARGS", "input must be byte array");
      return;
    }

    const auto& input_bytes = std::get<std::vector<uint8_t>>(input_val);
    std::vector<uint8_t> output_bytes(input_bytes.size());

    int num_samples = static_cast<int>(input_bytes.size() / sizeof(float));
    const float* input_float = reinterpret_cast<const float*>(input_bytes.data());
    float* output_float = reinterpret_cast<float*>(output_bytes.data());

    int ret = df_process_frame(
        static_cast<DeepFilter*>(state_),
        input_float, output_float, num_samples);

    EncodableMap result_map;
    result_map[EncodableValue("output")] = EncodableValue(output_bytes);
    result_map[EncodableValue("ret")] = EncodableValue(ret);
    result->Success(EncodableValue(result_map));
  } else if (method == "dispose") {
    if (state_) {
      df_destroy(static_cast<DeepFilter*>(state_));
      state_ = nullptr;
    }
    result->Success();
  } else {
    result->NotImplemented();
  }
}

}  // namespace deepfilter_livekit

void DeepFilterPluginRegisterWithRegistrar(
    FlutterDesktopPluginRegistrarRef registrar) {
  deepfilter_livekit::DeepFilterPlugin::RegisterWithRegistrar(
      flutter::PluginRegistrarManager::GetInstance()
          ->GetRegistrar<flutter::PluginRegistrarWindows>(registrar));
}
