# deepfilter_livekit

Real-time neural network-based noise suppression for LiveKit Flutter using [DeepFilterNet](https://github.com/Rikorose/DeepFilterNet).

## Features

- Full `TrackProcessor<AudioProcessorOptions>` implementation — use via `audioTrack.setProcessor()`
- Native processing via WebRTC APM capture hook on Windows, Linux, macOS
- Runtime enable/disable toggle
- Adjustable attenuation limit — tune suppression strength without rebuilding
- Dynamic library loading with automatic pass-through fallback
- Prebuilt library download scripts (fork CI)
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

// 2. Create processor (disabled initially, enable when ready)
final processor = DeepFilterProcessor(enabled: true);
await localAudioTrack.setProcessor(processor);

// Processing starts automatically on publish —
// noise suppression runs natively via WebRTC APM before audio is encoded.

// Check processing is fully active
if (DeepFilterProcessor.isRealLibrary && DeepFilterProcessor.isApmAttached) {
  // Real capi loaded and APM hook installed — suppression is live
}

// Toggle at runtime
processor.setEnabled(false); // passthrough, no processing
processor.setEnabled(true);  // resume processing

// Remove processor when done
await localAudioTrack.stopProcessor();
```

### Low-level API

```dart
// Initialize with optional model path
DeepFilterNative.init(sampleRate: 48000, modelPath: 'path/to/model_dir');

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

3. Place prebuilt binaries (or let the download script do it):
   - **Windows**: `windows/lib/deep_filter_lib.dll`
   - **Linux**: `linux/lib/libdeep_filter_lib.so`
   - **macOS**: `macos/lib/libdeep_filter_lib.dylib`

   When the library is absent, the plugin falls back to a pass-through stub automatically.

4. Download the ONNX model:
   - The download scripts install libraries only, not models.
   - Download a model from `https://github.com/Rikorose/DeepFilterNet/tree/main/models` (e.g. `DeepFilterNet3_onnx.tar.gz`)
   - Place the **tar.gz file** at `windows/lib/models/DeepFilterNet3_onnx.tar.gz` (Windows) — CMake copies it to the build output automatically
   - The adapter auto-discovers the tar.gz at runtime; no `modelPath` argument needed

## API

### `DeepFilterProcessor`
`TrackProcessor<AudioProcessorOptions>` implementation. Register via `LocalAudioTrack.setProcessor()`.

| Member | Description |
|--------|-------------|
| `DeepFilterProcessor.isSupported` | Whether native DeepFilterNet is available (static) |
| `DeepFilterProcessor.isRealLibrary` | Whether the real capi library was loaded (not the stub) |
| `DeepFilterProcessor.isApmAttached` | Whether the WebRTC APM capture hook is installed and processing frames |
| `name` | `'DeepFilterNet'` |
| `processedTrack` | Always returns `null` — processing is in-place via APM hook |
| `enabled` | Whether processing is active (default `true`); can be set via constructor |
| `setEnabled(bool)` | Toggle processing at runtime; passthrough when disabled |
| `init(options)` | Initialize processor state (does not start processing) |
| `restart(options)` | Tear down and re-initialize |
| `destroy()` | Release processor resources |
| `onPublish(room)` | Start processing when track is published |
| `onUnpublish()` | Stop processing when track is unpublished |
| `process(input, output)` | Manual frame processing (sync, desktop only) |
| `processAsync(input, output)` | Manual frame processing (async, all platforms) |
| `isProcessing` | Whether the processor is both enabled and published |

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

| Member | Description |
|--------|-------------|
| `setAttenLim(double db)` | Set attenuation limit in dB (default 100). Lower = gentler suppression. |
| `setApmEnabled(bool)` | Enable/disable APM hook (called automatically by `setEnabled`). |
| `isApmAttached` | Whether APM hook is installed. |
| `isRealLibrary` | Whether real capi library was loaded. |

### `DeepFilterMethodChannel`
MethodChannel helper for checking native availability from Dart.

## Platform Support

| Platform | Processing | Binary File | Status |
|----------|-----------|-------------|--------|
| Windows  | Native plugin (in-place) | `deep_filter_lib.dll` | Supported |
| Linux    | Native plugin (in-place) | `libdeep_filter_lib.so` | Supported |
| macOS    | Native plugin (in-place) | `libdeep_filter_lib.dylib` | Supported |
| Android  | MethodChannel (planned) | `libdeep_filter_lib.so` | CI not yet building |
| iOS      | MethodChannel (planned) | `libdeep_filter_lib.dylib` | CI not yet building |

Processing runs at the native audio layer — no Dart-side per-frame overhead when using the `TrackProcessor` integration. Each platform's adapter dynamically loads the capi library at runtime and falls back to a pass-through stub when the library is absent.

## Runtime Enable/Disable

```dart
final processor = DeepFilterProcessor(enabled: true);
// ... attach to track ...

// Disable noise suppression (passthrough)
processor.setEnabled(false);

// Re-enable
processor.setEnabled(true);
```

`isProcessing` reflects the combined state: `enabled && published`. Processing only starts after `onPublish()` is called, even if `enabled` is `true`.

## Tuning Suppression Strength

`atten_lim` controls how aggressively background noise is attenuated. Default is `100 dB` (maximum). Lower values pass more background through — useful when keyboard clicks or mechanical noise are being over-suppressed.

```dart
// Set at any time after init — takes effect immediately
DeepFilterNative.setAttenLim(40.0);  // gentle: fans removed, keyboard mostly audible
DeepFilterNative.setAttenLim(60.0);  // moderate — recommended starting point
DeepFilterNative.setAttenLim(100.0); // maximum (default)
```

Typical workflow: start at **60 dB** and tune down if mechanical sounds (keyboard, mouse clicks) are being suppressed along with wanted audio.

## Building the capi Library from Source

The capi library is built from the [Noobidoo/DeepFilterNet](https://github.com/Noobidoo/DeepFilterNet) fork:

```bash
git clone https://github.com/Noobidoo/DeepFilterNet.git
cd DeepFilterNet
cargo build --release -p libdf --features capi
```

The output is at `target/release/deep_filter_lib.{dll,so,dylib}` (or `target/release/libdeep_filter_lib.so` on Linux).

Prebuilt binaries are published at each fork [release](https://github.com/Noobidoo/DeepFilterNet/releases).

## Citation

This plugin bundles the **DeepFilterNet3** neural noise suppression model. If you use it in your research or application, please cite the original paper:

> H. Schröter, T. Rosenkranz, A. N. Escalante-B. and A. Maier, "DeepFilterNet: Perceptually Motivated Real-Time Speech Enhancement," in *INTERSPEECH*, 2023.

```bibtex
@inproceedings{schroeter2023deepfilternet3,
  title = {{DeepFilterNet}: Perceptually Motivated Real-Time Speech Enhancement},
  author = {Schröter, Hendrik and Rosenkranz, Tobias and Escalante-B., Alberto N. and Maier, Andreas},
  booktitle = {INTERSPEECH},
  year = {2023},
}
```

## License

MIT
