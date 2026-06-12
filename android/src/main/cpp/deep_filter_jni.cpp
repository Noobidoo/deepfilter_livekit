#include <jni.h>
#include <cstring>

extern "C" {
  typedef struct DFState DFState;
  DFState* df_create(const char* path, float atten_lim, const char* log_level);
  int df_get_frame_length(DFState* st);
  float df_process_frame(DFState* st, float* input, float* output);
  void df_free(DFState* model);
}

extern "C" JNIEXPORT jlong JNICALL
Java_io_deepfilter_livekit_DeepFilterPlugin_nativeInit(
    JNIEnv* env, jobject thiz, jstring model_path, jint sample_rate) {
  if (!model_path) return 0;

  const char* path = env->GetStringUTFChars(model_path, nullptr);
  if (!path || path[0] == '\0') {
    if (path) env->ReleaseStringUTFChars(model_path, path);
    return 0;
  }

  float atten_lim = 10.0f;
  DFState* df = df_create(path, atten_lim, nullptr);
  env->ReleaseStringUTFChars(model_path, path);
  return reinterpret_cast<jlong>(df);
}

extern "C" JNIEXPORT void JNICALL
Java_io_deepfilter_livekit_DeepFilterPlugin_nativeDestroy(
    JNIEnv* env, jobject thiz, jlong state) {
  if (state != 0) {
    df_free(reinterpret_cast<DFState*>(state));
  }
}

extern "C" JNIEXPORT jint JNICALL
Java_io_deepfilter_livekit_DeepFilterPlugin_nativeProcessFrame(
    JNIEnv* env, jobject thiz, jlong state, jbyteArray input, jbyteArray output) {
  if (state == 0) return -1;

  jsize input_len = env->GetArrayLength(input);
  jbyte* input_bytes = env->GetByteArrayElements(input, nullptr);
  jbyte* output_bytes = env->GetByteArrayElements(output, nullptr);

  int num_samples = input_len / sizeof(jfloat);
  df_process_frame(
      reinterpret_cast<DFState*>(state),
      reinterpret_cast<float*>(input_bytes),
      reinterpret_cast<float*>(output_bytes));

  env->ReleaseByteArrayElements(input, input_bytes, JNI_ABORT);
  env->ReleaseByteArrayElements(output, output_bytes, 0);
  return num_samples;
}

extern "C" JNIEXPORT jint JNICALL
Java_io_deepfilter_livekit_DeepFilterPlugin_nativeFrameSize(
    JNIEnv* env, jobject thiz, jlong state) {
  if (state == 0) return -1;
  return static_cast<jint>(df_get_frame_length(reinterpret_cast<DFState*>(state)));
}
