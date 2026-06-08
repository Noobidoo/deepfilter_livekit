param(
    [string]$Version = "v0.5.7-capi.1",
    [string]$Repo = "https://github.com/Noobidoo/DeepFilterNet"
)

$BaseUrl = "$Repo/releases/download/$Version"
$OutDir = Join-Path $PSScriptRoot ".."

function Download-File {
    param($Url, $OutFile)
    $dir = Split-Path $OutFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-Host "Downloading $Url -> $OutFile"
    Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
}

# Windows x86_64
$winDir = Join-Path $OutDir "windows\lib"
Download-File "$BaseUrl/deep_filter_lib.dll" "$winDir\deep_filter_lib.dll"

# Linux x86_64
$linuxDir = Join-Path $OutDir "linux\lib"
Download-File "$BaseUrl/libdeep_filter_lib.so" "$linuxDir\libdeep_filter_lib.so"

# macOS (universal)
$macDir = Join-Path $OutDir "macos\lib"
Download-File "$BaseUrl/libdeep_filter_lib.dylib" "$macDir\libdeep_filter_lib.dylib"

# Android arm64-v8a (best-effort — may not exist in release yet)
$androidDir = Join-Path $OutDir "android\src\main\jniLibs\arm64-v8a"
try {
    Download-File "$BaseUrl/libdeep_filter_lib-arm64-android.so" "$androidDir\libdeep_filter_lib.so"
} catch { Write-Warning "Android lib not available: $_" }

# iOS (best-effort — may not exist in release yet)
$iosDir = Join-Path $OutDir "ios\Frameworks"
try {
    Download-File "$BaseUrl/libdeep_filter_lib-ios.a" "$iosDir\libdeep_filter_lib.a"
} catch { Write-Warning "iOS lib not available: $_" }

# DeepFilterNet3 ONNX model (same for all platforms — placed in assets/models/
# so CMake can copy it to the build output on all host platforms)
$ModelUrl = "https://github.com/Rikorose/DeepFilterNet/raw/main/models/DeepFilterNet3_onnx.tar.gz"
$ModelDir = Join-Path $OutDir "assets\models"
Download-File $ModelUrl "$ModelDir\DeepFilterNet3_onnx.tar.gz"

Write-Host "Prebuilt libraries and model downloaded successfully."
