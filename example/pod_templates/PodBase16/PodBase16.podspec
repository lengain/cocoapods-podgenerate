Pod::Spec.new do |s|
  s.name             = 'PodBase16'
  s.version          = '1.0.0'
  s.summary          = 'PodBase16 - A test pod for CocoaPods performance benchmarking'
  s.description      = <<-DESC
      PodBase16 is a test pod used for CocoaPods performance testing.
      It contains ObjC and Swift source files and resource assets.
  DESC
  s.homepage         = 'https://github.com/example/PodBase16'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Example' => 'example@example.com' }
  s.source           = { :git => 'https://github.com/example/PodBase16.git', :tag => s.version.to_s }
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.swift_version    = '5.0'

  s.source_files     = 'Classes/**/*.{h,m,swift}'
  s.public_header_files = 'Classes/**/*.h'
  s.resource_bundles = {
    'PodBase16Resources' => ['Assets/**/*']
  }

  s.frameworks       = 'Foundation'
  s.requires_arc     = true
end
