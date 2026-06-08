# User-to-User Voice Chat with DeepFilter LiveKit

This guide shows how to build a peer-to-peer voice chat app with real-time neural noise suppression using `deepfilter_livekit` and LiveKit.

## Architecture

```
User A (speaker)                        User B (listener)
┌──────────────────────────┐            ┌──────────────────────────┐
│  Microphone capture      │            │  Speaker output          │
│         ↓                │            │         ↑                │
│  Native audio processing │            │  (incoming stream)       │
│  (DeepFilterNet in-place)│  ┌──────┐  │                          │
│         ↓                │  │LiveKI│  │                          │
│  LocalAudioTrack         │──│Server│──│  RemoteAudioTrack        │
└──────────────────────────┘  └──────┘  └──────────────────────────┘
```

Noise suppression runs **natively before WebRTC encoding** — the remote user only hears clean audio, and there is zero Dart-side per-frame overhead during the call.

## Prerequisites

- Flutter 3.27+ / Dart 3.10+
- A LiveKit server (or [LiveKit Cloud](https://cloud.livekit.io))
- Prebuilt libraries downloaded via `scripts/download_prebuilt.ps1`
- A DeepFilterNet ONNX model (download from upstream `models/` directory)

## 1. Project Setup

### pubspec.yaml

```yaml
dependencies:
  flutter:
    sdk: flutter
  livekit_client: ^2.7.0
  deepfilter_livekit:
    path: ./deepfilter_livekit
```

### Download prebuilt binaries

```powershell
# Windows
.\scripts\download_prebuilt.ps1

# macOS/Linux
chmod +x scripts/download_prebuilt.sh
./scripts/download_prebuilt.sh
```

The script downloads `deep_filter_lib.dll` (Windows), `libdeep_filter_lib.so` (Linux), and `libdeep_filter_lib.dylib` (macOS) from the [Noobidoo/DeepFilterNet](https://github.com/Noobidoo/DeepFilterNet) fork release.

If a library is absent at runtime, the plugin automatically falls back to a pass-through stub — the app still works without noise suppression.

### Download an ONNX model

Prebuilt CI releases only include the capi library, not the model. Download a model separately:

```bash
# Download DeepFilterNet3 ONNX model
curl -fsSL https://github.com/Rikorose/DeepFilterNet/raw/main/models/DeepFilterNet3_onnx.tar.gz \
  -o windows/lib/models/DeepFilterNet3_onnx.tar.gz
```

Place the **tar.gz file** at `windows/lib/models/DeepFilterNet3_onnx.tar.gz`. CMake copies it to the
build output automatically. The adapter finds it at runtime — no `modelPath` argument needed.

## 2. Basic Voice Chat Service

Create a service that manages the LiveKit room and noise suppression:

```dart
import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:deepfilter_livekit/deepfilter_livekit.dart';

class VoiceChatService {
  Room? _room;
  LocalAudioTrack? _localTrack;
  DeepFilterProcessor? _processor;

  /// Connect to a LiveKit room and publish local audio
  Future<void> connect({
    required String url,
    required String token,
    String? modelPath,
    int sampleRate = 48000,
  }) async {
    if (!DeepFilterProcessor.isSupported) {
      debugPrint('DeepFilterNet not available on this platform');
    }

    // 1. Create the room and listen for incoming tracks
    _room = Room();
    _room?.on<RoomEvent>(RoomEvent.trackSubscribed, _onTrackSubscribed);

    // 2. Create local audio track
    _localTrack = await LocalAudioTrack.create();

    // 3. Create and attach noise suppression processor
    //    Processing starts when the track is published (onPublish).
    //    Set enabled: false to start muted and toggle later.
    _processor = DeepFilterProcessor(
      modelPath: modelPath,
      sampleRate: sampleRate,
      enabled: true,
    );
    await _localTrack!.setProcessor(_processor);

    // Optional: verify processing is fully active
    if (DeepFilterProcessor.isRealLibrary) {
      debugPrint('DeepFilter capi loaded. APM hook: ${DeepFilterProcessor.isApmAttached}');
      // Tune suppression strength if needed (default 100 dB = max)
      // DeepFilterNative.setAttenLim(60.0); // moderate
    }

    // 4. Connect to LiveKit room and publish audio
    await _room?.connect(url, token, options: RoomOptions(
      defaultAudioPublishOptions: AudioPublishOptions(
        dtx: false,
      ),
    ));

    await _room?.localParticipant?.publishTrack(_localTrack);
    debugPrint('Connected to room: ${_room?.name}');
  }

  /// Toggle noise suppression at runtime
  void toggleNoiseSuppression(bool active) {
    _processor?.setEnabled(active);
  }

  /// Handle incoming remote audio tracks
  void _onTrackSubscribed(RoomEvent event) {
    final subscription = event.value as TrackSubscription;
    if (subscription.track is RemoteAudioTrack) {
      final remoteAudio = subscription.track as RemoteAudioTrack;
      remoteAudio.play();
      debugPrint('Remote audio track subscribed: ${remoteAudio.sid}');
    }
  }

  /// Mute/unmute local microphone
  Future<void> setMuted(bool muted) async {
    await _localTrack?.setEnabled(!muted);
  }

  /// Disconnect and clean up
  Future<void> disconnect() async {
    if (_processor != null) {
      await _localTrack?.stopProcessor();
      await _processor?.destroy();
    }
    await _room?.disconnect();
    _room?.dispose();
    _localTrack = null;
    _processor = null;
    _room = null;
  }

  bool get isConnected => _room?.connectionState == ConnectionState.connected;
}
```

## 3. Full UI Example

```dart
import 'package:flutter/material.dart';
import 'voice_chat_service.dart';

class VoiceChatScreen extends StatefulWidget {
  final String liveKitUrl;
  final String token;
  const VoiceChatScreen({
    super.key,
    required this.liveKitUrl,
    required this.token,
  });

  @override
  State<VoiceChatScreen> createState() => _VoiceChatScreenState();
}

class _VoiceChatScreenState extends State<VoiceChatScreen> {
  final _service = VoiceChatService();
  bool _connecting = false;
  bool _connected = false;
  bool _muted = false;
  bool _suppression = true;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      await _service.connect(
        url: widget.liveKitUrl,
        token: widget.token,
      );
      setState(() => _connected = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connection failed: $e')),
        );
      }
    } finally {
      setState(() => _connecting = false);
    }
  }

  @override
  void dispose() {
    _service.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voice Chat')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _connected ? Icons.headset : Icons.headset_off,
              size: 80,
              color: _connected ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: 24),
            Text(
              _connecting
                  ? 'Connecting...'
                  : _connected
                      ? 'Connected — noise suppression active'
                      : 'Disconnected',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 32),
            if (_connected) ...[
              // Mute toggle
              IconButton(
                icon: Icon(
                  _muted ? Icons.mic_off : Icons.mic,
                  size: 48,
                ),
                onPressed: () async {
                  await _service.setMuted(!_muted);
                  setState(() => _muted = !_muted);
                },
              ),
              const SizedBox(height: 16),
              // Noise suppression toggle
              SwitchListTile(
                title: const Text('Noise Suppression'),
                subtitle: Text(_suppression ? 'Active' : 'Bypassed'),
                value: _suppression,
                onChanged: (v) {
                  _service.toggleNoiseSuppression(v);
                  setState(() => _suppression = v);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

## 4. Obtaining a LiveKit Token

For a user-to-user chat, each participant needs a token. Below are two approaches.

### Using a LiveKit Cloud token endpoint

```dart
class TokenService {
  static Future<String> fetchToken({
    required String serverUrl,
    required String roomName,
    required String identity,
  }) async {
    final uri = Uri.parse('$serverUrl/token').replace(queryParameters: {
      'room': roomName,
      'identity': identity,
    });
    final response = await http.get(uri);
    return response.body;
  }
}
```

### Server-side token generation (Node.js example)

```js
const { AccessToken } = require('livekit-server-sdk');

const apiKey = process.env.LIVEKIT_API_KEY;
const apiSecret = process.env.LIVEKIT_API_SECRET;

app.get('/token', (req, res) => {
  const { room, identity } = req.query;
  const at = new AccessToken(apiKey, apiSecret, {
    identity,
    ttl: '1h',
  });
  at.addGrant({ roomJoin: true, room, canPublish: true, canSubscribe: true });
  res.json({ token: at.toJwt() });
});
```

## 5. Platform-Specific Notes

On all supported platforms the processing runs **natively at the audio layer** — the platform plugin dynamically loads the capi library at runtime and applies DeepFilterNet in-place before WebRTC encoding.

| Platform | Binary | Loading | Status |
|----------|--------|---------|--------|
| Windows | `deep_filter_lib.dll` | `LoadLibrary` + `GetProcAddress` | Supported |
| Linux | `libdeep_filter_lib.so` | `dlopen` + `dlsym` | Supported |
| macOS | `libdeep_filter_lib.dylib` | `dlopen` + `dlsym` | Supported |
| Android | `libdeep_filter_lib.so` | `dlopen` (via JNI) | CI not yet building |
| iOS | `libdeep_filter_lib.dylib` | `dlopen` | CI not yet building |

When the capi library is absent, each adapter falls back to a simple pass-through stub — audio flows unmodified.

### Runtime enable/disable

```dart
final processor = DeepFilterProcessor(enabled: true);
await track.setProcessor(processor);

// Bypass without detaching
processor.setEnabled(false);

// Re-enable
processor.setEnabled(true);
```

The `enabled` constructor parameter (default `true`) avoids a transient period of active processing on connect. `setEnabled()` toggles processing without detaching the processor from the track.

### Model path

```dart
DeepFilterProcessor(modelPath: 'assets/models/DeepFilterNet3')
```

If no model path is given, the capi library uses its built-in default model.

### Custom audio pipelines

```dart
final processor = DeepFilterProcessor();

// Desktop (sync FFI):
processor.process(input, output);

// All platforms (async):
await processor.processAsync(input, output);
```

### Checking availability at runtime

```dart
if (DeepFilterProcessor.isSupported) {
  final processor = DeepFilterProcessor();
  await track.setProcessor(processor);
} else {
  debugPrint('DeepFilterNet not available on this platform');
}
```

## 6. Full Example: Run Two Instances Locally

1. **Start a LiveKit server locally:**
   ```bash
   docker run --rm -p 7880:7880 -p 7881:7881 \
     -e LIVEKIT_KEYS="devkey: secret" \
     livekit/livekit-server --dev
   ```

2. **Generate tokens:**
   ```dart
   // User A
   final tokenA = await TokenService.fetchToken(
     serverUrl: 'http://localhost:7880',
     roomName: 'my-room',
     identity: 'Alice',
   );

   // User B
   final tokenB = await TokenService.fetchToken(
     serverUrl: 'http://localhost:7880',
     roomName: 'my-room',
     identity: 'Bob',
   );
   ```

3. **Launch VoiceChatScreen on two devices:**
   ```dart
   MaterialApp(
     home: VoiceChatScreen(
       liveKitUrl: 'ws://localhost:7880',
       token: tokenA,  // or tokenB
     ),
   )
   ```

## 7. Troubleshooting

| Symptom | Likely Cause | Fix |
|---------|-------------|-----|
| `DeepFilterException: Failed to load library` | Prebuilt binary not in expected path | Run `scripts/download_prebuilt.ps1` |
| `DeepFilterProcessor.isSupported` is `false` | Binary missing or wrong arch | Verify binary paths in platform folders |
| No audio from remote | Muted or track not published | Check `localParticipant.publishTrack()` |
| Echo / feedback | Suppression applied to playback | Only call `setProcessor()` on the **local** track |
| `processFrame()` throws on mobile | Sync API not available on mobile | Use `processAsync()` or rely on native `TrackProcessor` integration |
| Audio still noisy but `isProcessing` is `true` | Library falls back to pass-through stub | Confirm capi library exists at the expected path; check `dlopen`/`LoadLibrary` logs |
