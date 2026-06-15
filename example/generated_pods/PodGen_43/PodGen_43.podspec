  Pod::Spec.new do |s|
    s.name             = 'PodGen_43'
    s.version          = '1.0.0'
    s.summary          = 'PodGen_43 - [MidComponent] 中层功能组件，组合底层库实现特定业务能力'
    s.description      = <<-DESC
        PodGen_43 is a auto-generated test pod for CocoaPods performance benchmarking.
        Layer: MidComponent. 中层功能组件，组合底层库实现特定业务能力
    DESC
    s.homepage         = 'https://github.com/example/PodGen_43'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'Example' => 'example@example.com' }
    s.source           = { :git => 'https://github.com/example/PodGen_43.git', :tag => s.version.to_s }
    s.ios.deployment_target = '15.0'
    s.swift_version    = '5.0'

    s.source_files     = 'Classes/**/*.{h,m,swift}'
    s.public_header_files = 'Classes/**/*.h'
    s.resource_bundles = {
      'PodGen_43Resources' => ['Assets/**/*', 'Resources/**/*']
    }

    s.frameworks       = 'Foundation', 'UIKit'
    s.requires_arc     = true
  s.dependency 'PodGen_11', '~> 1.0'
  s.dependency 'PodGen_12', '~> 1.0'
  s.dependency 'PodGen_13', '~> 1.0'
  s.dependency 'PodGen_14', '~> 1.0'
  s.dependency 'PodGen_28', '~> 1.0'
  s.dependency 'PodGen_29', '~> 1.0'
  s.dependency 'PodGen_30', '~> 1.0'
  s.dependency 'PodGen_31', '~> 1.0'
  s.dependency 'PodGen_32', '~> 1.0'
    s.dependency 'Flutter', '~> 1.0'
  end