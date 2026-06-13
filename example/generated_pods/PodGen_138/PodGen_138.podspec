  Pod::Spec.new do |s|
    s.name             = 'PodGen_138'
    s.version          = '1.0.0'
    s.summary          = 'PodGen_138 - [HighBusiness] 高层业务模块，编排多个中层组件实现完整业务场景'
    s.description      = <<-DESC
        PodGen_138 is a auto-generated test pod for CocoaPods performance benchmarking.
        Layer: HighBusiness. 高层业务模块，编排多个中层组件实现完整业务场景
    DESC
    s.homepage         = 'https://github.com/example/PodGen_138'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'Example' => 'example@example.com' }
    s.source           = { :git => 'https://github.com/example/PodGen_138.git', :tag => s.version.to_s }
    s.ios.deployment_target = '15.0'
    s.swift_version    = '5.0'

    s.source_files     = 'Classes/**/*.{h,m,swift}'
    s.public_header_files = 'Classes/**/*.h'
    s.resource_bundles = {
      'PodGen_138Resources' => ['Assets/**/*', 'Resources/**/*']
    }

    s.frameworks       = 'Foundation', 'UIKit'
    s.requires_arc     = true
  s.dependency 'PodGen_45', '~> 1.0'
  s.dependency 'PodGen_46', '~> 1.0'
  s.dependency 'PodGen_47', '~> 1.0'
  s.dependency 'PodGen_61', '~> 1.0'
  s.dependency 'PodGen_62', '~> 1.0'
  s.dependency 'PodGen_63', '~> 1.0'
  s.dependency 'PodGen_78', '~> 1.0'
  s.dependency 'PodGen_79', '~> 1.0'
  s.dependency 'PodGen_80', '~> 1.0'
  s.dependency 'PodGen_1', '~> 1.0'
  s.dependency 'PodGen_5', '~> 1.0'
  s.dependency 'PodGen_9', '~> 1.0'
  s.dependency 'PodGen_14', '~> 1.0'
  s.dependency 'PodGen_18', '~> 1.0'
  s.dependency 'PodGen_23', '~> 1.0'
  s.dependency 'PodGen_27', '~> 1.0'
  s.dependency 'PodGen_31', '~> 1.0'
  end
