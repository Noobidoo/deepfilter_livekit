#include <jni.h>
#include <cstring>

extern "C" {
  typedef struct DeepFilter DeepFilter;
  DeepFilter* df_init(const char* model_path, int sample_rate);
  int df_process_frame(DeepFilter* df, const float* input, float* output, int num_samples);
  int df_get_frame_size(DeepFilter* df);
  int df_get_sample_rate(DeepFilter* df);
  void df_destroy(DeepFilter* df);
}

extern "C" JNIEXPORT jlong JNICALL
Java_io_deepfilter_livekit_DeepFilterPlugin_nativeInit(
    JNIEnv* env, jobject thiz, jstring model_path, jint sample_rate) {
  const char* path = model_path ? env->GetStringUTFChars(model_path, nullptr) : nullptr;
  DeepFilter* df = df_init(path, static_cast<int>(sample_rate));
  if (path) env->ReleaseStringUTFChars(model_path, path);
  return reinterpret_cast<jlong>(df);
}

extern "C" JNIEXPORT void JNICALL
Java_io_deepfilter_livekit_DeepFilterPlugin_nativeDestroy(
    JNIEnv* env, jobject thiz, jlong state) {
  if (state != 0) {
    df_destroy(reinterpret_cast<DeepFilter*>(state));
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
  jint ret = df_process_frame(
      reinterpret_cast<DeepFilter*>(state),
      reinterpret_cast<const float*>(input_bytes),
      reinterpret_cast<float*>(output_bytes),
      num_samples);

  env->ReleaseByteArrayElements(input, input_bytes, JNI_ABORT);
  env->ReleaseByteArrayElements(output, output_bytes, 0);
  return ret;
}

extern "C" JNIEXPORT jint JNICALL
Java_io_deepfilter_livekit_DeepFilterPlugin_nativeFrameSize(
    JNIEnv* env, jobject thiz, jlong state) {
  if (state == 0) return -1;
  return static_cast<jint>(df_get_frame_size(reinterpret_cast<DeepFilter*>(state)));
}
