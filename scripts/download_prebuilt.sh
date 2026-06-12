#!/bin/bash
set -euo pipefail

VERSION="${1:-v0.5.7-capi.3}"
REPO="${2:-https://github.com/Noobidoo/DeepFilterNet}"
BASE_URL="$REPO/releases/download/$VERSION"
OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

download() {
    local url="$1" outfile="$2"
    mkdir -p "$(dirname "$outfile")"
    echo "Downloading $url -> $outfile"
    curl -fsSL "$url" -o "$outfile"
}

# Windows x86_64
download "$BASE_URL/deep_filter_lib.dll" "$OUT_DIR/windows/lib/deep_filter_lib.dll"

# Linux x86_64
download "$BASE_URL/libdeep_filter_lib.so" "$OUT_DIR/linux/lib/libdeep_filter_lib.so"

# macOS
download "$BASE_URL/libdeep_filter_lib.dylib" "$OUT_DIR/macos/lib/libdeep_filter_lib.dylib"

# Android arm64-v8a
mkdir -p "$OUT_DIR/android/src/main/jniLibs/arm64-v8a"
curl -fsSL "$BASE_URL/libdeep_filter_lib-arm64-android.so" \
  -o "$OUT_DIR/android/src/main/jniLibs/arm64-v8a/libdeep_filter_lib.so" || \
  echo "Android arm64-v8a lib not available"

# Android armeabi-v7a
mkdir -p "$OUT_DIR/android/src/main/jniLibs/armeabi-v7a"
curl -fsSL "$BASE_URL/libdeep_filter_lib-arm-android.so" \
  -o "$OUT_DIR/android/src/main/jniLibs/armeabi-v7a/libdeep_filter_lib.so" || \
  echo "Android armeabi-v7a lib not available"

# Android x86_64
mkdir -p "$OUT_DIR/android/src/main/jniLibs/x86_64"
curl -fsSL "$BASE_URL/libdeep_filter_lib-x86_64-android.so" \
  -o "$OUT_DIR/android/src/main/jniLibs/x86_64/libdeep_filter_lib.so" || \
  echo "Android x86_64 lib not available"

# iOS (best-effort — may not exist in release yet)
mkdir -p "$OUT_DIR/ios/Frameworks"
curl -fsSL "$BASE_URL/libdeep_filter_lib-ios.a" \
  -o "$OUT_DIR/ios/Frameworks/libdeep_filter_lib.a" || \
  echo "iOS lib not available yet"

# DeepFilterNet3 ONNX model
MODEL_URL="https://github.com/Rikorose/DeepFilterNet/raw/main/models/DeepFilterNet3_onnx.tar.gz"
download "$MODEL_URL" "$OUT_DIR/assets/models/DeepFilterNet3_onnx.tar.gz"

echo "Prebuilt libraries and model downloaded successfully."
