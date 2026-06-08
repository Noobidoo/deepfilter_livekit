Pod::Spec.new do |s|
  s.name             = 'deepfilter_livekit'
  s.version          = '0.1.0'
  s.summary          = 'DeepFilterNet noise suppression plugin for LiveKit Flutter.'
  s.description      = <<-DESC
Real-time neural network-based noise suppression using DeepFilterNet for LiveKit Flutter.
                       DESC
  s.homepage         = 'https://github.com/your-org/deepfilter_livekit'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Your Name' => 'email@example.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform         = :osx, '10.15'

  s.vendored_libraries = '**/*.a', '**/*.dylib'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_OBJC_BRIDGING_HEADER' => '$(PODS_TARGET_SRCROOT)/Classes/deepfilter_livekit-Bridging-Header.h',
  }
  s.swift_version = '5.0'
end
