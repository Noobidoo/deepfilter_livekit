#!/bin/bash
set -euo pipefail

VERSION="${1:-v0.5.0}"
REPO="${2:-https://github.com/Rikorose/DeepFilterNet}"
BASE_URL="$REPO/releases/download/$VERSION"
OUT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

download() {
    local url="$1" outfile="$2"
    mkdir -p "$(dirname "$outfile")"
    echo "Downloading $url -> $outfile"
    curl -fsSL "$url" -o "$outfile"
}

unzip_to() {
    local zip="$1" dir="$2"
    mkdir -p "$dir"
    unzip -o "$zip" -d "$dir"
    rm "$zip"
}

# Windows x86_64
download "$BASE_URL/deep_filter_lib-x86_64-windows.zip" "$OUT_DIR/windows/lib/deep_filter_lib.zip"
unzip_to "$OUT_DIR/windows/lib/deep_filter_lib.zip" "$OUT_DIR/windows/lib"

# Linux x86_64
download "$BASE_URL/libdeep_filter_lib-x86_64-linux.zip" "$OUT_DIR/linux/lib/libdeep_filter_lib.zip"
unzip_to "$OUT_DIR/linux/lib/libdeep_filter_lib.zip" "$OUT_DIR/linux/lib"

# macOS universal
download "$BASE_URL/libdeep_filter_lib-universal-macos.zip" "$OUT_DIR/macos/lib/libdeep_filter_lib.zip"
unzip_to "$OUT_DIR/macos/lib/libdeep_filter_lib.zip" "$OUT_DIR/macos/lib"

# Android
for abi in arm64-v8a armeabi-v7a x86_64; do
    download "$BASE_URL/libdeep_filter_lib-${abi}-android.zip" "$OUT_DIR/android/src/main/jniLibs/${abi}/lib.zip"
    unzip_to "$OUT_DIR/android/src/main/jniLibs/${abi}/lib.zip" "$OUT_DIR/android/src/main/jniLibs/${abi}"
done

# iOS XCFramework
download "$BASE_URL/libdeep_filter_lib-ios-xcframework.zip" "$OUT_DIR/ios/Frameworks/libdeep_filter_lib.zip"
unzip_to "$OUT_DIR/ios/Frameworks/libdeep_filter_lib.zip" "$OUT_DIR/ios/Frameworks"

# Model (small)
download "https://github.com/Rikorose/DeepFilterNet/releases/download/$VERSION/DeepFilterNet-small.zip" "$OUT_DIR/assets/models/model.zip"
unzip_to "$OUT_DIR/assets/models/model.zip" "$OUT_DIR/assets/models"

echo "Prebuilt libraries and model downloaded successfully."
