import 'dart:typed_data';

import 'package:flutter/services.dart';

class DeepFilterException implements Exception {
  final String message;
  const DeepFilterException(this.message);

  @override
  String toString() => 'DeepFilterException: $message';
}

abstract final class DeepFilterNative {
  static int _frameSize = 0;
  static int _sampleRate = 48000;
  static bool _initialized = false;

  static void init({String? modelPath, int sampleRate = 48000}) {
    _sampleRate = sampleRate;
    _initialized = true;
  }

  static int processFrame(Float32List input, Float32List output) {
    if (!_initialized) {
      throw DeepFilterException('DeepFilter not initialized. Call init() first.');
    }
    return 0;
  }

  static Future<int> processFrameAsync(
    Float32List input,
    Float32List output,
  ) async {
    if (!_initialized) {
      throw DeepFilterException('DeepFilter not initialized. Call init() first.');
    }
    return 0;
  }

  static int get frameSize => _frameSize;
  static int get sampleRate => _sampleRate;

  static void dispose() {
    _frameSize = 0;
    _sampleRate = 48000;
    _initialized = false;
  }

  static void setAttenLim(double limDb) {}

  static void setApmEnabled(bool enabled) {}

  static bool get isApmAttached => false;
  static bool get isRealLibrary => false;
  static bool get isAvailable => false;
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
