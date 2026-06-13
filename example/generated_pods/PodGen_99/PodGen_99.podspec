  Pod::Spec.new do |s|
    s.name             = 'PodGen_99'
    s.version          = '1.0.0'
    s.summary          = 'PodGen_99 - [HighBusiness] 高层业务模块，编排多个中层组件实现完整业务场景'
    s.description      = <<-DESC
        PodGen_99 is a auto-generated test pod for CocoaPods performance benchmarking.
        Layer: HighBusiness. 高层业务模块，编排多个中层组件实现完整业务场景
    DESC
    s.homepage         = 'https://github.com/example/PodGen_99'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'Example' => 'example@example.com' }
    s.source           = { :git => 'https://github.com/example/PodGen_99.git', :tag => s.version.to_s }
    s.ios.deployment_target = '15.0'
    s.swift_version    = '5.0'

    s.source_files     = 'Classes/**/*.{h,m,swift}'
    s.public_header_files = 'Classes/**/*.h'
    s.resource_bundles = {
      'PodGen_99Resources' => ['Assets/**/*', 'Resources/**/*']
    }

    s.frameworks       = 'Foundation', 'UIKit'
    s.requires_arc     = true
  s.dependency 'PodGen_36', '~> 1.0'
  s.dependency 'PodGen_37', '~> 1.0'
  s.dependency 'PodGen_38', '~> 1.0'
  s.dependency 'PodGen_52', '~> 1.0'
  s.dependency 'PodGen_53', '~> 1.0'
  s.dependency 'PodGen_54', '~> 1.0'
  s.dependency 'PodGen_55', '~> 1.0'
  s.dependency 'PodGen_69', '~> 1.0'
  s.dependency 'PodGen_70', '~> 1.0'
  s.dependency 'PodGen_71', '~> 1.0'
  s.dependency 'PodGen_4', '~> 1.0'
  s.dependency 'PodGen_8', '~> 1.0'
  s.dependency 'PodGen_12', '~> 1.0'
  s.dependency 'PodGen_17', '~> 1.0'
  s.dependency 'PodGen_21', '~> 1.0'
  s.dependency 'PodGen_30', '~> 1.0'
  s.dependency 'PodGen_34', '~> 1.0'
  end
