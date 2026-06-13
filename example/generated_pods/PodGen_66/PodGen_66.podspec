  Pod::Spec.new do |s|
    s.name             = 'PodGen_66'
    s.version          = '1.0.0'
    s.summary          = 'PodGen_66 - [MidComponent] 中层功能组件，组合底层库实现特定业务能力'
    s.description      = <<-DESC
        PodGen_66 is a auto-generated test pod for CocoaPods performance benchmarking.
        Layer: MidComponent. 中层功能组件，组合底层库实现特定业务能力
    DESC
    s.homepage         = 'https://github.com/example/PodGen_66'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'Example' => 'example@example.com' }
    s.source           = { :git => 'https://github.com/example/PodGen_66.git', :tag => s.version.to_s }
    s.ios.deployment_target = '15.0'
    s.swift_version    = '5.0'

    s.source_files     = 'Classes/**/*.{h,m,swift}'
    s.public_header_files = 'Classes/**/*.h'
    s.resource_bundles = {
      'PodGen_66Resources' => ['Assets/**/*', 'Resources/**/*']
    }

    s.frameworks       = 'Foundation', 'UIKit'
    s.requires_arc     = true
  s.dependency 'PodGen_3', '~> 1.0'
  s.dependency 'PodGen_4', '~> 1.0'
  s.dependency 'PodGen_5', '~> 1.0'
  s.dependency 'PodGen_6', '~> 1.0'
  s.dependency 'PodGen_21', '~> 1.0'
  s.dependency 'PodGen_22', '~> 1.0'
  s.dependency 'PodGen_23', '~> 1.0'
  end
