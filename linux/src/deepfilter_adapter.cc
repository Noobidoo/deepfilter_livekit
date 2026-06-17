#include <dlfcn.h>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <new>
#include <atomic>
#include <thread>
#include <chrono>
#include <vector>
#include <mutex>
#include <sys/stat.h>

#ifdef DF_APM_HOOK_AVAILABLE
#include "rtc_audio_processing.h"
#include "flutter_webrtc_base.h"
#include "flutter_webrtc/flutter_web_r_t_c_plugin.h"
#endif

typedef void* (*DfCreate)(const char*, float, const char*);
typedef size_t (*DfFrameLen)(void*);
typedef float (*DfProcess)(void*, const float*, float*);
typedef void (*DfFree)(void*);
typedef void (*DfSetAttenLim)(void*, float);

static struct {
  void* lib;
  DfCreate create;
  DfFrameLen frame_len;
  DfProcess process;
  DfFree free;
  DfSetAttenLim set_atten_lim;
} g_capi = {};

// Base directory where the plugin SO lives (for default model path).
static char g_base_dir[4096] = {};

static bool load_capi() {
  if (g_capi.lib) return true;

  // Record the base directory of this shared library so we can find models.
  Dl_info info;
  if (dladdr((void*)&load_capi, &info) && info.dli_fname) {
    const char* fname = info.dli_fname;
    const char* last_slash = strrchr(fname, '/');
    if (last_slash) {
      size_t dir_len = last_slash - fname;
      strncpy(g_base_dir, fname, dir_len);
      g_base_dir[dir_len] = '\0';
    }
  }

  if (g_base_dir[0] != '\0') {
    char lib_path[4096];
    snprintf(lib_path, sizeof(lib_path), "%s/libdeep_filter_lib.so", g_base_dir);
    g_capi.lib = dlopen(lib_path, RTLD_NOW | RTLD_LOCAL);
  }
  if (!g_capi.lib) {
    g_capi.lib = dlopen("libdeep_filter_lib.so", RTLD_NOW | RTLD_LOCAL);
  }
  if (!g_capi.lib) {
    fprintf(stderr, "deepfilter_adapter: libdeep_filter_lib.so not found (%s)\n",
            dlerror());
    return false;
  }
  g_capi.create = (DfCreate)dlsym(g_capi.lib, "df_create");
  g_capi.frame_len = (DfFrameLen)dlsym(g_capi.lib, "df_get_frame_length");
  g_capi.process = (DfProcess)dlsym(g_capi.lib, "df_process_frame");
  g_capi.free = (DfFree)dlsym(g_capi.lib, "df_free");
  g_capi.set_atten_lim = (DfSetAttenLim)dlsym(g_capi.lib, "df_set_atten_lim");
  if (!g_capi.create || !g_capi.frame_len || !g_capi.process || !g_capi.free) {
    fprintf(stderr, "deepfilter_adapter: capi symbols not found\n");
    dlclose(g_capi.lib);
    g_capi.lib = nullptr;
    return false;
  }
  fprintf(stderr, "deepfilter_adapter: capi loaded successfully\n");
  return true;
}

// Resolve model path: use provided one, or default to <plugin_dir>/models.
// Returns heap-allocated string the caller must delete[].
static char* resolve_model_path(const char* model_path) {
  if (model_path && model_path[0] != '\0') {
    char* copy = new char[strlen(model_path) + 1];
    strcpy(copy, model_path);
    return copy;
  }

  if (g_base_dir[0] == '\0') return nullptr;

  size_t base_len = strlen(g_base_dir);
  char* default_path = new char[base_len + 32];
  strcpy(default_path, g_base_dir);
  strcat(default_path, "/models/DeepFilterNet3_onnx.tar.gz");

  struct stat st;
  if (stat(default_path, &st) != 0 || !S_ISREG(st.st_mode)) {
    fprintf(stderr, "deepfilter_adapter: default model file not found, using stub\n");
    delete[] default_path;
    return nullptr;
  }

  fprintf(stderr, "deepfilter_adapter: using default model file\n");
  return default_path;
}

struct DeepFilterStub {
  int sample_rate;
  int frame_size;
};

static std::atomic<bool> g_capi_init_attempted{false};
static std::atomic<bool> g_capi_init_done{false};
static void* g_capi_state = nullptr;

// ---------------------------------------------------------------------------
// APM capture post-processing hook
// ---------------------------------------------------------------------------
#ifdef DF_APM_HOOK_AVAILABLE

static std::atomic<bool> g_apm_enabled{true};

// Plain C helper for safe process call (no local C++ objects).
static void df_process_safe(const float* in, float* out) {
  g_capi.process(g_capi_state, in, out);
}

// Accumulates partial input frames until we have a full DeepFilter frame,
// then processes in-place and drains back into the APM buffer.
class DeepFilterAPMEffect
    : public libwebrtc::RTCAudioProcessing::CustomProcessing {
 public:
  DeepFilterAPMEffect() {}

  void Initialize(int sample_rate_hz, int num_channels) override {
    fprintf(stderr,
            "df_apm: Initialize rate=%d ch=%d\n",
            sample_rate_hz, num_channels);
    std::lock_guard<std::mutex> lk(mutex_);
    sample_rate_ = sample_rate_hz;
    num_channels_ = num_channels;
    accumulator_.clear();
    drain_.clear();
    df_frame_size_ = 0;
    if (g_capi_state && g_capi.lib) {
      df_frame_size_ = static_cast<int>(g_capi.frame_len(g_capi_state));
    }
    if (df_frame_size_ <= 0) df_frame_size_ = 480;
    fprintf(stderr, "df_apm: df_frame_size=%d\n", df_frame_size_);
  }

  // Called by WebRTC APM on the audio capture thread for every APM band frame.
  void Process(int num_bands, int num_frames, int buffer_size,
               float* buffer) override {
    if (!g_apm_enabled.load(std::memory_order_relaxed)) return;
    if (!g_capi_state || !g_capi.lib) return;

    std::lock_guard<std::mutex> lk(mutex_);
    if (df_frame_size_ <= 0) return;

    float* band0 = buffer;
    int band_samples = num_frames * num_channels_;

    accumulator_.insert(accumulator_.end(), band0, band0 + band_samples);

    while (static_cast<int>(accumulator_.size()) >= df_frame_size_) {
      if (num_channels_ == 1) {
        scratch_in_.assign(accumulator_.begin(),
                           accumulator_.begin() + df_frame_size_);
        scratch_out_ = scratch_in_;
        scratch_out_.resize(df_frame_size_);
        df_process_safe(scratch_in_.data(), scratch_out_.data());
        drain_.insert(drain_.end(), scratch_out_.begin(), scratch_out_.end());
      } else {
        int ch = num_channels_;
        int frames = df_frame_size_ / ch;
        if (df_frame_size_ % ch == 0) {
          scratch_in_.resize(frames);
          scratch_out_.resize(frames);
          std::vector<float> block(accumulator_.begin(),
                                   accumulator_.begin() + df_frame_size_);
          for (int i = 0; i < frames; ++i) scratch_in_[i] = block[i * ch];
          scratch_out_ = scratch_in_;
          df_process_safe(scratch_in_.data(), scratch_out_.data());
          for (int i = 0; i < frames; ++i) {
            for (int c = 0; c < ch; ++c)
              block[i * ch + c] = scratch_out_[i];
          }
          drain_.insert(drain_.end(), block.begin(), block.end());
        } else {
          drain_.insert(drain_.end(), accumulator_.begin(),
                        accumulator_.begin() + df_frame_size_);
        }
      }
      accumulator_.erase(accumulator_.begin(),
                         accumulator_.begin() + df_frame_size_);
    }

    int to_drain = (std::min)(band_samples, static_cast<int>(drain_.size()));
    if (to_drain > 0) {
      std::copy(drain_.begin(), drain_.begin() + to_drain, band0);
      drain_.erase(drain_.begin(), drain_.begin() + to_drain);
    }
  }

  void Reset(int new_rate) override {
    fprintf(stderr, "df_apm: Reset new_rate=%d\n", new_rate);
    std::lock_guard<std::mutex> lk(mutex_);
    sample_rate_ = new_rate;
    accumulator_.clear();
    drain_.clear();
  }

  void Release() override {
    fprintf(stderr, "df_apm: Release\n");
    delete this;
  }

 private:
  std::mutex mutex_;
  int sample_rate_ = 48000;
  int num_channels_ = 1;
  int df_frame_size_ = 480;
  std::vector<float> accumulator_;
  std::vector<float> drain_;
  std::vector<float> scratch_in_;
  std::vector<float> scratch_out_;
};

static DeepFilterAPMEffect* g_apm_effect = nullptr;
static std::atomic<bool> g_apm_attached{false};

static void attach_apm_hook() {
  if (g_apm_attached.exchange(true)) return;
  fprintf(stderr, "df_apm: attaching hook\n");

  void* fwrtc = dlopen("libflutter_webrtc_plugin.so", RTLD_NOLOAD | RTLD_LAZY);
  if (!fwrtc) {
    fprintf(stderr, "df_apm: libflutter_webrtc_plugin.so not found (%s)\n",
            dlerror());
    g_apm_attached.store(false);
    return;
  }

  using SharedInstanceFn = flutter_webrtc_plugin::FlutterWebRTCBase*(*)();
  auto fn = reinterpret_cast<SharedInstanceFn>(
      dlsym(fwrtc, "flutter_webrtc_plugin_get_shared_instance"));
  if (!fn) {
    fprintf(stderr,
            "df_apm: flutter_webrtc_plugin_get_shared_instance not found\n");
    g_apm_attached.store(false);
    return;
  }

  flutter_webrtc_plugin::FlutterWebRTCBase* instance = fn();
  if (!instance) {
    fprintf(stderr, "df_apm: shared instance is null\n");
    g_apm_attached.store(false);
    return;
  }

  auto apm = instance->audio_processing();
  if (!apm) {
    fprintf(stderr, "df_apm: audio_processing() returned null\n");
    g_apm_attached.store(false);
    return;
  }

  g_apm_effect = new DeepFilterAPMEffect();
  apm->SetCapturePostProcessing(g_apm_effect);
  fprintf(stderr, "df_apm: hook attached successfully\n");
}

#endif // DF_APM_HOOK_AVAILABLE

extern "C" {

__attribute__((visibility("default"))) void* df_init(const char* model_path, int sample_rate) {
  if (!load_capi()) {
    auto* df = new (std::nothrow) DeepFilterStub{};
    if (!df) return nullptr;
    df->sample_rate = sample_rate;
    df->frame_size = (sample_rate * 10) / 1000;
    return df;
  }

  char* resolved = resolve_model_path(model_path);
  if (!resolved) {
    fprintf(stderr, "deepfilter_adapter: no model path, using stub\n");
    auto* df = new (std::nothrow) DeepFilterStub{};
    if (!df) return nullptr;
    df->sample_rate = sample_rate;
    df->frame_size = (sample_rate * 10) / 1000;
    return df;
  }

  if (!g_capi_init_attempted.exchange(true)) {
    std::thread t([resolved, sample_rate]() {
      g_capi_state = g_capi.create(resolved, 100.0f, nullptr);
      g_capi_init_done.store(true);
      delete[] resolved;
    });
    t.detach();
  } else {
    delete[] resolved;
  }

  auto start = std::chrono::steady_clock::now();
  while (!g_capi_init_done.load()) {
    auto elapsed = std::chrono::steady_clock::now() - start;
    if (elapsed > std::chrono::seconds(5)) {
      fprintf(stderr,
          "deepfilter_adapter: df_create timed out (>5s), using stub\n");
      auto* df = new (std::nothrow) DeepFilterStub{};
      if (!df) return nullptr;
      df->sample_rate = sample_rate;
      df->frame_size = (sample_rate * 10) / 1000;
      return df;
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
  }

  fprintf(stderr, "deepfilter_adapter: df_create completed\n");
  if (g_capi_state) {
#ifdef DF_APM_HOOK_AVAILABLE
    attach_apm_hook();
#endif
    return g_capi_state;
  }

  fprintf(stderr, "deepfilter_adapter: df_create returned null\n");
  auto* df = new (std::nothrow) DeepFilterStub{};
  if (!df) return nullptr;
  df->sample_rate = sample_rate;
  df->frame_size = (sample_rate * 10) / 1000;
  return df;
}

__attribute__((visibility("default"))) int df_process_frame(void* state, const float* input, float* output, int num_samples) {
  if (g_capi_state && g_capi.lib) return (int)g_capi.process(state, input, output);
  for (int i = 0; i < num_samples; i++) output[i] = input[i];
  return num_samples;
}

__attribute__((visibility("default"))) int df_get_frame_size(void* state) {
  if (g_capi_state && g_capi.lib) return (int)g_capi.frame_len(state);
  return static_cast<DeepFilterStub*>(state)->frame_size;
}

__attribute__((visibility("default"))) int df_get_sample_rate(void* state) {
  return 48000;
}

__attribute__((visibility("default"))) void df_destroy(void* state) {
  if (state == g_capi_state) {
    while (!g_capi_init_done.load())
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    if (g_capi.lib) g_capi.free(state);
    g_capi_state = nullptr;
    g_capi_init_attempted.store(false);
    g_capi_init_done.store(false);
  } else {
    delete static_cast<DeepFilterStub*>(state);
  }
}

__attribute__((visibility("default"))) int df_is_real(void) {
  return (g_capi.lib && g_capi_init_done.load() && g_capi_state) ? 1 : 0;
}

__attribute__((visibility("default"))) void df_apm_set_enabled(int enabled) {
#ifdef DF_APM_HOOK_AVAILABLE
  g_apm_enabled.store(enabled != 0);
  fprintf(stderr, "df_apm: set_enabled=%d\n", enabled);
#endif
}

__attribute__((visibility("default"))) int df_apm_is_attached(void) {
#ifdef DF_APM_HOOK_AVAILABLE
  return g_apm_attached.load() && g_apm_effect != nullptr ? 1 : 0;
#else
  return 0;
#endif
}

__attribute__((visibility("default"))) void df_set_atten_lim_export(float lim_db) {
  if (!g_capi_state || !g_capi.lib) return;
  if (g_capi.set_atten_lim) {
    g_capi.set_atten_lim(g_capi_state, lim_db);
  }
}

}