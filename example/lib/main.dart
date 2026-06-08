import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:deepfilter_livekit/deepfilter_livekit.dart';

void main() {
  runApp(const DeepFilterExampleApp());
}

class DeepFilterExampleApp extends StatelessWidget {
  const DeepFilterExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DeepFilter + LiveKit',
      home: const DeepFilterDemo(),
    );
  }
}

class DeepFilterDemo extends StatefulWidget {
  const DeepFilterDemo({super.key});

  @override
  State<DeepFilterDemo> createState() => _DeepFilterDemoState();
}

class _DeepFilterDemoState extends State<DeepFilterDemo> {
  bool _inited = false;
  String _output = '';

  void _init() {
    try {
      DeepFilterNative.init(sampleRate: 48000);
      setState(() {
        _inited = true;
        _output = 'Initialized. Frame size: ${DeepFilterNative.frameSize}';
      });
    } catch (e) {
      setState(() => _output = 'Init failed: $e');
    }
  }

  void _process() {
    try {
      final size = DeepFilterNative.frameSize;
      if (size <= 0) {
        setState(() => _output = 'Invalid frame size');
        return;
      }
      final input = Float32List(size);
      final output = Float32List(size);
      input[0] = 0.5;
      DeepFilterNative.processFrame(input, output);
      setState(() => _output = 'Processed $size samples');
    } catch (e) {
      setState(() => _output = 'Process error: $e');
    }
  }

  void _dispose() {
    DeepFilterNative.dispose();
    setState(() {
      _inited = false;
      _output = 'Disposed';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('DeepFilterNet + LiveKit')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_output, style: const TextStyle(fontSize: 16)),
              const SizedBox(height: 24),

              // Init / Dispose controls
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                    onPressed: _inited ? null : _init,
                    child: const Text('Init'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _inited ? _process : null,
                    child: const Text('Process'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _inited ? _dispose : null,
                    child: const Text('Dispose'),
                  ),
                ],
              ),

              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),

              // TrackProcessor info
              Text(
                DeepFilterProcessor.isSupported
                    ? 'DeepFilterProcessor is available'
                    : 'DeepFilterProcessor NOT available\n(run download_prebuilt script)',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Usage in a LiveKit room:\n'
                '  await audioTrack.setProcessor(\n'
                '    DeepFilterProcessor(),\n'
                '  );',
                textAlign: TextAlign.center,
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
