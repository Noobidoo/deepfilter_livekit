#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <time.h>
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

static char g_base_dir[4096] = {};

static int load_capi(void) {
  if (g_capi.lib) return 1;

  // Record base directory of this dylib for default model path.
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

  g_capi.lib = dlopen("libdeep_filter_lib.dylib", RTLD_NOW | RTLD_LOCAL);
  if (!g_capi.lib) {
    fprintf(stderr, "deepfilter_adapter: libdeep_filter_lib.dylib not found (%s)\n",
            dlerror());
    return 0;
  }
  g_capi.create = (DfCreate)dlsym(g_capi.lib, "df_create");
  g_capi.frame_len = (DfFrameLen)dlsym(g_capi.lib, "df_get_frame_length");
  g_capi.process = (DfProcess)dlsym(g_capi.lib, "df_process_frame");
  g_capi.free = (DfFree)dlsym(g_capi.lib, "df_free");
  if (!g_capi.create || !g_capi.frame_len || !g_capi.process || !g_capi.free) {
    fprintf(stderr, "deepfilter_adapter: capi symbols not found\n");
    dlclose(g_capi.lib);
    g_capi.lib = NULL;
    return 0;
  }
  fprintf(stderr, "deepfilter_adapter: capi loaded successfully\n");
  return 1;
}

static int directory_exists(const char* path) {
  struct stat st;
  return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

// Resolve model path: use provided one, or default to <plugin_dir>/models.
// Returns heap-allocated string the caller must free().
static char* resolve_model_path(const char* model_path) {
  if (model_path && model_path[0] != '\0') {
    char* copy = calloc(strlen(model_path) + 1, 1);
    strcpy(copy, model_path);
    return copy;
  }

  if (g_base_dir[0] == '\0') return NULL;

  size_t base_len = strlen(g_base_dir);
  char* default_path = calloc(base_len + 8, 1);
  strcpy(default_path, g_base_dir);
  strcat(default_path, "/models");

  if (!directory_exists(default_path)) {
    fprintf(stderr, "deepfilter_adapter: default models dir not found, using stub\n");
    free(default_path);
    return NULL;
  }

  fprintf(stderr, "deepfilter_adapter: using default model path\n");
  return default_path;
}

struct DeepFilterStub {
  int sample_rate;
  int frame_size;
};

static int g_capi_init_attempted = 0;
static int g_capi_init_done = 0;
static void* g_capi_state = NULL;
static pthread_mutex_t g_init_mutex = PTHREAD_MUTEX_INITIALIZER;

struct InitParams {
  char* resolved_path;
  int sample_rate;
};

static void* init_thread(void* arg) {
  struct InitParams* p = (struct InitParams*)arg;
  g_capi_state = g_capi.create(p->resolved_path, 100.0f, NULL);
  g_capi_init_done = 1;
  if (p->resolved_path) free(p->resolved_path);
  free(p);
  return NULL;
}

void* df_init(const char* model_path, int sample_rate) {
  if (!load_capi()) {
    struct DeepFilterStub* df = calloc(1, sizeof(struct DeepFilterStub));
    if (!df) return NULL;
    df->sample_rate = sample_rate;
    df->frame_size = (sample_rate * 10) / 1000;
    return df;
  }

  char* resolved = resolve_model_path(model_path);
  if (!resolved) {
    fprintf(stderr, "deepfilter_adapter: no model path, using stub\n");
    struct DeepFilterStub* df = calloc(1, sizeof(struct DeepFilterStub));
    if (!df) return NULL;
    df->sample_rate = sample_rate;
    df->frame_size = (sample_rate * 10) / 1000;
    return df;
  }

  // Start capi init on a background thread once.
  pthread_mutex_lock(&g_init_mutex);
  if (!g_capi_init_attempted) {
    g_capi_init_attempted = 1;
    struct InitParams* p = calloc(1, sizeof(struct InitParams));
    p->resolved_path = resolved;
    p->sample_rate = sample_rate;

    pthread_t thread;
    pthread_create(&thread, NULL, init_thread, p);
    pthread_detach(thread);
  } else {
    free(resolved);
  }
  pthread_mutex_unlock(&g_init_mutex);

  // Wait up to 5 seconds
  struct timespec ts = {0, 50 * 1000000};
  int waited = 0;
  while (!g_capi_init_done && waited < 5000) {
    nanosleep(&ts, NULL);
    waited += 50;
  }

  if (!g_capi_init_done) {
    fprintf(stderr,
        "deepfilter_adapter: df_create timed out (>5s), using stub\n");
    struct DeepFilterStub* df = calloc(1, sizeof(struct DeepFilterStub));
    if (!df) return NULL;
    df->sample_rate = sample_rate;
    df->frame_size = (sample_rate * 10) / 1000;
    return df;
  }

  fprintf(stderr, "deepfilter_adapter: df_create completed\n");
  if (g_capi_state) return g_capi_state;

  fprintf(stderr, "deepfilter_adapter: df_create returned null\n");
  struct DeepFilterStub* df = calloc(1, sizeof(struct DeepFilterStub));
  if (!df) return NULL;
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
  return ((struct DeepFilterStub*)state)->frame_size;
}

int df_get_sample_rate(void* state) {
  return 48000;
}

void df_destroy(void* state) {
  if (state == g_capi_state) {
    while (!g_capi_init_done) {
      struct timespec ts = {0, 10 * 1000000};
      nanosleep(&ts, NULL);
    }
    if (g_capi.lib) g_capi.free(state);
  } else {
    free((struct DeepFilterStub*)state);
  }
}

int df_is_real(void) {
  return (g_capi.lib && g_capi_init_done && g_capi_state) ? 1 : 0;
}
