import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:deepfilter_livekit/deepfilter_livekit.dart';
import 'package:livekit_client/livekit_client.dart' show Room;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('LiveKitDeepFilter lifecycle', () {
    test('multiple enable/disable cycles', () async {
      final lk = LiveKitDeepFilter();
      expect(lk.isEnabled, false);

      for (int i = 0; i < 3; i++) {
        await lk.enable(modelPath: null, sampleRate: 48000);
        expect(lk.isEnabled, true);

        await lk.disable();
        expect(lk.isEnabled, false);
      }

      lk.dispose();
    });

    test('enable is no-op when already enabled', () async {
      final lk = LiveKitDeepFilter();
      expect(lk.isEnabled, false);
      await lk.enable();
      expect(lk.isEnabled, true);
      await lk.enable();
      expect(lk.isEnabled, true);
      lk.dispose();
    });

    test('disable when already disabled is safe', () async {
      final lk = LiveKitDeepFilter();
      await lk.disable();
      await lk.disable();
      expect(lk.isEnabled, false);
      lk.dispose();
    });

    test(
      'dispose only schedules async disable, isEnabled remains true',
      () async {
        final lk = LiveKitDeepFilter();
        await lk.enable();
        lk.dispose();
        expect(lk.isEnabled, true);
      },
    );

    test('processor is null after disable', () async {
      final lk = LiveKitDeepFilter();
      expect(lk.processor, isNull);
      await lk.enable();
      expect(lk.processor, isNotNull);
      await lk.disable();
      expect(lk.processor, isNull);
      lk.dispose();
    });

    test('processor is reassigned after re-enable', () async {
      final lk = LiveKitDeepFilter();
      await lk.enable();
      final p1 = lk.processor;
      await lk.disable();
      await lk.enable();
      final p2 = lk.processor;
      expect(p1, isNotNull);
      expect(p2, isNotNull);
      expect(p1, isNot(equals(p2)));
      lk.dispose();
    });
  });

  group('DeepFilterProcessor lifecycle', () {
    test('isProcessing is false by default', () {
      final processor = DeepFilterProcessor(autoInit: false);
      expect(processor.isProcessing, false);
    });

    test('enabled is true by default', () {
      final processor = DeepFilterProcessor(autoInit: false);
      expect(processor.enabled, true);
    });

    test('enabled can be set to false in constructor', () {
      final processor = DeepFilterProcessor(autoInit: false, enabled: false);
      expect(processor.enabled, false);
      expect(processor.isProcessing, false);
    });

    test(
      'onPublish respects enabled — when false, isProcessing stays false',
      () async {
        final processor = DeepFilterProcessor(autoInit: false, enabled: false);
        await processor.onPublish(Room());
        expect(processor.isProcessing, false);
      },
    );

    test('onPublish sets isProcessing true when enabled is true', () async {
      final processor = DeepFilterProcessor(autoInit: false);
      await processor.onPublish(Room());
      expect(processor.isProcessing, true);
    });

    test('setEnabled(false) stops processing while published', () async {
      final processor = DeepFilterProcessor(autoInit: false);
      await processor.onPublish(Room());
      expect(processor.isProcessing, true);

      processor.setEnabled(false);
      expect(processor.enabled, false);
      expect(processor.isProcessing, false);
    });

    test(
      'setEnabled(true) resumes processing after toggle if published',
      () async {
        final processor = DeepFilterProcessor(autoInit: false);
        await processor.onPublish(Room());
        processor.setEnabled(false);
        expect(processor.isProcessing, false);

        processor.setEnabled(true);
        expect(processor.enabled, true);
        expect(processor.isProcessing, true);
      },
    );

    test(
      'setEnabled(true) does not start processing when not published',
      () async {
        final processor = DeepFilterProcessor(autoInit: false, enabled: false);
        processor.setEnabled(true);
        expect(processor.enabled, true);
        expect(processor.isProcessing, false);
      },
    );

    test('destroy before init is safe', () async {
      final processor = DeepFilterProcessor(autoInit: false);
      await processor.destroy();
      expect(processor.isProcessing, false);
      await processor.destroy();
    });

    test('onUnpublish is safe without prior publish', () async {
      final processor = DeepFilterProcessor(autoInit: false);
      await processor.onUnpublish();
      expect(processor.isProcessing, false);
      await processor.destroy();
    });

    test('destroy resets isProcessing and published state', () async {
      final processor = DeepFilterProcessor(autoInit: false);
      await processor.onPublish(Room());
      expect(processor.isProcessing, true);

      await processor.destroy();
      expect(processor.isProcessing, false);

      processor.setEnabled(false);
      processor.setEnabled(true);
      expect(
        processor.isProcessing,
        false,
        reason: 'was unpublished by destroy',
      );
    });

    test('processedTrack always returns null', () {
      final processor = DeepFilterProcessor(autoInit: false);
      expect(processor.processedTrack, isNull);
    });

    test('processFrame without init throws', () {
      final processor = DeepFilterProcessor(autoInit: false);
      expect(
        () => processor.process(Float32List(480), Float32List(480)),
        throwsA(isA<DeepFilterException>()),
      );
    });

    test('processAsync without init throws', () async {
      final processor = DeepFilterProcessor(autoInit: false);
      expect(
        () => processor.processAsync(Float32List(480), Float32List(480)),
        throwsA(isA<DeepFilterException>()),
      );
    });
  });

  group('MethodChannel processFrame protocol', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('io.deepfilter.livekit'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'processFrame') {
                final inputBytes = methodCall.arguments['input'] as Uint8List;
                final outputBytes = Uint8List.fromList(inputBytes);
                return <String, dynamic>{'output': outputBytes, 'ret': 0};
              }
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('io.deepfilter.livekit'),
            null,
          );
    });

    test('protocol sends only input (no output arg)', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('io.deepfilter.livekit'),
            (MethodCall call) async {
              calls.add(call);
              if (call.method == 'processFrame') {
                final inputBytes = call.arguments['input'] as Uint8List;
                return <String, dynamic>{
                  'output': Uint8List.fromList(inputBytes),
                  'ret': 0,
                };
              }
              return null;
            },
          );

      const channel = MethodChannel('io.deepfilter.livekit');
      await channel.invokeMethod('processFrame', {
        'input': Float32List(480).buffer.asUint8List(),
      });

      expect(calls.length, 1);
      expect(calls[0].arguments.containsKey('input'), true);
      expect(calls[0].arguments.containsKey('output'), false);
    });

    test('protocol returns output data with same size as input', () async {
      const channel = MethodChannel('io.deepfilter.livekit');
      final input = Float32List(480);
      final inputBytes = input.buffer.asUint8List();

      final result = await channel.invokeMethod('processFrame', {
        'input': inputBytes,
      });

      final resultMap = result as Map;
      final outBytes = resultMap['output'] as Uint8List;
      final ret = resultMap['ret'] as int;

      expect(ret, 0);
      expect(outBytes.length, inputBytes.length);
    });

    test('protocol output bytes match input bytes after round-trip', () async {
      const channel = MethodChannel('io.deepfilter.livekit');
      final input = Float32List.fromList([0.75, -0.25, 1.0, -1.0]);
      final inputBytes = input.buffer.asUint8List();

      final result = await channel.invokeMethod('processFrame', {
        'input': inputBytes,
      });

      final resultMap = result as Map;
      final outBytes = resultMap['output'] as Uint8List;

      for (int i = 0; i < inputBytes.length; i++) {
        expect(outBytes[i], inputBytes[i]);
      }
    });

    test('protocol returns -1 when result is null', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('io.deepfilter.livekit'),
            (MethodCall methodCall) async => null,
          );

      const channel = MethodChannel('io.deepfilter.livekit');
      final result = await channel.invokeMethod('processFrame', {
        'input': Float32List(480).buffer.asUint8List(),
      });
      expect(result, isNull);
    });
  });

  group('DeepFilterMethodChannel', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('io.deepfilter.livekit'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'isAvailable') return true;
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('io.deepfilter.livekit'),
            null,
          );
    });

    test('isAvailable returns mocked value', () async {
      final available = await DeepFilterMethodChannel.isAvailable;
      expect(available, true);
    });

    test('isAvailable returns false on error', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('io.deepfilter.livekit'),
            (MethodCall methodCall) async =>
                throw PlatformException(code: 'NOT_FOUND'),
          );

      final available = await DeepFilterMethodChannel.isAvailable;
      expect(available, false);
    });
  });

  group('DeepFilterNative init channel', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('io.deepfilter.livekit'),
            (MethodCall methodCall) async {
              if (methodCall.method == 'init') return 'ok';
              if (methodCall.method == 'dispose') return null;
              return null;
            },
          );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('io.deepfilter.livekit'),
            null,
          );
    });

    test('init sends correct channel args', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('io.deepfilter.livekit'),
            (MethodCall call) async {
              calls.add(call);
              if (call.method == 'init') return 'ok';
              return null;
            },
          );

      const channel = MethodChannel('io.deepfilter.livekit');
      await channel.invokeMethod<String>('init', {
        'modelPath': '/custom/model.onnx',
        'sampleRate': 16000,
      });

      expect(calls.length, 1);
      expect(calls[0].method, 'init');
      expect(calls[0].arguments['modelPath'], '/custom/model.onnx');
      expect(calls[0].arguments['sampleRate'], 16000);
    });
  });

  group('DeepFilterNative state management', () {
    test('processFrame throws when not initialized', () {
      expect(
        () => DeepFilterNative.processFrame(Float32List(480), Float32List(480)),
        throwsA(isA<DeepFilterException>()),
      );
    });

    test('processFrameAsync throws when not initialized', () async {
      expect(
        () => DeepFilterNative.processFrameAsync(
          Float32List(480),
          Float32List(480),
        ),
        throwsA(isA<DeepFilterException>()),
      );
    });

    test('dispose resets initialized flag', () {
      DeepFilterNative.dispose();
      expect(
        () => DeepFilterNative.processFrame(Float32List(480), Float32List(480)),
        throwsA(isA<DeepFilterException>()),
      );
    });

    test('dispose multiple times is safe', () {
      DeepFilterNative.dispose();
      DeepFilterNative.dispose();
    });

    test('dispose resets sampleRate to default', () {
      DeepFilterNative.dispose();
      expect(DeepFilterNative.sampleRate, 48000);
    });

    test('frameSize is 0 after dispose', () {
      DeepFilterNative.dispose();
      expect(DeepFilterNative.frameSize, 0);
    });

    test('sampleRate has default value', () {
      expect(DeepFilterNative.sampleRate, 48000);
    });

    test('frameSize is 0 before init', () {
      expect(DeepFilterNative.frameSize, 0);
    });

    test('isAvailable does not throw', () {
      expect(DeepFilterNative.isAvailable, anyOf(true, false));
    });
  });
}
