import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:deepfilter_livekit/deepfilter_livekit.dart';

void main() {
  group('DeepFilterBindings', () {
    test('isAvailable returns false when library not bundled', () {
      // In test environment, the native library won't be available
      expect(DeepFilterNative.isAvailable, false);
    });

    test('processFrame throws when not initialized', () {
      expect(
        () => DeepFilterNative.processFrame(Float32List(480), Float32List(480)),
        throwsA(isA<DeepFilterException>()),
      );
    });

    test('frameSize is 0 before init', () {
      expect(DeepFilterNative.frameSize, 0);
    });

    test('sampleRate has default value', () {
      expect(DeepFilterNative.sampleRate, 48000);
    });

    test('dispose is safe when not initialized', () {
      expect(DeepFilterNative.dispose, returnsNormally);
    });
  });

  group('DeepFilterProcessor', () {
    test('can be instantiated without model', () {
      final processor = DeepFilterProcessor(autoInit: false);
      expect(processor.name, 'DeepFilterNet');
      expect(DeepFilterProcessor.isSupported, anyOf(true, false));
      expect(processor.processedTrack, isNull); // null before init
    });

    test('destroy is safe before init', () async {
      final processor = DeepFilterProcessor(autoInit: false);
      await processor.destroy();
    });
  });

  group('LiveKitDeepFilter', () {
    test('can be created with defaults', () {
      final lk = LiveKitDeepFilter();
      expect(lk.isEnabled, true);
      expect(lk.processor, isNotNull);
      lk.dispose();
    });

    test('disable and enable lifecycle', () async {
      final lk = LiveKitDeepFilter();
      expect(lk.isEnabled, true);
      await lk.disable();
      expect(lk.isEnabled, false);
      await lk.enable();
      expect(lk.isEnabled, true);
      lk.dispose();
    });
  });

  group('DeepFilterMethodChannel', () {
    test('isAvailable returns false in test environment', () async {
      final available = await DeepFilterMethodChannel.isAvailable;
      expect(available, false);
    });
  });
}
