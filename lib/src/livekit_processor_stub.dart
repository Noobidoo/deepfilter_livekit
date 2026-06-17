import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:livekit_client/livekit_client.dart';

class DeepFilterProcessor implements TrackProcessor<AudioProcessorOptions> {
  @override
  String get name => 'DeepFilterNet';

  static bool get isSupported => false;
  static bool get isRealLibrary => false;
  static Future<void> attachApmHook() async {}
  static bool get isApmAttached => false;

  @override
  MediaStreamTrack? get processedTrack => null;

  bool get isProcessing => false;
  bool get enabled => _enabled;
  bool _enabled;

  DeepFilterProcessor({
    String? modelPath,
    int sampleRate = 48000,
    bool autoInit = true,
    bool enabled = true,
  }) : _enabled = enabled;

  void setEnabled(bool value) {
    _enabled = value;
  }

  @override
  Future<void> init(AudioProcessorOptions options) async {}

  @override
  Future<void> restart(AudioProcessorOptions options) async {}

  @override
  Future<void> destroy() async {
    _enabled = false;
  }

  @override
  Future<void> onPublish(Room room) async {}

  @override
  Future<void> onUnpublish() async {
    _enabled = false;
  }

  int process(Float32List input, Float32List output) => 0;

  Future<int> processAsync(Float32List input, Float32List output) async => 0;
}

class LiveKitDeepFilter {
  DeepFilterProcessor? _processor;

  LiveKitDeepFilter();

  static bool get isSupported => false;
  static bool get isRealLibrary => false;

  bool get isProcessing => false;
  bool get isEnabled => _processor != null;

  DeepFilterProcessor? get processor => _processor;

  Future<void> enable({
    String? modelPath,
    int sampleRate = 48000,
    bool enabled = true,
  }) async {}

  Future<void> disable() async {
    await _processor?.destroy();
    _processor = null;
  }

  void setEnabled(bool value) {}

  Future<void> attachToTrack(LocalAudioTrack track) async {}

  Future<void> detachFromTrack(LocalAudioTrack track) async {}

  void dispose() {
    unawaited(disable());
  }
}

