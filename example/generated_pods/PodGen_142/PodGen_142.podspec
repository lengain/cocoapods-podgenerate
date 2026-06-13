  Pod::Spec.new do |s|
    s.name             = 'PodGen_142'
    s.version          = '1.0.0'
    s.summary          = 'PodGen_142 - [HighBusiness] 高层业务模块，编排多个中层组件实现完整业务场景'
    s.description      = <<-DESC
        PodGen_142 is a auto-generated test pod for CocoaPods performance benchmarking.
        Layer: HighBusiness. 高层业务模块，编排多个中层组件实现完整业务场景
    DESC
    s.homepage         = 'https://github.com/example/PodGen_142'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'Example' => 'example@example.com' }
    s.source           = { :git => 'https://github.com/example/PodGen_142.git', :tag => s.version.to_s }
    s.ios.deployment_target = '15.0'
    s.swift_version    = '5.0'

    s.source_files     = 'Classes/**/*.{h,m,swift}'
    s.public_header_files = 'Classes/**/*.h'
    s.resource_bundles = {
      'PodGen_142Resources' => ['Assets/**/*', 'Resources/**/*']
    }

    s.frameworks       = 'Foundation', 'UIKit'
    s.requires_arc     = true
  s.dependency 'PodGen_36', '~> 1.0'
  s.dependency 'PodGen_37', '~> 1.0'
  s.dependency 'PodGen_52', '~> 1.0'
  s.dependency 'PodGen_53', '~> 1.0'
  s.dependency 'PodGen_54', '~> 1.0'
  s.dependency 'PodGen_69', '~> 1.0'
  s.dependency 'PodGen_70', '~> 1.0'
  s.dependency 'PodGen_71', '~> 1.0'
  s.dependency 'PodGen_85', '~> 1.0'
  s.dependency 'PodGen_2', '~> 1.0'
  s.dependency 'PodGen_7', '~> 1.0'
  s.dependency 'PodGen_11', '~> 1.0'
  s.dependency 'PodGen_15', '~> 1.0'
  s.dependency 'PodGen_20', '~> 1.0'
  s.dependency 'PodGen_24', '~> 1.0'
  s.dependency 'PodGen_28', '~> 1.0'
  s.dependency 'PodGen_33', '~> 1.0'
  end
