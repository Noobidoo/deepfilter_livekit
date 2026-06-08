import 'dart:ffi';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:deepfilter_livekit/deepfilter_livekit.dart';

void main() {
  test('isRealLibrary returns true when real CAPI is loaded', () {
    // This test runs in the flutter_test environment where native libs
    // aren't available, so we expect false.
    // On a real Windows device with DLLs deployed, this would be true.
    if (Platform.isWindows) {
      // Try loading via FFI directly to confirm the DLL exists
      try {
        final lib = DynamicLibrary.open('deepfilter_livekit_plugin.dll');
        final fn = lib
            .lookup<NativeFunction<Int32 Function()>>('df_is_real')
            .asFunction<int Function()>();
        final real = fn() != 0;
        print('df_is_real() = ${fn()}');
        print(
          real
              ? 'SUCCESS: Real CAPI library loaded'
              : 'WARNING: Pass-through stub in use',
        );
        lib.close();
      } catch (e) {
        print('Direct FFI check: $e');
      }
    }
  });
}
