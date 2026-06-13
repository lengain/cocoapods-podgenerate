  Pod::Spec.new do |s|
    s.name             = 'PodGen_118'
    s.version          = '1.0.0'
    s.summary          = 'PodGen_118 - [HighBusiness] 高层业务模块，编排多个中层组件实现完整业务场景'
    s.description      = <<-DESC
        PodGen_118 is a auto-generated test pod for CocoaPods performance benchmarking.
        Layer: HighBusiness. 高层业务模块，编排多个中层组件实现完整业务场景
    DESC
    s.homepage         = 'https://github.com/example/PodGen_118'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'Example' => 'example@example.com' }
    s.source           = { :git => 'https://github.com/example/PodGen_118.git', :tag => s.version.to_s }
    s.ios.deployment_target = '15.0'
    s.swift_version    = '5.0'

    s.source_files     = 'Classes/**/*.{h,m,swift}'
    s.public_header_files = 'Classes/**/*.h'
    s.resource_bundles = {
      'PodGen_118Resources' => ['Assets/**/*', 'Resources/**/*']
    }

    s.frameworks       = 'Foundation', 'UIKit'
    s.requires_arc     = true
  s.dependency 'PodGen_41', '~> 1.0'
  s.dependency 'PodGen_42', '~> 1.0'
  s.dependency 'PodGen_43', '~> 1.0'
  s.dependency 'PodGen_58', '~> 1.0'
  s.dependency 'PodGen_59', '~> 1.0'
  s.dependency 'PodGen_60', '~> 1.0'
  s.dependency 'PodGen_75', '~> 1.0'
  s.dependency 'PodGen_76', '~> 1.0'
  s.dependency 'PodGen_77', '~> 1.0'
  s.dependency 'PodGen_2', '~> 1.0'
  s.dependency 'PodGen_6', '~> 1.0'
  s.dependency 'PodGen_11', '~> 1.0'
  s.dependency 'PodGen_15', '~> 1.0'
  s.dependency 'PodGen_19', '~> 1.0'
  s.dependency 'PodGen_24', '~> 1.0'
  s.dependency 'PodGen_28', '~> 1.0'
  s.dependency 'PodGen_33', '~> 1.0'
  end
