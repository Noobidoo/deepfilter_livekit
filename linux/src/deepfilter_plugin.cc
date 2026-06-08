#include "deepfilter_livekit/deepfilter_plugin.h"

#include <flutter_linux/flutter_linux.h>
#include <cstring>
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
  auto plugin = std::make_unique<DeepFilterPlugin>();
  auto* plugin_ptr = plugin.release();

  fl_plugin_registrar_set_method_call_handler(
      registrar,
      "io.deepfilter.livekit",
      HandleMethodCall,
      plugin_ptr,
      [](gpointer data) {
        delete static_cast<DeepFilterPlugin*>(data);
      });
}

void DeepFilterPlugin::HandleMethodCall(
    FlPluginRegistrar* registrar,
    FlMethodCall* method_call,
    gpointer user_data) {
  auto* plugin = static_cast<DeepFilterPlugin*>(user_data);
  auto method = fl_method_call_get_name(method_call);

  if (strcmp(method, "isAvailable") == 0) {
    auto response = FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_bool(true)));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (strcmp(method, "init") == 0) {
    auto* args = fl_method_call_get_args(method_call);
    const char* model_path = nullptr;
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
    auto* response = plugin->state_
        ? FL_METHOD_RESPONSE(fl_method_success_response_new(fl_value_new_string("ok")))
        : FL_METHOD_RESPONSE(fl_method_error_response_new(
            "INIT_FAILED", "df_init returned null", nullptr));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (strcmp(method, "processFrame") == 0) {
    if (!plugin->state_) {
      auto* response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "NOT_INIT", "Not initialized", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    auto* args = fl_method_call_get_args(method_call);
    if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP) {
      auto* response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGS", "Expected map", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    auto* input_val = fl_value_lookup_string(args, "input");
    if (!input_val) {
      auto* response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_ARGS", "input required", nullptr));
      fl_method_call_respond(method_call, response, nullptr);
      return;
    }

    size_t input_size;
    const uint8_t* input_data = fl_value_get_binary(input_val, &input_size);

    int num_samples = input_size / sizeof(float);
    std::vector<uint8_t> output_data(input_size);
    int ret = df_process_frame(
        static_cast<DeepFilter*>(plugin->state_),
        reinterpret_cast<const float*>(input_data),
        reinterpret_cast<float*>(output_data.data()),
        num_samples);

    auto* result_map = fl_value_new_map();
    fl_value_set_string_take(result_map, "output",
        fl_value_new_binary(output_data.data(), output_data.size()));
    fl_value_set_string_take(result_map, "ret",
        fl_value_new_int(ret));
    auto* response = FL_METHOD_RESPONSE(fl_method_success_response_new(result_map));
    fl_method_call_respond(method_call, response, nullptr);
  } else if (strcmp(method, "dispose") == 0) {
    if (plugin->state_) {
      df_destroy(static_cast<DeepFilter*>(plugin->state_));
      plugin->state_ = nullptr;
    }
    auto* response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    fl_method_call_respond(method_call, response, nullptr);
  } else {
    auto* response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    fl_method_call_respond(method_call, response, nullptr);
  }
}

}  // namespace deepfilter_livekit

extern "C" void fl_deepfilter_livekit_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  deepfilter_livekit::DeepFilterPlugin::RegisterWithRegistrar(registrar);
}
