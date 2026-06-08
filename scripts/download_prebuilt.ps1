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

# Android — not yet built in CI (add when CI adds android targets)
# $androidDir = Join-Path $OutDir "android\src\main\jniLibs"
# Download-File "$BaseUrl/libdeep_filter_lib-arm64-android.so" "$androidDir\arm64-v8a\libdeep_filter_lib.so"

# iOS — not yet built in CI

Write-Host "Prebuilt libraries downloaded successfully."
