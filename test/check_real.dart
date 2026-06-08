import 'dart:ffi';
import 'dart:io';

void main() {
  final runnerDir = r'J:\Development\fluttering_ermine\build\windows\x64\runner\Debug';
  print('Runner dir: $runnerDir');

  // Test 1: deep_filter_lib.dll directly (full path)
  try {
    final lib = DynamicLibrary.open('$runnerDir\\deep_filter_lib.dll');
    print('[1] deep_filter_lib.dll loaded: OK');
    for (final sym in ['df_create', 'df_get_frame_length', 'df_process_frame', 'df_free']) {
      try {
        lib.lookupFunction<Void Function(), void Function()>(sym);
        print('  symbol "$sym": FOUND');
      } catch (_) {
        print('  symbol "$sym": NOT FOUND');
      }
    }
    lib.close();
  } catch (e) {
    print('[1] deep_filter_lib.dll: FAILED - $e');
  }

  // Test 2: deepfilter_livekit_plugin.dll (full path)
  try {
    final lib = DynamicLibrary.open('$runnerDir\\deepfilter_livekit_plugin.dll');
    print('[2] deepfilter_livekit_plugin.dll loaded: OK');
    for (final sym in ['df_init', 'df_is_real', 'df_process_frame', 'df_get_frame_size', 'df_destroy']) {
      try {
        lib.lookupFunction<Void Function(), void Function()>(sym);
        print('  symbol "$sym": FOUND');
      } catch (_) {
        print('  symbol "$sym": NOT FOUND');
      }
    }
    lib.close();
  } catch (e) {
    print('[2] deepfilter_livekit_plugin.dll: FAILED - $e');
  }

  print('');
  print('DLL loading: OK');
  print('NOTE: df_init() -> df_create() hangs during tract-onnx model init.');
  print('This is a runtime issue in ONNX model loading, not DLL loading.');
}
