#define _CRT_SECURE_NO_WARNINGS
#include <windows.h>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <new>
#include <atomic>
#include <vector>
#include <mutex>

#ifdef DF_APM_HOOK_AVAILABLE
#include "rtc_audio_processing.h"
#include "flutter_webrtc_base.h"
#include "flutter_webrtc/flutter_web_r_t_c_plugin.h"
#endif


static void df_trace(const char* msg) {
  OutputDebugStringA(msg);
  // Also write to a file so it's visible without DebugView
  static FILE* log = nullptr;
  if (!log) {
    char path[MAX_PATH];
    GetTempPathA(MAX_PATH, path);
    strcat_s(path, MAX_PATH, "deepfilter_adapter.log");
    fopen_s(&log, path, "a");
  }
  if (log) {
    fprintf(log, "%s\n", msg);
    fflush(log);
  }
}

#define TRACE(msg) do { \
    char _buf[512]; \
    snprintf(_buf, sizeof(_buf), "df_adapter: %s", msg); \
    df_trace(_buf); \
} while(0)

typedef void* (*DfCreate)(const char*, float, const char*);
typedef size_t (*DfFrameLen)(void*);
typedef float (*DfProcess)(void*, const float*, float*);
typedef void (*DfFree)(void*);
typedef void (*DfSetAttenLim)(void*, float);

static struct {
  HMODULE lib;
  DfCreate create;
  DfFrameLen frame_len;
  DfProcess process;
  DfFree free;
  DfSetAttenLim set_atten_lim;
} g_capi = {};

static char g_base_dir[MAX_PATH] = {};

static bool load_capi() {
  TRACE("load_capi enter");
  if (g_capi.lib) { TRACE("load_capi already loaded"); return true; }

  HMODULE self;
  if (GetModuleHandleExA(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS,
                         reinterpret_cast<LPCSTR>(&load_capi), &self)) {
    char self_path[MAX_PATH] = {};
    DWORD self_len = GetModuleFileNameA(self, self_path, MAX_PATH);
    if (self_len > 0 && self_len < MAX_PATH) {
      char* last_slash = strrchr(self_path, '\\');
      if (last_slash) {
        size_t dir_len = last_slash - self_path;
        strncpy_s(g_base_dir, sizeof(g_base_dir), self_path, dir_len);

        size_t tail_capacity = sizeof(self_path) - (dir_len + 1);
        strcpy_s(last_slash + 1, tail_capacity,
                 "deep_filter_lib.dll");
        TRACE("load_capi loading deep_filter_lib.dll from plugin dir");
        g_capi.lib = LoadLibraryA(self_path);
      }
    } else {
      TRACE("load_capi GetModuleFileNameA failed or path truncated");
    }
    FreeLibrary(self);
  }

  if (!g_capi.lib) {
    TRACE("load_capi loading deep_filter_lib.dll from search path");
    g_capi.lib = LoadLibraryA("deep_filter_lib.dll");
  }

  if (!g_capi.lib) {
    char buf[256];
    snprintf(buf, sizeof(buf), "load_capi deep_filter_lib.dll not found (err=%lu)", GetLastError());
    OutputDebugStringA(buf);
    return false;
  }

  TRACE("load_capi resolving symbols");
  g_capi.create = (DfCreate)GetProcAddress(g_capi.lib, "df_create");
  g_capi.frame_len = (DfFrameLen)GetProcAddress(g_capi.lib, "df_get_frame_length");
  g_capi.process = (DfProcess)GetProcAddress(g_capi.lib, "df_process_frame");
  g_capi.free = (DfFree)GetProcAddress(g_capi.lib, "df_free");
  g_capi.set_atten_lim = (DfSetAttenLim)GetProcAddress(g_capi.lib, "df_set_atten_lim"); // optional
  if (!g_capi.create || !g_capi.frame_len || !g_capi.process || !g_capi.free) {
    TRACE("load_capi symbols not found");
    FreeLibrary(g_capi.lib);
    g_capi.lib = nullptr;
    return false;
  }

  TRACE("load_capi success");
  return true;
}

static bool directory_exists(const char* path) {
  DWORD attr = GetFileAttributesA(path);
  return attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY);
}

// Find the first file matching a pattern inside a directory.
// Returns a heap-allocated full path, or nullptr if not found.
static char* find_first_file(const char* dir, const char* pattern) {
  char query[MAX_PATH];
  snprintf(query, sizeof(query), "%s\\%s", dir, pattern);
  WIN32_FIND_DATAA ffd;
  HANDLE h = FindFirstFileA(query, &ffd);
  if (h == INVALID_HANDLE_VALUE) return nullptr;
  FindClose(h);
  size_t dlen = strlen(dir);
  size_t flen = strlen(ffd.cFileName);
  char* result = new char[dlen + 1 + flen + 1];
  strcpy_s(result, dlen + 1 + flen + 1, dir);
  strcat_s(result, dlen + 1 + flen + 1, "\\");
  strcat_s(result, dlen + 1 + flen + 1, ffd.cFileName);
  return result;
}

static char* resolve_model_path(const char* model_path) {
  if (model_path && model_path[0] != '\0') {
    TRACE("resolve_model_path using provided path");
    char* copy = new char[strlen(model_path) + 1];
    strcpy_s(copy, strlen(model_path) + 1, model_path);
    return copy;
  }

  if (g_base_dir[0] == '\0') {
    TRACE("resolve_model_path base_dir empty");
    return nullptr;
  }

  size_t base_len = strlen(g_base_dir);
  char* models_dir = new char[base_len + 8];
  strcpy_s(models_dir, base_len + 8, g_base_dir);
  strcat_s(models_dir, base_len + 8, "\\models");

  {
    char buf[512];
    snprintf(buf, sizeof(buf), "resolve_model_path checking: %s", models_dir);
    OutputDebugStringA(buf);
  }

  if (!directory_exists(models_dir)) {
    TRACE("resolve_model_path models dir not found");
    delete[] models_dir;
    return nullptr;
  }

  // df_create expects a path to a .tar.gz file, not a directory.
  char* tar_path = find_first_file(models_dir, "*.tar.gz");
  if (!tar_path) tar_path = find_first_file(models_dir, "*.tar");
  delete[] models_dir;

  if (tar_path) {
    char buf[512];
    snprintf(buf, sizeof(buf), "resolve_model_path found tar: %s", tar_path);
    OutputDebugStringA(buf);
    return tar_path;
  }

  TRACE("resolve_model_path no tar.gz found in models dir");
  return nullptr;
}

struct DeepFilterStub {
  int sample_rate;
  int frame_size;
};

static DeepFilterStub* create_stub(int sample_rate) {
  auto* df = new (std::nothrow) DeepFilterStub{};
  if (!df) return nullptr;
  df->sample_rate = sample_rate;
  df->frame_size = (sample_rate * 10) / 1000;
  return df;
}

static std::atomic<bool> g_capi_init_attempted{false};
static std::atomic<bool> g_capi_init_done{false};
static void* g_capi_state = nullptr;

// ---------------------------------------------------------------------------
// APM capture post-processing hook
// ---------------------------------------------------------------------------
#ifdef DF_APM_HOOK_AVAILABLE

static std::atomic<bool> g_apm_enabled{true};

// Plain C helper — no local C++ objects so __try/__except is legal here.
static void __cdecl df_process_safe(const float* in, float* out) {
  __try {
    g_capi.process(g_capi_state, in, out);
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    // pass-through on crash
    // caller copies input to output before this call, so out already has input
  }
}

// Accumulates partial input frames until we have a full DeepFilter frame,
// then processes in-place and drains back into the APM buffer.
class DeepFilterAPMEffect : public libwebrtc::RTCAudioProcessing::CustomProcessing {
 public:
  DeepFilterAPMEffect() {}

  void Initialize(int sample_rate_hz, int num_channels) override {
    char buf[128];
    snprintf(buf, sizeof(buf),
             "df_apm: Initialize rate=%d ch=%d", sample_rate_hz, num_channels);
    TRACE(buf);
    std::lock_guard<std::mutex> lk(mutex_);
    sample_rate_ = sample_rate_hz;
    num_channels_ = num_channels;
    accumulator_.clear();
    drain_.clear();
    df_frame_size_ = 0;
    // Query frame size from capi if available
    if (g_capi_state && g_capi.lib) {
      df_frame_size_ = static_cast<int>(g_capi.frame_len(g_capi_state));
    }
    if (df_frame_size_ <= 0) df_frame_size_ = 480; // 10ms at 48kHz
    snprintf(buf, sizeof(buf), "df_apm: df_frame_size=%d", df_frame_size_);
    TRACE(buf);
  }

  // Called by WebRTC APM on the audio capture thread for every APM band frame.
  // num_bands: number of frequency bands (usually 1 below 16kHz)
  // num_frames: samples per channel per band
  // buffer_size: total floats in buffer (num_bands * num_frames * num_channels_)
  void Process(int num_bands, int num_frames, int buffer_size,
               float* buffer) override {
    if (!g_apm_enabled.load(std::memory_order_relaxed)) return;
    if (!g_capi_state || !g_capi.lib) return;

    std::lock_guard<std::mutex> lk(mutex_);

    if (df_frame_size_ <= 0) return;

    // APM gives us interleaved float samples per band.
    // We only process band 0 (full-rate capture).
    // num_frames samples, num_channels_ channels, interleaved.
    float* band0 = buffer; // first band starts at buffer[0]
    int band_samples = num_frames * num_channels_;

    // Append incoming samples to accumulator
    accumulator_.insert(accumulator_.end(), band0, band0 + band_samples);

    // Process complete DeepFilter frames
    while (static_cast<int>(accumulator_.size()) >= df_frame_size_) {
      // df_process_frame works on mono float32 frames
      // If multi-channel, process each channel separately
      if (num_channels_ == 1) {
        // Mono: process in-place via temp scratch
        scratch_in_.assign(accumulator_.begin(),
                           accumulator_.begin() + df_frame_size_);
        scratch_out_ = scratch_in_; // pre-copy so safe fallback is input
        scratch_out_.resize(df_frame_size_);
        df_process_safe(scratch_in_.data(), scratch_out_.data());
        drain_.insert(drain_.end(), scratch_out_.begin(), scratch_out_.end());
      } else {
        // Multi-channel: de-interleave, process ch0, re-interleave
        int ch = num_channels_;
        int frames = df_frame_size_ / ch;
        // Only process if evenly divisible
        if (df_frame_size_ % ch == 0) {
          scratch_in_.resize(frames);
          scratch_out_.resize(frames);
          std::vector<float> block(accumulator_.begin(),
                                   accumulator_.begin() + df_frame_size_);
          // De-interleave ch0
          for (int i = 0; i < frames; ++i) scratch_in_[i] = block[i * ch];
          // Pre-copy for safe fallback
          scratch_out_ = scratch_in_;
          df_process_safe(scratch_in_.data(), scratch_out_.data());
          // Write back to all channels
          for (int i = 0; i < frames; ++i) {
            for (int c = 0; c < ch; ++c)
              block[i * ch + c] = scratch_out_[i];
          }
          drain_.insert(drain_.end(), block.begin(), block.end());
        } else {
          // Frame size not divisible by channels - pass through
          drain_.insert(drain_.end(), accumulator_.begin(),
                        accumulator_.begin() + df_frame_size_);
        }
      }
      accumulator_.erase(accumulator_.begin(),
                         accumulator_.begin() + df_frame_size_);
    }

    // Drain processed samples back into APM buffer
    int to_drain = (std::min)(band_samples, static_cast<int>(drain_.size()));
    if (to_drain > 0) {
      std::copy(drain_.begin(), drain_.begin() + to_drain, band0);
      drain_.erase(drain_.begin(), drain_.begin() + to_drain);
    }
  }

  void Reset(int new_rate) override {
    char buf[64];
    snprintf(buf, sizeof(buf), "df_apm: Reset new_rate=%d", new_rate);
    TRACE(buf);
    std::lock_guard<std::mutex> lk(mutex_);
    sample_rate_ = new_rate;
    accumulator_.clear();
    drain_.clear();
  }

  void Release() override {
    TRACE("df_apm: Release");
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
  TRACE("df_apm: attaching hook");

  // Get the FlutterWebRTC shared instance exported by flutter_webrtc_plugin.dll
  HMODULE fwrtc = GetModuleHandleA("flutter_webrtc_plugin.dll");
  if (!fwrtc) {
    TRACE("df_apm: flutter_webrtc_plugin.dll not found");
    g_apm_attached.store(false);
    return;
  }

  using SharedInstanceFn = flutter_webrtc_plugin::FlutterWebRTCBase*(*)();
  auto fn = reinterpret_cast<SharedInstanceFn>(
      GetProcAddress(fwrtc, "FlutterWebRTCPluginSharedInstance"));
  if (!fn) {
    TRACE("df_apm: FlutterWebRTCPluginSharedInstance not found");
    g_apm_attached.store(false);
    return;
  }

  flutter_webrtc_plugin::FlutterWebRTCBase* instance = fn();
  if (!instance) {
    TRACE("df_apm: shared instance is null");
    g_apm_attached.store(false);
    return;
  }

  auto apm = instance->audio_processing();
  if (!apm) {
    TRACE("df_apm: audio_processing() returned null");
    g_apm_attached.store(false);
    return;
  }

  g_apm_effect = new DeepFilterAPMEffect();
  apm->SetCapturePostProcessing(g_apm_effect);
  TRACE("df_apm: hook attached successfully");
}

#endif // DF_APM_HOOK_AVAILABLE

extern "C" {

__declspec(dllexport) void* df_init(const char* model_path, int sample_rate) {
  TRACE("df_init enter");

  if (!load_capi()) {
    TRACE("df_init capi not loaded, returning stub");
    return create_stub(sample_rate);
  }

  char* resolved = resolve_model_path(model_path);
  if (!resolved) {
    TRACE("df_init no model path, returning stub");
    return create_stub(sample_rate);
  }

  if (g_capi_init_attempted.exchange(true)) {
    TRACE("df_init init already attempted, freeing extra resolved path");
    delete[] resolved;
    // Wait for the first attempt to complete (real or stub path)
    while (!g_capi_init_done.load()) Sleep(50);
    if (g_capi_state) {
      TRACE("df_init returning previously created capi state");
      return g_capi_state;
    }
    TRACE("df_init previous attempt failed, returning stub");
    return create_stub(sample_rate);
  }

  // First call: try synchronous creation with SEH protection.
  // If it crashes (Rust abort/panic), the process dies — nothing we can do.
  // If SEH catches an access violation, we fall back to stub and never retry.
  TRACE("df_init trying synchronous df_create");
  __try {
    g_capi_state = g_capi.create(resolved, 100.0f, nullptr);
  } __except (EXCEPTION_EXECUTE_HANDLER) {
    TRACE("df_init df_create crashed (SEH)");
    g_capi_state = nullptr;
  }
  g_capi_init_done.store(true);

  delete[] resolved;

  if (g_capi_state) {
    TRACE("df_init returning real capi state");
#ifdef DF_APM_HOOK_AVAILABLE
    attach_apm_hook();
#endif
    return g_capi_state;
  }

  TRACE("df_init capi returned null or crashed, returning stub");
  return create_stub(sample_rate);
}

__declspec(dllexport) int df_process_frame(void* state, const float* input,
                                            float* output, int num_samples) {
  if (g_capi_state && g_capi.lib) {
    __try {
      return (int)g_capi.process(state, input, output);
    } __except (EXCEPTION_EXECUTE_HANDLER) {
      TRACE("df_process_frame crashed (SEH)");
    }
  }
  for (int i = 0; i < num_samples; i++) output[i] = input[i];
  return num_samples;
}

__declspec(dllexport) int df_get_frame_size(void* state) {
  if (g_capi_state && g_capi.lib) return (int)g_capi.frame_len(state);
  return static_cast<DeepFilterStub*>(state)->frame_size;
}

__declspec(dllexport) int df_get_sample_rate(void* state) {
  return 48000;
}

__declspec(dllexport) void df_destroy(void* state) {
  if (state == g_capi_state) {
    while (!g_capi_init_done.load()) Sleep(10);
    if (g_capi.lib) g_capi.free(state);
  } else {
    delete static_cast<DeepFilterStub*>(state);
  }
}

__declspec(dllexport) int df_is_real(void) {
  return (g_capi.lib && g_capi_init_done.load() && g_capi_state) ? 1 : 0;
}

__declspec(dllexport) void df_apm_set_enabled(int enabled) {
#ifdef DF_APM_HOOK_AVAILABLE
  g_apm_enabled.store(enabled != 0);
  char buf[64];
  snprintf(buf, sizeof(buf), "df_apm: set_enabled=%d", enabled);
  TRACE(buf);
#endif
}

__declspec(dllexport) int df_apm_is_attached(void) {
#ifdef DF_APM_HOOK_AVAILABLE
  return g_apm_attached.load() && g_apm_effect != nullptr ? 1 : 0;
#else
  return 0;
#endif
}

__declspec(dllexport) void df_set_atten_lim_export(float lim_db) {
  if (!g_capi_state || !g_capi.lib) return;
  if (g_capi.set_atten_lim) {
    g_capi.set_atten_lim(g_capi_state, lim_db);
    char buf[64];
    snprintf(buf, sizeof(buf), "df_set_atten_lim: %.1f dB", lim_db);
    TRACE(buf);
  }
}

}

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID lpReserved) {
  if (reason == DLL_PROCESS_ATTACH) {
    OutputDebugStringA("df_adapter: DllMain DLL_PROCESS_ATTACH\n");
    DisableThreadLibraryCalls(hModule);
  }
  return TRUE;
}
