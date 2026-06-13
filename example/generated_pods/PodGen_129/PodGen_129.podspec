  Pod::Spec.new do |s|
    s.name             = 'PodGen_129'
    s.version          = '1.0.0'
    s.summary          = 'PodGen_129 - [HighBusiness] 高层业务模块，编排多个中层组件实现完整业务场景'
    s.description      = <<-DESC
        PodGen_129 is a auto-generated test pod for CocoaPods performance benchmarking.
        Layer: HighBusiness. 高层业务模块，编排多个中层组件实现完整业务场景
    DESC
    s.homepage         = 'https://github.com/example/PodGen_129'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'Example' => 'example@example.com' }
    s.source           = { :git => 'https://github.com/example/PodGen_129.git', :tag => s.version.to_s }
    s.ios.deployment_target = '15.0'
    s.swift_version    = '5.0'

    s.source_files     = 'Classes/**/*.{h,m,swift}'
    s.public_header_files = 'Classes/**/*.h'
    s.resource_bundles = {
      'PodGen_129Resources' => ['Assets/**/*', 'Resources/**/*']
    }

    s.frameworks       = 'Foundation', 'UIKit'
    s.requires_arc     = true
  s.dependency 'PodGen_49', '~> 1.0'
  s.dependency 'PodGen_50', '~> 1.0'
  s.dependency 'PodGen_51', '~> 1.0'
  s.dependency 'PodGen_66', '~> 1.0'
  s.dependency 'PodGen_67', '~> 1.0'
  s.dependency 'PodGen_68', '~> 1.0'
  s.dependency 'PodGen_82', '~> 1.0'
  s.dependency 'PodGen_83', '~> 1.0'
  s.dependency 'PodGen_84', '~> 1.0'
  s.dependency 'PodGen_85', '~> 1.0'
  s.dependency 'PodGen_2', '~> 1.0'
  s.dependency 'PodGen_6', '~> 1.0'
  s.dependency 'PodGen_15', '~> 1.0'
  s.dependency 'PodGen_19', '~> 1.0'
  s.dependency 'PodGen_24', '~> 1.0'
  s.dependency 'PodGen_28', '~> 1.0'
  s.dependency 'PodGen_32', '~> 1.0'
  end
