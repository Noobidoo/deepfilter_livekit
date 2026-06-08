#!/bin/bash
set -euo pipefail

VERSION="${1:-v0.5.7-capi.1}"
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

# Android — not yet built in CI
# download "$BASE_URL/libdeep_filter_lib-arm64-android.so" "$OUT_DIR/android/src/main/jniLibs/arm64-v8a/libdeep_filter_lib.so"

# iOS — not yet built in CI

echo "Prebuilt libraries downloaded successfully."
