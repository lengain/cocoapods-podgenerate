  Pod::Spec.new do |s|
    s.name             = 'PodGen_110'
    s.version          = '1.0.0'
    s.summary          = 'PodGen_110 - [HighBusiness] 高层业务模块，编排多个中层组件实现完整业务场景'
    s.description      = <<-DESC
        PodGen_110 is a auto-generated test pod for CocoaPods performance benchmarking.
        Layer: HighBusiness. 高层业务模块，编排多个中层组件实现完整业务场景
    DESC
    s.homepage         = 'https://github.com/example/PodGen_110'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'Example' => 'example@example.com' }
    s.source           = { :git => 'https://github.com/example/PodGen_110.git', :tag => s.version.to_s }
    s.ios.deployment_target = '15.0'
    s.swift_version    = '5.0'

    s.source_files     = 'Classes/**/*.{h,m,swift}'
    s.public_header_files = 'Classes/**/*.h'
    s.resource_bundles = {
      'PodGen_110Resources' => ['Assets/**/*', 'Resources/**/*']
    }

    s.frameworks       = 'Foundation', 'UIKit'
    s.requires_arc     = true
  s.dependency 'PodGen_43', '~> 1.0'
  s.dependency 'PodGen_44', '~> 1.0'
  s.dependency 'PodGen_45', '~> 1.0'
  s.dependency 'PodGen_60', '~> 1.0'
  s.dependency 'PodGen_61', '~> 1.0'
  s.dependency 'PodGen_62', '~> 1.0'
  s.dependency 'PodGen_77', '~> 1.0'
  s.dependency 'PodGen_78', '~> 1.0'
  s.dependency 'PodGen_79', '~> 1.0'
  s.dependency 'PodGen_3', '~> 1.0'
  s.dependency 'PodGen_8', '~> 1.0'
  s.dependency 'PodGen_12', '~> 1.0'
  s.dependency 'PodGen_16', '~> 1.0'
  s.dependency 'PodGen_21', '~> 1.0'
  s.dependency 'PodGen_25', '~> 1.0'
  s.dependency 'PodGen_30', '~> 1.0'
  s.dependency 'PodGen_34', '~> 1.0'
  end
