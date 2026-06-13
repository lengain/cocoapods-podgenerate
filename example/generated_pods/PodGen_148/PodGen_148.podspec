  Pod::Spec.new do |s|
    s.name             = 'PodGen_148'
    s.version          = '1.0.0'
    s.summary          = 'PodGen_148 - [HighBusiness] 高层业务模块，编排多个中层组件实现完整业务场景'
    s.description      = <<-DESC
        PodGen_148 is a auto-generated test pod for CocoaPods performance benchmarking.
        Layer: HighBusiness. 高层业务模块，编排多个中层组件实现完整业务场景
    DESC
    s.homepage         = 'https://github.com/example/PodGen_148'
    s.license          = { :type => 'MIT', :file => 'LICENSE' }
    s.author           = { 'Example' => 'example@example.com' }
    s.source           = { :git => 'https://github.com/example/PodGen_148.git', :tag => s.version.to_s }
    s.ios.deployment_target = '15.0'
    s.swift_version    = '5.0'

    s.source_files     = 'Classes/**/*.{h,m,swift}'
    s.public_header_files = 'Classes/**/*.h'
    s.resource_bundles = {
      'PodGen_148Resources' => ['Assets/**/*', 'Resources/**/*']
    }

    s.frameworks       = 'Foundation', 'UIKit'
    s.requires_arc     = true
  s.dependency 'PodGen_38', '~> 1.0'
  s.dependency 'PodGen_39', '~> 1.0'
  s.dependency 'PodGen_40', '~> 1.0'
  s.dependency 'PodGen_55', '~> 1.0'
  s.dependency 'PodGen_56', '~> 1.0'
  s.dependency 'PodGen_57', '~> 1.0'
  s.dependency 'PodGen_71', '~> 1.0'
  s.dependency 'PodGen_72', '~> 1.0'
  s.dependency 'PodGen_73', '~> 1.0'
  s.dependency 'PodGen_4', '~> 1.0'
  s.dependency 'PodGen_9', '~> 1.0'
  s.dependency 'PodGen_13', '~> 1.0'
  s.dependency 'PodGen_18', '~> 1.0'
  s.dependency 'PodGen_22', '~> 1.0'
  s.dependency 'PodGen_26', '~> 1.0'
  s.dependency 'PodGen_31', '~> 1.0'
  s.dependency 'PodGen_35', '~> 1.0'
  end
