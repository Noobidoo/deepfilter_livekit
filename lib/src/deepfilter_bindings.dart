import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart';

final class _DfState extends Opaque {}

typedef _DfInitC = Pointer<_DfState> Function(Pointer<Int8>, Int32);
typedef _DfInitDart = Pointer<_DfState> Function(Pointer<Int8>, int);

typedef _DfProcessC = Int32 Function(
  Pointer<_DfState>, Pointer<Float>, Pointer<Float>, Int32,
);
typedef _DfProcessDart = int Function(
  Pointer<_DfState>, Pointer<Float>, Pointer<Float>, int,
);

typedef _DfFrameSizeC = Int32 Function(Pointer<_DfState>);
typedef _DfFrameSizeDart = int Function(Pointer<_DfState>);

typedef _DfSampleRateC = Int32 Function(Pointer<_DfState>);
typedef _DfSampleRateDart = int Function(Pointer<_DfState>);

typedef _DfDestroyC = Void Function(Pointer<_DfState>);
typedef _DfDestroyDart = void Function(Pointer<_DfState>);

class DeepFilterException implements Exception {
  final String message;
  const DeepFilterException(this.message);

  @override
  String toString() => 'DeepFilterException: $message';
}

abstract final class DeepFilterNative {
  static DynamicLibrary? _lib;
  static Pointer<_DfState>? _state;
  static int _frameSize = 0;
  static int _sampleRate = 48000;
  static bool _initialized = false;

  static String get _libName {
    if (Platform.isWindows) return 'deep_filter_lib.dll';
    if (Platform.isLinux) return 'libdeep_filter_lib.so';
    if (Platform.isMacOS) return 'libdeep_filter_lib.dylib';
    if (Platform.isAndroid) return 'libdeep_filter_lib.so';
    if (Platform.isIOS) return 'libdeep_filter_lib.a';
    throw UnsupportedError('Unsupported platform');
  }

  static DynamicLibrary _load() {
    if (_lib != null) return _lib!;
    try {
      _lib = DynamicLibrary.open(_libName);
    } catch (e) {
      throw DeepFilterException(
        'Failed to load DeepFilterNet library ($_libName): $e\n'
        'Ensure prebuilt binary is bundled for your platform.',
      );
    }
    return _lib!;
  }

  static void init({String? modelPath, int sampleRate = 48000}) {
    if (_initialized) return;

    if (Platform.isAndroid || Platform.isIOS) {
      _initChannel(modelPath, sampleRate);
      return;
    }

    final lib = _load();
    final dfInit = lib
        .lookup<NativeFunction<_DfInitC>>('df_init')
        .asFunction<_DfInitDart>();
    final dfFrameSize = lib
        .lookup<NativeFunction<_DfFrameSizeC>>('df_get_frame_size')
        .asFunction<_DfFrameSizeDart>();
    final dfSampleRate = lib
        .lookup<NativeFunction<_DfSampleRateC>>('df_get_sample_rate')
        .asFunction<_DfSampleRateDart>();

    final modelPtr = modelPath != null && modelPath.isNotEmpty
        ? modelPath.toNativeUtf8(allocator: calloc).cast<Int8>()
        : nullptr;
    _state = dfInit(modelPtr, sampleRate);
    if (modelPtr != nullptr) calloc.free(modelPtr);

    if (_state == nullptr || _state!.address == 0) {
      throw DeepFilterException(
        'df_init returned null state. Check model path: $modelPath',
      );
    }

    _frameSize = dfFrameSize(_state!);
    _sampleRate = dfSampleRate(_state!);
    _initialized = true;
  }

  static void _initChannel(String? modelPath, int sampleRate) {
    const MethodChannel('io.deepfilter.livekit').invokeMethod<String>('init', {
      'modelPath': modelPath ?? '',
      'sampleRate': sampleRate,
    });
    _sampleRate = sampleRate;
    _initialized = true;
  }

  static int processFrame(Float32List input, Float32List output) {
    if (!_initialized) {
      throw DeepFilterException('DeepFilter not initialized. Call init() first.');
    }

    if (Platform.isAndroid || Platform.isIOS) {
      throw DeepFilterException(
        'processFrame() is synchronous and cannot be used on mobile. '
        'Use processFrameAsync() instead.',
      );
    }

    final lib = _load();
    final dfProcess = lib
        .lookup<NativeFunction<_DfProcessC>>('df_process_frame')
        .asFunction<_DfProcessDart>();

    if (input.length != _frameSize) {
      _frameSize = _queryFrameSize();
    }

    final inPtr = calloc<Float>(input.length);
    final outPtr = calloc<Float>(output.length);
    for (int i = 0; i < input.length; i++) {
      inPtr[i] = input[i];
    }

    try {
      return dfProcess(_state!, inPtr, outPtr, input.length);
    } finally {
      for (int i = 0; i < output.length; i++) {
        output[i] = outPtr[i];
      }
      calloc.free(inPtr);
      calloc.free(outPtr);
    }
  }

  static Future<int> processFrameAsync(Float32List input, Float32List output) async {
    if (!_initialized) {
      throw DeepFilterException('DeepFilter not initialized. Call init() first.');
    }

    if (Platform.isAndroid || Platform.isIOS) {
      return _processChannel(input, output);
    }

    // Desktop: use sync FFI wrapped in a microtask
    return Future.sync(() => processFrame(input, output));
  }

  static Future<int> _processChannel(Float32List input, Float32List output) async {
    const channel = MethodChannel('io.deepfilter.livekit');
    final result = await channel.invokeMethod<Map>('processFrame', {
      'input': input.buffer.asUint8List(),
    });
    if (result == null) return -1;
    final outBytes = result['output'] as Uint8List;
    final ret = result['ret'] as int;
    final byteData = outBytes.buffer.asByteData();
    for (int i = 0; i < output.length; i++) {
      output[i] = byteData.getFloat32(i * 4, Endian.host);
    }
    return ret;
  }

  static int get frameSize {
    if (_state == null || _state!.address == 0) return 0;
    if (Platform.isAndroid || Platform.isIOS) return _frameSize;
    return _queryFrameSize();
  }

  static int _queryFrameSize() {
    final lib = _load();
    return lib
        .lookup<NativeFunction<_DfFrameSizeC>>('df_get_frame_size')
        .asFunction<_DfFrameSizeDart>()(_state!);
  }

  static int get sampleRate => _sampleRate;

  static void dispose() {
    if (!_initialized) return;

    if (Platform.isAndroid || Platform.isIOS) {
      const MethodChannel('io.deepfilter.livekit').invokeMethod<void>('dispose');
    } else if (_state != null && _state!.address != 0) {
      final lib = _load();
      lib
          .lookup<NativeFunction<_DfDestroyC>>('df_destroy')
          .asFunction<_DfDestroyDart>()(_state!);
    }
    _state = null;
    _frameSize = 0;
    _sampleRate = 48000;
    _initialized = false;
  }

  static bool get isAvailable {
    if (Platform.isAndroid || Platform.isIOS) {
      return true;
    }
    try {
      _load();
      return true;
    } catch (_) {
      return false;
    }
  }
}
