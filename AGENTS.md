# Agent Guide: deepfilter_livekit Integration

Real-time neural noise suppression for LiveKit Flutter using DeepFilterNet.

## Dependency

```yaml
dependencies:
  deepfilter_livekit:
    path: ./deepfilter_livekit   # or git/pub version
```

## Prebuilt Libraries

```powershell
# Windows
.\scripts\download_prebuilt.ps1

# Linux/macOS
chmod +x scripts/download_prebuilt.sh
./scripts/download_prebuilt.sh
```

Downloads `deep_filter_lib.dll`, `libdeep_filter_lib.so`, `libdeep_filter_lib.dylib`
from the [Noobidoo/DeepFilterNet](https://github.com/Noobidoo/DeepFilterNet) fork
release v0.5.7-capi.1.

## Deploy Model in Your App (Desktop)

The model tar.gz must be copied next to the runner EXE so the adapter's
auto-discovery can find it. Add this to your **runner's CMakeLists.txt**
(e.g. `windows/runner/CMakeLists.txt` or `linux/CMakeLists.txt`):

```cmake
# Windows runner: windows/runner/CMakeLists.txt
set(PLUGIN_MODELS_DIR "${FLUTTER_MANAGED_DIR}/ephemeral/.plugin_symlinks/deepfilter_livekit/assets/models")
if(EXISTS "${PLUGIN_MODELS_DIR}/DeepFilterNet3_onnx.tar.gz")
  add_custom_command(TARGET ${BINARY_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_directory
      "${PLUGIN_MODELS_DIR}"
      "$<TARGET_FILE_DIR:${BINARY_NAME}>/models"
    COMMENT "deepfilter_adapter: copying models to runner output"
  )
endif()
```

The adapter auto-discovers the model by checking:
1. `<plugin-dll-dir>/models/` (same dir as `deepfilter_livekit_plugin.*`)
2. `<exe-dir>/models/` (same dir as the runner EXE)

One of these must contain `DeepFilterNet3_onnx.tar.gz`.

## Model

Download an ONNX model separately from
[upstream models/](https://github.com/Rikorose/DeepFilterNet/tree/main/models):

```bash
curl -fsSL https://github.com/Rikorose/DeepFilterNet/raw/main/models/DeepFilterNet3_onnx.tar.gz \
  -o assets/models/DeepFilterNet3_onnx.tar.gz
cd assets/models && tar -xzf DeepFilterNet3_onnx.tar.gz && cd ../..
```

Pass `modelPath: 'assets/models/DeepFilterNet3_onnx.tar.gz'` (the **tar.gz file path**) to `DeepFilterProcessor`.

## Quick Start

```dart
import 'package:deepfilter_livekit/deepfilter_livekit.dart';

final processor = DeepFilterProcessor(modelPath: 'assets/models/export');
await localAudioTrack.setProcessor(processor);
```

Processing starts when the track is published (LiveKit calls `onPublish`).
No manual frame loop needed — processing is in-place at the native layer.

## Verify It's Working

```dart
if (!DeepFilterProcessor.isRealLibrary) {
  // capi library not loaded — audio passes through unmodified.
  // Check that deep_filter_lib.{dll,so,dylib} exists in the build output.
}
if (!DeepFilterProcessor.isApmAttached) {
  // Library loaded but APM hook not attached yet.
  // Hook attaches automatically after df_init succeeds on first connect.
}
```

`isRealLibrary` — real capi found and loaded.  
`isApmAttached` — WebRTC APM capture hook installed; frames actively processed.

## Tuning Suppression Strength

`atten_lim` (dB) controls how aggressively background noise is attenuated.
Default is `100` (maximum). Lower values = gentler suppression — good when
keyboard clicks or chair creaks pass through at max setting.

```dart
// Set at any time after init — takes effect immediately
DeepFilterNative.setAttenLim(40.0); // gentle: fans gone, keyboard mostly audible
DeepFilterNative.setAttenLim(60.0); // moderate (recommended default)
DeepFilterNative.setAttenLim(100.0); // maximum (default)
```

Typical starting point: **60 dB**. Tune down to **30–40 dB** if mechanical
noise (keyboard, mouse) is being over-suppressed alongside wanted audio.

## Architecture

```
Dart                         Native Plugin DLL         capi Library
┌──────────────────┐         ┌──────────────────┐      ┌──────────────────┐
│ DeepFilterNative │──FFI──→│ deepfilter_adapter│─dl──→│ deep_filter_lib  │
│ .init()          │         │ .cpp/.cc/.c      │ open │ .dll/.so/.dylib  │
│ .setApmEnabled() │         │                  │      │ (df_create,      │
│ .isApmAttached   │←──export── df_init,         │      │  df_process,     │
└──────────────────┘         │  df_apm_set_en.. │      │  df_free)        │
                             │  df_apm_is_att.. │      └──────────────────┘
                             └──────────────────┘
                                        │
                          ┌─────────────┴──────────────┐
                          │  DeepFilterAPMEffect        │
                          │  (RTCAudioProcessing::      │
                          │   CustomProcessing)         │
                          │  Hooked into flutter_webrtc │
                          │  APM via                    │
                          │  FlutterWebRTCPluginShared  │
                          │  Instance()->               │
                          │  audio_processing()->       │
                          │  SetCapturePostProcessing() │
                          │  Called per capture frame   │
                          │  before WebRTC encoding     │
                          └─────────────────────────────┘

If the capi file doesn't exist at build time, the copy step is skipped
gracefully (the `if(EXISTS ...)` guard). The app still compiles and runs —
but uses the pass-through stub.

**macOS**: the podspec's `vendored_libraries = '**/*.dylib'` bundles
`libdeep_filter_lib.dylib` via CocoaPods. Ensure it's in `macos/lib/`.

## Critical Rules

| Rule | Why |
|------|-----|
| Always check `isRealLibrary` after init | Silent stub fallback = no noise suppression |
| Check `isApmAttached` if unsure processing is active | Hook attaches on first successful `df_init`, not before |
| Model path must be the `.tar.gz` **file** (e.g. `models/DeepFilterNet3_onnx.tar.gz`) | `df_create` in the capi expects a tar.gz file path, not a directory |
| Call `setProcessor()` on the **local** track only | Applying to remote/playback tracks causes echo |
| `processedTrack` returns `null` | Processing is in-place via APM hook; no track replacement |
| Use `processAsync()` on mobile | Sync `processFrame()` throws on Android/iOS |

## Troubleshooting

| Symptom | Check |
|---------|-------|
| No noise reduction but `isSupported`=true | Check `isRealLibrary` — capi likely not loaded |
| `isRealLibrary`=true but no effect | Check `isApmAttached` — APM hook may not have fired yet; ensure `df_init` ran (happens on first `DeepFilterProcessor()` construction) |
| `isRealLibrary`=false | Verify `deep_filter_lib.{dll,so,dylib}` exists next to the runner EXE |
| App crashes on init | Capi library missing a dependency (onnxruntime). View OutputDebugString / flutter logs |
| Model not found | Path must be the `.tar.gz` **file** (e.g. `models/DeepFilterNet3_onnx.tar.gz`), not a directory — `df_create` in the capi expects a tar.gz file path |
| `modelPtr=null` in log but model exists | Adapter auto-discovers: checks `<plugin-dll-dir>/models/` then `<exe-dir>/models/`. If both fail, no model found. Ensure runner CMakeLists.txt copies model next to EXE. |
| Too aggressive — keyboard/clicks suppressed | Lower `atten_lim`: `DeepFilterNative.setAttenLim(40.0)` |
| Build fails with "sprintf not found" | MSVC needs `<cstdio>` include (already fixed in adapter) |

## Files an Agent Should Touch

- **Add dependency**: `pubspec.yaml`
- **Download libs**: `scripts/download_prebuilt.ps1` or `.sh`
- **Use processor**: your app's audio setup code
- **Check diagnosis**: `DeepFilterProcessor.isRealLibrary`, `DeepFilterProcessor.isApmAttached`
- **Tune suppression**: `DeepFilterNative.setAttenLim(db)` — call after init
- **Model deploy**: `example/windows/runner/CMakeLists.txt` (model copy)
- **Auto-discovery**: `windows/src/deepfilter_adapter.cpp` (`resolve_model_path`)

Do not modify `macos/` podspec unless you understand the adapter/capi symbol
bridge.
