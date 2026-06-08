param(
    [string]$Version = "v0.5.0",
    [string]$Repo = "https://github.com/Rikorose/DeepFilterNet"
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
Download-File "$BaseUrl/deep_filter_lib-x86_64-windows.zip" "$winDir\deep_filter_lib.zip"
# Extract
Expand-Archive -Path "$winDir\deep_filter_lib.zip" -DestinationPath $winDir -Force
Remove-Item "$winDir\deep_filter_lib.zip"

# Linux x86_64
$linuxDir = Join-Path $OutDir "linux\lib"
Download-File "$BaseUrl/libdeep_filter_lib-x86_64-linux.zip" "$linuxDir\libdeep_filter_lib.zip"
Expand-Archive -Path "$linuxDir\libdeep_filter_lib.zip" -DestinationPath $linuxDir -Force
Remove-Item "$linuxDir\libdeep_filter_lib.zip"

# macOS (universal)
$macDir = Join-Path $OutDir "macos\lib"
Download-File "$BaseUrl/libdeep_filter_lib-universal-macos.zip" "$macDir\libdeep_filter_lib.zip"
Expand-Archive -Path "$macDir\libdeep_filter_lib.zip" -DestinationPath $macDir -Force
Remove-Item "$macDir\libdeep_filter_lib.zip"

# Android
$androidDir = Join-Path $OutDir "android\src\main\jniLibs"
Download-File "$BaseUrl/libdeep_filter_lib-arm64-v8a-android.zip" "$androidDir\arm64-v8a\lib.zip"
Expand-Archive -Path "$androidDir\arm64-v8a\lib.zip" -DestinationPath "$androidDir\arm64-v8a" -Force
Remove-Item "$androidDir\arm64-v8a\lib.zip"

Download-File "$BaseUrl/libdeep_filter_lib-armeabi-v7a-android.zip" "$androidDir\armeabi-v7a\lib.zip"
Expand-Archive -Path "$androidDir\armeabi-v7a\lib.zip" -DestinationPath "$androidDir\armeabi-v7a" -Force
Remove-Item "$androidDir\armeabi-v7a\lib.zip"

Download-File "$BaseUrl/libdeep_filter_lib-x86_64-android.zip" "$androidDir\x86_64\lib.zip"
Expand-Archive -Path "$androidDir\x86_64\lib.zip" -DestinationPath "$androidDir\x86_64" -Force
Remove-Item "$androidDir\x86_64\lib.zip"

# iOS (xcframework)
$iosDir = Join-Path $OutDir "ios\Frameworks"
Download-File "$BaseUrl/libdeep_filter_lib-ios-xcframework.zip" "$iosDir\libdeep_filter_lib.zip"
Expand-Archive -Path "$iosDir\libdeep_filter_lib.zip" -DestinationPath $iosDir -Force
Remove-Item "$iosDir\libdeep_filter_lib.zip"

# Model (DeepFilterNet small model)
$modelDir = Join-Path $OutDir "assets\models"
Download-File "https://github.com/Rikorose/DeepFilterNet/releases/download/$Version/DeepFilterNet-small.zip" "$modelDir\model.zip"
Expand-Archive -Path "$modelDir\model.zip" -DestinationPath $modelDir -Force
Remove-Item "$modelDir\model.zip"

Write-Host "Prebuilt libraries and model downloaded successfully."
