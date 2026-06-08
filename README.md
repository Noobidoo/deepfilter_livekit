# deepfilter_livekit

Real-time neural network-based noise suppression for LiveKit Flutter using [DeepFilterNet](https://github.com/Rikorose/DeepFilterNet).

## Features

- Full `TrackProcessor<AudioProcessorOptions>` implementation — use via `audioTrack.setProcessor()`
- Native processing on all platforms (Windows, Linux, macOS, Android, iOS)
- Prebuilt library download scripts
- Manual per-frame processing API for custom audio pipelines

## Usage

```dart
import 'package:deepfilter_livekit/deepfilter_livekit.dart';
import 'package:livekit_client/livekit_client.dart';
```

### LiveKit TrackProcessor (recommended)

```dart
// 1. Check availability
if (!DeepFilterProcessor.isSupported) {
  // handle unsupported platform
}

// 2. Create processor and attach to a local audio track
final processor = DeepFilterProcessor();
await localAudioTrack.setProcessor(processor);

// Processing starts automatically — noise suppression
// runs natively before audio is published to the room.

// Remove processor when done
await localAudioTrack.stopProcessor();
```

### Low-level API

```dart
// Initialize
DeepFilterNative.init(sampleRate: 48000);

// Process raw PCM frames
final input = Float32List(480);
final output = Float32List(480);

// Desktop (synchronous FFI):
DeepFilterNative.processFrame(input, output);

// Cross-platform (async):
await DeepFilterNative.processFrameAsync(input, output);

// Clean up
DeepFilterNative.dispose();
```

### User-to-user voice chat

See the [user-to-user voice chat guide](docs/user-to-user-voice-chat.md) for a complete walkthrough with room setup, noise suppression, and a full Flutter UI example.

## Setup

1. Add dependency to `pubspec.yaml`:
```yaml
dependencies:
  deepfilter_livekit:
    path: ./deepfilter_livekit
```

2. Download prebuilt libraries:
```bash
# Windows PowerShell
.\scripts\download_prebuilt.ps1

# Linux/macOS
chmod +x scripts/download_prebuilt.sh
./scripts/download_prebuilt.sh
```

3. Place prebuilt binaries:
   - **Windows**: `windows/lib/deep_filter_lib.dll` + `.lib`
   - **Linux**: `linux/lib/libdeep_filter_lib.so`
   - **macOS**: `macos/lib/libdeep_filter_lib.dylib`
   - **Android**: `android/src/main/jniLibs/{abi}/libdeep_filter_lib.so`
   - **iOS**: bundled via podspec (`.a` or `.xcframework`)

## API

### `DeepFilterProcessor`
`TrackProcessor<AudioProcessorOptions>` implementation. Register via `LocalAudioTrack.setProcessor()`.

| Member | Description |
|--------|-------------|
| `DeepFilterProcessor.isSupported` | Whether native DeepFilterNet is available (static) |
| `name` | `'DeepFilterNet'` |
| `processedTrack` | Processed audio track (returns original track; native processing is transparent) |
| `init(options)` | Initialize processor with the audio track |
| `restart(options)` | Tear down and re-initialize |
| `destroy()` | Release processor resources |
| `onPublish(room)` | Lifecycle hook (currently no-op) |
| `onUnpublish()` | Calls `destroy()` |
| `process(input, output)` | Manual frame processing (sync, desktop only) |
| `processAsync(input, output)` | Manual frame processing (async, all platforms) |
| `isProcessing` | Whether the processor is initialized and active |

### `LiveKitDeepFilter`
High-level helper that wraps `DeepFilterProcessor` lifecycle.

| Member | Description |
|--------|-------------|
| `processor` | The underlying `DeepFilterProcessor` |
| `attach(track)` | Calls `track.setProcessor(processor)` |
| `detach(track)` | Calls `track.setProcessor(null)` |
| `enable()` | Create and attach a new processor |
| `disable()` | Destroy processor and dispose native resources |
| `dispose()` | Fire-and-forget `disable()` |
| `isEnabled` | Whether a processor exists |

### `DeepFilterNative`
Low-level FFI bindings. Used internally by `DeepFilterProcessor`.

### `DeepFilterMethodChannel`
MethodChannel helper for checking native availability from Dart.

## Platform Support

| Platform | Processing | Binary File |
|----------|-----------|-------------|
| Windows  | Native plugin (in-place) | `deep_filter_lib.dll` |
| Linux    | Native plugin (in-place) | `libdeep_filter_lib.so` |
| macOS    | Native plugin (in-place) | `libdeep_filter_lib.dylib` |
| Android  | Native plugin (in-place) | `libdeep_filter_lib.so` |
| iOS      | Native plugin (in-place) | `libdeep_filter_lib.a` |

Processing runs at the native audio layer on every platform — no Dart-side per-frame processing needed when using the `TrackProcessor` integration.

## Building from Source

```bash
git clone https://github.com/Rikorose/DeepFilterNet.git
cd DeepFilterNet
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build .
```

## License

MIT
