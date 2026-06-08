import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

final class _DfState extends Opaque {}

typedef _DfInitC = Pointer<_DfState> Function(Pointer<Int8>, Int32);
typedef _DfInitDart = Pointer<_DfState> Function(Pointer<Int8>, int);

typedef _DfProcessC =
    Int32 Function(Pointer<_DfState>, Pointer<Float>, Pointer<Float>, Int32);
typedef _DfProcessDart =
    int Function(Pointer<_DfState>, Pointer<Float>, Pointer<Float>, int);

typedef _DfFrameSizeC = Int32 Function(Pointer<_DfState>);
typedef _DfFrameSizeDart = int Function(Pointer<_DfState>);

typedef _DfSampleRateC = Int32 Function(Pointer<_DfState>);
typedef _DfSampleRateDart = int Function(Pointer<_DfState>);

typedef _DfIsRealC = Int32 Function();
typedef _DfIsRealDart = int Function();

typedef _DfDestroyC = Void Function(Pointer<_DfState>);
typedef _DfDestroyDart = void Function(Pointer<_DfState>);

typedef _DfApmSetEnabledC = Void Function(Int32);
typedef _DfApmSetEnabledDart = void Function(int);

typedef _DfApmIsAttachedC = Int32 Function();
typedef _DfApmIsAttachedDart = int Function();

typedef _DfSetAttenLimC = Void Function(Float);
typedef _DfSetAttenLimDart = void Function(double);

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

  static String get _pluginLibName {
    if (Platform.isWindows) return 'deepfilter_livekit_plugin.dll';
    if (Platform.isLinux) return 'libdeepfilter_livekit_plugin.so';
    if (Platform.isMacOS) return 'libdeepfilter_livekit_plugin.dylib';
    return '';
  }

  static DynamicLibrary _load() {
    if (_lib != null) {
      debugPrint('[df:bindings] _load: already loaded, returning cached');
      return _lib!;
    }

    final names = <String>[];
    final pluginName = _pluginLibName;
    if (pluginName.isNotEmpty) names.add(pluginName);
    names.add(_libName);

    for (final name in names) {
      debugPrint('[df:bindings] _load: trying "$name"');
      try {
        _lib = DynamicLibrary.open(name);
        debugPrint('[df:bindings] _load: SUCCESS with "$name"');
        return _lib!;
      } catch (e) {
        debugPrint('[df:bindings] _load: failed "$name": $e');
      }
    }

    throw DeepFilterException(
      'Failed to load DeepFilterNet library. '
      'Tried: ${names.join(', ')}.\n'
      'Ensure prebuilt binary is bundled for your platform.',
    );
  }

  static void init({String? modelPath, int sampleRate = 48000}) {
    debugPrint(
      '[df:bindings] init() called modelPath=$modelPath sampleRate=$sampleRate _initialized=$_initialized',
    );
    if (_initialized) {
      debugPrint('[df:bindings] init: already initialized, returning');
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      debugPrint('[df:bindings] init: mobile path, delegating to _initChannel');
      _initChannel(modelPath, sampleRate);
      return;
    }

    debugPrint('[df:bindings] init: desktop path, loading library');
    DynamicLibrary lib;
    try {
      lib = _load();
    } catch (e) {
      debugPrint('[df:bindings] init: _load() FAILED: $e');
      rethrow;
    }
    debugPrint('[df:bindings] init: lib loaded, looking up df_init symbol');
    final dfInit = lib
        .lookup<NativeFunction<_DfInitC>>('df_init')
        .asFunction<_DfInitDart>();
    debugPrint('[df:bindings] init: df_init symbol resolved');
    final dfFrameSize = lib
        .lookup<NativeFunction<_DfFrameSizeC>>('df_get_frame_size')
        .asFunction<_DfFrameSizeDart>();
    final dfSampleRate = lib
        .lookup<NativeFunction<_DfSampleRateC>>('df_get_sample_rate')
        .asFunction<_DfSampleRateDart>();

    final modelPtr = modelPath != null && modelPath.isNotEmpty
        ? modelPath.toNativeUtf8(allocator: calloc).cast<Int8>()
        : nullptr;
    debugPrint(
      '[df:bindings] init: calling dfInit (FFI) modelPtr=${modelPtr != nullptr ? "non-null" : "null"} sampleRate=$sampleRate',
    );
    _state = dfInit(modelPtr, sampleRate);
    debugPrint(
      '[df:bindings] init: dfInit returned state=${_state != null ? _state!.address : 0}',
    );
    if (modelPtr != nullptr) calloc.free(modelPtr);

    if (_state == nullptr || _state!.address == 0) {
      throw DeepFilterException(
        'df_init returned null state. Check model path: $modelPath',
      );
    }

    debugPrint('[df:bindings] init: querying frame size and sample rate');
    _frameSize = dfFrameSize(_state!);
    _sampleRate = dfSampleRate(_state!);
    _initialized = true;
    debugPrint(
      '[df:bindings] init: complete frameSize=$_frameSize sampleRate=$_sampleRate',
    );
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
      throw DeepFilterException(
        'DeepFilter not initialized. Call init() first.',
      );
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

  static Future<int> processFrameAsync(
    Float32List input,
    Float32List output,
  ) async {
    if (!_initialized) {
      throw DeepFilterException(
        'DeepFilter not initialized. Call init() first.',
      );
    }

    if (Platform.isAndroid || Platform.isIOS) {
      return _processChannel(input, output);
    }

    // Desktop: use sync FFI wrapped in a microtask
    return Future.sync(() => processFrame(input, output));
  }

  static Future<int> _processChannel(
    Float32List input,
    Float32List output,
  ) async {
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
      const MethodChannel(
        'io.deepfilter.livekit',
      ).invokeMethod<void>('dispose');
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

  /// Whether the real capi library was loaded (vs the pass-through stub).
  ///
  /// Returns `true` only when the DeepFilterNet capi `.dll`/`.so`/`.dylib`
  /// was found and its symbols resolved. When `false`, the stub fallback
  /// is in use — audio passes through unmodified.
  /// Sets the attenuation limit in dB. Lower = gentler suppression.
  ///
  /// Typical range 20–100 dB. Default 100 (maximum). Try 30–50 for
  /// keyboards/clicks while still suppressing background noise.
  static void setAttenLim(double limDb) {
    if (Platform.isAndroid || Platform.isIOS) return;
    try {
      final lib = _load();
      lib
          .lookup<NativeFunction<_DfSetAttenLimC>>('df_set_atten_lim_export')
          .asFunction<_DfSetAttenLimDart>()(limDb);
      debugPrint('[df:bindings] setAttenLim($limDb)');
    } catch (e) {
      debugPrint('[df:bindings] setAttenLim failed: $e');
    }
  }

  /// Enables or disables the WebRTC APM capture post-processing hook.
  ///
  /// When disabled, audio passes through the APM unmodified.
  /// Only has effect on desktop platforms where the APM hook is available.
  static void setApmEnabled(bool enabled) {
    if (Platform.isAndroid || Platform.isIOS) return;
    try {
      final lib = _load();
      lib
          .lookup<NativeFunction<_DfApmSetEnabledC>>('df_apm_set_enabled')
          .asFunction<_DfApmSetEnabledDart>()(enabled ? 1 : 0);
      debugPrint('[df:bindings] setApmEnabled($enabled)');
    } catch (e) {
      debugPrint('[df:bindings] setApmEnabled failed: $e');
    }
  }

  /// Whether the WebRTC APM capture post-processing hook is attached.
  static bool get isApmAttached {
    if (Platform.isAndroid || Platform.isIOS) return false;
    try {
      final lib = _load();
      return lib
              .lookup<NativeFunction<_DfApmIsAttachedC>>('df_apm_is_attached')
              .asFunction<_DfApmIsAttachedDart>()() !=
          0;
    } catch (_) {
      return false;
    }
  }

  static bool get isRealLibrary {
    if (Platform.isAndroid || Platform.isIOS) return true;
    try {
      final lib = _load();
      final fn = lib
          .lookup<NativeFunction<_DfIsRealC>>('df_is_real')
          .asFunction<_DfIsRealDart>();
      return fn() != 0;
    } catch (_) {
      return false;
    }
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
