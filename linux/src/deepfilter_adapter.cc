#include <dlfcn.h>
#include <cstddef>
#include <cstdio>
#include <cstring>
#include <new>
#include <atomic>
#include <thread>
#include <chrono>
#include <sys/stat.h>

typedef void* (*DfCreate)(const char*, float, const char*);
typedef size_t (*DfFrameLen)(void*);
typedef float (*DfProcess)(void*, const float*, float*);
typedef void (*DfFree)(void*);

static struct {
  void* lib;
  DfCreate create;
  DfFrameLen frame_len;
  DfProcess process;
  DfFree free;
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

  g_capi.lib = dlopen("libdeep_filter_lib.so", RTLD_NOW | RTLD_LOCAL);
  if (!g_capi.lib) {
    fprintf(stderr, "deepfilter_adapter: libdeep_filter_lib.so not found (%s)\n",
            dlerror());
    return false;
  }
  g_capi.create = (DfCreate)dlsym(g_capi.lib, "df_create");
  g_capi.frame_len = (DfFrameLen)dlsym(g_capi.lib, "df_get_frame_length");
  g_capi.process = (DfProcess)dlsym(g_capi.lib, "df_process_frame");
  g_capi.free = (DfFree)dlsym(g_capi.lib, "df_free");
  if (!g_capi.create || !g_capi.frame_len || !g_capi.process || !g_capi.free) {
    fprintf(stderr, "deepfilter_adapter: capi symbols not found\n");
    dlclose(g_capi.lib);
    g_capi.lib = nullptr;
    return false;
  }
  fprintf(stderr, "deepfilter_adapter: capi loaded successfully\n");
  return true;
}

static bool directory_exists(const char* path) {
  struct stat st;
  return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
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
  char* default_path = new char[base_len + 8];
  strcpy(default_path, g_base_dir);
  strcat(default_path, "/models");

  if (!directory_exists(default_path)) {
    fprintf(stderr, "deepfilter_adapter: default models dir not found, using stub\n");
    delete[] default_path;
    return nullptr;
  }

  fprintf(stderr, "deepfilter_adapter: using default model path\n");
  return default_path;
}

struct DeepFilterStub {
  int sample_rate;
  int frame_size;
};

static std::atomic<bool> g_capi_init_attempted{false};
static std::atomic<bool> g_capi_init_done{false};
static void* g_capi_state = nullptr;

extern "C" {

void* df_init(const char* model_path, int sample_rate) {
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
  if (g_capi_state) return g_capi_state;

  fprintf(stderr, "deepfilter_adapter: df_create returned null\n");
  auto* df = new (std::nothrow) DeepFilterStub{};
  if (!df) return nullptr;
  df->sample_rate = sample_rate;
  df->frame_size = (sample_rate * 10) / 1000;
  return df;
}

int df_process_frame(void* state, const float* input, float* output, int num_samples) {
  if (g_capi_state && g_capi.lib) return (int)g_capi.process(state, input, output);
  for (int i = 0; i < num_samples; i++) output[i] = input[i];
  return num_samples;
}

int df_get_frame_size(void* state) {
  if (g_capi_state && g_capi.lib) return (int)g_capi.frame_len(state);
  return static_cast<DeepFilterStub*>(state)->frame_size;
}

int df_get_sample_rate(void* state) {
  return 48000;
}

void df_destroy(void* state) {
  if (state == g_capi_state) {
    while (!g_capi_init_done.load())
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
    if (g_capi.lib) g_capi.free(state);
  } else {
    delete static_cast<DeepFilterStub*>(state);
  }
}

int df_is_real(void) {
  return (g_capi.lib && g_capi_init_done.load() && g_capi_state) ? 1 : 0;
}

}