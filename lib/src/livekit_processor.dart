import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';
import 'deepfilter_bindings.dart';

class DeepFilterProcessor implements TrackProcessor<AudioProcessorOptions> {
  @override
  String get name => 'DeepFilterNet';

  /// Whether the native DeepFilterNet library is available on this platform.
  /// Check this before attaching the processor.
  static bool get isSupported => DeepFilterNative.isAvailable;

  /// Whether the real capi library was loaded (vs the pass-through stub).
  ///
  /// When `false`, the adapter fallback is in use and audio passes through
  /// unmodified — usually because `deep_filter_lib.{dll,so,dylib}` is missing
  /// from the build output. Run `scripts/download_prebuilt.ps1` and rebuild.
  static bool get isRealLibrary => DeepFilterNative.isRealLibrary;

  /// Attach the WebRTC APM capture hook on Android.
  static Future<void> attachApmHook() => DeepFilterNative.attachApmHook();

  /// Whether the WebRTC APM capture hook is attached and processing is active.
  static bool get isApmAttached => DeepFilterNative.isApmAttached;

  /// Returns `null` — we do not replace the track.
  ///
  /// Processing happens **in-place at the native audio layer** (inside the
  /// platform plugin), not via Dart track replacement. The original
  /// [MediaStreamTrack] carries denoised audio because the native plugin
  /// intercepts and processes audio frames before WebRTC encoding.
  @override
  MediaStreamTrack? get processedTrack => null;

  int _frameSize = 0;

  /// Whether the processor is actively denoising.
  bool get isProcessing => _processing;
  bool _processing = false;

  /// Whether noise suppression is enabled.
  ///
  /// When `false`, [isProcessing] is `false` and audio passes through
  /// unmodified. Toggle at any time via [setEnabled].
  bool get enabled => _enabled;
  bool _enabled;

  DeepFilterProcessor({
    String? modelPath,
    int sampleRate = 48000,
    bool autoInit = true,
    bool enabled = true,
  }) : _enabled = enabled {
    debugPrint(
      '[df:processor] DeepFilterProcessor() autoInit=$autoInit modelPath=$modelPath sampleRate=$sampleRate',
    );
    if (autoInit) {
      debugPrint('[df:processor] calling DeepFilterNative.init()');
      DeepFilterNative.init(modelPath: modelPath, sampleRate: sampleRate);
      debugPrint('[df:processor] DeepFilterNative.init() returned');
    }
  }

  /// Enable or disable noise suppression at runtime.
  ///
  /// When disabled, [isProcessing] becomes `false` and audio passes through
  /// unmodified. When re-enabled while the track is still published,
  /// [isProcessing] returns to `true`. No processor lifecycle changes are
  /// needed — the same [DeepFilterProcessor] remains attached.
  void setEnabled(bool value) {
    _enabled = value;
    _processing = value;
    unawaited(DeepFilterNative.setApmEnabled(value));
  }

  @override
  Future<void> init(AudioProcessorOptions options) async {
    if (defaultTargetPlatform == TargetPlatform.android && isSupported) {
      await attachApmHook();
    }
    _frameSize = _frameSize > 0 ? _frameSize : DeepFilterNative.frameSize;
    if (_frameSize <= 0) _frameSize = 480;
  }

  @override
  Future<void> restart(AudioProcessorOptions options) async {
    await destroy();
    await init(options);
  }

  @override
  Future<void> destroy() async {
    _processing = false;
    await DeepFilterNative.setApmEnabled(false);
  }

  @override
  Future<void> onPublish(Room room) async {
    _processing = _enabled;
    await DeepFilterNative.setApmEnabled(_enabled);
  }

  @override
  Future<void> onUnpublish() async {
    _processing = false;
    await DeepFilterNative.setApmEnabled(false);
  }

  /// Process a raw PCM frame synchronously (desktop FFI only).
  /// Throws [DeepFilterException] on mobile — use [processAsync] instead.
  int process(Float32List input, Float32List output) {
    return DeepFilterNative.processFrame(input, output);
  }

  /// Process a raw PCM frame asynchronously (all platforms).
  Future<int> processAsync(Float32List input, Float32List output) {
    return DeepFilterNative.processFrameAsync(input, output);
  }
}

class LiveKitDeepFilter {
  DeepFilterProcessor? _processor;

  /// Whether the native DeepFilterNet library is available on this platform.
  static bool get isSupported => DeepFilterProcessor.isSupported;

  /// Whether the real capi library was loaded (vs the pass-through stub).
  static bool get isRealLibrary => DeepFilterProcessor.isRealLibrary;

  /// Whether the processor is actively denoising.
  bool get isProcessing => _processor?.isProcessing ?? false;

  /// Whether a processor instance exists.
  bool get isEnabled => _processor != null;

  /// The underlying processor, or `null`. Pass to [AudioCaptureOptions.processor]
  /// when enabling the microphone for automatic lifecycle management.
  DeepFilterProcessor? get processor => _processor;

  LiveKitDeepFilter();

  /// Create a processor. No-op if one already exists.
  ///
  /// Call before [Room] connection so the processor can be passed via
  /// [AudioCaptureOptions.processor]. This lets the LiveKit SDK handle
  /// [TrackProcessor.init], [TrackProcessor.onPublish], and
  /// [TrackProcessor.destroy] automatically.
  Future<void> enable({
    String? modelPath,
    int sampleRate = 48000,
    bool enabled = true,
  }) async {
    if (_processor != null) return;
    if (DeepFilterNative.isAvailable) {
      DeepFilterNative.init(modelPath: modelPath, sampleRate: sampleRate);
    }
    _processor = DeepFilterProcessor(
      modelPath: modelPath,
      sampleRate: sampleRate,
      autoInit: false,
      enabled: enabled,
    );
  }

  /// Destroy the processor. Call when leaving a voice channel.
  Future<void> disable() async {
    await _processor?.destroy();
    DeepFilterNative.dispose();
    _processor = null;
  }

  /// Toggle noise suppression at runtime.
  void setEnabled(bool value) {
    _processor?.setEnabled(value);
  }

  /// Attach the processor to an already-published local audio track.
  ///
  /// Used when enabling DeepFilter mid-call after joining without a processor.
  /// If the processor was passed via [AudioCaptureOptions.processer] at join
  /// time, the SDK manages the lifecycle and this is not needed.
  Future<void> attachToTrack(LocalAudioTrack track) async {
    if (_processor == null) return;
    await track.setProcessor(_processor!);
  }

  /// Detach the processor from a local audio track.
  Future<void> detachFromTrack(LocalAudioTrack track) async {
    await track.setProcessor(null);
  }

  void dispose() {
    unawaited(disable());
  }
}

final class DeepFilterMethodChannel {
  static const _channel = MethodChannel('io.deepfilter.livekit');

  static Future<bool> get isAvailable async {
    try {
      await _channel.invokeMethod<bool>('isAvailable');
      return true;
    } catch (_) {
      return false;
    }
  }
}
