#include "deepfilter_livekit/deep_filter_plugin.h"

#include <string>
#include <vector>

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

void DeepFilterPlugin::RegisterWithRegistrar(FlPluginRegistrar* registrar) {
  auto* messenger = fl_plugin_registrar_get_messenger(registrar);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  auto* channel = fl_method_channel_new(
      messenger,
      "io.deepfilter.livekit",
      FL_METHOD_CODEC(codec));
  auto plugin = std::make_unique<DeepFilterPlugin>();
  fl_method_channel_set_method_call_handler(
      channel,
      HandleMethodCall,
      plugin.release(),
      [](gpointer data) {
        delete static_cast<DeepFilterPlugin*>(data);
      });
}

void DeepFilterPlugin::HandleMethodCall(
    FlMethodChannel* channel,
    FlMethodCall* method_call,
    gpointer user_data) {
  auto* plugin = static_cast<DeepFilterPlugin*>(user_data);
  auto* method = fl_method_call_get_name(method_call);

  if (strcmp(method, "isAvailable") == 0) {
    g_autoptr(GError) error = nullptr;
    fl_method_call_respond_success(
        method_call, fl_value_new_bool(true), &error);
  } else if (strcmp(method, "init") == 0) {
    auto* args = fl_method_call_get_args(method_call);
    const char* model_path = "";
    int64_t sample_rate = 48000;

    if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      auto* model_val = fl_value_lookup_string(args, "modelPath");
      if (model_val && fl_value_get_type(model_val) == FL_VALUE_TYPE_STRING) {
        model_path = fl_value_get_string(model_val);
      }
      auto* rate_val = fl_value_lookup_string(args, "sampleRate");
      if (rate_val && fl_value_get_type(rate_val) == FL_VALUE_TYPE_INT) {
        sample_rate = fl_value_get_int(rate_val);
      }
    }

    if (plugin->state_) {
      df_destroy(static_cast<DeepFilter*>(plugin->state_));
      plugin->state_ = nullptr;
    }

    plugin->state_ = df_init(model_path, static_cast<int>(sample_rate));
    g_autoptr(GError) error = nullptr;
    if (plugin->state_) {
      fl_method_call_respond_success(
          method_call, fl_value_new_string("ok"), &error);
    } else {
      fl_method_call_respond_error(
          method_call, "INIT_FAILED", "df_init returned null", nullptr, &error);
    }
  } else if (strcmp(method, "processFrame") == 0) {
    if (!plugin->state_) {
      g_autoptr(GError) error = nullptr;
      fl_method_call_respond_error(
          method_call, "NOT_INIT", "Not initialized", nullptr, &error);
      return;
    }

    auto* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      g_autoptr(GError) error = nullptr;
      fl_method_call_respond_error(
          method_call, "INVALID_ARGS", "Expected map", nullptr, &error);
      return;
    }

    auto* input_val = fl_value_lookup_string(args, "input");
    if (!input_val || fl_value_get_type(input_val) != FL_VALUE_TYPE_UINT8_LIST) {
      g_autoptr(GError) error = nullptr;
      fl_method_call_respond_error(
          method_call, "INVALID_ARGS", "input required as Uint8List", nullptr, &error);
      return;
    }

    size_t input_size = fl_value_get_length(input_val);
    const uint8_t* input_data = fl_value_get_uint8_list(input_val);
    int num_samples = static_cast<int>(input_size / sizeof(float));

    std::vector<uint8_t> output_data(input_size);
    int ret = df_process_frame(
        static_cast<DeepFilter*>(plugin->state_),
        reinterpret_cast<const float*>(input_data),
        reinterpret_cast<float*>(output_data.data()),
        num_samples);

    g_autoptr(FlValue) result_map = fl_value_new_map();
    fl_value_set_string_take(result_map, "output",
        fl_value_new_uint8_list(output_data.data(), output_data.size()));
    fl_value_set_string_take(result_map, "ret",
        fl_value_new_int(ret));
    g_autoptr(GError) error = nullptr;
    fl_method_call_respond_success(method_call, result_map, &error);
  } else if (strcmp(method, "dispose") == 0) {
    if (plugin->state_) {
      df_destroy(static_cast<DeepFilter*>(plugin->state_));
      plugin->state_ = nullptr;
    }
    g_autoptr(GError) error = nullptr;
    fl_method_call_respond_success(method_call, nullptr, &error);
  } else {
    g_autoptr(GError) error = nullptr;
    fl_method_call_respond_not_implemented(method_call, &error);
  }
}

}  // namespace deepfilter_livekit

G_MODULE_EXPORT extern "C" void deep_filter_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  deepfilter_livekit::DeepFilterPlugin::RegisterWithRegistrar(registrar);
}
