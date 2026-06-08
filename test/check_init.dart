// ignore_for_file: avoid_print

import 'dart:ffi';
import 'dart:io';

final class _DfState extends Opaque {}

typedef _DfInitC = Pointer<_DfState> Function(Pointer<Int8>, Int32);
typedef _DfInitDart = Pointer<_DfState> Function(Pointer<Int8>, int);
typedef _DfIsRealC = Int32 Function();
typedef _DfIsRealDart = int Function();
typedef _DfFrameSizeC = Int32 Function(Pointer<_DfState>);
typedef _DfFrameSizeDart = int Function(Pointer<_DfState>);
typedef _DfDestroyC = Void Function(Pointer<_DfState>);
typedef _DfDestroyDart = void Function(Pointer<_DfState>);
typedef _DfProcessC =
    Int32 Function(Pointer<_DfState>, Pointer<Float>, Pointer<Float>, Int32);
typedef _DfProcessDart =
    int Function(Pointer<_DfState>, Pointer<Float>, Pointer<Float>, int);

Pointer<Int8> _strPtr(String s) {
  final plib = DynamicLibrary.process();
  final malloc = plib
      .lookup<NativeFunction<Pointer<Void> Function(IntPtr)>>('malloc')
      .asFunction<Pointer<Void> Function(int)>();
  final ptr = malloc(s.codeUnits.length + 1).cast<Int8>();
  for (int i = 0; i < s.codeUnits.length; i++) {
    ptr[i] = s.codeUnits[i];
  }
  ptr[s.codeUnits.length] = 0;
  return ptr;
}

void _free(Pointer<Int8> p) {
  final plib = DynamicLibrary.process();
  final free = plib
      .lookup<NativeFunction<Void Function(Pointer<Void>)>>('free')
      .asFunction<void Function(Pointer<Void>)>();
  free(p.cast<Void>());
}

void main() {
  final runnerDir =
      r'J:\Development\fluttering_ermine\build\windows\x64\runner\Debug';
  final modelPath =
      r'J:\Development\deepfilter_livekit\windows\lib\models\DeepFilterNet3_onnx.tar.gz';

  try {
    final lib = DynamicLibrary.open(
      '$runnerDir\\deepfilter_livekit_plugin.dll',
    );
    print('[OK] Plugin DLL loaded');

    // Try with model path, catch any crash/hang via process-level timeout
    final ptr = _strPtr(modelPath);
    final dfInit = lib
        .lookup<NativeFunction<_DfInitC>>('df_init')
        .asFunction<_DfInitDart>();

    print('Calling df_init("$modelPath", 48000)...');
    final state = dfInit(ptr, 48000);
    _free(ptr);
    print('df_init returned state=${state.address}');

    if (state.address == 0) {
      print('[FAIL] df_init returned null state');
      lib.close();
      exit(1);
    }

    // If we get here, init succeeded
    final isReal = lib
        .lookup<NativeFunction<_DfIsRealC>>('df_is_real')
        .asFunction<_DfIsRealDart>();
    print('df_is_real = ${isReal()}');
    print(isReal() != 0 ? '[OK] Real CAPI loaded!' : '[STUB] Stub in use');

    final dfFrameSize = lib
        .lookup<NativeFunction<_DfFrameSizeC>>('df_get_frame_size')
        .asFunction<_DfFrameSizeDart>();
    final frameSize = dfFrameSize(state);
    print('frame_size = $frameSize');

    // Try processing a frame
    final dfProcess = lib
        .lookup<NativeFunction<_DfProcessC>>('df_process_frame')
        .asFunction<_DfProcessDart>();
    final plib = DynamicLibrary.process();
    final malloc = plib
        .lookup<NativeFunction<Pointer<Void> Function(IntPtr)>>('malloc')
        .asFunction<Pointer<Void> Function(int)>();
    final free = plib
        .lookup<NativeFunction<Void Function(Pointer<Void>)>>('free')
        .asFunction<void Function(Pointer<Void>)>();

    final input = malloc(frameSize * 4).cast<Float>();
    final output = malloc(frameSize * 4).cast<Float>();
    for (int i = 0; i < frameSize; i++) {
      input[i] = 0.0;
    }
    input[0] = 0.5; // a sample

    print('Processing $frameSize samples...');
    final ret = dfProcess(state, input, output, frameSize);
    print('process returned $ret');
    print('output[0] = ${output[0]}');

    free(input.cast<Void>());
    free(output.cast<Void>());

    final dfDestroy = lib
        .lookup<NativeFunction<_DfDestroyC>>('df_destroy')
        .asFunction<_DfDestroyDart>();
    dfDestroy(state);
    lib.close();
    print('[OK] All checks passed');
  } catch (e) {
    print('[FAIL] $e');
    exit(1);
  }
}
