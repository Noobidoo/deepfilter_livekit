#ifndef DEEP_FILTER_ADAPTER_H
#define DEEP_FILTER_ADAPTER_H

#ifdef __cplusplus
extern "C" {
#endif

void* df_init(const char* model_path, int sample_rate);
int df_process_frame(void* state, const float* input, float* output, int num_samples);
int df_get_frame_size(void* state);
int df_get_sample_rate(void* state);
void df_destroy(void* state);
int df_is_real(void);

#ifdef __cplusplus
}
#endif

#endif
